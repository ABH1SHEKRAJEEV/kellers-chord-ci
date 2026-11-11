import SwiftUI

/// Per-glyph "living typography" shader for Keller's Chord.
///
/// Conforms to `SwiftUI.TextRenderer` (which itself inherits `Animatable`) and
/// morphs every glyph of the rendered sentence in real time from the active
/// `ProsodyFrame`. It is the visual twin of `TactileHapticEngine`: both are
/// driven by the very same frame, so a warm purr always accompanies warm
/// blooming type and a sarcastic snap always accompanies sheared, razor-edged
/// type.
///
/// Three layered transforms are applied per glyph, exactly per
/// `Everything.md` section 7.2:
/// 1. **Harmonic Warmth Bloom** — a blurred background pass when the centroid
///    is low and the voice is present.
/// 2. **Pitch Inflection Wave** — a vertical sine offset scaled by how far the
///    normalized pitch sits from centre.
/// 3. **Tremor & Sarcasm Shear** — a `CGAffineTransform` around the glyph's
///    centre combining vertical stretch and horizontal micro-jitter.
///
/// `Animatable` exposes `animatableData` so SwiftUI can interpolate between two
/// renderers when the frame changes, keeping motion buttery instead of stepped.
struct ProsodyTextRenderer: TextRenderer, Animatable {

    /// The prosody snapshot driving every transform.
    var frame: ProsodyFrame
    /// Seconds elapsed for the animation timeline (supplied by `TimelineView`).
    var elapsedTime: Double
    /// Honours the Accessibility Reduce Motion setting.
    var reduceMotion: Bool

    // MARK: - Animatable

    /// Interpolates the four continuous metrics so SwiftUI can tween frames.
    var animatableData: AnimatablePair<AnimatablePair<Float, Float>,
                              AnimatablePair<Float, Float>> {
        get {
            AnimatablePair(
                AnimatablePair(frame.rmsAmplitude, frame.normalizedPitch),
                AnimatablePair(frame.spectralCentroid, frame.pitchJitter)
            )
        }
        set {
            frame.rmsAmplitude = newValue.first.first
            frame.normalizedPitch = newValue.first.second
            frame.spectralCentroid = newValue.second.first
            frame.pitchJitter = newValue.second.second
        }
    }

    // MARK: - Derived emotion properties

    /// The emotion currently driving the per-glyph vocabulary.
    private var activeEmotion: EmotionalProfile { frame.classifiedEmotion }
    /// The clamped loudness, reused by the scale helpers.
    private var energyClamp: Float { min(max(frame.rmsAmplitude, 0), 1) }

    // MARK: - TextRenderer

