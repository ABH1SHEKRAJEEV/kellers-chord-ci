import AVFoundation
import Foundation
import Speech

/// On-device speech transcription for Act III's Vocal Mirror.
///
/// The manager never touches the microphone itself: `ProsodyDSPEngine` owns the
/// one legal tap on `inputNode`, and this type receives those same PCM buffers
/// through `consumeCapturedBuffer(_:)`. That keeps Keller's Chord to a single
/// `installTap(onBus: 0)` and avoids the `AVAudioEngine.inputNode` crash that
/// two competing taps would cause.
///
/// Everything degrades gracefully. If the microphone or speech-recognition
/// permission is denied, if on-device models are not yet downloaded, or if the
/// judge enables "Simulate Live Voice", the manager drives a realistic simulated
/// cadence stream from `ProceduralVoiceSynthesizer.simulatedFrame` instead, so
/// the act can always be demonstrated without a dead-end error screen.
///
/// Phase 2 (Batch 9) adds three capabilities on top of the Phase 1 contract,
/// all of them additive so no existing call site changes:
///
/// * **Upgrade 7 — sub-180 ms partials & 60 s seamless pause rollover.** Partial
///   results are always requested, and once the recognition session passes 38 s
///   the manager waits for 350 ms of silence (or the hard 60 s limit) and then
///   swaps in a fresh `SFSpeechAudioBufferRecognitionRequest` *without* stopping
///   `AVAudioEngine`, concatenating everything into one uninterrupted transcript.
/// * **Upgrade 3 — `[WordProsodySnapshot]` recorder.** A rolling 1.5 s frame
///   buffer is sliced into a `WordProsodySnapshot` for every new word, and
///   `scrubWord(at:)` replays a word's dominant frame for Vocal Braille
///   scrubbing.
/// * **Upgrade 10 — the 3-Take Live Stage deck.** `takes` accumulates up to three
///   `LiveChallengeTake` recordings of the same phrase (`beginTake`/`endTake`).
@MainActor
final class OfflineSpeechManager {

    /// How transcriber availability resolved.
    enum Status: Equatable {
        case idle
        case requestingPermission
        /// Real on-device recognition is running.
        case live
        /// A simulated stream is standing in for real recognition.
        case simulated(reason: String)
        /// The recognizer is configured and awaiting its first audio buffer.
        case listening
        /// Neither live capture nor simulation is possible right now.
        case unavailable(reason: String)

        /// Short badge copy for the UI. Intentionally non-alarming.
        var badgeLabel: String {
            switch self {
            case .idle: return "Ready"
            case .requestingPermission: return "Requesting Permission..."
            case .live: return "Live On-Device"
            case .simulated: return "Simulated Live Voice"
            case .listening: return "Listening"
            case .unavailable: return "Unavailable"
            }
        }

        /// Explanatory sentence shown under the badge and read by VoiceOver.
        var detail: String {
            switch self {
            case .idle:
                return "Tap Start Speaking to mirror your voice."
            case .requestingPermission:
                return "Waiting for microphone and speech recognition permission."
            case .live:
                return "Recognizing your speech fully offline, on this device."
            case .simulated(let reason):
                return reason
            case .listening:
                return "Capturing audio while the on-device model warms up."
            case .unavailable(let reason):
                return reason
            }
        }
    }

    /// Fires whenever the transcript should be re-rendered. Always `@MainActor`.
    var onTranscript: (@MainActor (String) -> Void)?
    /// Fires at roughly 60 Hz while simulated, with the synthetic prosody frame.
    var onSimulatedFrame: (@MainActor (ProsodyFrame) -> Void)?
    /// Fires when a word snapshot is recorded, so the Vocal Braille scrubber and
    /// the 3-Take deck can extend themselves without polling.
    var onWordSnapshotsChanged: (@MainActor ([WordProsodySnapshot]) -> Void)?

    private(set) var status: Status = .idle {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }
    /// Mirrors `status`'s simulated case as a plain `Bool` so views can bind
    /// without pattern matching.
    private(set) var isUsingSimulation = false
    private(set) var transcript = "" {
        didSet { onTranscript?(transcript) }
    }
    private(set) var lastError: String?

