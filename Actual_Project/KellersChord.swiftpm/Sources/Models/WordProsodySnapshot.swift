import Foundation

/// An immutable, `Sendable` slice of prosody captured for a single spoken word.
///
/// Defined by `Everything2.md` Section 4.1. Act III's `OfflineSpeechManager`
/// packages the trailing ~350 ms of `ProsodyFrame` values into one of these
/// whenever a new word lands, which powers two Phase 2 features:
/// 1. **"Vocal Braille" time-scrubbing** — dragging a finger across a word
///    replays `dominantFrame` as a slow-motion tactile signature.
/// 2. **The 3-Take Live Stage Challenge deck** — three takes are compared
///    side-by-side through their `[WordProsodySnapshot]` arrays.
struct WordProsodySnapshot: Identifiable, Sendable, Equatable {
    /// Stable identity for `Identifiable` list rendering.
    let id: UUID
    /// The recognized word text.
    let word: String
    /// Seconds from the start of the take at which this word began.
    let timestampOffset: TimeInterval
    /// Spoken duration of the word in seconds.
    let duration: TimeInterval
    /// The ordered `ProsodyFrame` slice that produced this word.
    let frames: [ProsodyFrame]
    /// The single most representative frame (peak RMS, else the mean).
    let dominantFrame: ProsodyFrame
    /// `true` when the word carried a strong `4-8 kHz` consonant air-burst.
    let hasConsonantSpark: Bool
    /// The classified trailing intonation of the word.
    let terminalInflection: TerminalInflectionType

    /// Rising question tail vs. grounded statement drop vs. steady cadence.
    enum TerminalInflectionType: String, Sendable, Equatable {
        case steady = "Steady"
        case risingQuestion = "Rising Question"
        case groundedDrop = "Statement Drop"
    }

    init(
        id: UUID = UUID(),
        word: String,
        timestampOffset: TimeInterval,
        duration: TimeInterval,
        frames: [ProsodyFrame],
        dominantFrame: ProsodyFrame,
        hasConsonantSpark: Bool,
        terminalInflection: TerminalInflectionType
    ) {
        self.id = id
        self.word = word
        self.timestampOffset = timestampOffset
        self.duration = duration
        self.frames = frames
        self.dominantFrame = dominantFrame
        self.hasConsonantSpark = hasConsonantSpark
        self.terminalInflection = terminalInflection
    }
}

/// One of the three live emotional takes in the Act III "3-Take Live Stage
/// Challenge" deck. Defined by `Everything2.md` Section 4.1.
struct LiveChallengeTake: Identifiable, Sendable, Equatable {
    /// Stable identity for `Identifiable` deck rendering.
    let id: UUID
    /// 1-based take index shown on the comparison card.
    let takeNumber: Int
    /// The emotional target the speaker was asked to hit (e.g. "Warm Relief").
    let targetLabel: String
    /// The transcribed text of the take, if speech recognition produced one.
    let transcript: String
    /// The per-word prosody slices recorded during the take.
    let snapshots: [WordProsodySnapshot]
    /// The averaged frame across the whole take, for the comparison metrics.
    let averageFrame: ProsodyFrame

    init(
        id: UUID = UUID(),
        takeNumber: Int,
        targetLabel: String,
        transcript: String,
        snapshots: [WordProsodySnapshot],
        averageFrame: ProsodyFrame
    ) {
        self.id = id
        self.takeNumber = takeNumber
        self.targetLabel = targetLabel
        self.transcript = transcript
        self.snapshots = snapshots
        self.averageFrame = averageFrame
    }

    /// Mean of `frames` across every snapshot, falling back to `.silent`.
    /// Used to populate `averageFrame` when a take is finalized.
    static func averagedFrame(of snapshots: [WordProsodySnapshot]) -> ProsodyFrame {
        let all = snapshots.flatMap { $0.frames }
        guard !all.isEmpty else { return .silent }
        let count = Float(all.count)
        func mean(_ keyPath: KeyPath<ProsodyFrame, Float>) -> Float {
            all.reduce(0) { $0 + $1[keyPath: keyPath] } / count
        }
        return ProsodyFrame(
            rmsAmplitude: mean(\.rmsAmplitude),
            fundamentalPitchHz: mean(\.fundamentalPitchHz),
            normalizedPitch: mean(\.normalizedPitch),
            spectralCentroid: mean(\.spectralCentroid),
            pitchJitter: mean(\.pitchJitter),
            classifiedEmotion: all[all.count / 2].classifiedEmotion,
            sibilanceEnergy: mean(\.sibilanceEnergy),
            terminalPitchSlope: mean(\.terminalPitchSlope),
            ambientNoiseDB: mean(\.ambientNoiseDB)
        )
    }
}
