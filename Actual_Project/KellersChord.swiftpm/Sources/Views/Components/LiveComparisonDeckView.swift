import SwiftUI

/// The 3-Take Live Stage Challenge: three emotional takes of the *same* sentence,
/// pinned side by side so the difference is impossible to miss.
///
/// The judge records (or simulates) the phrase *"Good luck with your application."*
/// three times — warm empathy, quiet anxiety, biting sarcasm — and each take stays
/// on screen rendered through `ProsodyTextRenderer` with its captured
/// `[WordProsodySnapshot]`. Dragging a finger across any take replays that take's
/// prosody through the haptic engine, so the same words can be *felt* three
/// different ways in the same breath.
///
/// This is the direct answer to Act I's blindspot: the words never change, only the
/// meaning, and here all three meanings sit together.
struct LiveComparisonDeckView: View {

    /// The recorded takes, in recording order (at most three).
    var takes: [LiveChallengeTake]
    /// Which target the next recording will be, if any.
    var activeTarget: String?
    /// The live frame, used to animate a slot that is currently recording.
    var liveFrame: ProsodyFrame
    /// Ambient clock for the living typography.
    var elapsedTime: Double
    /// Accessibility Reduce Motion.
    var reduceMotion: Bool
    /// Starts a take for the given target label.
    var onBeginTake: (String) -> Void
    /// Ends the take in progress.
    var onEndTake: () -> Void
    /// Called when a finger lands on a take, so the host can play its haptics.
    var onPreviewTake: (LiveChallengeTake) -> Void
    /// Closes the deck and returns to the standard Act III layout.
    var onClose: () -> Void

    /// The take whose slot the finger is currently on, for the highlight.
    @State private var previewingTakeID: UUID?

    /// The three targets, in order, from the speech manager's static list.
    private var targets: [String] { OfflineSpeechManager.takeTargets }

    /// The phrase every slot recites.
    private var phrase: String { OfflineSpeechManager.comparisonPhrase }