    /// Optional observer for SwiftUI to react to status transitions.
    var onStatusChange: (@MainActor (Status) -> Void)?

    // MARK: - Phase 2 public state (Batch 9)

    /// Per-word prosody slices for Vocal Braille scrubbing (Upgrade 3).
    ///
    /// Capped at `Self.snapshotLimit` so a long rehearsal cannot grow without
    /// bound; the oldest word is dropped first.
    private(set) var wordSnapshots: [WordProsodySnapshot] = []

    /// The recorded takes of the "3-Take Live Stage Challenge" deck (Upgrade 10).
    ///
    /// At most `Self.takeLimit` takes are retained; calling `beginTake` after the
    /// deck is full recycles the last slot so the judge can keep re-recording.
    private(set) var takes: [LiveChallengeTake] = []

    /// The emotional target for the take currently being recorded, if any.
    private(set) var activeTakeTarget: String?

    /// True while a take is being accumulated (`beginTake` -> `endTake`).
    var isRecordingTake: Bool { activeTakeTarget != nil }

    /// The three viva prompts the judge can rehearse, as specified for Act III.
    static let vivaPrompts: [String] = [
        "Introduce your project and why it matters in two sentences.",
        "Describe one technical challenge you solved and how you solved it.",
        "Walk me through one design decision you would change today."
    ]

    /// The single phrase all three 3-Take slots recite, per `Everything2.md` 4.5.
    static let comparisonPhrase = "Good luck with your application."

    /// The three emotional targets for the 3-Take deck, in recording order.
    static let takeTargets: [String] = [
        "Warm Empathy",
        "Quiet Anxiety",
        "Biting Sarcasm"
    ]

    /// Maximum retained word snapshots (Vocal Braille scrubber length).
    private static let snapshotLimit = 120
    /// Maximum retained 3-Take deck slots.
    private static let takeLimit = 3
    /// Rolling window of frames kept for slicing a word's prosody (~1.5 s).
    private static let frameBufferLimit = 90
    /// A word snapshot is built from the trailing ~350 ms of frames.
    private static let wordSliceCount = 21

    // MARK: Phase 2 rollover constants (Upgrade 7)

    /// Begin looking for a silence gap after this many seconds of a session.
    private static let rolloverEarliest: TimeInterval = 38.0
    /// Hard ceiling: Apple terminates recognition sessions at 60 s.
    private static let rolloverHardLimit: TimeInterval = 56.0
    /// Silence needed to hand over cleanly (~350 ms of frames).
    private static let rolloverSilenceDuration: TimeInterval = 0.35
    /// RMS below which a frame counts as silence for the rollover gate.
    private static let rolloverSilenceRMS: Float = 0.05
    /// Minimum spacing between two rollovers (~1.2 s).
    private static let rolloverCooldown: TimeInterval = 1.2

    // MARK: - Private state

    private let recognizer: SFSpeechRecognizer?
    /// `true` when the device reports a downloaded, offline-capable model.
    private let supportsOnDevice: Bool

    /// Guards `request`/`task` so audio-thread appends never race a teardown.
    ///
    /// Both are `nonisolated(unsafe)` because `consumeCapturedBuffer(_:)` is a
    /// `nonisolated` method called from the CoreAudio render thread and must read
    /// `request`. In Swift 6 an actor-isolated `var` cannot be touched from a
    /// nonisolated context at all (a lock does not satisfy the compiler), so this
    /// attribute is what makes the hand-off legal. Every access - here and on the
    /// main actor - goes through `lock`.
    private let lock = NSLock()
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?
    nonisolated(unsafe) private var task: SFSpeechRecognitionTask?

    private var simulationTask: Task<Void, Never>?
    private var simulationStart: Date?
    private var simulationProfile: EmotionalProfile = .warmRelief

    // MARK: Phase 2 rollover state (Upgrade 7)

