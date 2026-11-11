import Foundation

#if canImport(CoreHaptics)
import CoreHaptics
#endif

#if os(macOS)
import AppKit
#endif

/// Translates `ProsodyFrame` acoustics into touchable vibration.
///
/// Three platforms are covered by one API surface:
/// * **iOS / iPadOS** — a `CHHapticEngine` playing continuous `CHHapticAdvanced-
///   PatternPlayer`s modulated live from the frame metrics, plus transient hits
///   for sarcasm snaps and the anxious 6.5 Hz heartbeat.
/// * **macOS** — `NSHapticFeedbackManager.defaultPerformer` `.levelChange` taps
///   so a MacBook Force Touch trackpad physically flutters during emotional
///   peaks. macOS has no continuous haptics, so the engine synthesizes a stream
///   of throttled discrete taps whose density scales with `rmsAmplitude`.
/// * **Fallback** — a no-op that keeps the whole app compiling and running on
///   hardware without haptics, reporting unavailability instead of crashing.
///
/// Haptics also carry Act III's 130 WPM pacing pulse, i.e. the calm viva cadence
/// the speaker can feel while rehearsing aloud.
///
/// Phase 2 (Batch 9) adds four more tactile vocabularies on top of the Phase 1
/// surface, all additive:
///
/// * **Consonant Spark** (`4-8 kHz`, `sibilanceEnergy > 0.55`) — an 8 ms crisp
///   index-finger tick marking a sharp `S`/`SH`/`T`/`K` air-burst.
/// * **Terminal inflection glide** — a two-step upward glide for a rising
///   question tail, and a heavier single settle for a grounded statement drop.
/// * **Lombard room-volume nudge** — a double-tap when the speaker is too quiet
///   or too loud *for the calibrated room*, so loudness is judged in context.
/// * **Vocal Braille slow-motion scrub** — replays one word's prosody as a
///   slowed tactile signature as the finger drags across it.
@MainActor
final class TactileHapticEngine {

    /// Master switch, bound to the Act II / Act III haptic toggle.
    var isEnabled = true
    /// Act III's tactile pacing pulse (Calm Viva Cadence, 130 WPM).
    ///
    /// Setting this true starts the engine's own 130 WPM heartbeat; setting it
    /// false stops it. `CadenceHorizonBar` only needs to bind a toggle to it.
    var isPacingEnabled = false {
        didSet {
            guard isPacingEnabled != oldValue else { return }
            if isPacingEnabled { startPacing() } else { stopPacing() }
        }
    }
    /// `true` only when the current device actually produced a haptic engine.
    private(set) var isAvailable = false
    /// Last recoverable failure, surfaced as an accessibility value.
    private(set) var lastError: String?

    // MARK: - Phase 2 switches (Batch 9)
    // Each feature is individually defaulted-on and independently disablable, so
    // a view can mute one vocabulary without touching the others.

    /// Consonant Spark ticks (Upgrade 10). Defaulted on.
    var isConsonantSparkEnabled = true
    /// Terminal question / statement inflection glide (Upgrade 12). Defaulted on.
    var isInflectionGlideEnabled = true
    /// Lombard room-aware volume nudge (Upgrade 11). Defaulted on.
    var isLombardNudgeEnabled = true

    // MARK: - Tuning constants

    /// The current emotional signature, after light hysteresis, so the tactile
    /// texture never flickers between profiles on a single noisy frame.
    private var activeProfile: EmotionalProfile = .neutral

    /// Continuous intensity target and its smoothed value (0...1).
    private var smoothedIntensity: Float = 0
    /// Continuous sharpness target and its smoothed value (0...1).
    private var smoothedSharpness: Float = 0.15

    /// Exponential smoothing so the purr breathes instead of stepping.
    private static let intensitySmoothing: Float = 0.18
    private static let sharpnessSmoothing: Float = 0.14

