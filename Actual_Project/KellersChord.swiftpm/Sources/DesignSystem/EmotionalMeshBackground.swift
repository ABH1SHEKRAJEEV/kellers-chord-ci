import SwiftUI

/// The reactive emotional aura that sits behind every act.
///
/// A 3x3 `MeshGradient` whose nine vertices drift on a slow ambient clock and
/// migrate toward the active emotion's palette from `ThemeTokens.Palette` as
/// prosody energy rises. It is the third leg of the cross-modal stool: the same
/// `ProsodyFrame` that drives `ProsodyTextRenderer`'s glyph morphs and
/// `TactileHapticEngine`'s vibration also colors this backdrop, so a judge sees,
/// feels, and hears one coherent emotional state.
///
/// The mesh never competes with the type — it breathes at a low amplitude and a
/// slow cadence, guaranteeing the single clear focal point (the living sentence)
/// stays dominant. A base obsidian floor keeps the Apple-Design-Award dark
/// aesthetic intact on every act.
struct EmotionalMeshBackground: View {

    /// The prosody snapshot driving the aura's color and motion.
    var frame: ProsodyFrame
    /// Continuous seconds for the ambient drift clock.
    var elapsedTime: Double
    /// Accessibility Reduce Motion: freeze the drift, keep the color emotion.
    var reduceMotion: Bool
    /// Extra stillness multiplier the acts can dial up for calm screens.
    var intensityScale: Double

    /// The full environment, so colors can be resolved for the current
    /// appearance exactly the way SwiftUI will render them.
    @Environment(\.self) private var environment

    init(
        frame: ProsodyFrame,
        elapsedTime: Double,
        reduceMotion: Bool,
        intensityScale: Double = 1.0
    ) {
        self.frame = frame
        self.elapsedTime = elapsedTime
        self.reduceMotion = reduceMotion
        self.intensityScale = intensityScale
    }

    // MARK: - Blended palette

    /// The three emotion stops blended toward the baseline neutral at low energy,
    /// so a silent or unvoiced frame quietly rests on obsidian rather than
    /// shouting a saturated color the audio does not justify.
    private var blendedStops: (primary: Color, secondary: Color, tertiary: Color) {
        let palette = ThemeTokens.Palette.colors(for: frame.classifiedEmotion)
        let base = ThemeTokens.Palette.neutral

        // `ProsodyFrame` is deliberately `Float` (it is built on the CoreAudio
        // render thread), while SwiftUI color maths is `Double`, so the energy is
        // widened once here instead of at every use.
        let energy = Double(min(max(frame.rmsAmplitude, 0), 1))
        // v2: the field has a floor. v1 multiplied by 0.04 when unvoiced, which made
        // silence render as pure black - the whole app read as lifeless slate in the
        // run-5 screenshots. The base field now carries the emotion's colour at all
        // times, and audio only adds to it, so motion means "this is the voice".
        let base = 0.62
        let live = frame.isVoiced ? (0.20 + 0.80 * energy) : 0
        let mix = min((base + live * 0.70) * intensityScale, 1.0)

        func blend(_ a: Color, _ b: Color) -> Color {
            let lhs = a.resolve(in: environment)
            let rhs = b.resolve(in: environment)
            let m = Float(min(max(mix, 0), 1))
            return Color(
                .sRGB,
                red: Double(lhs.red * m + rhs.red * (1 - m)),
                green: Double(lhs.green * m + rhs.green * (1 - m)),
                blue: Double(lhs.blue * m + rhs.blue * (1 - m)),
                opacity: 1
            )
        }

        return (
            blend(palette[0], base[0]),
            blend(palette[1], base[1]),
            blend(palette[2], base[2])
        )
    }

    // MARK: - Body

    var body: some View {
        let stops = blendedStops
        ZStack {
            // Obsidian floor: the mesh only ever tints the top of it, never
            // replaces the deep-black canvas.
            ThemeTokens.obsidian

            // The plain 4-argument initializer is the one that exists on every
            // iOS 18 / macOS 15 SDK. `background:` is redundant anyway: this mesh
            // is drawn over the obsidian floor in the ZStack below.
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints,
                colors: meshColors(stops: stops)
            )

            // Vignette keeps the eye pulled to the centre stage.
            RadialGradient(
                colors: [.clear, ThemeTokens.obsidian.opacity(0.85)],
                center: .center,
                startRadius: 120,
                endRadius: 620
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .animation(ThemeTokens.Motion.ambience, value: frame.classifiedEmotion)
    }

    // MARK: - Mesh geometry

    /// The nine drifting vertices of the 3x3 mesh.
    ///
    /// The centre vertex is the emotional heart of the aura: it swells hottest
    /// and moves the most. Corner vertices stay pinned so the mesh always fills
    /// the frame, and edge midpoints sway gently on the ambient clock.
    private var meshPoints: [SIMD2<Float>] {
        // Drift amplitude: near-zero under Reduce Motion so the aura is static.
        let amplitude = reduceMotion ? 0.0 : 0.045 * intensityScale
        let t = elapsedTime

        // Centre bloom: how far the middle vertex is pulled toward the gaze.
        let bloom = reduceMotion
            ? 0.0
            : amplitude * 1.6 * (0.5 + 0.5 * sin(t * 0.6))

        /// One vertex's ambient sway in mesh space, sized as a `Double` so it can
        /// be summed with the `0...1` layout literals before conversion.
        func sway(_ phase: Double, _ axisScale: Double = 1.0) -> Double {
            sin(t * 0.55 + phase) * amplitude * axisScale
        }

        /// Packs a `(x, y)` pair into the `SIMD2<Float>` the mesh expects.
        func vertex(_ x: Double, _ y: Double) -> SIMD2<Float> {
            SIMD2<Float>(Float(x), Float(y))
        }

        return [
            vertex(0.00, 0.00),                                  // top-left (pinned)
            vertex(0.50 + sway(0.4, 0.6), 0.00),                 // top-mid
            vertex(1.00, 0.00),                                  // top-right (pinned)

            vertex(0.00, 0.50 + sway(1.1, 0.6)),                 // mid-left
            vertex(0.50 + bloom, 0.48 + sway(0.2, 0.7)),         // centre bloom
            vertex(1.00, 0.50 + sway(2.0, 0.6)),                 // mid-right

            vertex(0.00, 1.00),                                  // bottom-left (pinned)
            vertex(0.50 + sway(2.7, 0.6), 1.00),                 // bottom-mid
            vertex(1.00, 1.00)                                   // bottom-right (pinned)
        ]
    }

    /// The nine vertex colors.
    ///
    /// Primary emotion paints the centre and top row, secondary warms one
    /// diagonal, and the darkest stop grounds the bottom so the aura fades into
    /// the obsidian floor instead of ending on a hard edge.
    private func meshColors(stops: (primary: Color, secondary: Color, tertiary: Color)) -> [Color] {
        let dark = stops.tertiary
        let mid = stops.secondary
        let hot = stops.primary

        return [
            dark, mid, dark,          // top row
            mid,  hot, mid,           // middle row (hot centre)
            dark, dark, dark          // bottom row (grounds into obsidian)
        ]
    }
}