    /// Text committed by every finished recognition session, oldest first.
    private var committedTranscriptPrefix = ""
    /// The transcript produced by the *current* recognition session only.
    private var liveSegmentTranscript = ""
    /// When the current recognition session started, for the 38 s / 56 s gates.
    private var sessionStartTime: Date?
    /// A rollover has been armed for the current session (fires exactly once).
    private var hasArmedRollover = false
    /// When the last successful rollover happened, for the cooldown gate.
    private var lastRolloverTime: Date = .distantPast
    /// Consecutive silent frames ending at the most recent published frame.
    private var consecutiveSilentFrames = 0

    // MARK: Phase 2 recorder state (Upgrade 3 / Upgrade 10)

    /// Rolling window of recent frames, oldest first, capped at 90 (~1.5 s).
    private var frameBuffer: [ProsodyFrame] = []
    /// The clock origin for `WordProsodySnapshot.timestampOffset`.
    private var listeningStartTime: Date?
    /// The word text most recently packaged, to detect a genuinely new word.
    private var lastRecordedWord = ""
    /// How many segments of the current recognition session have already been
    /// packaged into snapshots.
    ///
    /// Partial results are cumulative: every callback re-reports the whole
    /// sentence. This counter is what makes "new word" mean "segment index past
    /// the ones I have," instead of relying on text equality with the previous
    /// word, which re-recorded the entire sentence on every update.
    private var recordedSegmentCount = 0
    /// Words accumulated for the take in progress.
    private var activeTakeSnapshots: [WordProsodySnapshot] = []
    /// Words accumulated for the take in progress, in order.
    private var activeTakeTranscript = ""

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        supportsOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
    }

    /// `true` when real, fully offline recognition is genuinely possible.
    var canUseLiveRecognition: Bool {
        recognizer?.isAvailable == true && supportsOnDevice
    }

    /// `true` when the OS has already refused a permission this app needs.
    ///
    /// Checked *before* asking. iOS never re-prompts after a denial, so calling
    /// `requestAuthorization` again only returns `false` after a pointless status
    /// round-trip. Detecting it up front lets the simulated stream start in the
    /// same run-loop turn, so the judge never sees a stalled "requesting" state or
    /// a dialog that cannot appear.
    private static var permissionsAlreadyRefused: Bool {
        let speech = SFSpeechRecognizer.authorizationStatus()
        if speech == .denied || speech == .restricted { return true }
        #if os(iOS)
        if AVAudioApplication.shared.recordPermission == .denied { return true }
        #endif
        return false
    }

    // MARK: - Live capture control

    /// Requests the two permissions, then arms on-device recognition.
    ///
    /// On success the manager moves to `.listening` and waits for
    /// `consumeCapturedBuffer(_:)`; on any denial it switches to the simulated
    /// stream with a human-readable reason.
    func startLive() async {
        status = .requestingPermission

        // Zero permission dead-ends: if the OS has already refused, start the
        // simulated stream immediately instead of bouncing the judge through a
        // prompt that iOS will never show again.
        if Self.permissionsAlreadyRefused {
            beginSimulated(
                reason: "Microphone or speech access is off, so Keller's Chord is mirroring a realistic simulated voice instead.",
                profile: simulationProfile
            )
            return
        }

        guard await requestSpeechPermission() else {
            beginSimulated(
                reason: "Speech recognition permission is off, so Keller's Chord is mirroring a realistic simulated voice instead.",
                profile: simulationProfile
            )
            return
        }

        #if os(iOS)
        guard await requestRecordPermission() else {
            beginSimulated(
                reason: "Microphone access is off, so Keller's Chord is mirroring a realistic simulated voice instead.",
                profile: simulationProfile
            )
            return
        }
        #endif

        guard let recognizer else {
            beginSimulated(
                reason: "On-device speech models are unavailable in this locale, so Keller's Chord is mirroring a realistic simulated voice instead.",
                profile: simulationProfile
            )
            return
        }
        guard canUseLiveRecognition else {
            beginSimulated(
                reason: "The on-device speech model is still downloading, so Keller's Chord is mirroring a realistic simulated voice instead.",
                profile: simulationProfile
            )
            return
        }

        stopSimulation()
        resetRecognitionSessions()
        makeRecognitionRequest(with: recognizer)
        isUsingSimulation = false
        status = .live
    }

    /// Stops whichever capture path is active.
    func stopLive() {
        let (activeRequest, activeTask) = takeRecognitionHandles()
        activeRequest?.endAudio()
        activeTask?.cancel()
        stopSimulation()
        resetRecognitionSessions()
        if !isUsingSimulation {
            status = .idle
        }
    }

    /// Act III's "Simulate Live Voice" toggle.
    ///
    /// Enabling it stops live capture and starts the synthetic stream; disabling
    /// it returns to `.idle` so the view can call `startLive()` again.
    func setSimulationEnabled(_ enabled: Bool, profile: EmotionalProfile = .warmRelief) {
        if enabled {
            let (activeRequest, activeTask) = takeRecognitionHandles()
            activeRequest?.endAudio()
            activeTask?.cancel()
            resetRecognitionSessions()
            beginSimulated(
                reason: "Simulating a live voice so you can rehearse viva cadence without speaking aloud.",
                profile: profile
            )
        } else {
            stopSimulation()
            resetRecognitionSessions()
            status = .idle
        }
    }

    // MARK: - Audio-thread hand-off

    /// Appends one PCM buffer captured by `ProsodyDSPEngine`'s single tap.
    ///
    /// This is called on the real-time CoreAudio thread, so it must stay
    /// allocation-free and free of `@MainActor` access. The buffer is appended
    /// directly inside the lock; `SFSpeechAudioBufferRecognitionRequest.append`
    /// is itself thread-safe, but the optional unwrap is not.
    nonisolated func consumeCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let activeRequest = request
        lock.unlock()
        guard let activeRequest else { return }
        guard buffer.frameLength > 0 else { return }
        activeRequest.append(buffer)
    }

    // MARK: - Upgrade 3: frame window feeding the word recorder

    /// Feeds one published prosody frame to the word recorder.
    ///
    /// Called from the coordinator's `onFrame` / `onSimulatedFrame` path at
    /// ≈60 Hz. Bounded to `frameBufferLimit` frames (~1.5 s), so a long
    /// rehearsal costs a fixed amount of memory.
    func ingestFrame(_ frame: ProsodyFrame) {
        if listeningStartTime == nil { listeningStartTime = Date() }

        frameBuffer.append(frame)
        if frameBuffer.count > Self.frameBufferLimit {
            frameBuffer.removeFirst(frameBuffer.count - Self.frameBufferLimit)
        }

        // Upgrade 7: track how long the room has been quiet so a rollover can be
        // taken in a silence gap instead of mid-syllable.
        if frame.rmsAmplitude < Self.rolloverSilenceRMS {
            consecutiveSilentFrames += 1
        } else {
            consecutiveSilentFrames = 0
        }
        maybeRollOverRecognitionSession()
    }

    // MARK: - Upgrade 3: Vocal Braille recorder & scrubbing

    /// Packages the trailing ~350 ms of frames as one word snapshot.
    ///
    /// Called with the recognized word text; ignored when the same word text and
    /// frame position produce a duplicate, so a burst of partial results cannot
    /// flood the scrubber with repeats of one word.
    func recordWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !frameBuffer.isEmpty else { return }
        guard trimmed != lastRecordedWord else { return }
        lastRecordedWord = trimmed

        let slice = Array(frameBuffer.suffix(Self.wordSliceCount))
        guard !slice.isEmpty else { return }

        // The dominant frame is the loudest one; fall back to the middle slice.
        let peak = slice.max { $0.rmsAmplitude < $1.rmsAmplitude } ?? slice[slice.count / 2]
        let dominant = peak.rmsAmplitude > 0.02 ? peak : slice[slice.count / 2]

        let duration = Double(slice.count) / 60.0
        let offset = max((listeningStartTime.map { Date().timeIntervalSince($0) } ?? 0) - duration, 0)

        let snapshot = WordProsodySnapshot(
            word: trimmed,
            timestampOffset: offset,
            duration: duration,
            frames: slice,
            dominantFrame: dominant,
            hasConsonantSpark: slice.contains { $0.hasConsonantSpark },
            terminalInflection: dominant.terminalInflection
        )

        wordSnapshots.append(snapshot)
        if wordSnapshots.count > Self.snapshotLimit {
            wordSnapshots.removeFirst(wordSnapshots.count - Self.snapshotLimit)
        }

        // Upgrade 10: also accumulate into the take in progress, if any.
        if isRecordingTake {
            activeTakeSnapshots.append(snapshot)
            if activeTakeTranscript.isEmpty {
                activeTakeTranscript = trimmed
            } else {
                activeTakeTranscript += " " + trimmed
            }
        }

        onWordSnapshotsChanged?(wordSnapshots)
    }

    /// Replays one word's dominant frame for Vocal Braille scrubbing.
    ///
    /// Returns the frame the UI should display, or `nil` when the index is out of
    /// range. The caller hands it to `TactileHapticEngine.playBrailleScrub(for:)`
    /// so the same signature is felt and seen at once.
    @discardableResult
    func scrubWord(at index: Int) -> ProsodyFrame? {
        guard wordSnapshots.indices.contains(index) else { return nil }
        return wordSnapshots[index].dominantFrame
    }

    /// Clears the Vocal Braille scrubber (used by the Judge Tour reset).
    func clearWordSnapshots() {
        wordSnapshots.removeAll(keepingCapacity: true)
        lastRecordedWord = ""
        onWordSnapshotsChanged?(wordSnapshots)
    }

    // MARK: - Upgrade 10: 3-Take Live Stage deck

    /// Opens a new take for `target` (e.g. "Warm Empathy") and clears the
    /// per-take word accumulators so the next words belong to this take.
    func beginTake(target: String) {
        finishActiveTakeIfNeeded()
        activeTakeTarget = target
        activeTakeSnapshots.removeAll(keepingCapacity: true)
        activeTakeTranscript = ""
    }

    /// Closes the take in progress and appends it to `takes`.
    ///
    /// A take with no words is discarded rather than stored, so an accidental tap
    /// cannot leave three empty slots on the judge's comparison deck.
    func endTake() {
        guard let target = activeTakeTarget else { return }
        let snapshots = activeTakeSnapshots
        let spoken = activeTakeTranscript
        activeTakeTarget = nil
        activeTakeSnapshots.removeAll(keepingCapacity: true)
        activeTakeTranscript = ""

        guard !snapshots.isEmpty else { return }

        if takes.count >= Self.takeLimit {
            takes.removeFirst()
        }
        let take = LiveChallengeTake(
            takeNumber: takes.count + 1,
            targetLabel: target,
            transcript: spoken.isEmpty ? Self.comparisonPhrase : spoken,
            snapshots: snapshots,
            averageFrame: LiveChallengeTake.averagedFrame(of: snapshots)
        )
        takes.append(take)
    }

    /// Clears the 3-Take comparison deck.
    func clearTakes() {
        activeTakeTarget = nil
        activeTakeSnapshots.removeAll(keepingCapacity: true)
        activeTakeTranscript = ""
        takes.removeAll(keepingCapacity: true)
    }

    /// Closes an in-flight take if the deck is being restarted underneath it.
    private func finishActiveTakeIfNeeded() {
        guard activeTakeTarget != nil else { return }
        endTake()
    }

    // MARK: - Upgrade 7: recognition session rollover

    /// Arms one rollover per session and performs it in a silence gap.
    ///
    /// Apple ends `SFSpeechRecognizer` sessions at 60 s. Rather than letting the
    /// transcript die mid-demo, this moves to a fresh request without ever
    /// stopping `AVAudioEngine`, so the judge sees one continuous transcript.
    private func maybeRollOverRecognitionSession() {
        guard let sessionStartTime, !isUsingSimulation else { return }
        guard request != nil else { return }

        let elapsed = Date().timeIntervalSince(sessionStartTime)
        guard elapsed >= Self.rolloverEarliest, !hasArmedRollover else { return }

        let silenceFrames = Int((Self.rolloverSilenceDuration * 60).rounded())
        let isQuiet = consecutiveSilentFrames >= max(silenceFrames, 6)
        let isAtHardLimit = elapsed >= Self.rolloverHardLimit

        // Take the hand-over in a 350 ms silence gap, or unconditionally once the
        // session is close enough to Apple's 60 s cut-off that waiting would lose
        // words outright.
        guard isQuiet || isAtHardLimit else { return }
        guard Date().timeIntervalSince(lastRolloverTime) >= Self.rolloverCooldown else { return }
        guard let recognizer else { return }

        hasArmedRollover = true
        lastRolloverTime = Date()
        consecutiveSilentFrames = 0

        // Commit what the current session recognized, then swap in a fresh one.
        if !liveSegmentTranscript.isEmpty {
            committedTranscriptPrefix = Self.joined(committedTranscriptPrefix, liveSegmentTranscript)
        }
        liveSegmentTranscript = ""
        transcript = committedTranscriptPrefix

        let (oldRequest, oldTask) = takeRecognitionHandles()
        oldRequest?.endAudio()
        oldTask?.cancel()
        makeRecognitionRequest(with: recognizer)
    }

    /// Creates a fresh recognition request/task pair for a new session.
    private func makeRecognitionRequest(with recognizer: SFSpeechRecognizer) {
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        // Upgrade 7: sub-180 ms partial syllables — always ask for partials.
        newRequest.shouldReportPartialResults = true
        newRequest.taskHint = .dictation
        // The spec's rule: only claim on-device recognition once the device has
        // confirmed it actually supports it.
        newRequest.requiresOnDeviceRecognition = supportsOnDevice

        lock.lock()
        request = newRequest
        lock.unlock()

        sessionStartTime = Date()
        hasArmedRollover = false
        consecutiveSilentFrames = 0
        if listeningStartTime == nil { listeningStartTime = Date() }

        // Capture only `Sendable` values before hopping to the main actor.
        // `SFSpeechRecognitionResult` is not `Sendable`, so capturing it in a
        // `@Sendable` Task is a Swift 6 concurrency error.
        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let segments = result?.bestTranscription.segments.map(\.substring) ?? []
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor in
                self?.handleRecognition(
                    text: text,
                    segments: segments,
                    isFinal: isFinal,
                    failure: failure
                )
            }
        }

        if status != .live {
            status = .live
        }
    }

    /// Drops all rollover bookkeeping (not the recorded snapshots).
    private func resetRecognitionSessions() {
        committedTranscriptPrefix = ""
        liveSegmentTranscript = ""
        sessionStartTime = nil
        hasArmedRollover = false
        consecutiveSilentFrames = 0
        listeningStartTime = nil
        frameBuffer.removeAll(keepingCapacity: true)
        lastRecordedWord = ""
        recordedSegmentCount = 0
        transcript = ""
    }

    // MARK: - Recognition callbacks

    /// Applies a partial or final recognition result on the main actor.
    private func handleRecognition(
        text: String?,
        segments: [String],
        isFinal: Bool,
        failure: String?
    ) {
        if let text {
            liveSegmentTranscript = text
            // Upgrade 7: the visible transcript is always prefix + live session,
            // so a rollover is invisible to the speaker and the judge.
            transcript = Self.joined(committedTranscriptPrefix, liveSegmentTranscript)

            // Upgrade 3: package a snapshot for each newly recognized word.
            recordNewWords(from: segments, fallbackText: text)

            if isFinal {
                lastError = nil
            }
        }

        guard let failure else { return }
        lastError = failure

        // A recognition failure (offline model missing, interruption, etc.) must
        // never dead-end the judge: fall through to the simulated stream.
        if !isUsingSimulation {
            beginSimulated(
                reason: "On-device recognition stopped, so Keller's Chord is mirroring a realistic simulated voice instead.",
                profile: simulationProfile
            )
        }
    }

    /// Records a word snapshot for every word recognised since the last callback.
    ///
    /// `SFTranscription.segments` is cumulative and ordered, so only the tail past
    /// `recordedSegmentCount` is new. When a recognizer returns no segments the
    /// formatted string is split instead and the whole visible sentence is used.
    private func recordNewWords(from segments: [String], fallbackText: String) {
        if !segments.isEmpty {
            // A fresh session (or a re-segmented partial) may report fewer
            // segments than before; restart the cursor rather than skipping words.
            if segments.count < recordedSegmentCount { recordedSegmentCount = 0 }
            guard recordedSegmentCount < segments.count else { return }
            for index in recordedSegmentCount..<segments.count {
                recordWord(segments[index])
            }
            recordedSegmentCount = segments.count
            return
        }

        for word in fallbackText.split(separator: " ") {
            recordWord(String(word))
        }
    }

    // MARK: - Simulation engine

    /// Starts the ≈60 Hz synthetic cadence stream and a rolling transcript.
    private func beginSimulated(reason: String, profile: EmotionalProfile) {
        stopSimulation()
        simulationProfile = profile
        simulationStart = Date()
        listeningStartTime = Date()
        isUsingSimulation = true
        lastError = nil
        status = .simulated(reason: reason)

        let profile = simulationProfile
        // A gentle, believable viva sentence for this emotional contour.
        let fullSentence = Self.simulatedSentence(for: profile)
        let words = fullSentence.split(separator: " ").map(String.init)

        simulationTask = Task { [weak self] in
            var revealed = 0
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = self.simulationElapsed()

                // Reveal one word per ~0.5 s, then hold for the tail of the loop.
                let targetWordCount = min(words.count, Int(elapsed / 0.5) + 1)
                if targetWordCount != revealed {
                    revealed = targetWordCount
                    let partial = words.prefix(revealed).joined(separator: " ")
                    self.transcript = partial
                    // Upgrade 3 / Upgrade 10: the simulated stream feeds the same
                    // recorder, so Vocal Braille and the 3-Take deck work without a
                    // microphone.
                    self.recordWord(words[revealed - 1])
                }

                let frame = ProceduralVoiceSynthesizer.simulatedFrame(profile: profile, elapsed: elapsed)
                // `onSimulatedFrame` reaches `CoordinatorModel.apply(_:)`, which is
                // the single place that calls `ingestFrame`. Calling it here as
                // well fed every frame to the recorder twice.
                self.onSimulatedFrame?(frame)

                // Recycle the loop so the judge can watch cadence indefinitely.
                if elapsed > Double(words.count) * 0.5 + 2.0 {
                    self.simulationStart = Date()
                    self.listeningStartTime = Date()
                    self.lastRecordedWord = ""
                    revealed = 0
                    self.transcript = ""
                }

                try? await Task.sleep(nanoseconds: 16_666_667) // about 60 fps
            }
        }
    }

    /// Cancels the simulated stream, if any.
    private func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        simulationStart = nil
        isUsingSimulation = false
    }

    private func simulationElapsed() -> Double {
        guard let simulationStart else { return 0 }
        return Date().timeIntervalSince(simulationStart)
    }

    /// A believable transcript for each emotional contour.
    private static func simulatedSentence(for profile: EmotionalProfile) -> String {
        switch profile {
        case .warmRelief:
            return "I'm fine with that, and honestly I'm glad we talked it through."
        case .anxiousTremor:
            return "I'm fine with that, I just want to be sure I understood correctly."
        case .sharpSarcasm:
            return "I'm fine with that. Really. Absolutely fine with all of it."
        case .neutral:
            return "I'm fine with that."
        }
    }

    /// Joins a committed prefix with a live segment without doubling spaces.
    private static func joined(_ prefix: String, _ segment: String) -> String {
        let left = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }

    // MARK: - Permission helpers

    /// Requests speech-recognition authorization on the main actor.
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                continuation.resume(returning: authorizationStatus == .authorized)
            }
        }
    }

    #if os(iOS)
    /// Requests microphone authorization through the iOS 17+ API.
    private func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    #endif

    /// Atomically clears and returns the live recognition handles.
    private func takeRecognitionHandles() -> (SFSpeechAudioBufferRecognitionRequest?, SFSpeechRecognitionTask?) {
        lock.lock()
        let activeRequest = request
        let activeTask = task
        request = nil
        task = nil
        lock.unlock()
        return (activeRequest, activeTask)
    }
}