    /// Minimum gap between two discrete macOS taps (≈28 Hz max flutter rate).
    private static let macTapInterval: TimeInterval = 1.0 / 28.0
    private var lastMacTapTime: Date = .distantPast

    /// 6.5 Hz anxious tremor heartbeat.
    private static let tremorInterval: TimeInterval = 1.0 / 6.5

    /// 130 words per minute -> one calm pacing beat every 60/130 s.
    private static let pacingInterval: TimeInterval = 60.0 / 130.0

    // MARK: Phase 2 timing constants (Batch 9)

    /// A Consonant Spark must not repeat faster than this (~80 ms), or a run of
    /// sibilants would read as one long buzz instead of distinct ticks.
    private static let sparkInterval: TimeInterval = 1.0 / 12.0
    /// The terminal inflection glide fires at most this often.
    private static let inflectionInterval: TimeInterval = 0.5
    /// The Lombard nudge fires at most this often; it is coaching, not nagging.
    private static let lombardInterval: TimeInterval = 2.5
    /// The delay between the two halves of a Lombard double-tap.
    private static let lombardDoubleTapGap: TimeInterval = 0.12
    /// Delay before the second, higher step of a rising-question glide.
    private static let questionGlideGap: TimeInterval = 0.075
    /// One Braille scrub step; 8 steps read a word back at "slow motion".
    private static let brailleStepInterval: TimeInterval = 0.055
    /// The Braille signature plays at most this many steps per word.
    private static let brailleStepCount = 8

    private var lastSparkTime: Date = .distantPast
    private var lastInflectionTime: Date = .distantPast
    private var lastLombardTime: Date = .distantPast
    private var brailleTask: Task<Void, Never>?

    // MARK: - Platform state

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var purrPlayer: CHHapticAdvancedPatternPlayer?
    private var lastTremorFire: Date = .distantPast
    #endif

    /// Drives the Act III 130 WPM cadence heartbeat. Cross-platform, so it lives
    /// outside the Core Haptics block.
    private var pacingTimer: Timer?

    // MARK: - Lifecycle

    /// Starts the platform haptic engine. Safe to call repeatedly; re-arms after
    /// the system stops the engine (backgrounding, audio interruption).
    func prepare() {
        #if canImport(CoreHaptics)
        prepareCoreHaptics()
        #elseif os(macOS)
        isAvailable = NSHapticFeedbackManager.defaultPerformer.canPerform()
        #else
        isAvailable = false
        #endif
    }

    /// Stops every in-flight haptic and releases the engine.
    func stop() {
        stopPacing()
        cancelBrailleScrub()
        #if canImport(CoreHaptics)
        try? purrPlayer?.stop(atTime: CHHapticTimeImmediate)
        purrPlayer = nil
        engine?.stop()
        #endif
        smoothedIntensity = 0
        activeProfile = .neutral
    }

    // MARK: - Act III pacing (Calm Viva Cadence, 130 WPM)

