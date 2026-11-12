import SwiftUI
import Observation

/// The top-level 3-Act container for Keller's Chord.
///
/// This view is the *frame*, never the picture: it owns the shared engines, keeps
/// the single-tap audio contract intact, and swaps the three acts inside a near
/// invisible obsidian shell with one glassmorphic progress pill.
///
/// Wiring it performs once, on appear:
/// * `AudioSampleLoader.loadAll()` -> the three emotional samples.
/// * `dspEngine.onFrame` -> `currentFrame` + `hapticEngine.render(_:)` + the
///   rolling `amplitudeHistory` for the Cadence Horizon.
/// * `dspEngine.onCapturedBuffer` -> `speechManager.consumeCapturedBuffer(_:)`,
///   so live microphone PCM reaches the recognizer without a second tap.
///
/// `TimelineView(.animation)` supplies the ambient clock the designers need, so
/// no `Timer.publish` instance ever leaks (per the audit checklist).
struct RootCoordinatorView: View {

    // MARK: - Model (engines + shared live state, owned once)

    /// A `@MainActor` holder for the engines and shared state.
    ///
    /// Keeping the three `@MainActor` engines inside one observable model avoids
    /// constructing them in a `@State` default initializer (which Swift 6 strict
    /// concurrency may evaluate off the main actor) and gives the whole app a
    /// single place to reason about the audio pipeline.
    @State private var model = CoordinatorModel()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The launch flags CI passes to open a specific state for screenshots.
    private let intent = LaunchIntent.current()

    var body: some View {
        // §9 Rule 5: drive the 60fps clock through `TimelineView(.animation(...))`
        // with a `paused` flag, never a leaking `Timer.publish`. It pauses when
        // nothing is moving (no voiced frame and no active playback) to save power.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: model.isIdle)) { timeline in
            ZStack {
                // Reactive emotional aura behind everything.
                EmotionalMeshBackground(
                    frame: model.currentFrame,
                    elapsedTime: timeline.date.timeIntervalSinceReferenceDate,
                    reduceMotion: reduceMotion
                )

                VStack(spacing: 0) {
                    WordmarkBar(
                        current: model.actStage,
                        emotion: model.currentFrame.classifiedEmotion,
                        progress: model.progress,
                        onSelect: { stage in advance(to: stage) }
                    )

                    actContent(elapsedTime: timeline.date.timeIntervalSinceReferenceDate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                }
            }
        }
        .background(ThemeTokens.obsidian)
        .preferredColorScheme(.dark)
        .onAppear(perform: prepare)
        .onDisappear(perform: teardown)
    }

    // MARK: - Act content

    /// Renders the active act, injecting the shared engines and live frame.
    @ViewBuilder
    private func actContent(elapsedTime: Double) -> some View {
        Group {
            switch model.actStage {
            case .act1Blindspot:
                Act1CaptionBlindspotView(
                    samples: model.samples,
                    dspEngine: model.dspEngine,
                    hapticEngine: model.hapticEngine,
                    liveFrame: model.currentFrame,
                    elapsedTime: elapsedTime,
                    reduceMotion: reduceMotion,
                    usesSynthesizedAudio: model.usesSynthesizedAudio,
                    initiallyUnlocked: intent.opensActOneUnlocked,
                    onComplete: { advance(to: .act2TactileDecoder) }
                )
            case .act2TactileDecoder:
                Act2TactileProsodyView(
                    samples: model.samples,
                    dspEngine: model.dspEngine,
                    hapticEngine: model.hapticEngine,
                    liveFrame: model.currentFrame,
                    elapsedTime: elapsedTime,
                    reduceMotion: reduceMotion,
                    previewFrame: intent.actTwoFrame,
                    onComplete: { advance(to: .act3VocalMirror) }
                )
            case .act3VocalMirror:
                Act3VocalMirrorView(
                    dspEngine: model.dspEngine,
                    speechManager: model.speechManager,
                    hapticEngine: model.hapticEngine,
                    liveFrame: model.currentFrame,
                    amplitudeHistory: model.amplitudeHistory,
                    elapsedTime: elapsedTime,
                    reduceMotion: reduceMotion,
                    openInDuet: intent.opensInDuet,
                    onRestart: { restart() }
                )
            }
        }
    }

    // MARK: - Lifecycle

    /// Loads samples and wires the engine callbacks exactly once.
    private func prepare() {
        model.prepare()
        // CI only: open the act a screenshot was asked for. Without flags this is
        // a no-op, so the shipping path is untouched.
        if intent.act != .act1Blindspot, model.actStage != intent.act {
            model.advance(to: intent.act)
        }
    }

    /// Stops every engine and clears the callbacks on the way out.
    private func teardown() {
        model.teardown()
    }

    // MARK: - Act choreography

    /// Moves to another act, stopping playback so no audio leaks across the cut.
    private func advance(to stage: ActStage) {
        withAnimation(reduceMotion ? nil : ThemeTokens.Motion.act) {
            model.advance(to: stage)
        }
    }

    /// Restarts the whole 180-second experience from Act I.
    private func restart() {
        withAnimation(reduceMotion ? nil : ThemeTokens.Motion.act) {
            model.restart()
        }
    }
}

// MARK: - Coordinator model

