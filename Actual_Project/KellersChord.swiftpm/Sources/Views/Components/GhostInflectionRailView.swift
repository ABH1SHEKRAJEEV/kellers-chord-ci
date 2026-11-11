import SwiftUI

/// The magnetic "Ghost Inflection Rail": a target prosody contour drawn *behind*
/// an Act III viva prompt, with the speaker's live voice riding along it.
///
/// A deaf student rehearsing aloud cannot hear whether their sentence is heading
/// toward a confident settle or a rising question. This component makes the
/// intended trajectory visible before they speak and shows, moment to moment, how
/// close their voice sits to it:
///
/// * **The rail** is a smooth cubic Bezier ribbon computed for the prompt — a
///   rising warmth on the key noun, a steady middle, then either a confident pitch
///   settle at the period or a rising tail if the prompt is a question.
/// * **The cursor** rides the rail at the live `normalizedPitch`, and drifts off it
///   as warmth departs from the target (`spectralCentroid`).
/// * **"LOCKED IN CADENCE"** illuminates when the summed pitch/warmth delta is
///   `<= 0.16`, and a single gentle haptic click marks the moment of lock.
///
/// The lock click fires *once per lock event* (not per frame), so holding a good
/// cadence does not buzz continuously.
struct GhostInflectionRailView: View {

    /// The live prosody frame from the speaker.
    var frame: ProsodyFrame
    /// The rail's target contour, `0...1` samples from left to right.
    var targetContour: [Float]
    /// `true` when the prompt is a question (rising tail) rather than a statement.
    var isQuestion: Bool
    /// Ambient clock for the cursor's shimmer.
    var elapsedTime: Double
    /// Accessibility Reduce Motion: freezes the shimmer, keeps the lock badge.
    var reduceMotion: Bool
    /// Called once each time the speaker enters the lock band.
    var onLockedIn: (() -> Void)?

    // MARK: - Tuning

    /// The summed pitch+warmth delta at or under which the speaker reads as locked.
    private static let lockThreshold: Float = 0.16
    /// How many samples the default contour is resampled to.
    static let contourSampleCount = 48

    /// Whether the speaker is currently inside the lock band.
    @State private var wasLocked = false

    // MARK: - Derived state

    /// The pitch difference between the live voice and the rail at its position.
    /// Zero when silent, so a quiet moment never reads as "locked".
    private var pitchDelta: Float {
        guard frame.isVoiced else { return 1 }
        let index = min(max(Int(frame.normalizedPitch * Float(Self.contourSampleCount - 1)), 0),
                        Self.contourSampleCount - 1)
        let target = targetValue(at: index)
        return abs(frame.normalizedPitch - target)
    }

    /// The warmth difference between the live voice and the rail's ideal warmth.
    private var warmthDelta: Float {
        guard frame.isVoiced else { return 1 }
        return abs(frame.spectralCentroid - idealWarmth)
    }

    /// The combined deviation used for the lock decision.
    private var combinedDelta: Float { pitchDelta + warmthDelta }

    /// The warmth the rail expects: warm chest resonance mid-sentence, brighter
    /// on a question's rising tail.
    private var idealWarmth: Float { isQuestion ? 0.55 : 0.30 }

    /// `true` inside the lock band.
    private var isLocked: Bool { frame.isVoiced && combinedDelta <= Self.lockThreshold }

