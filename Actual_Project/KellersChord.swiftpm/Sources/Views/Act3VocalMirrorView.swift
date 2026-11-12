import SwiftUI

/// Act III — The Vocal Mirror & Viva Coach (1:45 - 3:00).
///
/// Empowers a deaf or hard-of-hearing student to rehearse speaking aloud for a
/// college viva. The judge picks a prompt, speaks (or taps *Simulate Live
/// Voice*), and watches their own transcript morph through `ProsodyTextRenderer`
/// in real time, with `CadenceHorizonBar` coaching volume, warmth and cadence and
/// a 130 WPM tactile pulse to hold onto.
///
/// The view never touches the microphone directly: `ProsodyDSPEngine` owns the
/// single tap and `OfflineSpeechManager` consumes those buffers, so the
/// single-tap audio contract is preserved end to end.
///
/// Phase 2 (Batch 12) adds the live-stage layer on top of the Phase 1 mirror:
/// * **Vocal Braille scrubbing** — dragging across a word replays its recorded
///   prosody as slow-motion touch.
/// * **16 ms Pre-Echo Ink Seed** — a reactive orb at the transcript's trailing edge
///   that wakes on `rmsAmplitude > 0.08`, ~150 ms before speech recognition has
///   decoded anything, so the speaker feels zero latency.
/// * **Room Calibration** — a 1.5 s gate that measures the ambient floor.
/// * **Three mode pills** — Tabletop Duet, 3-Take Live Stage and the Vocal
///   Signature passport, each presenting its Batch 11 component.
struct Act3VocalMirrorView: View {

    // MARK: - Injected dependencies

    /// The shared playback + DSP engine (used for live mic capture here).
    var dspEngine: ProsodyDSPEngine
    /// The shared on-device speech manager (transcript + simulation fallback).
    var speechManager: OfflineSpeechManager
    /// The shared haptic engine (also carries the 130 WPM pacing pulse).
    var hapticEngine: TactileHapticEngine
    /// The live prosody frame published by the DSP engine.
    var liveFrame: ProsodyFrame
    /// Rolling amplitude history for the Cadence Horizon's inflection mirror.
    var amplitudeHistory: [Float]
    /// Ambient clock for the living-typography animation.
    var elapsedTime: Double
    /// Accessibility Reduce Motion.
    var reduceMotion: Bool
    /// CI only (`--ci-act3-duet`): open in tabletop duet instead of the mirror.
    var openInDuet: Bool = false
    /// Restarts the whole 3-act experience from Act I.
    var onRestart: () -> Void

    // MARK: - State

    /// Whether the judge has started the mirror.
    @State private var isRunning = false
    /// Bound to `CadenceHorizonBar`; drives `TactileHapticEngine.isPacingEnabled`.
    @State private var isPacingOn = false
    /// Bound to the "Simulate Live Voice" toggle.
    @State private var isSimulating = false
    /// The selected viva prompt index.
    @State private var promptIndex = 0
    /// The active live-stage mode, or `nil` for the standard mirror.
    @State private var stageMode: StageMode?
    /// `true` while the 1.5 s room calibration is running.
    @State private var isCalibrating = false
    /// The word currently being scrubbed, for the chip highlight.
    @State private var scrubbingWordID: UUID?
    /// Every frame seen this act, for the Prosody Passport summary.
    @State private var capturedFrames: [ProsodyFrame] = []
    /// Throttle counter for `capturedFrames`; the passport only needs ~20 Hz.
    @State private var frameTick = 0
    /// While a braille word is being held, the mirror shows *that* word's prosody
    /// instead of the live frame (Upgrade 3 / Section 4.3).
    @State private var scrubbedFrame: ProsodyFrame?

    /// The three optional live-stage presentations (Batch 11 components).
    enum StageMode: String, Identifiable {
        case tabletopDuet
        case threeTakeDeck
        case passport

        var id: String { rawValue }
    }

    /// The frame the mirror renders: the word being scrubbed, otherwise live mic
    /// prosody or the simulated stream.
    private var mirrorFrame: ProsodyFrame {
        scrubbedFrame ?? liveFrame
    }

