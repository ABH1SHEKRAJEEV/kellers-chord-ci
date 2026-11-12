import SwiftUI

/// Act II — The Helen Keller Tactile Decoder (0:45 - 1:45).
///
/// The neuroscience act. The judge either replays the three voice notes while
/// resting fingers on the sensory pad, or physically scrubs the pad to sculpt the
/// emotion of a sentence in real time and feels how typography and haptics fuse
/// into one language.
///
/// Layout mirrors `Everything.md`: a large living-typography stage on top,
/// driving a selectable phrase, and the `TactileFingerPadView` below. Everything
/// reads and writes a single `ProsodyFrame`, so whichever source is active (a
/// recorded note or a hand-sculpted pad) the type and haptics respond identically.
struct Act2TactileProsodyView: View {

    // MARK: - Injected dependencies

    /// The three loaded samples, keyed by emotion (always exactly three).
    var samples: [AudioSampleLoader.LoadedSample]
    /// The shared playback + DSP engine.
    var dspEngine: ProsodyDSPEngine
    /// The shared haptic engine.
    var hapticEngine: TactileHapticEngine
    /// The live prosody frame published by the DSP engine during playback.
    var liveFrame: ProsodyFrame
    /// Ambient clock for the living-typography animation.
    var elapsedTime: Double
    /// Accessibility Reduce Motion.
    var reduceMotion: Bool
    /// CI only (`--ci-act2-chladni`): the frame the pad opens on.
    ///
    /// The Chladni plate is driven by `sculptedFrame`, which is silent until a
    /// finger touches it. CI has no finger, so this seeds one designed state to
    /// photograph. Defaulted to nil, so the shipping path opens silent.
    var previewFrame: ProsodyFrame? = nil
    /// Advances the 3-act choreography once Act II is complete.
    var onComplete: () -> Void

    // MARK: - State

    /// The phrase displayed on the living-typography stage.
    @State private var phraseIndex = 0
    /// The frame the pad is sculpting by hand, if the judge is scrubbing.
    @State private var sculptedFrame: ProsodyFrame = .silent
    /// The voice currently replaying through the engine, if any.
    @State private var playingVoice: Int?

    /// The three phrases the stage cycles through, exactly per the spec.
    private let phrases = [
        "I'm fine with that.",
        "Yeah, great job on that presentation.",
        "Don't worry, we'll figure it out together."
    ]

    /// The samples ordered warm / anxious / sarcasm so the replay buttons map to
    /// the same A/B/C emotional vocabulary as Act I.
    private var orderedSamples: [AudioSampleLoader.LoadedSample] {
        let order: [EmotionalProfile] = [.warmRelief, .anxiousTremor, .sharpSarcasm]
        return order.compactMap { profile in
            samples.first { $0.profile == profile }
        }
    }

    /// The frame the stage renders: live playback wins, else the sculpted pad,
    /// else silence. Both sources share the same shape, so the stage is agnostic.
    private var stageFrame: ProsodyFrame {
        if playingVoice != nil { return liveFrame }
        return sculptedFrame
    }

    /// The phrase shown: while replaying a note, use that note's canonical line.
    private var stagePhrase: String {
        phrases[phraseIndex % phrases.count]
    }

    var body: some View {
        VStack(spacing: ThemeTokens.Spacing.section) {
            stage
            phrasePicker
            sourceRow
            TactileFingerPadView(
                sculptedFrame: $sculptedFrame,
                reduceMotion: reduceMotion,
                onFrameChanged: { frame in
                    // §8 Act II: the judge may "replay the 3 recorded voice notes
                    // while resting their fingers on the 3 zones" OR scrub to
                    // sculpt. Keep the sculpted frame as the stage's fallback but
                    // never kill an in-flight replay, so the two coexist: while a
                    // voice plays, its live prosody wins the stage; when it stops,
                    // the sculpted emotion takes over.
                    hapticEngine.render(frame)
                }
            )
            continueButton
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.regular)
        .onAppear {
            // CI only: seed the pad with a designed emotion so the Chladni plate can
            // be photographed. A finger scrubbing wins immediately afterwards.
            if let previewFrame, !sculptedFrame.isVoiced {
                sculptedFrame = previewFrame
            }
        }
        .onDisappear { stopPlayback() }
    }

