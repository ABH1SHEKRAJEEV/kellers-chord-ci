import Foundation

// MARK: - Launch intent
//
// A Windows-only author cannot tap through the iPad Simulator, so CI has to be able
// to ask the app for any state it wants to photograph. Each flag below opens one
// exact state; without flags the app behaves exactly as a judge would see it.
//
// Supported flags:
//   --ci-act1-unlocked  Act I, chord already unlocked, living typography running
//   --ci-act2-chladni   Act II, 3-finger pad over a warm-relief Chladni field
//   --ci-act3-mirror    Act III, live prosody stream + ghost rail + braille strip
//   --ci-act3-duet      Act III, tabletop face-to-face duet (180 degree split)
//
// Unknown arguments are ignored, so the same binary is the shipping binary.

struct LaunchIntent: Sendable, Equatable {
    /// The act to open on.
    var act: ActStage
    /// Act I: skip the guessing game and unlock the chord immediately.
    var opensActOneUnlocked: Bool
    /// Act III: present the tabletop duet overlay straight away.
    var opensInDuet: Bool
    /// Act II: the prosody frame the tactile pad sculpts on launch.
    var actTwoFrame: ProsodyFrame?

    static let judge = LaunchIntent(
        act: .act1Blindspot,
        opensActOneUnlocked: false,
        opensInDuet: false,
        actTwoFrame: nil
    )

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> LaunchIntent {
        var intent = LaunchIntent.judge
        for argument in arguments {
            switch argument {
            case "--ci-act1-unlocked":
                intent.act = .act1Blindspot
                intent.opensActOneUnlocked = true
            case "--ci-act2-chladni":
                intent.act = .act2TactileDecoder
                intent.actTwoFrame = .preview(.warmRelief)
            case "--ci-act3-mirror":
                intent.act = .act3VocalMirror
            case "--ci-act3-duet":
                intent.act = .act3VocalMirror
                intent.opensInDuet = true
            default:
                continue
            }
        }
        return intent
    }
}

extension ProsodyFrame {
    /// A voiced frame that renders the given emotion's field without audio.
    ///
    /// Used only by the CI preview harness (`--ci-act2-chladni`), so the Chladni
    /// plate and the tactile pad can be photographed in a designed state instead of
    /// the silent baseline. The numbers are the mid-points of each emotion's band in
    /// the mapping matrix, not noise.
    static func preview(_ profile: EmotionalProfile) -> ProsodyFrame {
        switch profile {
        case .warmRelief:
            return ProsodyFrame(
                rmsAmplitude: 0.62,
                fundamentalPitchHz: 142,
                normalizedPitch: 0.34,
                spectralCentroid: 0.30,
                pitchJitter: 0.12,
                classifiedEmotion: .warmRelief,
                sibilanceEnergy: 0.24,
                terminalPitchSlope: 0.41
            )
        case .anxiousTremor:
            return ProsodyFrame(
                rmsAmplitude: 0.38,
                fundamentalPitchHz: 236,
                normalizedPitch: 0.72,
                spectralCentroid: 0.68,
                pitchJitter: 0.81,
                classifiedEmotion: .anxiousTremor,
                sibilanceEnergy: 0.33,
                terminalPitchSlope: 0.35
            )
        case .sharpSarcasm:
            return ProsodyFrame(
                rmsAmplitude: 0.54,
                fundamentalPitchHz: 188,
                normalizedPitch: 0.55,
                spectralCentroid: 0.86,
                pitchJitter: 0.44,
                classifiedEmotion: .sharpSarcasm,
                sibilanceEnergy: 0.71,
                terminalPitchSlope: -0.52
            )
        case .neutral:
            return .silent
        }
    }
}