    /// The currently selected viva prompt text.
    private var currentPrompt: String {
        OfflineSpeechManager.vivaPrompts[promptIndex % OfflineSpeechManager.vivaPrompts.count]
    }

    var body: some View {
        ZStack {
            standardMirror
            if let stageMode {
                stageOverlay(stageMode)
                    .transition(.opacity)
            }
        }
        .onChange(of: isPacingOn) { _, newValue in
            hapticEngine.isPacingEnabled = newValue
        }
        .onChange(of: liveFrame.rmsAmplitude) { _, _ in
            // Upgrade 13: keep a bounded record of the act for the passport.
            //
            // Sampled at ~20 Hz rather than every 60 fps callback: the passport
            // only computes shares and means, so 3x fewer frames gives the same
            // answer while cutting both the array shift and the downstream
            // `ProsodyPassportSheet` diff to a third.
            guard liveFrame.isVoiced else { return }
            frameTick &+= 1
            guard frameTick % 3 == 0 else { return }
            capturedFrames.append(liveFrame)
            if capturedFrames.count > 600 {
                capturedFrames.removeFirst(capturedFrames.count - 600)
            }
        }
        .onAppear {
            if openInDuet, stageMode == nil {
                stageMode = .tabletopDuet
            }
        }
        .onDisappear { stopMirror() }
    }

    // MARK: - Standard mirror

    private var standardMirror: some View {
        VStack(spacing: ThemeTokens.Spacing.regular) {
            promptCard
            modePills
            mirrorStage
            statusBadge
            brailleStrip
            controls
            CadenceHorizonBar(
                frame: mirrorFrame,
                history: amplitudeHistory,
                isPacingOn: $isPacingOn,
                elapsedTime: elapsedTime,
                reduceMotion: reduceMotion
            )
            restartButton
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.regular)
    }

    /// Presents a Batch 11 live-stage component over the mirror.
    @ViewBuilder
    private func stageOverlay(_ mode: StageMode) -> some View {
        switch mode {
        case .tabletopDuet:
            TabletopDuetOverlay(
                frame: mirrorFrame,
                transcript: speechManager.transcript,
                wordSnapshots: speechManager.wordSnapshots,
                elapsedTime: elapsedTime,
                reduceMotion: reduceMotion,
                onScrubWord: { snapshot in
                    hapticEngine.playBrailleScrub(for: snapshot)
                },
                onClose: { stageMode = nil }
            )
        case .threeTakeDeck:
            LiveComparisonDeckView(
                takes: speechManager.takes,
                activeTarget: speechManager.activeTakeTarget,
                liveFrame: mirrorFrame,
                elapsedTime: elapsedTime,
                reduceMotion: reduceMotion,
                onBeginTake: { target in
                    speechManager.beginTake(target: target)
                },
                onEndTake: {
                    speechManager.endTake()
                },
                onPreviewTake: { take in
                    if let first = take.snapshots.first {
                        hapticEngine.playBrailleScrub(for: first)
                    }
                },
                onClose: { stageMode = nil }
            )
        case .passport:
            ProsodyPassportSheet(
                frames: capturedFrames,
                wordSnapshots: speechManager.wordSnapshots,
                ambientNoiseDB: dspEngine.ambientNoiseDB,
                onDismiss: { stageMode = nil },
                onResetTour: {
                    stageMode = nil
                    stopMirror()
                    speechManager.clearWordSnapshots()
                    speechManager.clearTakes()
                    capturedFrames.removeAll(keepingCapacity: true)
                    onRestart()
                }
            )
        }
    }

    // MARK: - Prompt card