    private func startPacing() {
        stopPacing()
        let timer = Timer(timeInterval: Self.pacingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pulseForPacingPulse() }
        }
        // Common mode keeps the beat alive during scroll gestures and tracking.
        RunLoop.main.add(timer, forMode: .common)
        pacingTimer = timer
    }

    private func stopPacing() {
        pacingTimer?.invalidate()
        pacingTimer = nil
    }

    // MARK: - Per-frame rendering

    /// Maps one prosody frame onto the current tactile texture.
    ///
    /// Called at ≈60 Hz from the coordinator's `onFrame` handler. Continuous
    /// parameters are updated in place (no re-allocation), and discrete events
    /// (sarcasm snaps, anxious heartbeat) are rate-limited per profile.
    func render(_ frame: ProsodyFrame) {
        guard isEnabled else { return }

        updateProfile(with: frame)

        // Spec mapping (Section 7.1):
        //   warm relief   -> soft warm purr      intensity 0.55, sharpness 0.15
        //   anxious       -> 6.5 Hz heartbeat    intensity 0.45, sharpness 0.50
        //   sharp sarcasm -> staccato snap       intensity 0.90, sharpness 0.95
        let target = Self.continuousTarget(for: activeProfile, frame: frame)
        smoothedIntensity += Self.intensitySmoothing * (target.intensity - smoothedIntensity)
        smoothedSharpness += Self.sharpnessSmoothing * (target.sharpness - smoothedSharpness)

        #if canImport(CoreHaptics)
        updatePurr(intensity: smoothedIntensity, sharpness: smoothedSharpness)
        handleDiscreteEvents(profile: activeProfile, frame: frame)
        #elseif os(macOS)
        driveMacTrackpad(frame: frame)
        #endif

        // Phase 2 vocabularies, shared by every platform.
        handleConsonantSpark(frame)
        handleInflectionGlide(frame)
        handleLombardNudge(frame)
    }

    /// Fires one discrete pacing beat on the engine's own 130 WPM schedule, so
    /// the speaker feels a calm, confident viva cadence. Public so
    /// `CadenceHorizonBar` can flash its pulse indicator in lockstep.
    func pulseForPacingPulse() {
        guard isEnabled, isPacingEnabled else { return }
        #if canImport(CoreHaptics)
        playTransient(intensity: 0.4, sharpness: 0.2)
        #elseif os(macOS)
        performMacFeedback()
        #endif
    }

    // MARK: - Upgrade 10: Consonant Spark tick (4-8 kHz)

    /// An 8 ms crisp tick on the index finger whenever a sharp fricative or
    /// plosive air-burst lands, giving unvoiced consonants a tactile presence that
    /// the low-frequency purr can never carry.
    private func handleConsonantSpark(_ frame: ProsodyFrame) {
        guard isConsonantSparkEnabled else { return }
        guard frame.hasConsonantSpark else { return }

        let now = Date()
        guard now.timeIntervalSince(lastSparkTime) >= Self.sparkInterval else { return }
        lastSparkTime = now

        // Louder sibilance reads as a harder tick: 0.42...0.85, sharpness 0.78.
        let strength = min(max(frame.sibilanceEnergy, 0), 1)
        let intensity = 0.42 + 0.43 * strength
        #if canImport(CoreHaptics)
        playTransient(intensity: intensity, sharpness: 0.78)
        #elseif os(macOS)
        performMacFeedback(crisp: true)
        #endif
    }

    // MARK: - Upgrade 12: terminal inflection glide

    /// Two-step upward glide for a rising question tail; one heavier settle for a
    /// grounded statement drop. The direction of a sentence ending is one of the
    /// hardest prosodic cues to lip-read, so it gets its own vocabulary.
    private func handleInflectionGlide(_ frame: ProsodyFrame) {
        guard isInflectionGlideEnabled else { return }
        guard frame.isVoiced else { return }

        let inflection = frame.terminalInflection
        guard inflection != .steady else { return }

        let now = Date()
        guard now.timeIntervalSince(lastInflectionTime) >= Self.inflectionInterval else { return }
        lastInflectionTime = now

        switch inflection {
        case .risingQuestion:
            // Light then higher: a physical arrow pointing up.
            emitTransient(intensity: 0.35, sharpness: 0.45)
            scheduleTransient(
                after: Self.questionGlideGap,
                intensity: 0.62,
                sharpness: 0.60
            )
        case .groundedDrop:
            // A single soft, heavy landing: a physical full stop.
            emitTransient(intensity: 0.70, sharpness: 0.30)
        case .steady:
            break
        }
    }

    // MARK: - Upgrade 11: Lombard room-aware volume nudge

    /// A double-tap when the speaker's loudness does not match the calibrated room.
    ///
    /// The Lombard effect is why people shout in a noisy hall and whisper in a
    /// library; a deaf speaker cannot hear the room, so the device tells them with
    /// two quick taps whether to project or soften.
    private func handleLombardNudge(_ frame: ProsodyFrame) {
        guard isLombardNudgeEnabled else { return }
        guard frame.isVoiced else { return }

        let ambient = frame.ambientNoiseDB
        // One shared definition of the room-aware band, so the nudge can never
        // disagree with the Cadence Horizon bar or the Prosody Passport ring.
        let band = ProsodyFrame.loudnessBand(ambientNoiseDB: ambient)

        let loudness = frame.rmsAmplitude
        let isTooQuiet = loudness < band.low
        let isTooLoud = loudness > band.high
        guard isTooQuiet || isTooLoud else { return }

        let now = Date()
        guard now.timeIntervalSince(lastLombardTime) >= Self.lombardInterval else { return }
        lastLombardTime = now

        // Too quiet -> two soft rising taps ("speak up"). Too loud -> two firm
        // flat taps ("ease off"), so direction is distinguishable in the hand.
        if isTooQuiet {
            emitTransient(intensity: 0.30, sharpness: 0.25)
            scheduleTransient(after: Self.lombardDoubleTapGap, intensity: 0.45, sharpness: 0.35)
        } else {
            emitTransient(intensity: 0.75, sharpness: 0.85)
            scheduleTransient(after: Self.lombardDoubleTapGap, intensity: 0.75, sharpness: 0.85)
        }
    }

    // MARK: - Upgrade 3/4: Vocal Braille slow-motion scrub playback

    /// Replays one word's prosody in slow motion under the fingertip.
    ///
    /// Called by Act III when the user drags across a word. The word's `frames`
    /// are stepped through at ≈18 Hz rather than 60 Hz, so a 350 ms syllable is
    /// stretched to roughly half a second — long enough to read as a shape rather
    /// than a blur.
    func playBrailleScrub(for snapshot: WordProsodySnapshot) {
        guard isEnabled else { return }
        cancelBrailleScrub()

        let frames = brailleSteps(for: snapshot)
        guard !frames.isEmpty else { return }

        brailleTask = Task { [weak self] in
            for frame in frames {
                if Task.isCancelled { return }
                guard let self else { return }
                self.emitBrailleStep(frame)
                try? await Task.sleep(nanoseconds: UInt64(Self.brailleStepInterval * 1_000_000_000))
            }
        }
    }

    /// Cancels an in-flight Braille scrub (finger lifted, or word changed).
    func cancelBrailleScrub() {
        brailleTask?.cancel()
        brailleTask = nil
    }

    /// Downsamples a word's frame slice to at most `brailleStepCount` steps,
    /// always keeping the first, peak and last frames so the contour's shape
    /// survives the reduction.
    private func brailleSteps(for snapshot: WordProsodySnapshot) -> [ProsodyFrame] {
        let frames = snapshot.frames
        guard frames.count > Self.brailleStepCount else {
            return frames.isEmpty ? [snapshot.dominantFrame] : frames
        }
        let stride = Double(frames.count - 1) / Double(Self.brailleStepCount - 1)
        var steps: [ProsodyFrame] = []
        steps.reserveCapacity(Self.brailleStepCount)
        for index in 0..<Self.brailleStepCount {
            let position = min(Int((Double(index) * stride).rounded()), frames.count - 1)
            steps.append(frames[position])
        }
        return steps
    }

    /// One tactile step of a Braille scrub: intensity from loudness, sharpness
    /// from brightness, plus a spark tick when the word carries a consonant.
    private func emitBrailleStep(_ frame: ProsodyFrame) {
        let loudness = min(max(frame.rmsAmplitude, 0), 1)
        let brightness = min(max(frame.spectralCentroid, 0), 1)
        let intensity = min(max(0.16 + 0.52 * loudness, 0.10), 0.92)
        let sharpness = min(max(0.12 + 0.72 * brightness, 0.05), 0.95)
        emitTransient(intensity: intensity, sharpness: sharpness)

        if isConsonantSparkEnabled, frame.hasConsonantSpark {
            emitTransient(intensity: 0.55, sharpness: 0.88)
        }
    }

    // MARK: - Profile hysteresis

    /// Switches the tactile texture only once a contour is unambiguous, so a
    /// single jittery frame cannot flip the whole haptic language mid-sentence.
    private func updateProfile(with frame: ProsodyFrame) {
        guard frame.isVoiced else {
            activeProfile = .neutral
            return
        }
        switch frame.classifiedEmotion {
        case .neutral:
            // Voiced but unclassifiable: hold the last expressive profile so the
            // purr decays smoothly instead of snapping off mid-sentence.
            break
        case .warmRelief, .anxiousTremor, .sharpSarcasm:
            activeProfile = frame.classifiedEmotion
        }
    }

    /// The continuous (intensity, sharpness) target for a profile, nudged by the
    /// frame so louder/strainier speech feels stronger within a profile.
    private static func continuousTarget(
        for profile: EmotionalProfile,
        frame: ProsodyFrame
    ) -> (intensity: Float, sharpness: Float) {
        let loudness = min(max(frame.rmsAmplitude, 0), 1)
        switch profile {
        case .neutral:
            return (0.12 + 0.10 * loudness, 0.30)
        case .warmRelief:
            // Warm, low-frequency purr that swells slightly with chest resonance.
            let warmth = 1 - min(max(frame.spectralCentroid, 0), 1)
            return (min(0.55 + 0.20 * loudness * warmth, 1), 0.15)
        case .anxiousTremor:
            let jitter = min(max(frame.pitchJitter, 0), 1)
            return (min(0.40 + 0.25 * jitter, 1), 0.50)
        case .sharpSarcasm:
            let brightness = min(max(frame.spectralCentroid, 0), 1)
            return (min(0.70 + 0.30 * brightness, 1), 0.92)
        }
    }

    // MARK: - Deferred one-shot helpers

    /// Schedules a single transient `delay` seconds from now.
    ///
    /// Used by the two-step question glide and the Lombard double-tap. The task is
    /// fire-and-forget and cannot outlive the engine dangerously: it only calls a
    /// `@MainActor` transient, which is itself a no-op when haptics are
    /// unavailable.
    private func scheduleTransient(after delay: TimeInterval, intensity: Float, sharpness: Float) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            self.emitTransient(intensity: intensity, sharpness: sharpness)
        }
    }

    /// Plays a transient on whichever platform is available.
    private func emitTransient(intensity: Float, sharpness: Float) {
        guard isEnabled else { return }
        #if canImport(CoreHaptics)
        playTransient(intensity: intensity, sharpness: sharpness)
        #elseif os(macOS)
        performMacFeedback(crisp: sharpness > 0.6)
        #endif
    }

    #if canImport(CoreHaptics)

    // MARK: - CoreHaptics (iOS / iPadOS)

    /// Boots the haptic engine and its auto-recovery handlers.
    private func prepareCoreHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            isAvailable = false
            lastError = "This device does not support Core Haptics."
            return
        }
        do {
            let created = try CHHapticEngine()
            created.playsHapticsOnly = true
            // Let the system resume us after a call, Siri, or backgrounding.
            created.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.isAvailable = false }
            }
            created.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.engine?.start()
                    self?.isAvailable = true
                }
            }
            try created.start()
            engine = created
            isAvailable = true
            lastError = nil
        } catch {
            isAvailable = false
            lastError = "Core Haptics engine failed to start: \(error.localizedDescription)"
        }
    }

    /// Starts (or re-targets) the continuous purr that carries warm relief and
    /// the low-frequency foundation of every other profile.
    private func updatePurr(intensity: Float, sharpness: Float) {
        guard isAvailable, let engine else { return }
        guard intensity > 0.02 else {
            try? purrPlayer?.stop(atTime: CHHapticTimeImmediate)
            purrPlayer = nil
            return
        }

        let clampedIntensity = min(max(intensity, 0.02), 1)
        let clampedSharpness = min(max(sharpness, 0), 1)

        // Rebuild the pattern whenever sharpness shifts materially: player
        // parameters handle intensity, but sharpness is baked into the event.
        if purrPlayer == nil || abs(clampedSharpness - lastPurrSharpness) > 0.08 {
            lastPurrSharpness = clampedSharpness
            purrPlayer = makePurrPlayer(engine: engine, sharpness: clampedSharpness)
        }

        let intensityParameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: clampedIntensity,
            relativeTime: 0
        )
        try? purrPlayer?.sendParameters([intensityParameter], atTime: CHHapticTimeImmediate)
    }

    /// Builds the continuous player: a slow swelled event whose sharpness gives
    /// it either a soft purr or a bright buzz character.
    private func makePurrPlayer(engine: CHHapticEngine, sharpness: Float) -> CHHapticAdvancedPatternPlayer? {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: 1.0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            // Loop forever; `render(_:)` re-targets intensity each frame.
            player.loopEnabled = true
            try? purrPlayer?.stop(atTime: CHHapticTimeImmediate)
            try player.start(atTime: CHHapticTimeImmediate)
            return player
        } catch {
            lastError = "Continuous haptic player could not be created: \(error.localizedDescription)"
            return nil
        }
    }

    /// The sharpness the current purr player was built with.
    private var lastPurrSharpness: Float = -1

    /// Fires the profile-specific discrete hits.
    private func handleDiscreteEvents(profile: EmotionalProfile, frame: ProsodyFrame) {
        let now = Date()
        switch profile {
        case .anxiousTremor:
            // A 6.5 Hz heartbeat that the judge can physically feel.
            if now.timeIntervalSince(lastTremorFire) >= Self.tremorInterval {
                lastTremorFire = now
                let jitter = min(max(frame.pitchJitter, 0), 1)
                playTransient(intensity: 0.45 + 0.25 * jitter, sharpness: 0.50)
            }
        case .sharpSarcasm:
            // A staccato snap on each abrupt volume spike (the "FINE" moment).
            if frame.rmsAmplitude > 0.55,
               now.timeIntervalSince(lastTremorFire) >= 0.12 {
                lastTremorFire = now
                playTransient(intensity: 0.90, sharpness: 0.95)
            }
        case .warmRelief, .neutral:
            break
        }
    }

    /// Plays a single transient hit.
    private func playTransient(intensity: Float, sharpness: Float) {
        guard isAvailable, let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(max(intensity, 0), 1)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: min(max(sharpness, 0), 1))
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            lastError = "Transient haptic could not be played: \(error.localizedDescription)"
        }
    }

    #endif

    #if os(macOS)

    // MARK: - macOS Force Touch trackpad

    /// macOS has no continuous haptics, so the engine renders a stream of
    /// `.levelChange` taps whose rate tracks vocal effort. The throttle keeps the
    /// flutter at a comfortable maximum, and `.alignment` vs `.levelChange`
    /// distinguishes the two sharp profiles from the warm ones.
    private func driveMacTrackpad(frame: ProsodyFrame) {
        guard isAvailable else { return }
        guard frame.isVoiced else { return }

        let rate: TimeInterval
        switch activeProfile {
        case .warmRelief: rate = 1.0 / 12.0    // slow, warm pulsing
        case .anxiousTremor: rate = 1.0 / 22.0 // nervous flutter
        case .sharpSarcasm: rate = 1.0 / 28.0  // fastest snaps
        case .neutral: rate = 1.0 / 8.0
        }

        let now = Date()
        guard now.timeIntervalSince(lastMacTapTime) >= max(rate, Self.macTapInterval) else { return }
        lastMacTapTime = now
        performMacFeedback(crisp: activeProfile == .sharpSarcasm)
    }

    /// A single macOS tap. Sarcasm gets the crisper alignment tap so the two
    /// emotional extremes feel physically distinct.
    private func performMacFeedback(crisp: Bool = false) {
        guard isAvailable else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            crisp ? .alignment : .levelChange,
            performanceTime: .now
        )
    }

    #endif
}
