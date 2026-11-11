import SwiftUI

/// A 60 fps pure-Swift cymatic standing-wave field, drawn under the fingertips in
/// Act II's Helen Keller sensory pad.
///
/// Real acoustic plates do not vibrate uniformly: a driven plate settles into
/// *standing waves* whose **nodal lines** are the places that stay still while
/// everything else moves. Press a fingertip to a Chladni plate and the sand
/// migrates to exactly those still lines, drawing the shape of the sound. This
/// canvas reproduces that geometry so a deaf speaker can *see* the harmonic
/// fingerprint of a voice and then feel the same field through haptics.
///
/// The plate equation is Chladni's biharmonic solution, band-limited to the modes
/// a vocal tract can actually excite (from `Everything2.md` Section 4.4):
///
///     C(x, y) = cos(n π x)·cos(m π y) − cos(m π x)·cos(n π y)
///
/// with
///
///     n = 1.5 + normalizedPitch × 4.5
///     m = 2.0 + spectralCentroid × 5.0
///
/// So pitch raises the number of nodal *rows* and warmth raises the number of
/// nodal *columns*: a low warm voice draws a few slow curves, a bright strained
/// one draws a fine metallic grid. Particles whose `|C| < 0.28` sit on the nodal
/// lines and glow brightest.
///
/// Everything is drawn inside `Canvas` with `TimelineView(.animation(...))`, the
/// same 60 fps clock rule the rest of the app obeys (no leaking `Timer.publish`).
/// Under Reduce Motion the field freezes into a single static harmonic contour
/// ring so the act still communicates pitch and warmth without any oscillation.
struct ChladniWaveCanvas: View {

    /// The prosody frame driving the modal geometry.
    var frame: ProsodyFrame
    /// Accessibility Reduce Motion: freezes oscillation and draws a static ring.
    var reduceMotion: Bool
    /// Diameter the canvas should occupy. The pad passes its zone size so the
    /// field reads as living *inside* the fingertip, not behind it.
    var diameter: CGFloat

    /// The rim accent: pulled from the active emotion so the physics matches the
    /// type and the haptics.
    var accent: Color

    // MARK: - Cymatic constants (Everything2.md 4.4)

    /// Grid density: a 28 × 28 lattice of resonant acoustic particles.
    private static let gridCount = 28
    /// A particle within this distance of a nodal line is "on" the line and glows.
    private static let nodalTolerance: Double = 0.28
    /// Modal mode numbers for the lowest and highest expressible voice.
    private static let pitchModeBase: Double = 1.5
    private static let pitchModeSpan: Double = 4.5
    private static let centroidModeBase: Double = 2.0
    private static let centroidModeSpan: Double = 5.0