    /// A selectable viva prompt, so the speaker always knows what to practise.
    ///
    /// The `GhostInflectionRailView` sits behind the prompt text, showing the ideal
    /// vocal trajectory for this sentence before the speaker begins.
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: ThemeTokens.Spacing.tight) {
            Text("PROMPT \(promptIndex + 1) OF \(OfflineSpeechManager.vivaPrompts.count)")
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
            Text(currentPrompt)
                .font(ThemeTokens.Typography.body)
                .foregroundStyle(ThemeTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            GhostInflectionRailView(
                frame: mirrorFrame,
                targetContour: GhostInflectionRailView.targetContour(for: currentPrompt),
                isQuestion: GhostInflectionRailView.isQuestion(currentPrompt),
                elapsedTime: elapsedTime,
                reduceMotion: reduceMotion,
                onLockedIn: {
                    // A single gentle click the moment the speaker locks cadence.
                    hapticEngine.playBrailleScrub(
                        for: WordProsodySnapshot(
                            word: "cadence",
                            timestampOffset: 0,
                            duration: 0.1,
                            frames: [mirrorFrame],
                            dominantFrame: mirrorFrame,
                            hasConsonantSpark: false,
                            terminalInflection: mirrorFrame.terminalInflection
                        )
                    )
                }
            )

            HStack(spacing: ThemeTokens.Spacing.tight) {
                Button("Previous") {
                    promptIndex = (promptIndex - 1 + OfflineSpeechManager.vivaPrompts.count)
                        % OfflineSpeechManager.vivaPrompts.count
                }
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
                .accessibilityLabel("Previous prompt")
                .accessibilityValue("Prompt \(promptIndex + 1) of \(OfflineSpeechManager.vivaPrompts.count)")
                .accessibilityHint("Moves to the previous viva prompt to practise.")
                Button("Next Prompt") {
                    promptIndex = (promptIndex + 1) % OfflineSpeechManager.vivaPrompts.count
                }
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.accent(for: .warmRelief))
                .accessibilityLabel("Next prompt")
                .accessibilityValue("Prompt \(promptIndex + 1) of \(OfflineSpeechManager.vivaPrompts.count)")
                .accessibilityHint("Moves to the next viva prompt to practise.")
            }
            .buttonStyle(.plain)
        }
        .padding(ThemeTokens.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                .fill(ThemeTokens.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                        .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Viva prompt \(promptIndex + 1)")
    }

    // MARK: - Mode pills

    /// The three live-stage mode pills plus the room calibration gate.
    private var modePills: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            modePill(title: "Duet", symbol: "rectangle.split.2x1", mode: .tabletopDuet)
            modePill(title: "3-Take", symbol: "square.3.layers.3d", mode: .threeTakeDeck)
            modePill(title: "Signature", symbol: "circle.hexagongrid", mode: .passport)
            Spacer(minLength: 0)
            calibrateButton
        }
    }

    private func modePill(title: String, symbol: String, mode: StageMode) -> some View {
        let isActive = stageMode == mode
        return Button {
            stageMode = isActive ? nil : mode
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(ThemeTokens.Typography.pill)
            }
            .foregroundStyle(isActive ? ThemeTokens.obsidian : ThemeTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive
                          ? ThemeTokens.accent(for: .warmRelief)
                          : ThemeTokens.glassFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isActive ? "On" : "Off")
        .accessibilityHint("Opens the \(title) live stage view.")
        .accessibilityAddTraits(.isButton)
    }

    /// The 1.5 s room calibration gate (Upgrade 6's user-facing affordance).
    private var calibrateButton: some View {
        Button {
            guard !isCalibrating else { return }
            // Stop any capture first: calibration takes exclusive ownership of the
            // input tap, so a live session must not be running underneath it.
            dspEngine.stopLiveInput()
            Task { await calibrateRoom() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCalibrating ? "hourglass" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                Text(isCalibrating ? "Calibrating" : "Calibrate Room")
                    .font(ThemeTokens.Typography.pill)
            }
            .foregroundStyle(ThemeTokens.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(ThemeTokens.glassFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isCalibrating)
        .accessibilityLabel("Calibrate room noise")
        .accessibilityValue(isCalibrating ? "Calibrating" : "Ready")
        .accessibilityHint("Measures the room for one and a half seconds so volume advice matches this space.")
    }

    // MARK: - Mirror stage

    /// The hero: the living transcript, morphed from the speaker's own prosody,
    /// with the Pre-Echo Ink Seed at its trailing edge.
    private var mirrorStage: some View {
        let transcript = speechManager.transcript
        let shown = transcript.isEmpty ? "Start speaking and your words will bloom here." : transcript
        let accent = ThemeTokens.accent(for: mirrorFrame.classifiedEmotion)

        return ZStack {
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                .fill(ThemeTokens.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                        .stroke(accent.opacity(mirrorFrame.isVoiced ? 0.5 : 0.12), lineWidth: 1)
                )

            // The transcript, with the Ink Seed sharing its HStack so the orb always
            // sits at the trailing edge of the last word.
            HStack(alignment: .center, spacing: 8) {
                Text(shown)
                    .font(transcript.isEmpty ? ThemeTokens.Typography.body : ThemeTokens.Typography.hero)
                    .fontWeight(ThemeTokens.emphasisWeight(for: mirrorFrame))
                    .foregroundStyle(transcript.isEmpty ? ThemeTokens.textSecondary : ThemeTokens.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .textRenderer(
                        ProsodyTextRenderer(
                            frame: mirrorFrame,
                            elapsedTime: elapsedTime,
                            reduceMotion: reduceMotion
                        )
                    )
                vocalInkSeed
            }
            .padding(ThemeTokens.Spacing.section)
        }
        .frame(minHeight: 180)
        .animation(reduceMotion ? nil : ThemeTokens.Motion.act, value: mirrorFrame.classifiedEmotion)
        .accessibilityElement()
        .accessibilityLabel("Your live transcript")
        .accessibilityValue(transcript.isEmpty ? "No speech yet" : transcript)
        .accessibilityHint("Your words appear here and change shape with your voice.")
    }

    /// The 16 ms Pre-Echo Ink Seed (Upgrade 8).
    ///
    /// Speech recognition needs roughly 150 ms to decode a syllable, but the DSP
    /// engine already knows the voice is present within one 16.6 ms frame. This orb
    /// therefore wakes on `rmsAmplitude > 0.08` and breathes with loudness, giving
    /// the speaker an instant answer from the screen before any word exists. It
    /// carries no haptic of its own - `TactileHapticEngine.render` is already
    /// driving touch from the same frame, so adding another would double-fire.
    private var vocalInkSeed: some View {
        let isAwake = mirrorFrame.rmsAmplitude > 0.08
        let energy = min(max(mirrorFrame.rmsAmplitude, 0), 1)
        let accent = ThemeTokens.accent(for: mirrorFrame.classifiedEmotion)
        // Grows from 8 to ~18 pt with loudness once awake.
        let diameter = 8 + CGFloat(energy) * 10

        return Circle()
            .fill(accent)
            .frame(width: diameter, height: diameter)
            .shadow(color: accent.opacity(isAwake ? 0.8 : 0), radius: isAwake ? 8 : 0)
            .opacity(isAwake ? 1 : 0.18)
            .scaleEffect(isAwake && !reduceMotion ? 1.0 + CGFloat(energy) * 0.15 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isAwake)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: mirrorFrame.rmsAmplitude)
            .accessibilityHidden(true)
    }

    // MARK: - Braille strip

    /// The Vocal Braille word scrubber (Upgrade 3's user-facing surface).
    ///
    /// Dragging onto a word replays that word's recorded prosody in slow motion, so
    /// the user can re-feel a syllable they missed rather than re-listening to the
    /// whole sentence.
    @ViewBuilder
    private var brailleStrip: some View {
        let allWords = speechManager.wordSnapshots
        let words = Array(allWords.suffix(8))
        // Global index of the first chip, so a chip can ask the manager to scrub
        // by position in `wordSnapshots` rather than in this suffix.
        let offset = max(allWords.count - words.count, 0)
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("VOCAL BRAILLE - DRAG TO FEEL")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .textCase(.uppercase)
                HStack(spacing: 6) {
                    ForEach(Array(words.enumerated()), id: \.element.id) { position, snapshot in
                        brailleChip(snapshot, index: offset + position)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Vocal braille word scrubber")
        }
    }

    /// One braille word chip. Holding it replays that word's prosody through
    /// `OfflineSpeechManager.scrubWord(at:)`, which both re-fires the haptic
    /// signature and hands back the frame so the mirror's type morphs to the word
    /// being felt.
    private func brailleChip(_ snapshot: WordProsodySnapshot, index: Int) -> some View {
        let isActive = scrubbingWordID == snapshot.id
        let color = ThemeTokens.accent(for: snapshot.dominantFrame.classifiedEmotion)
        return Text(snapshot.word)
            .font(ThemeTokens.Typography.pill)
            .foregroundStyle(isActive ? ThemeTokens.obsidian : ThemeTokens.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? color : ThemeTokens.glassFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isActive ? color : ThemeTokens.glassStroke, lineWidth: 1)
                    )
            )
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard scrubbingWordID != snapshot.id else { return }
                        scrubbingWordID = snapshot.id
                        hapticEngine.playBrailleScrub(for: snapshot)
                        // `scrubWord` is the manager's supported way to address a
                        // word by position, and its returned frame is what makes
                        // the mirror's type morph to the word being felt.
                        scrubbedFrame = speechManager.scrubWord(at: index) ?? snapshot.dominantFrame
                    }
                    .onEnded { _ in
                        scrubbingWordID = nil
                        scrubbedFrame = nil
                        hapticEngine.cancelBrailleScrub()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Word \(snapshot.word)")
            .accessibilityValue(snapshot.dominantFrame.classifiedEmotion.displayName)
            .accessibilityHint("Touch to feel this word's vocal tone again.")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Status badge

    /// A sleek, non-blocking badge reporting live / simulated / listening.
    private var statusBadge: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(speechManager.status.badgeLabel)
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textPrimary)
            Spacer(minLength: 0)
            Text(speechManager.status.detail)
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, ThemeTokens.Spacing.regular)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous).fill(ThemeTokens.glassFill)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recognition status")
        .accessibilityValue(speechManager.status.badgeLabel)
    }

    /// Dot colour for the recognition badge.
    ///
    /// Exhaustive over `Status` (six cases). The previous version handled five and
    /// reached `.simulated` through a separate `if`, which both omitted the case
    /// from the switch (a compiler error) and would have needed two edits to add a
    /// new state.
    private var statusColor: Color {
        switch speechManager.status {
        case .live, .listening: return ThemeTokens.accent(for: .warmRelief)
        case .simulated(reason: _): return ThemeTokens.accent(for: .anxiousTremor)
        case .unavailable(reason: _): return ThemeTokens.accent(for: .sharpSarcasm)
        case .idle, .requestingPermission: return ThemeTokens.textSecondary
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: ThemeTokens.Spacing.regular) {
            Button {
                startMirror()
            } label: {
                Text(isRunning ? "Stop Mirroring" : "Start Mirroring My Voice")
                    .font(ThemeTokens.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(ThemeTokens.obsidian)
                    .padding(.horizontal, ThemeTokens.Spacing.section)
                    .padding(.vertical, ThemeTokens.Spacing.regular)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isRunning
                                  ? ThemeTokens.accent(for: .sharpSarcasm)
                                  : ThemeTokens.accent(for: .warmRelief))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRunning ? "Stop mirroring my voice" : "Start mirroring my voice")
            .accessibilityHint("Turns the live vocal mirror on or off.")

            modePill
        }
    }

    /// The single-tap Live / Simulated voice-source switch.
    ///
    /// One tap at any time: it starts the simulated stream immediately, or hands
    /// the pipeline back to the microphone. It is not a dead end in either
    /// direction - if the hardware or the permissions refuse, the pill silently
    /// returns to simulation and the status badge says exactly that.
    private var modePill: some View {
        Button {
            toggleMode()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSimulating ? "waveform" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(isSimulating ? "Sim" : "Live")
                    .font(ThemeTokens.Typography.pill)
            }
            .foregroundStyle(isSimulating
                             ? ThemeTokens.accent(for: .anxiousTremor)
                             : ThemeTokens.textSecondary)
            .frame(minWidth: 46)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSimulating
                          ? ThemeTokens.accent(for: .anxiousTremor).opacity(0.16)
                          : ThemeTokens.glassFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isSimulating
                                    ? ThemeTokens.accent(for: .anxiousTremor).opacity(0.5)
                                    : ThemeTokens.glassStroke,
                                    lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice source")
        .accessibilityValue(isSimulating ? "Simulated voice" : "Live microphone")
        .accessibilityHint("Switches between the live microphone and the simulated voice.")
    }

    private var restartButton: some View {
        Button {
            stopMirror()
            speechManager.clearWordSnapshots()
            speechManager.clearTakes()
            capturedFrames.removeAll(keepingCapacity: true)
            onRestart()
        } label: {
            Text("Replay the Full Experience")
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replay the full experience")
        .accessibilityHint("Returns to Act I from the beginning.")
    }

    // MARK: - Logic

    /// Starts or stops the mirror.
    ///
    /// Starting arms the on-device recognizer and switches the DSP engine to the
    /// microphone; the recognizer consumes the same single tap, never its own.
    /// If the microphone tap cannot start at all, the mirror falls straight into
    /// the simulated stream so the judge is never left on a silent, dead screen.
    private func startMirror() {
        if isRunning {
            stopMirror()
            return
        }
        isRunning = true

        guard !isSimulating else {
            speechManager.setSimulationEnabled(true, profile: mirrorFrame.classifiedEmotion)
            return
        }

        dspEngine.startLiveInput()
        guard dspEngine.mode == .liveInput else {
            // No usable input hardware (or the session refused to start).
            isSimulating = true
            speechManager.setSimulationEnabled(true, profile: mirrorFrame.classifiedEmotion)
            return
        }
        Task { await speechManager.startLive() }
    }

    /// Flips between the live microphone and the simulated voice in one tap.
    ///
    /// Handled entirely here rather than in an `onChange`, so a fallback cannot
    /// re-trigger itself: the pill's local state only ever changes in response to
    /// a tap or to a confirmed failure.
    private func toggleMode() {
        let wantSimulation = !isSimulating
        isSimulating = wantSimulation

        guard wantSimulation else {
            // Switching back to live. Nothing to do unless the mirror is running.
            speechManager.setSimulationEnabled(false)
            guard isRunning else { return }
            dspEngine.startLiveInput()
            guard dspEngine.mode == .liveInput else {
                isSimulating = true
                speechManager.setSimulationEnabled(true, profile: mirrorFrame.classifiedEmotion)
                return
            }
            Task {
                await speechManager.startLive()
                // The manager may still land on simulation (permission refused,
                // model not downloaded). Mirror that truth in the pill so it can
                // never claim "Live" while a synthetic voice is playing.
                if speechManager.isUsingSimulation { isSimulating = true }
            }
            return
        }

        // Switching to simulation: release the microphone first so only one
        // source ever drives the frame pipeline.
        dspEngine.stopLiveInput()
        isRunning = true
        speechManager.setSimulationEnabled(true, profile: mirrorFrame.classifiedEmotion)
    }

    /// Stops whichever capture path is active and resets pacing.
    private func stopMirror() {
        isRunning = false
        isPacingOn = false
        hapticEngine.isPacingEnabled = false
        hapticEngine.cancelBrailleScrub()
        scrubbingWordID = nil
        scrubbedFrame = nil
        speechManager.stopLive()
        dspEngine.stopLiveInput()
    }

    /// Runs the room calibration without blocking the run loop.
    ///
    /// The engine splits the work into `beginRoomCalibration()` and
    /// `finishRoomCalibration()` because an `async` engine method would send this
    /// non-`Sendable` audio class off the main actor, which Swift 6 rejects. The
    /// waiting lives in the caller instead: `Task.sleep` suspends this task and
    /// yields to the main actor, so `isCalibrating` really does render its
    /// "Calibrating" label while the microphone samples the silent room.
    private func calibrateRoom() async {
        isCalibrating = true
        defer { isCalibrating = false }
        dspEngine.beginRoomCalibration()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        dspEngine.finishRoomCalibration()
    }
}
