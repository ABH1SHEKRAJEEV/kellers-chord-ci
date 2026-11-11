import Foundation

/// The four emotional prosody states Keller's Chord can render.
///
/// `neutral` is the prosody-stripped caption baseline. The other three are the
/// contours the DSP engine classifies from live acoustic features. The type is
/// intentionally `Sendable` and free of any UI import so the real-time CoreAudio
/// thread can construct it safely.
enum EmotionalProfile: String, CaseIterable, Sendable, Identifiable, Equatable {
    case neutral
    case warmRelief
    case anxiousTremor
    case sharpSarcasm

    var id: String { rawValue }

    /// Human-facing name used by Act I's emotion tags and by VoiceOver.
    var displayName: String {
        switch self {
        case .neutral: return "Flat Caption"
        case .warmRelief: return "Warm Relief"
        case .anxiousTremor: return "Quiet Anxiety"
        case .sharpSarcasm: return "Biting Sarcasm"
        }
    }

    /// One-line acoustic signature, surfaced as an accessibility value.
    var acousticSummary: String {
        switch self {
        case .neutral: return "No prosody data. Uniform weight, flat tone."
        case .warmRelief: return "Low spectral centroid, smooth falling pitch, steady volume."
        case .anxiousTremor: return "High pitch jitter, rising pitch, fluctuating volume."
        case .sharpSarcasm: return "High spectral centroid, abrupt volume spikes, steep pitch drop."
        }
    }

    /// The three emotions a judge can assign in Act I.
    static var actOneChoices: [EmotionalProfile] { [.warmRelief, .anxiousTremor, .sharpSarcasm] }

    /// Classifies a normalized prosody snapshot.
    ///
    /// Order is deliberate: tremor's instability wins first, then sarcasm's
    /// metallic centroid, then warm chest resonance, and only then `neutral`.
    static func classify(centroid: Float, jitter: Float, pitchSlope: Float, rms: Float) -> EmotionalProfile {
        if jitter > 0.45 { return .anxiousTremor }
        if centroid > 0.65 { return .sharpSarcasm }
        if centroid < 0.35, rms > 0.15 { return .warmRelief }
        if pitchSlope < -0.18, centroid < 0.50, rms > 0.15 { return .warmRelief }
        return .neutral
    }
}
