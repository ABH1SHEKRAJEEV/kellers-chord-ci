import SwiftUI

/// The Tabletop 180° Duet: a split-screen, face-to-face conversation mode.
///
/// Place the iPad flat on a desk between two people. The top half is rotated 180°
/// so the person *across* the desk reads it upright; the bottom half faces the deaf
/// or hard-of-hearing user. Both halves show the same live transcript, so the
/// hearing partner can watch their own words bloom into emotion while the user
/// reads the tactile-typographic version.
///
/// The two halves deliberately are **not** mirror images:
/// * **Partner half (top, 180°)** — the living caption, an emotion aura, and a
///   prompt inviting them to speak naturally. Simple, because a hearing speaker
///   needs only gentle acknowledgement that their voice is landing.
/// * **User half (bottom, upright)** — the upright caption, the Vocal Braille
///   scrubber, the Consonant Spark and Question/Statement badges, and three
///   one-tap conversational replies the user can show instead of speaking.
///
/// A glowing acoustic divider separates the halves and doubles as the "you are
/// here" boundary, which matters when one side of the screen is upside down.
struct TabletopDuetOverlay: View {

    /// The live prosody frame driving the half-screen aura and badges.
    var frame: ProsodyFrame
    /// The live transcript shown on both halves.
    var transcript: String
    /// Per-word prosody slices for the user's Braille scrubber.
    var wordSnapshots: [WordProsodySnapshot]
    /// Ambient clock for the living typography.
    var elapsedTime: Double
    /// Accessibility Reduce Motion.
    var reduceMotion: Bool
    /// Called when the user drags onto a word, so the host can play its haptic
    /// signature through `TactileHapticEngine.playBrailleScrub(for:)`.
    var onScrubWord: (WordProsodySnapshot) -> Void
    /// Closes the overlay and returns to the standard Act III layout.
    var onClose: () -> Void

    /// The three one-tap replies in the user's half.
    static let replyCards: [String] = [
        "Could you repeat that slower?",
        "I can feel your vocal tone on my screen",
        "Let me answer that"
    ]

    /// The word index the finger is currently scrubbing, for highlight.
    @State private var scrubbingWordID: UUID?

    /// The caption shown when nothing has been said yet.
    private let placeholder = "Speak and your words appear on both sides of the table."