    /// The contour value at a sample index, clamped into `0...1`.
    private func targetValue(at index: Int) -> Float {
        guard !targetContour.isEmpty else { return 0.5 }
        let safe = min(max(index, 0), targetContour.count - 1)
        return min(max(targetContour[safe], 0), 1)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeTokens.Spacing.tight) {
            header
            rail
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ghost inflection rail")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Aim your pitch and warmth so your voice rides along the glowing trail.")
        .onChange(of: isLocked) { _, locked in
            guard locked, !wasLocked else {
                wasLocked = locked
                return
            }
            wasLocked = true
            onLockedIn?()
        }
    }

    private var header: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            Text("TARGET CADENCE")
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
                .textCase(.uppercase)
            Spacer(minLength: 0)
            if isLocked {
                Label("LOCKED IN CADENCE", systemImage: "checkmark.seal.fill")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(lockColor)
                    .transition(.opacity.combined(with: .scale))
            } else {
                Text(isQuestion ? "Lift at the end" : "Settle at the end")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
        .animation(reduceMotion ? nil : ThemeTokens.Motion.snappy, value: isLocked)
    }

    /// The rail plus the live cursor, drawn on one `Canvas`.
    private var rail: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, canvasSize in
                drawRail(in: &context, size: canvasSize)
                drawCursor(in: &context, size: canvasSize, clock: elapsedTime)
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(height: 74)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                .fill(ThemeTokens.obsidian.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                        .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Drawing

    /// Converts a contour value (`0...1`) into a point, with `1` at the top.
    private func point(index: Int, total: Int, value: Float, size: CGSize, inset: CGFloat) -> CGPoint {
        let usableWidth = max(size.width - inset * 2, 1)
        let usableHeight = max(size.height - inset * 2, 1)
        let x = inset + usableWidth * CGFloat(index) / CGFloat(max(total - 1, 1))
        let y = inset + usableHeight * (1 - CGFloat(min(max(value, 0), 1)))
        return CGPoint(x: x, y: y)
    }

    /// Draws the ghost ribbon: a soft filled band beneath a crisp centre line.
    private func drawRail(in context: inout GraphicsContext, size: CGSize) {
        let inset: CGFloat = 10
        let values = targetContour.isEmpty
            ? Array(repeating: Float(0.55), count: Self.contourSampleCount)
            : targetContour
        let total = values.count

        var line = Path()
        for index in 0..<total {
            let p = point(index: index, total: total, value: values[index], size: size, inset: inset)
            if index == 0 {
                line.move(to: p)
            } else {
                line.addLine(to: p)
            }
        }

        // A soft band behind the line so the rail reads as a path, not a graph.
        var band = line
        band.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
        band.addLine(to: CGPoint(x: inset, y: size.height - inset))
        band.closeSubpath()
        context.fill(band, with: .color(ThemeTokens.accent(for: .warmRelief).opacity(0.10)))

        context.stroke(
            line,
            with: .color(ThemeTokens.accent(for: .warmRelief).opacity(isLocked ? 0.95 : 0.55)),
            style: StrokeStyle(lineWidth: isLocked ? 2.6 : 2, lineCap: .round, lineJoin: .round)
        )
    }

    /// Draws the live cursor: where the speaker's voice actually sits.
    ///
    /// Horizontal position tracks the same pitch axis the rail uses; vertical
    /// offset from the target line grows with `combinedDelta`, so drifting off
    /// cadence is visible as the dot leaving the trail.
    private func drawCursor(in context: inout GraphicsContext, size: CGSize, clock: Double) {
        guard frame.isVoiced else { return }
        let inset: CGFloat = 10
        let total = max(targetContour.count, 1)
        let index = min(max(Int(frame.normalizedPitch * Float(total - 1)), 0), total - 1)
        let target = point(index: index, total: total, value: targetValue(at: index),
                           size: size, inset: inset)

        // Deviation pushes the cursor away from the rail; lock pulls it onto it.
        let deviation = reduceMotion ? 0 : CGFloat(combinedDelta) * 12
        let shimmer = reduceMotion ? 0 : CGFloat(sin(clock * 5.0)) * 1.2
        let cursorPoint = CGPoint(
            x: target.x,
            y: min(max(target.y + deviation + shimmer, inset), size.height - inset)
        )

        let radius: CGFloat = isLocked ? 6 : 5
        let dotRect = CGRect(x: cursorPoint.x - radius, y: cursorPoint.y - radius,
                             width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(lockColor))

        // A halo only while locked, so the reward is visible but not constant.
        if isLocked {
            let haloRadius = radius * 2.1
            let haloRect = CGRect(x: cursorPoint.x - haloRadius, y: cursorPoint.y - haloRadius,
                                  width: haloRadius * 2, height: haloRadius * 2)
            var halo = context
            halo.opacity = 0.30
            halo.addFilter(.blur(radius: 4))
            halo.fill(Path(ellipseIn: haloRect), with: .color(lockColor))
        }
    }

    /// The cursor and lock color: green when locked, emotion accent otherwise.
    private var lockColor: Color {
        isLocked ? Color(hex: 0x34D399) : ThemeTokens.accent(for: frame.classifiedEmotion)
    }

    private var accessibilityValue: String {
        if !frame.isVoiced { return "Waiting for your voice" }
        return isLocked
            ? "Locked in cadence"
            : "Off cadence by \(Int(combinedDelta * 100)) percent"
    }
}

// MARK: - Prompt contour builder

extension GhostInflectionRailView {

    /// Builds the target contour for a viva prompt.
    ///
    /// The shape encodes the sentence itself rather than a fixed curve: a gentle
    /// rise across the first third (the opening clause), a steady middle, then
    /// either a confident settle or a rising tail depending on `isQuestion`.
    /// Resampled to `contourSampleCount` so the rail is smooth at any width.
    static func targetContour(for prompt: String) -> [Float] {
        // A trailing question mark means the sentence is asking, not stating.
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuestion = trimmed.hasSuffix("?")
        return targetContour(isQuestion: isQuestion)
    }

    /// The contour for a known question/statement shape.
    static func targetContour(isQuestion: Bool) -> [Float] {
        let count = contourSampleCount
        return (0..<count).map { index in
            let progress = Double(index) / Double(max(count - 1, 1))
            let opening = 0.42 + 0.18 * min(progress / 0.30, 1)
            let middle = 0.60 - 0.04 * sin(progress * .pi * 2)
            let shape: Double
            if progress < 0.30 {
                shape = opening
            } else if progress < 0.72 {
                shape = middle
            } else {
                let tail = (progress - 0.72) / 0.28
                shape = isQuestion
                    ? middle + 0.34 * tail       // rising question tail
                    : middle - 0.22 * tail       // grounded statement settle
            }
            return Float(min(max(shape, 0), 1))
        }
    }

    /// The question/statement verdict for a prompt, so the host view can label it.
    static func isQuestion(_ prompt: String) -> Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    }
}
