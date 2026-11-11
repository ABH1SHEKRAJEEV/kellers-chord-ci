import Foundation

/// An immutable, `Sendable` snapshot of one ≈16.6 ms (60 fps) prosody slice.
///
/// All continuous values are normalized to `0...1` except `fundamentalPitchHz`,
/// which carries the raw pitch so the UI can show real numbers to the user.
struct ProsodyFrame: Sendable, Equatable {
    /// Normalized vocal loudness in `0...1`.
    var rmsAmplitude: Float
    /// Raw fundamental frequency `F0` in Hz (nominally 80...400).
    var fundamentalPitchHz: Float
    /// `F0` mapped from 85 Hz...320 Hz into `0...1`.
    var normalizedPitch: Float
    /// Brightness / sharpness in `0...1`. Low is warm chest resonance, high is metallic.
    var spectralCentroid: Float
    /// Micro-tremor instability over a 12-frame rolling window, in `0...1`.
    var pitchJitter: Float
    /// The emotion classified from the four metrics above.
    var classifiedEmotion: EmotionalProfile

    // MARK: - Phase 2 additions (Everything2.md Section 4.1)
    // Every new member below is defaulted, so the Phase 1 memberwise initializer
    // call sites in Batches 1-7 continue to compile unchanged.

    /// High-frequency (`4 kHz - 8 kHz`) fricative / plosive consonant energy
    /// (`S`, `SH`, `CH`, `T`, `K`), normalized to `0...1`.
    var sibilanceEnergy: Float = 0.0
    /// Linear-regression slope of `F0` across the trailing ~350 ms (20 frames),
    /// normalized to `-1.0...1.0`. Rising questions read `> 0.28`, grounded
    /// statement drops read `< -0.25`.
    var terminalPitchSlope: Float = 0.0
    /// Calibrated room noise floor in decibels, for the Lombard volume governor.
    var ambientNoiseDB: Float = -50.0

    /// The flat caption baseline: no prosody at all.
    ///
    /// `normalizedPitch` sits at `0.5` rather than `0` because every downstream
    /// shader treats it as a *bipolar* value (`normalizedPitch - 0.5`): a `0`
    /// baseline would strand Live Mic mode at the very bottom of the pitch range
    /// and collapse the `EmotionalMeshBackground` gradient into its lowest stop.
    /// Centering it keeps a silent frame visually and tactually neutral.
    static let silent = ProsodyFrame(
        rmsAmplitude: 0,
        fundamentalPitchHz: 0,
        normalizedPitch: 0.5,
        spectralCentroid: 0.5,
        pitchJitter: 0,
        classifiedEmotion: .neutral
    )

    /// `true` when the frame carries audible, meaningful prosody.
    var isVoiced: Bool { rmsAmplitude > 0.05 }

    /// `true` when the high-frequency consonant air-burst (`4-8 kHz`) is strong
    /// enough to earn a Consonant Spark accent. Threshold from `Everything2.md`
    /// Section 4.4.
    var hasConsonantSpark: Bool { sibilanceEnergy > 0.55 }

    /// Classifies the trailing intonation from `terminalPitchSlope` using the
    /// thresholds defined in `Everything2.md` Section 4.2 (Upgrade 12).
    var terminalInflection: WordProsodySnapshot.TerminalInflectionType {
        if terminalPitchSlope > 0.28 { return .risingQuestion }
        if terminalPitchSlope < -0.25 { return .groundedDrop }
        return .steady
    }

    /// The comfortable vocal-loudness band for a room with the given noise floor.
    ///
    /// Single source of truth for the Lombard volume governor. `CadenceHorizonBar`,
    /// `ProsodyPassportSheet` and `TactileHapticEngine` all call this, so the bar,
    /// the passport ring and the double-tap nudge can never disagree about whether
    /// a given loudness is too quiet for this room.
    static func loudnessBand(ambientNoiseDB: Float) -> (low: Float, high: Float) {
        let decibels = ambientNoiseDB.isFinite ? ambientNoiseDB : -50
        let roomLift = min(max((decibels + 50) / 35, 0), 1) * 0.18
        return (0.24 + roomLift, min(0.72 + roomLift, 0.94))
    }

    /// Lerps every metric toward `other`. Used by the tactile pad so sculpted
    /// values glide instead of jumping between drag samples.
    func interpolated(toward other: ProsodyFrame, factor: Float) -> ProsodyFrame {
        let f = min(max(factor, 0), 1)
        func lerp(_ a: Float, _ b: Float) -> Float { a + (b - a) * f }
        return ProsodyFrame(
            rmsAmplitude: lerp(rmsAmplitude, other.rmsAmplitude),
            fundamentalPitchHz: lerp(fundamentalPitchHz, other.fundamentalPitchHz),
            normalizedPitch: lerp(normalizedPitch, other.normalizedPitch),
            spectralCentroid: lerp(spectralCentroid, other.spectralCentroid),
            pitchJitter: lerp(pitchJitter, other.pitchJitter),
            classifiedEmotion: other.classifiedEmotion,
            sibilanceEnergy: lerp(sibilanceEnergy, other.sibilanceEnergy),
            terminalPitchSlope: lerp(terminalPitchSlope, other.terminalPitchSlope),
            ambientNoiseDB: lerp(ambientNoiseDB, other.ambientNoiseDB)
        )
    }
}
