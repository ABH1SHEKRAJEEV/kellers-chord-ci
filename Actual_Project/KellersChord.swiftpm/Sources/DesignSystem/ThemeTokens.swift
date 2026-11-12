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

        /// Flat caption baseline / idle: a designed ink field, not black.
        ///
        /// v1 used three near-black stops for `neutral`, so an idle app (no audio
        /// yet) rendered as an empty black rectangle - the first thing the eye saw
        /// in the run-5 screenshots. The idle state now has a real field: deep ink
        /// blue into plum, so the app has an identity before anyone speaks.
        static let neutral: [Color] = [
            Color(hex: 0x1E2A44),   // Ink blue
            Color(hex: 0x2A1E3A),   // Plum ink
            Color(hex: 0x0B0D12)    // Obsidian floor
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

    // MARK: - Type scale (v2)
    //
    // The v1 scale was five sizes between 11 and 24 with `hero` at 44, which is
    // why every screen read as a form: nothing was ever *large*. The v2 scale has
    // one genuinely big size (`display`, 64-84 depending on width), one headline,
    // one body and one label. Headline-to-body ratio is ~3.8, close to the 4.3
    // median of the studied gallery sites, and the old 11pt tracked caps labels are
    // gone (uppercase + letterspacing at 11pt is the single most common generated
    // page tell).
    enum Text {
        /// The one big thing on each screen. Sized by the caller for the width.
        static func display(_ size: CGFloat = 64) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }
        /// Section headline.
        static let headline = Font.system(size: 30, weight: .semibold)
        /// Supporting sentence directly under a headline.
        static let subhead = Font.system(size: 19, weight: .regular)
        /// Running text. Full ink, never grey.
        static let body = Font.system(size: 17, weight: .regular)
        /// Secondary notes and control labels. Sentence case.
        static let label = Font.system(size: 14, weight: .medium)
        /// Numeric readouts that change in place.
        static let metric = Font.system(size: 13, weight: .medium, design: .monospaced)
        /// The wordmark.
        static let wordmark = Font.system(size: 15, weight: .bold)
    }

    // MARK: - Surfaces (tone steps, never lines)

    /// Three flat tone steps above obsidian. Surfaces are separated by a step in
    /// tone; the old build separated everything with 1 pt strokes, which is what
    /// made it read as a stack of wireframes rather than a designed surface.
    enum Surface {
        static let level0 = Color(hex: 0x08090C)
        static let level1 = Color(hex: 0x101319)
        static let level2 = Color(hex: 0x171B23)
        static let level3 = Color(hex: 0x1F242E)
    }

    /// The app's own colour, independent of emotion: ember on ink. Used for the
    /// wordmark, the primary action and the idle field, so the app has an
    /// identity before any audio exists (v1 showed nothing at all while idle).
    enum House {
        static let ember = Color(hex: 0xF59E0B)
        static let ink = Color(hex: 0x0E1116)
        static let paper = Color(hex: 0xF6F4EF)
        static let slate = Color(hex: 0x1B2130)
    }

    // MARK: - Typography scales

    enum Typography {
        /// The large living-typography stage in Acts I, II and III.
        ///
        /// Shares its family with `caption` so the Act I A/B is a pure prosody
        /// comparison. Emotion is carried by `ProsodyTextRenderer` (bloom, wave,
        /// shear) and `emphasisWeight(for:)` - not by the typeface.
        ///
        /// v2 removed `design: .rounded` from every style. The rounded system face
        /// is iOS's default "friendly app" voice: it made all three acts read as the
        /// same generic product, and it undercut the one place the app needs an
        /// editorial tone - the caption the whole project is about. SF with weight
        /// contrast and a larger scale does the same job with a real voice.
        static let hero = Font.system(size: 56, weight: .semibold)
        /// The sterile Act I baseline face.
        ///
        /// Deliberately the SAME family as `hero` with the same optical size, so the
        /// Stage 1 -> Stage 2 transition reads as *the prosody changing the text* and
        /// not as a typeface swap. The sterility comes from uniform weight, 70% white,
        /// and zero motion - never from a different font. (A monospaced face here
        /// would hand the viewer a second, unrelated variable and contaminate the
        /// app's single most important comparison.) Monospace is reserved for
        /// `metric`, where digits genuinely change in place.
        static let caption = Font.system(size: 56, weight: .regular)
        /// Section titles.
        static let title = Font.system(size: 28, weight: .semibold)
        /// Supporting body copy.
        static let body = Font.system(size: 17, weight: .regular)
        /// Control and badge labels.
        static let pill = Font.system(size: 13, weight: .semibold)
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