    var body: some View {
        VStack(spacing: ThemeTokens.Spacing.regular) {
            header
            VStack(spacing: ThemeTokens.Spacing.tight) {
                ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                    slot(index: index, target: target)
                }
            }
            controls
        }
        .padding(ThemeTokens.Spacing.regular)
        .background(ThemeTokens.obsidian.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                .stroke(ThemeTokens.glassStroke, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            VStack(alignment: .leading, spacing: 2) {
                Text("3-TAKE LIVE STAGE")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .textCase(.uppercase)
                Text("\u{201C}\(phrase)\u{201D}")
                    .font(ThemeTokens.Typography.body)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close three take deck")
            .accessibilityHint("Returns to the standard vocal mirror layout.")
        }
    }

    // MARK: - One take slot

    /// A single take slot: recorded takes render their captured prosody; an empty
    /// slot invites recording; the active slot renders the live frame as it fills.
    private func slot(index: Int, target: String) -> some View {
        let take = recordedTake(at: index)
        let isRecording = activeTarget == target
        let isPreviewing = take.map { previewingTakeID == $0.id } ?? false
        // The frame backing this slot's typography.
        let slotFrame: ProsodyFrame = {
            if let take { return take.averageFrame }
            if isRecording { return liveFrame }
            return .silent
        }()
        let accent = ThemeTokens.accent(for: slotFrame.classifiedEmotion)
        let isFilled = take != nil || isRecording

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: ThemeTokens.Spacing.tight) {
                Text("TAKE \(index + 1)")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Text(target)
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(isFilled ? accent : ThemeTokens.textSecondary)
                Spacer(minLength: 0)
                if isRecording {
                    Text("RECORDING")
                        .font(ThemeTokens.Typography.pill)
                        .foregroundStyle(ThemeTokens.accent(for: .sharpSarcasm))
                } else if let take {
                    Text("\(take.snapshots.count) words")
                        .font(ThemeTokens.Typography.pill)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
            }

            Text(phrase)
                .font(ThemeTokens.Typography.body)
                .fontWeight(ThemeTokens.emphasisWeight(for: slotFrame))
                .foregroundStyle(isFilled ? ThemeTokens.textPrimary : ThemeTokens.textSecondary.opacity(0.6))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textRenderer(
                    ProsodyTextRenderer(
                        frame: slotFrame,
                        elapsedTime: elapsedTime,
                        reduceMotion: reduceMotion
                    )
                )

            if let take {
                HStack(spacing: ThemeTokens.Spacing.tight) {
                    metricChip(label: "Pitch", value: "\(Int(take.averageFrame.fundamentalPitchHz)) Hz")
                    metricChip(label: "Warmth", value: warmthLabel(take.averageFrame.spectralCentroid))
                    metricChip(label: "Tremor", value: "\(Int(take.averageFrame.pitchJitter * 100))%")
                }
            }
        }
        .padding(ThemeTokens.Spacing.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                .fill(isPreviewing ? accent.opacity(0.18) : ThemeTokens.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                        .stroke(isPreviewing ? accent.opacity(0.7) : ThemeTokens.glassStroke,
                                lineWidth: isPreviewing ? 2 : 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous))
        .opacity(isFilled ? 1 : 0.7)
        .gesture(
            // Dragging across a filled slot replays that take's prosody in the hand.
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard let take, previewingTakeID != take.id else { return }
                    previewingTakeID = take.id
                    onPreviewTake(take)
                }
                .onEnded { _ in
                    previewingTakeID = nil
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Take \(index + 1), \(target)")
        .accessibilityValue(slotAccessibilityValue(take: take, isRecording: isRecording))
        .accessibilityHint("Touch to feel this take's vocal tone again.")
    }

    private func metricChip(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(ThemeTokens.textSecondary)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(ThemeTokens.textPrimary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(ThemeTokens.obsidian.opacity(0.5))
        )
    }

    private func warmthLabel(_ centroid: Float) -> String {
        switch centroid {
        case ..<0.35: return "Warm"
        case ..<0.65: return "Neutral"
        default: return "Sharp"
        }
    }

    private func slotAccessibilityValue(take: LiveChallengeTake?, isRecording: Bool) -> String {
        if isRecording { return "Recording now" }
        guard let take else { return "Empty, not recorded yet" }
        return "\(take.averageFrame.classifiedEmotion.displayName), \(take.snapshots.count) words captured"
    }

    // MARK: - Controls

    /// The record affordance: starts the next empty slot, or ends the active take.
    private var controls: some View {
        HStack(spacing: ThemeTokens.Spacing.regular) {
            Button {
                if activeTarget != nil {
                    onEndTake()
                } else if let nextTarget = nextTarget {
                    onBeginTake(nextTarget)
                }
            } label: {
                Text(buttonTitle)
                    .font(ThemeTokens.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(canPress ? ThemeTokens.obsidian : ThemeTokens.textSecondary)
                    .padding(.horizontal, ThemeTokens.Spacing.section)
                    .padding(.vertical, ThemeTokens.Spacing.regular)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canPress
                                  ? ThemeTokens.accent(for: .warmRelief)
                                  : ThemeTokens.glassFill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canPress)
            .accessibilityLabel(buttonTitle)
            .accessibilityHint("Records or stops the current take of the comparison phrase.")
        }
    }

    /// The slot that will record next, or `nil` when all three are filled.
    private var nextTarget: String? {
        targets.first { target in
            recordedTake(at: targets.firstIndex(of: target) ?? 0) == nil
        }
    }

    private var canPress: Bool { activeTarget != nil || nextTarget != nil }

    private var buttonTitle: String {
        if let activeTarget { return "Stop Recording \(activeTarget)" }
        if let nextTarget { return "Record Take \(takes.count + 1): \(nextTarget)" }
        return "All Three Takes Captured"
    }

    /// The take recorded for the slot at `index`, if that slot has been filled.
    private func recordedTake(at index: Int) -> LiveChallengeTake? {
        guard takes.indices.contains(index) else { return nil }
        return takes[index]
    }
}