    var body: some View {
        VStack(spacing: 0) {
            partnerHalf
            divider
            userHalf
        }
        .background(ThemeTokens.obsidian.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                .stroke(ThemeTokens.glassStroke, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - Partner half (rotated 180°)

    /// The top half, rendered upsidedown so the person across the desk reads it.
    private var partnerHalf: some View {
        ZStack {
            auraBackground(opacity: 0.22)

            VStack(spacing: ThemeTokens.Spacing.tight) {
                Text("YOUR VOICE - READ ACROSS THE TABLE")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .textCase(.uppercase)

                Text(shownTranscript)
                    .font(transcript.isEmpty ? ThemeTokens.Typography.body : ThemeTokens.Typography.title)
                    .fontWeight(ThemeTokens.emphasisWeight(for: frame))
                    .foregroundStyle(transcript.isEmpty ? ThemeTokens.textSecondary : ThemeTokens.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, ThemeTokens.Spacing.regular)
                    .textRenderer(
                        ProsodyTextRenderer(
                            frame: frame,
                            elapsedTime: elapsedTime,
                            reduceMotion: reduceMotion
                        )
                    )

                HStack(spacing: 6) {
                    Circle()
                        .fill(ThemeTokens.accent(for: frame.classifiedEmotion))
                        .frame(width: 8, height: 8)
                    Text(frame.isVoiced ? frame.classifiedEmotion.displayName : "Listening")
                        .font(ThemeTokens.Typography.pill)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
            }
            .padding(.vertical, ThemeTokens.Spacing.regular)

            closeButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(ThemeTokens.Spacing.tight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Everything in the partner half is upside down, including the close button.
        .rotationEffect(.degrees(180))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Partner side, rotated for the person across the table")
    }

    // MARK: - Divider

    /// The glowing acoustic divider: the physical boundary between the two people.
    private var divider: some View {
        ZStack {
            Rectangle()
                .fill(ThemeTokens.obsidian)
                .frame(height: 18)
            Capsule()
                .fill(ThemeTokens.accent(for: frame.classifiedEmotion).opacity(0.55))
                .frame(height: 2)
                .shadow(color: ThemeTokens.accent(for: frame.classifiedEmotion).opacity(0.7), radius: 8)
        }
        .accessibilityHidden(true)
    }

    // MARK: - User half (upright)

    /// The bottom half: caption, badges, Braille scrubber and reply cards.
    private var userHalf: some View {
        ZStack {
            auraBackground(opacity: 0.16)

            VStack(spacing: ThemeTokens.Spacing.tight) {
                badges
                brailleScrubber
                replyRow
            }
            .padding(ThemeTokens.Spacing.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your side of the table")
    }

    /// The Consonant Spark and terminal-inflection badges.
    ///
    /// These are the two cues that unvoiced consonants and sentence direction even
    /// exist, so they belong on the side doing the reading.
    private var badges: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            if frame.hasConsonantSpark {
                badge(
                    text: "Consonant",
                    symbol: "sparkle",
                    color: Color(hex: 0xF8FAFC)
                )
            }
            switch frame.terminalInflection {
            case .risingQuestion:
                badge(
                    text: "Rising Question",
                    symbol: "arrow.up.right",
                    color: ThemeTokens.accent(for: .anxiousTremor)
                )
            case .groundedDrop:
                badge(
                    text: "Statement Drop",
                    symbol: "arrow.down.right",
                    color: ThemeTokens.accent(for: .warmRelief)
                )
            case .steady:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .animation(reduceMotion ? nil : ThemeTokens.Motion.snappy, value: frame.hasConsonantSpark)
    }

    private func badge(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(ThemeTokens.Typography.pill)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(Capsule(style: .continuous).stroke(color.opacity(0.45), lineWidth: 1))
        )
    }

    /// The Vocal Braille scrubber: the most recent words, each a touch target that
    /// replays its recorded prosody under the fingertip.
    private var brailleScrubber: some View {
        let words = Array(wordSnapshots.suffix(6))
        return VStack(alignment: .leading, spacing: 4) {
            Text("VOCAL BRAILLE - DRAG TO FEEL")
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
                .textCase(.uppercase)

            if words.isEmpty {
                Text("Words you hear will appear here as touchable shapes.")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    ForEach(words) { snapshot in
                        brailleChip(snapshot)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One scrubable word chip.
    private func brailleChip(_ snapshot: WordProsodySnapshot) -> some View {
        let isActive = scrubbingWordID == snapshot.id
        let color = ThemeTokens.accent(for: snapshot.dominantFrame.classifiedEmotion)
        return Text(snapshot.word)
            .font(ThemeTokens.Typography.pill)
            .foregroundStyle(isActive ? ThemeTokens.obsidian : ThemeTokens.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? color : ThemeTokens.glassFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isActive ? color : ThemeTokens.glassStroke, lineWidth: 1)
                    )
            )
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard scrubbingWordID != snapshot.id else { return }
                        scrubbingWordID = snapshot.id
                        onScrubWord(snapshot)
                    }
                    .onEnded { _ in
                        scrubbingWordID = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Word \(snapshot.word)")
            .accessibilityValue(snapshot.dominantFrame.classifiedEmotion.displayName)
            .accessibilityHint("Touch to feel this word's vocal tone again.")
            .accessibilityAddTraits(.isButton)
    }

    /// The three one-tap replies, so the user can respond without speaking.
    private var replyRow: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            ForEach(Self.replyCards, id: \.self) { reply in
                Text(reply)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                            .fill(ThemeTokens.glassFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                                    .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                            )
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Reply: \(reply)")
            }
        }
    }

    // MARK: - Shared pieces

    /// A soft emotion aura behind each half, kept subtle so text stays the focus.
    private func auraBackground(opacity: Double) -> some View {
        let palette = ThemeTokens.Palette.colors(for: frame.classifiedEmotion)
        let strength = frame.isVoiced ? opacity : opacity * 0.25
        return LinearGradient(
            colors: [
                (palette.first ?? ThemeTokens.obsidian).opacity(strength),
                ThemeTokens.obsidian.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The close affordance, placed inside the rotated half so it stays reachable
    /// from the partner's side too.
    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ThemeTokens.textSecondary)
                .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close tabletop duet")
        .accessibilityHint("Returns to the standard vocal mirror layout.")
    }

    /// The transcript, or a gentle placeholder before anything is said.
    private var shownTranscript: String {
        transcript.isEmpty ? placeholder : transcript
    }
}