/// Owns the three engines and the shared live state for the whole experience.
///
/// A single `@MainActor` reference type keeps every `@MainActor` engine out of a
/// `@State` default initializer (which Swift 6 strict concurrency may evaluate off
/// the main actor) and gives the audio pipeline one clear home. `@Observable` lets
/// SwiftUI re-render only the views that read the changed fields.
@MainActor
@Observable
final class CoordinatorModel {

    // Engines (owned once, injected everywhere).
    let dspEngine = ProsodyDSPEngine()
    let hapticEngine = TactileHapticEngine()
    let speechManager = OfflineSpeechManager()

    // Shared live state.
    private(set) var samples: [AudioSampleLoader.LoadedSample] = []
    private(set) var usesSynthesizedAudio = false
    private(set) var currentFrame: ProsodyFrame = .silent
    private(set) var amplitudeHistory: [Float] = []
    private(set) var actStage: ActStage = .act1Blindspot

    /// Guards one-time setup.
    private var didPrepare = false

    /// How many recent amplitudes the Cadence Horizon's mirror keeps. The mirror
    /// itself reads `.suffix(48)` / `.suffix(24)`, so 48 is the useful ceiling.
    private static let historyLimit = 48

    /// When the current act began, so the progress bar can fill in real time.
    private var actStartTime: Date?

    /// `true` when nothing needs the 60fps clock: no voiced frame is streaming.
    /// The `TimelineView` pauses on this to save battery between animated moments.
    var isIdle: Bool {
        !currentFrame.isVoiced && dspEngine.mode == nil
    }

    /// Fraction of the whole experience complete, filling smoothly across the act.
    ///
    /// The span and the planned length both come from `ActStage`, so the
    /// choreography's 0:45 / 1:45 / 3:00 boundaries have exactly one definition.
    var progress: Double {
        let span = actStage.progressSpan
        guard let actStartTime else { return span.start }
        let elapsed = Date().timeIntervalSince(actStartTime)
        let fraction = min(max(elapsed / actStage.durationSeconds, 0), 1)
        return span.start + (span.end - span.start) * fraction
    }

    /// Loads samples and wires the engine callbacks exactly once.
    ///
    /// The two closures below are the heart of the architecture:
    /// * `onFrame` hops finished prosody to the main actor -> `currentFrame`,
    ///   which feeds living typography, the mesh aura, the tactile engine and the
    ///   Cadence Horizon's amplitude history.
    /// * `onCapturedBuffer` hands raw mic PCM to the recognizer on the audio
    ///   thread, so only ONE tap is ever installed (no `inputNode` crash).
    func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        let loaded = AudioSampleLoader().loadAll()
        samples = loaded
        usesSynthesizedAudio = loaded.contains { $0.isSynthesized }

        hapticEngine.prepare()
        actStartTime = Date()

        // Capture the recognizer in a local so the audio-thread closure never
        // reaches back through `self`.
        let speech = speechManager

        dspEngine.onFrame = { [weak self] frame in
            self?.apply(frame)
        }

        // `onCapturedBuffer` fires on the CoreAudio render thread, so it must be
        // `@Sendable` and touch no actor-isolated state. `consumeCapturedBuffer`
        // is `nonisolated` and internally lock-guarded for exactly this reason.
        dspEngine.onCapturedBuffer = { buffer in
            speech.consumeCapturedBuffer(buffer)
        }

        // Wire the recognizer's simulated fallback straight into the mirror.
        speechManager.onSimulatedFrame = { [weak self] frame in
            self?.apply(frame)
        }
    }

    /// Stops every engine and clears the callbacks on the way out.
    func teardown() {
        dspEngine.stopAll()
        hapticEngine.stop()
        speechManager.stopLive()
        dspEngine.onFrame = nil
        dspEngine.onCapturedBuffer = nil
        speechManager.onSimulatedFrame = nil
    }

    /// Moves to another act, stopping playback and any capture so nothing leaks
    /// across the cut. Reachable at any time from the act control.
    func advance(to stage: ActStage) {
        dspEngine.stopAll()
        speechManager.stopLive()
        hapticEngine.stop()
        actStage = stage
        currentFrame = .silent
        amplitudeHistory.removeAll(keepingCapacity: true)
        actStartTime = Date()
    }

    /// Restarts the whole 180-second experience from Act I.
    func restart() {
        dspEngine.stopAll()
        hapticEngine.stop()
        speechManager.stopLive()
        actStage = .act1Blindspot
        currentFrame = .silent
        amplitudeHistory.removeAll(keepingCapacity: true)
        actStartTime = Date()
    }

    /// Applies one frame everywhere: type, aura, haptics and history.
    ///
    /// Phase 2 (Batch 9): the same frame also feeds `OfflineSpeechManager`'s
    /// rolling frame window, which is what the Vocal Braille word recorder slices
    /// its `WordProsodySnapshot`s from. Done here (not in each view) so both live
    /// microphone frames and simulated frames reach the recorder through one path.
    private func apply(_ frame: ProsodyFrame) {
        currentFrame = frame
        hapticEngine.render(frame)
        speechManager.ingestFrame(frame)
        amplitudeHistory.append(frame.rmsAmplitude)
        if amplitudeHistory.count > Self.historyLimit {
            amplitudeHistory.removeFirst(amplitudeHistory.count - Self.historyLimit)
        }
    }
}
