import SwiftUI

/// Act III's bottom instrument: three calm, non-clinical guides that help a deaf
/// or hard-of-hearing speaker self-monitor a college viva in real time.
///
/// 1. **Volume Safe-Zone Pill** — whispers *Too Quiet*, *Conversational Sweet
///    Spot*, or *Overly Loud for a Quiet Room*, never a raw decibel number.
/// 2. **Warmth & Inflection Mirror** — shows whether the voice is flat/monotone
///    or carrying natural rises and warm chest resonance, as a drifting contour.
/// 3. **Tactile Pacing Pulse** — a gentle 130 WPM heartbeat the speaker can feel
///    while holding the device. The `isPacingOn` binding is wired straight into
///    `TactileHapticEngine.isPacingEnabled` by the parent view.
///
/// Everything reads from one `ProsodyFrame`, so the bar behaves identically
/// whether the transcript comes from a live microphone or the simulated stream.
struct CadenceHorizonBar: View {

    /// The live prosody snapshot.
    var frame: ProsodyFrame
    /// Recent `rmsAmplitude` samples (newest last) for the inflection mirror.
    var history: [Float]
    /// Whether the tactile 130 WPM pacing pulse is currently on.
    @Binding var isPacingOn: Bool
    /// Drives the pulse indicator blink; supplied by the parent `TimelineView`.
    var elapsedTime: Double
    /// Honours Reduce Motion for the contour drift and pulse animation.
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: ThemeTokens.Spacing.regular) {
            volumePill
            roomBadge
            warmthMirror
            pacingRow
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                .fill(ThemeTokens.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                        .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cadence horizon")
    }

    // MARK: - 1. Volume safe-zone pill

    /// The volume zone a `0...1` amplitude falls into.
    private enum VolumeZone {
        case tooQuiet
        case sweetSpot
        case tooLoud

        var label: String {
            switch self {
            case .tooQuiet: return "Too Quiet"
            case .sweetSpot: return "Conversational Sweet Spot"
            case .tooLoud: return "Overly Loud for a Quiet Room"
            }
        }

        var color: Color {
            switch self {
            case .tooQuiet: return Color(hex: 0x38BDF8)
            case .sweetSpot: return Color(hex: 0x34D399)
            case .tooLoud: return Color(hex: 0xF43F5E)
            }
        }
    }

    private var currentZone: VolumeZone {
        switch frame.rmsAmplitude {
        case ..<sweetSpotLow: return .tooQuiet
        case ..<sweetSpotHigh: return .sweetSpot
        default: return .tooLoud
        }
    }

    // MARK: - Phase 2 (Upgrade 11): Lombard room-aware volume governor

    /// The lower bound of the conversational sweet spot for this room.
    ///
    /// Delegated to `ProsodyFrame.loudnessBand` so the bar, the Prosody Passport
    /// ring and the haptic nudge share one definition. They previously carried two
    /// different floors (0.28 here, 0.24 elsewhere), so a frame at 0.26 was
    /// "conversational" on the passport and "too quiet" here at the same instant.
    private var sweetSpotLow: Float {
        ProsodyFrame.loudnessBand(ambientNoiseDB: frame.ambientNoiseDB).low
    }

    /// The upper bound of the conversational sweet spot for this room.
    private var sweetSpotHigh: Float {
        ProsodyFrame.loudnessBand(ambientNoiseDB: frame.ambientNoiseDB).high
    }

    /// The calibrated room environment badge, per Section 4.5 Upgrade 11.
    ///
    /// Tells the speaker *which* room they are in and therefore which voice target
    /// applies, so "Too Quiet" is never ambiguous advice.
    private var roomBadge: some View {
        let decibels = frame.ambientNoiseDB.isFinite ? frame.ambientNoiseDB : -50
        let descriptor = roomDescriptor(for: decibels)
        return HStack(spacing: ThemeTokens.Spacing.tight) {
            Image(systemName: descriptor.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text("\(descriptor.name) (\(Int(decibels)) dB) - \(descriptor.target) Voice Target")
                .font(ThemeTokens.Typography.pill)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ThemeTokens.textSecondary)
        .padding(.horizontal, ThemeTokens.Spacing.tight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Room environment")
        .accessibilityValue("\(descriptor.name), \(descriptor.target) voice target")
    }

    /// Maps a calibrated dB floor onto a human room description and voice target.
    private func roomDescriptor(for decibels: Float)
        -> (name: String, target: String, symbol: String) {
        switch decibels {
        case ..<(-45):
            return ("Quiet Room", "Soft", "speaker.slash")
        case ..<(-30):
            return ("Normal Room", "Conversational", "speaker.wave.2")
        default:
            return ("Noisy Hall", "Project", "speaker.wave.3")
        }
    }

    private var volumePill: some View {
        let zone = currentZone
        return HStack(spacing: ThemeTokens.Spacing.tight) {
            Image(systemName: volumeSymbol(for: zone))
                .font(.system(size: 14, weight: .semibold))
            Text(zone.label)
                .font(ThemeTokens.Typography.body)
                .fontWeight(.medium)
            Spacer(minLength: 0)
        }
        .foregroundStyle(zone.color)
        .padding(.horizontal, ThemeTokens.Spacing.regular)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(zone.color.opacity(0.14))
                .overlay(Capsule(style: .continuous).stroke(zone.color.opacity(0.4), lineWidth: 1))
        )
        .animation(ThemeTokens.Motion.snappy, value: frame.rmsAmplitude > 0.72)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(zone.label)
        .accessibilityHint("Speak so this reads Conversational Sweet Spot for a calm viva voice.")
    }

    private func volumeSymbol(for zone: VolumeZone) -> String {
        switch zone {
        case .tooQuiet: return "speaker.slash.fill"
        case .sweetSpot: return "checkmark.circle.fill"
        case .tooLoud: return "speaker.wave.3.fill"
        }
    }

    // MARK: - 2. Warmth & inflection mirror

    /// Whether the recent contour reads as expressive or flat.
    private var isMonotone: Bool {
        guard history.count >= 6 else { return false }
        let slice = history.suffix(24)
        let mean = slice.reduce(0, +) / Float(slice.count)
        guard mean > 0.02 else { return true }
        let variance = slice.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(slice.count)
        return variance.squareRoot() / mean < 0.18
    }

    private var warmthMirror: some View {
        let accent = ThemeTokens.accent(for: frame.classifiedEmotion)
        let contour = isMonotone ? ThemeTokens.textSecondary : accent
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Warmth & Inflection")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                inflectionBadge
                Text(isMonotone ? "Flat / Monotone" : "Expressive")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(contour)
            }

            // A drifting contour line: the spoken pitch/volume shape over time.
            Canvas { context, size in
                guard history.count >= 2 else { return }
                let points = history.suffix(48)
                let stepX = size.width / CGFloat(max(points.count - 1, 1))
                var path = Path()
                for (index, value) in points.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = size.height * (1 - CGFloat(min(max(value, 0), 1)))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(
                    path,
                    with: .color(contour),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                    .fill(ThemeTokens.obsidian.opacity(0.5))
            )
            .animation(reduceMotion ? nil : ThemeTokens.Motion.snappy, value: frame.rmsAmplitude)
        }
        .accessibilityElement()
        .accessibilityLabel("Warmth and inflection")
        .accessibilityValue(isMonotone ? "Flat and monotone" : "Expressive with natural rises")
        .accessibilityHint("Let your pitch rise and fall naturally so this reads expressive.")
    }

    // MARK: - 3. Tactile pacing pulse

    // MARK: - Phase 2 (Upgrade 12): terminal question / statement badge

    /// A badge naming how the sentence is ending.
    ///
    /// Whether a sentence is rising into a question or settling into a statement is
    /// one of the most meaning-carrying and least visible prosodic cues, so it gets
    /// a permanent label rather than being implied by the contour line alone.
    @ViewBuilder
    private var inflectionBadge: some View {
        switch frame.terminalInflection {
        case .risingQuestion:
            inflectChip(symbol: "arrow.up.right",
                        color: ThemeTokens.accent(for: .anxiousTremor))
        case .groundedDrop:
            inflectChip(symbol: "arrow.down.right",
                        color: ThemeTokens.accent(for: .warmRelief))
        case .steady:
            EmptyView()
        }
    }

    private func inflectChip(symbol: String, color: Color) -> some View {
        let text = frame.terminalInflection.rawValue
        return HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(ThemeTokens.Typography.pill)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous).fill(color.opacity(0.16))
        )
        .accessibilityElement()
        .accessibilityLabel("Sentence ending")
        .accessibilityValue(text)
    }

    private var pacingRow: some View {
        // The 130 WPM beat: one pulse every 60/130 s, flashed on the ambient clock.
        let beat = 60.0 / 130.0
        let phase = reduceMotion ? 0.0 : (elapsedTime.truncatingRemainder(dividingBy: beat) / beat)
        let pulse = isPacingOn ? max(0, 1 - phase) : 0

        return HStack(spacing: ThemeTokens.Spacing.regular) {
            ZStack {
                Circle()
                    .fill(ThemeTokens.accent(for: .warmRelief))
                    .frame(width: 12, height: 12)
                    .scaleEffect(1 + CGFloat(pulse) * 1.4)
                    .opacity(0.35 + 0.65 * (1 - pulse))
                Circle()
                    .stroke(ThemeTokens.accent(for: .warmRelief), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .opacity(isPacingOn ? 0.5 : 0.2)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tactile Pacing Pulse")
                    .font(ThemeTokens.Typography.body)
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text("130 words per minute")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isPacingOn)
                .labelsHidden()
                .tint(ThemeTokens.accent(for: .warmRelief))
                .accessibilityLabel("Tactile pacing pulse")
                .accessibilityValue(isPacingOn ? "On" : "Off")
                .accessibilityHint("Turn on to feel a gentle 130 words per minute heartbeat while you speak.")
        }
    }
}