    /// `TextRenderer` conformance requirement.
    ///
    /// Appendix B.3 deleted this as "unused" because no call site reads it — which
    /// was true, and also wrong: SwiftUI reads it, and the protocol requires it.
    /// It is now restored, and the comment says why so it is not deleted again.
    /// Vertical padding only, so the Consonant Spark diamonds drawn above the
    /// glyphs are not clipped by the render area.
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
    }

    /// Draws the layout glyph by glyph, applying the three prosody transforms.
    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        // A per-frame energy gate: below this the type stays crisp and steady.
        let energy = min(max(frame.rmsAmplitude, 0), 1)
        let centroid = min(max(frame.spectralCentroid, 0), 1)
        let jitter = min(max(frame.pitchJitter, 0), 1)
        let pitchOffset = Double(frame.normalizedPitch) - 0.5

        for line in layout {
            // Count the glyphs on this line so trailing-falloff and the line-
            // relative index are correct even for multi-line captions.
            var count = 0
            for run in line { count += run.count }
            let lineGlyphCount = max(count, 1)
            var index = 0

            // ── Phase 2 (Upgrade 12): terminal inflection tail ──
            // The final three glyphs of a line carry the sentence's intonation:
            // an upward baseline lift for a rising question tail, a grounded
            // downward settle for a statement drop. Computed once per line so the
            // three glyphs share one continuous curve instead of three steps.
            let tailLift = terminalTailLift()
            let tailStart = max(lineGlyphCount - 3, 0)

            for run in line {
                for glyph in run {
                    draw(
                        glyph: glyph,
                        index: index,
                        indexCount: lineGlyphCount,
                        energy: energy,
                        centroid: centroid,
                        jitter: jitter,
                        pitchOffset: pitchOffset,
                        tailLift: index >= tailStart ? tailLift : 0,
                        ctx: &ctx
                    )
                    index += 1
                }
            }
        }
    }

    // MARK: - Phase 2 typography layers (Everything2.md 4.4)

    /// The vertical baseline shift applied to the last three glyphs of a line.
    ///
    /// Rising question (`terminalPitchSlope > 0.28`) lifts the tail by up to
    /// `-8 pt`; a grounded statement drop (`< -0.25`) settles it by up to `+5 pt`;
    /// anything between reads as steady and gets no shift. The magnitude scales
    /// with how far past the threshold the slope is, so the gesture is proportional
    /// rather than binary.
    private func terminalTailLift() -> Double {
        let slope = Double(min(max(frame.terminalPitchSlope, -1), 1))
        if slope > 0.28 {
            let excess = (slope - 0.28) / 0.72     // 0...1 past the question threshold
            return -8.0 * min(max(excess, 0), 1)
        }
        if slope < -0.25 {
            let excess = (-0.25 - slope) / 0.75    // 0...1 past the drop threshold
            return 5.0 * min(max(excess, 0), 1)
        }
        return 0
    }

    /// Draws the Consonant Spark micro-diamond above one glyph.
    ///
    /// A crisp 4-point star 6 pt above the glyph, in Ice White (`#F8FAFC`),
    /// signalling that a high-frequency (`4-8 kHz`) consonant air-burst really
    /// landed. Unvoiced consonants (`S`, `SH`, `CH`, `T`, `K`) are otherwise
    /// invisible in every caption system, so this is the one cue that tells a deaf
    /// speaker their articulation was sharp and audible.
    ///
    /// **Placement policy (deliberate):** `Text.Layout.Glyph` is only guaranteed
    /// to expose `typographicBounds` across the iOS 18 SwiftUI surface, so this
    /// layer never asks which *letter* it is over. Instead it draws the spark above
    /// **every glyph of the line** while the `4-8 kHz` sibilance band is active,
    /// which is the honest reading of the acoustic data: the air-burst is a
    /// property of the *syllable being spoken right now*, not of a specific
    /// character. Capping the count keeps it a punctuation-like accent rather than
    /// a stripe.
    private func drawConsonantSpark(
        above rect: CGRect,
        sibilance: Float,
        ctx: inout GraphicsContext
    ) {
        guard sibilance > Self.sparkThreshold else { return }

        let strength = Double(min(max((sibilance - Self.sparkThreshold)
                                      / (1 - Self.sparkThreshold), 0), 1))
        // 3.0...5.0 pt across the spark band: small, precise, unmistakable.
        let radius = 3.0 + 2.0 * strength
        let center = CGPoint(x: rect.midX, y: rect.minY - Self.sparkRise)

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius * 0.62, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius * 0.62, y: center.y))
        path.closeSubpath()

        // A hairline bloom makes the spark read as light, not as a shape.
        var glow = ctx
        glow.opacity = 0.35 * strength
        glow.addFilter(.blur(radius: 2.0))
        glow.fill(path, with: .color(Self.sparkColor))

        ctx.fill(path, with: .color(Self.sparkColor.opacity(0.55 + 0.45 * strength)))
    }

    /// The Consonant Spark threshold, matching `ProsodyFrame.hasConsonantSpark`.
    private static let sparkThreshold: Float = 0.55
    /// Vertical gap between the glyph cap and the spark's centre.
    private static let sparkRise: CGFloat = 6
    /// One spark per this many glyphs, so the accent stays punctuating, not solid.
    private static let sparkDensity = 3
    /// Ice White (`#F8FAFC`) from `Everything2.md` Section 4.4.
    private static let sparkColor = Color(hex: 0xF8FAFC)

    // MARK: - Per-glyph pipeline

    /// Applies the three layered transforms to one glyph.
    private func draw(
        glyph: Text.Layout.Glyph,
        index: Int,
        indexCount: Int,
        energy: Float,
        centroid: Float,
        jitter: Float,
        pitchOffset: Double,
        tailLift: Double,
        ctx: inout GraphicsContext
    ) {
        let bounds = glyph.typographicBounds
        let rect = bounds.rect
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // ── Layer 2: Pitch Inflection Wave ──
        // Vertical sine offset scaled by how far pitch sits from centre.
        let waveOffset: Double
        if reduceMotion {
            // Reduce Motion: a gentle static lift proportional to pitch instead
            // of an oscillating wave.
            waveOffset = -pitchOffset * 6.0 + tailLift
        } else {
            waveOffset = -pitchOffset * 18.0
                * sin(Double(index) * 0.45 + elapsedTime * 4.0) + tailLift
        }

        // ── Layer 3: Tremor & Sarcasm Shear ──
        // Vertical stretch grows with loudness; horizontal jitter grows with
        // tremor but is disabled entirely under Reduce Motion.
        let verticalStretch = 1.0 + Double(energy) * 0.28
        let horizontalJitter: Double
        if reduceMotion {
            horizontalJitter = 0
        } else {
            horizontalJitter = Double(jitter) * 4.0
                * cos(elapsedTime * 42.0 + Double(index) * 1.7)
        }
        let shear = -0.18 * Double(centroid)

        // §7.1 Warm Empathy's "1.08x horizontal breathing scale".
        let hScale = horizontalScale

        // ── Layer 1: Harmonic Warmth Bloom (§7.2) ──
        // A blurred background copy, used only for genuinely warm, present audio.
        if centroid < 0.4, energy > 0.15 {
            var bloom = ctx
            bloom.opacity = Double(energy) * 0.6
            bloom.addFilter(.blur(radius: CGFloat(6 * (1 - Double(centroid)))))
            drawTransformed(
                glyph: glyph,
                center: center,
                waveOffset: waveOffset,
                verticalStretch: verticalStretch,
                horizontalScale: hScale,
                horizontalJitter: horizontalJitter,
                shear: shear,
                ctx: &bloom
            )
        }

        // ── Crisp foreground pass ──
        var foreground = ctx
        // §7.1 Anxious Hesitation: "fading trailing opacity" - each glyph fades
        // a little more than the one before it as tremor rises.
        if activeEmotion == .anxiousTremor {
            let falloff = 1.0 - 0.55 * Double(jitter) * trailingFraction(index: index, count: indexCount)
            foreground.opacity *= max(0.35, falloff)
        }
        drawTransformed(
            glyph: glyph,
            center: center,
            waveOffset: waveOffset,
            verticalStretch: verticalStretch,
            horizontalScale: hScale,
            horizontalJitter: horizontalJitter,
            shear: shear,
            ctx: &foreground
        )

        // ── Phase 2 (Upgrade 10): Consonant Spark micro-diamond ──
        // Drawn unfiltered on the parent context so the bloom pass cannot smear
        // it, and offset by the glyph's own pitch wave so it tracks the letter.
        // Density is capped: only every third glyph carries a spark, so a sibilant
        // burst reads as a scatter of punctuation-like accents rather than a solid
        // stripe across the sentence.
        if index % Self.sparkDensity == 0 {
            drawConsonantSpark(
                above: rect.offsetBy(dx: 0, dy: CGFloat(waveOffset)),
                sibilance: frame.sibilanceEnergy,
                ctx: &ctx
            )
        }
    }

    /// §7.1 Warm Empathy: the "1.08x horizontal breathing scale" that swells the
    /// whole sentence with chest warmth.
    private var horizontalScale: Double {
        guard activeEmotion == .warmRelief else { return 1.0 }
        let breath = reduceMotion ? 0.0 : 0.04 * sin(elapsedTime * 2.2)
        return 1.0 + Double(energyClamp) * 0.08 + breath
    }

    /// 0 at the first glyph, 1 at the last, for trailing-opacity falloff.
    private func trailingFraction(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(index) / Double(count - 1)
    }

    /// Draws one glyph with an affine transform anchored at its own centre.
    ///
    /// The transform combines vertical scale, a small horizontal breathing scale,
    /// a shear, and horizontal micro-jitter, then applies the vertical pitch wave
    /// as a translation.
    private func drawTransformed(
        glyph: Text.Layout.Glyph,
        center: CGPoint,
        waveOffset: Double,
        verticalStretch: Double,
        horizontalScale: Double,
        horizontalJitter: Double,
        shear: Double,
        ctx: inout GraphicsContext
    ) {
        var transform = ctx.transform
        // Move the origin to the glyph centre so scaling and shear pivot there.
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.scaledBy(x: CGFloat(horizontalScale), y: CGFloat(verticalStretch))
        // Shear the top of the glyph horizontally by `shear` per unit height.
        transform = transform.concatenating(
            CGAffineTransform(a: 1, b: 0, c: CGFloat(shear), d: 1, tx: 0, ty: 0)
        )
        transform = transform.translatedBy(x: CGFloat(horizontalJitter), y: CGFloat(waveOffset))
        transform = transform.translatedBy(x: -center.x, y: -center.y)

        var glyphContext = ctx
        glyphContext.transform = transform

        // Draw at the glyph's own layout origin; the transform handles motion.
        let origin = glyph.typographicBounds.origin
        glyphContext.draw(glyph, at: origin)
    }
}