    /// Clamped loudness, reused by the glow and radius maths.
    private var energy: Double { Double(min(max(frame.rmsAmplitude, 0), 1)) }
    /// Clamped pitch, drives the `n` mode.
    private var pitch: Double { Double(min(max(frame.normalizedPitch, 0), 1)) }
    /// Clamped centroid, drives the `m` mode.
    private var centroid: Double { Double(min(max(frame.spectralCentroid, 0), 1)) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let clock = timeline.date.timeIntervalSinceReferenceDate
                if reduceMotion {
                    drawStaticContour(in: &context, size: size)
                } else {
                    drawNodalField(in: &context, size: size, clock: clock)
                }
                drawRim(in: &context, size: size)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Live cymatic field

    /// Draws the 28 × 28 particle lattice, glowing the particles that sit on a
    /// nodal line and drifting them gently so the field breathes with the voice.
    private func drawNodalField(in context: inout GraphicsContext, size: CGSize, clock: Double) {
        let radius = min(size.width, size.height) / 2
        // Pre-compute the mode numbers once per frame, not per particle.
        let n = Self.pitchModeBase + pitch * Self.pitchModeSpan
        let m = Self.centroidModeBase + centroid * Self.centroidModeSpan

        // A slow drift so the nodal lines shimmer like a driven plate rather than
        // looking like a printed engraving. Amplitude stays small so the geometry
        // is still legible as *pitch* and *warmth*.
        let drift = 0.06 * sin(clock * 0.9)
        let breath = 0.5 + 0.5 * sin(clock * 1.6)

        let count = Self.gridCount
        let origin = CGPoint(x: radius, y: radius)

        for row in 0..<count {
            for column in 0..<count {
                // Normalized plate coordinates in -1...1 on both axes.
                let x = -1.0 + (2.0 * Double(column) / Double(count - 1))
                let y = -1.0 + (2.0 * Double(row) / Double(count - 1))

                let value = chladni(x: x + drift, y: y - drift, n: n, m: m)
                let distance = abs(value)

                // Particles far from a nodal line are nearly invisible: the plate
                // is *moving* there, so the sand (and the eye) is not.
                guard distance < 1.4 else { continue }
                let onNode = distance < Self.nodalTolerance

                // Nodal particles dominate the image; off-node ones ghost it.
                let proximity = max(0, 1 - distance / 1.4)
                let baseOpacity = onNode ? 0.95 : 0.10 + 0.18 * proximity
                let opacity = baseOpacity * (0.45 + 0.55 * energy)

                // Radius scales with loudness, and nodal particles get a boost.
                let nodeBoost = onNode ? 1.8 : 1.0
                let particleRadius = max(0.6, (0.9 + 1.9 * energy * breath) * nodeBoost)

                let position = CGPoint(
                    x: origin.x + CGFloat(x) * radius,
                    y: origin.y + CGFloat(y) * radius
                )

                // Skip anything outside the circular plate (touching corners).
                let dx = Double(position.x - origin.x)
                let dy = Double(position.y - origin.y)
                guard (dx * dx + dy * dy).squareRoot() <= Double(radius) else { continue }

                let color = onNode
                    ? accent.opacity(opacity)
                    : ThemeTokens.textSecondary.opacity(opacity * 0.55)

                let rect = CGRect(
                    x: position.x - particleRadius,
                    y: position.y - particleRadius,
                    width: particleRadius * 2,
                    height: particleRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }

    /// Chladni's biharmonic plate equation, band-limited to the spatial frequency
    /// a voice can excite.
    ///
    /// `|C|` near zero means the plate is still there: a nodal line.
    private func chladni(x: Double, y: Double, n: Double, m: Double) -> Double {
        cos(n * .pi * x) * cos(m * .pi * y) - cos(m * .pi * x) * cos(n * .pi * y)
    }

    // MARK: - Reduce Motion fallback

    /// A single static harmonic contour ring: the same pitch/warmth information
    /// carried by curvature alone, with zero oscillation.
    ///
    /// The ring's lobed outline uses the same `n` and `m` mode numbers, so the
    /// shape still changes with the voice even though nothing moves.
    private func drawStaticContour(in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let n = Self.pitchModeBase + pitch * Self.pitchModeSpan
        let m = Self.centroidModeBase + centroid * Self.centroidModeSpan
        // Two counter-rotating lobes give a readable, still shape.
        let lobedRadius = radius * (0.42 + 0.28 * energy)

        var path = Path()
        let sampleCount = 180
        for index in 0...sampleCount {
            let angle = (Double(index) / Double(sampleCount)) * 2 * .pi
            let wave = sin(n * angle) * 0.5 + cos(m * angle) * 0.5
            let r = lobedRadius * (1.0 + 0.16 * wave)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle) * r),
                y: center.y + CGFloat(sin(angle) * r)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()

        // A soft filled plate plus a crisp nodal outline.
        context.fill(path, with: .color(accent.opacity(0.10 + 0.18 * energy)))
        context.stroke(
            path,
            with: .color(accent.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.4, lineJoin: .round)
        )
    }

    // MARK: - Rim

    /// A hairline rim so the field reads as a plate with an edge, not a blob.
    private func drawRim(in context: inout GraphicsContext, size: CGSize) {
        let inset: CGFloat = 1.5
        let rect = CGRect(
            x: inset,
            y: inset,
            width: max(size.width - inset * 2, 0),
            height: max(size.height - inset * 2, 0)
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(ThemeTokens.glassStroke),
            style: StrokeStyle(lineWidth: 1)
        )
    }
}