    // MARK: - Living typography stage

    /// The large focal stage: one sentence, morphed glyph by glyph from the
    /// active prosody frame. The single clear focal point of Act II.
    private var stage: some View {
        let accent = ThemeTokens.accent(for: stageFrame.classifiedEmotion)
        return ZStack {
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                .fill(ThemeTokens.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                        .stroke(accent.opacity(stageFrame.isVoiced ? 0.5 : 0.12), lineWidth: 1)
                )

            Text(stagePhrase)
                .font(ThemeTokens.Typography.hero)
                .fontWeight(ThemeTokens.emphasisWeight(for: stageFrame))
                .foregroundStyle(ThemeTokens.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .padding(ThemeTokens.Spacing.section)
                .textRenderer(
                    ProsodyTextRenderer(
                        frame: stageFrame,
                        elapsedTime: elapsedTime,
                        reduceMotion: reduceMotion
                    )
                )
        }
        .frame(minHeight: 200)
        .animation(reduceMotion ? nil : ThemeTokens.Motion.act, value: stageFrame.classifiedEmotion)
        .accessibilityElement()
        .accessibilityLabel("Living typography stage")
        .accessibilityValue(stagePhrase)
        .accessibilityHint("This sentence morphs to show the emotion of the current voice or your finger position.")
    }

    // MARK: - Phrase picker

    /// Cycles the stage phrase, so the judge can sculpt different sentences.
    private var phrasePicker: some View {
        HStack(spacing: ThemeTokens.Spacing.tight) {
            ForEach(phrases.indices, id: \.self) { index in
                Button {
                    phraseIndex = index
                } label: {
                    Circle()
                        .fill(index == phraseIndex % phrases.count
                              ? ThemeTokens.textPrimary
                              : ThemeTokens.textSecondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Phrase \(index + 1)")
                .accessibilityAddTraits(index == phraseIndex % phrases.count ? [.isSelected, .isButton] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Voice replay row

    /// Replays the three recorded (or synthesized) voice notes on demand.
    private var sourceRow: some View {
        HStack(spacing: ThemeTokens.Spacing.regular) {
            ForEach(Array(orderedSamples.enumerated()), id: \.offset) { index, sample in
                replayButton(index: index, sample: sample)
            }
        }
    }

    private func replayButton(index: Int, sample: AudioSampleLoader.LoadedSample) -> some View {
        let isPlaying = playingVoice == index
        let accent = ThemeTokens.accent(for: sample.profile)
        return Button {
            replay(index)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: isPlaying ? "waveform" : "play.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text(sample.profile.displayName)
                    .font(ThemeTokens.Typography.pill)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isPlaying ? accent : ThemeTokens.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ThemeTokens.Spacing.regular)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                    .fill(isPlaying ? accent.opacity(0.16) : ThemeTokens.glassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                            .stroke(isPlaying ? accent.opacity(0.5) : ThemeTokens.glassStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replay \(sample.profile.displayName)")
        .accessibilityValue(sample.profile.acousticSummary)
        .accessibilityHint("Plays this voice note while the stage shows its living typography.")
    }

    // MARK: - Continue

    private var continueButton: some View {
        Button {
            stopPlayback()
            onComplete()
        } label: {
            Text("Continue to Your Vocal Mirror")
                .font(ThemeTokens.Typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(ThemeTokens.obsidian)
                .padding(.horizontal, ThemeTokens.Spacing.section)
                .padding(.vertical, ThemeTokens.Spacing.regular)
                .frame(maxWidth: .infinity)
                .background(Capsule(style: .continuous).fill(ThemeTokens.textPrimary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue to your vocal mirror")
        .accessibilityHint("Moves on to Act III, where the mirror reflects your own voice.")
    }

    // MARK: - Interaction logic

    /// Replays one voice note through the shared DSP engine.
    private func replay(_ index: Int) {
        guard index < orderedSamples.count else { return }
        playingVoice = index
        dspEngine.play(orderedSamples[index])
    }

    /// Tears down playback when leaving Act II.
    private func stopPlayback() {
        playingVoice = nil
        dspEngine.stopPlayback()
    }
}
