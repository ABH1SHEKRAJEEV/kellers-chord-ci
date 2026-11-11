import SwiftUI

/// The single source of truth for Keller's Chord's visual language.
///
/// Every color, spring, radius and type size used anywhere in the app resolves
/// through this namespace, so the Apple-Design-Award dark aesthetic stays
/// coherent and the 3-Act choreography never drifts between screens. All
/// palettes come verbatim from the Visual-Tactile Mapping Matrix in
/// `Everything.md` section 7.1.
enum ThemeTokens {

    // MARK: - Core surfaces

    /// The deep obsidian canvas every act floats on.
    static let obsidian = Color(hex: 0x08090C)

    // MARK: - Emotional palettes (Everything.md section 7.1)

    /// Four stops per emotion: primary, secondary, tertiary, and the aura base.
    /// Order is chosen so `EmotionalMeshBackground` can address them positionally.
    enum Palette {
        /// Warm Empathy / Relief: Golden Amber, Warm Coral, Deep Honey.
        static let warm: [Color] = [
            Color(hex: 0xF59E0B),   // Golden Amber
            Color(hex: 0xFB7185),   // Warm Coral
            Color(hex: 0x78350F)    // Deep Honey
        ]

        /// Anxious Hesitation / Tremor: Electric Cyan, Pale Lavender, Midnight Indigo.
        static let anxious: [Color] = [
            Color(hex: 0x38BDF8),   // Electric Cyan
            Color(hex: 0xA78BFA),   // Pale Lavender
            Color(hex: 0x1E1B4B)    // Midnight Indigo
        ]

        /// Sharp Sarcasm / Tension: Acid Crimson, Neon Magenta, Burnt Obsidian.
        static let sarcasm: [Color] = [
            Color(hex: 0xF43F5E),   // Acid Crimson
            Color(hex: 0xD946EF),   // Neon Magenta
            Color(hex: 0x270914)    // Burnt Obsidian
        ]

        /// Flat caption baseline: slate fading into obsidian.
        static let neutral: [Color] = [
            Color(hex: 0x16181D),
            Color(hex: 0x0E1014),
            Color(hex: 0x08090C)
        ]

        /// The ordered palette for an emotion.
        static func colors(for profile: EmotionalProfile) -> [Color] {
            switch profile {
            case .warmRelief: return warm
            case .anxiousTremor: return anxious
            case .sharpSarcasm: return sarcasm
            case .neutral: return neutral
            }
        }
    }

    /// The accent color per emotion, used for pills, badges and focus rings.
    static func accent(for profile: EmotionalProfile) -> Color {
        switch profile {
        case .warmRelief: return Color(hex: 0xF59E0B)
        case .anxiousTremor: return Color(hex: 0x38BDF8)
        case .sharpSarcasm: return Color(hex: 0xF43F5E)
        case .neutral: return Color(hex: 0xB9BDC7)
        }
    }

    // MARK: - Text

    /// Primary on-surface text: near-white, never pure white.
    static let textPrimary = Color(hex: 0xF5F6F8)
    /// The 70%-opacity white the caption blindspot deliberately uses.
    static let captionBaseline = Color.white.opacity(0.70)
    /// Secondary labels and numeric readouts.
    static let textSecondary = Color.white.opacity(0.55)

    // MARK: - Materials & strokes

    /// Glassmorphic pill fill.
    static let glassFill = Color.white.opacity(0.06)
    /// Glassmorphic pill hairline border.
    static let glassStroke = Color.white.opacity(0.14)

    // MARK: - Motion (fluid spring physics)

    enum Motion {
        /// The signature ease for act transitions and card reveals.
        static let act = Animation.spring(response: 0.55, dampingFraction: 0.82)
        /// Snappier spring for taps, toggles and focus changes.
        static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.74)
        /// Slow, breathy spring for the mesh backdrop's drift.
        static let ambience = Animation.spring(response: 1.20, dampingFraction: 0.90)
        /// The chunky pop used when the Tactile Prosody Engine unlocks.
        static let reveal = Animation.spring(response: 0.42, dampingFraction: 0.68)
    }

    // MARK: - Geometry

    enum Radius {
        static let card: CGFloat = 28
        static let pill: CGFloat = 22
        static let pad: CGFloat = 120
        static let chip: CGFloat = 14
    }

    enum Spacing {
        static let tight: CGFloat = 8
        static let regular: CGFloat = 16
        static let section: CGFloat = 28
        static let stage: CGFloat = 44
    }

    // MARK: - Typography scales

    enum Typography {
        /// The large living-typography stage in Acts I, II and III.
        ///
        /// Shares its family with `caption` so the Act I A/B is a pure prosody
        /// comparison. Emotion is carried by `ProsodyTextRenderer` (bloom, wave,
        /// shear) and `emphasisWeight(for:)` - not by the typeface.
        static let hero = Font.system(size: 44, weight: .semibold)
        /// The sterile Act I baseline face.
        ///
        /// Deliberately the SAME family as `hero` with the same optical size, so the
        /// Stage 1 -> Stage 2 transition reads as *the prosody changing the text* and
        /// not as a typeface swap. The sterility comes from uniform weight, 70% white,
        /// and zero motion - never from a different font. (A monospaced face here
        /// would hand the viewer a second, unrelated variable and contaminate the
        /// app's single most important comparison.) Monospace is reserved for
        /// `metric`, where digits genuinely change in place.
        static let caption = Font.system(size: 44, weight: .regular)
        /// Section titles.
        static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
        /// Supporting body copy.
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        /// The tiny act pill / badge label.
        static let pill = Font.system(size: 11, weight: .bold, design: .rounded)
        /// Numeric metric readouts.
        static let metric = Font.system(size: 13, weight: .medium, design: .monospaced)
    }

    // MARK: - Emphasis weights driven by prosody

    /// A font weight that leans heavier as prosody energy rises, so Reduce Motion
    /// users still perceive emotion through type weight alone.
    static func emphasisWeight(for frame: ProsodyFrame) -> Font.Weight {
        let energy = min(max(frame.rmsAmplitude, 0), 1)
        switch frame.classifiedEmotion {
        case .neutral: return .regular
        case .warmRelief: return energy > 0.5 ? .semibold : .medium
        case .anxiousTremor: return .medium
        case .sharpSarcasm: return energy > 0.4 ? .heavy : .bold
        }
    }
}

// MARK: - Hex convenience

extension Color {
    /// Builds a `Color` from a packed `0xRRGGBB` value, matching the hex literals
    /// used throughout `Everything.md`.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
