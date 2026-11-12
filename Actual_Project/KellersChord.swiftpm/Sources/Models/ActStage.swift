import Foundation

/// The three-act state machine that drives the 180-second judge choreography.
enum ActStage: Int, CaseIterable, Sendable, Identifiable, Equatable {
    case act1Blindspot
    case act2TactileDecoder
    case act3VocalMirror

    var id: Int { rawValue }

    /// Glassmorphic pill copy, exactly as specified in the choreography.
    var pillLabel: String {
        switch self {
        case .act1Blindspot: return "ACT I OF III • THE CAPTION BLINDSPOT"
        case .act2TactileDecoder: return "ACT II OF III • THE HELEN KELLER TACTILE DECODER"
        case .act3VocalMirror: return "ACT III OF III • THE VOCAL MIRROR"
        }
    }

    /// The act's real name, used in the wordmark bar.
    ///
    /// v1 navigated by `I` / `II` / `III`, which told a judge nothing and read as
    /// index numbering. The rail now names what each act is.
    var name: String {
        switch self {
        case .act1Blindspot: return "The Blindspot"
        case .act2TactileDecoder: return "Tactile Prosody"
        case .act3VocalMirror: return "The Vocal Mirror"
        }
    }

    /// The target timecode of the act inside the 3-minute experience.
    var timecode: String {
        switch self {
        case .act1Blindspot: return "0:00 – 0:45"
        case .act2TactileDecoder: return "0:45 – 1:45"
        case .act3VocalMirror: return "1:45 – 3:00"
        }
    }

    var next: ActStage? { ActStage(rawValue: rawValue + 1) }
    var previous: ActStage? { ActStage(rawValue: rawValue - 1) }

    /// Two-character label for the free-switching segmented act control.
    var shortLabel: String {
        switch self {
        case .act1Blindspot: return "I"
        case .act2TactileDecoder: return "II"
        case .act3VocalMirror: return "III"
        }
    }

    /// Fractional anchor of this act inside the 180-second run, for the progress pill.
    var progressAnchor: Double {
        switch self {
        case .act1Blindspot: return 0.0
        case .act2TactileDecoder: return 0.25
        case .act3VocalMirror: return 0.583
        }
    }

    /// Planned length of this act in seconds.
    ///
    /// Lives here, next to `progressAnchor`, so the choreography's timings have
    /// exactly one definition. `CoordinatorModel.progress` reads both instead of
    /// repeating the numbers.
    var durationSeconds: Double {
        switch self {
        case .act1Blindspot: return 45
        case .act2TactileDecoder: return 60
        case .act3VocalMirror: return 75
        }
    }

    /// The fraction of the whole run this act covers: start anchor to the next
    /// act's anchor (or 1.0 for the last act).
    var progressSpan: (start: Double, end: Double) {
        (progressAnchor, next?.progressAnchor ?? 1.0)
    }
}
