import SwiftUI

/// Act I — The Caption Blindspot (0:00 - 0:45).
///
/// A two-stage guessing game that makes the judge *feel* the emotional blindness
/// of standard subtitles before it reveals the solution.
///
/// * **Stage 1 (Muted Prosody):** three cards show the identical sterile caption
///   "I'm fine with that." Tapping one flashes flat white text with zero audio
///   and zero animation, then asks the judge to guess its emotion. Any guess is
///   revealed as a coin flip — because with flat captions all three are the same.
/// * **Stage 2 (Cross-Modal Prosody):** after the judge taps *Unlock Keller's
///   Chord*, the same three cards replay their real voice notes through
///   `ProsodyDSPEngine`, and the caption erupts into living typography driven by
///   `ProsodyTextRenderer` and `EmotionalMeshBackground`, synchronized with the
///   `TactileHapticEngine`.
///
/// The view owns only its own choreography state; all audio/DSP/haptics are
/// injected by `RootCoordinatorView` so the single-tap audio contract is honored.
struct Act1CaptionBlindspotView: View {

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
    /// `true` when the app fell back to synthesized demo voices, surfaced honestly.
    var usesSynthesizedAudio: Bool
    /// Advances the 3-act choreography once Act I is complete.
    var onComplete: () -> Void

    // MARK: - Choreography state

    /// Which stage of Act I the judge is in.
    private enum Stage {
        case mutedGuess
        case revealed
    }

    @State private var stage: Stage = .mutedGuess

    /// The voice (index 0...2) the judge tapped in Stage 1, if any.
    @State private var tappedVoice: Int?
    /// The emotion the judge assigned to the tapped voice.
    @State private var guessedEmotion: EmotionalProfile?
    /// `true` once a guess has been made and the "identical" reveal shown.
    @State private var guessRevealed = false

    /// The voice currently playing in Stage 2, if any.
    @State private var playingVoice: Int?
    /// The voice flashing from a Stage 1 tap (the spec's sterile white flash).
    @State private var flashingVoice: Int?
    /// Drives the automatic A -> B -> C replay chain after unlock.
    @State private var sequenceTask: Task<Void, Never>?
    /// Phase 2 (Upgrade 1): the 280 Hz Cochlear Loss Simulator.
    ///
    /// When on, Act I playback is pushed through a cascaded 280 Hz low-pass so the
    /// judge hears how profound sensorineural hearing loss reduces every voice to
    /// the same indistinct rumble - and then feels how haptics and living
    /// typography restore the missing emotion. Off by default so the reveal reads
    /// clean first.
    @State private var isCochlearSimulationOn = false

    /// The three voices, in fixed order A/B/C.
    private let voiceLetters = ["A", "B", "C"]
    /// The caption every voice shares in Stage 1: deliberately identical.
    private let caption = "I'm fine with that."

    /// The samples ordered warm / anxious / sarcasm so A/B/C map predictably.
    private var orderedSamples: [AudioSampleLoader.LoadedSample] {
        let order: [EmotionalProfile] = [.warmRelief, .anxiousTremor, .sharpSarcasm]
        return order.compactMap { profile in
            samples.first { $0.profile == profile }
        }
    }

    /// The frame backing a card: live during Stage 2 playback, else silent.
    private func frame(for index: Int) -> ProsodyFrame {
        guard stage == .revealed, playingVoice == index else { return .silent }
        return liveFrame
    }

    var body: some View {
        VStack(spacing: ThemeTokens.Spacing.section) {
            header
            cards
            spacerAndControls
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .padding(.vertical, ThemeTokens.Spacing.regular)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: ThemeTokens.Spacing.tight) {
            Text("THE CAPTION BLINDSPOT")
                .font(ThemeTokens.Typography.title)
                .foregroundStyle(ThemeTokens.textPrimary)
                .multilineTextAlignment(.center)
            Text(stage == .mutedGuess
                 ? "Tap a voice, then guess what it really felt. Subtitles throw that away."
                 : "Same words. Now you can finally feel the difference.")
                .font(ThemeTokens.Typography.body)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if usesSynthesizedAudio {
                // Honest labeling: the judge should know these are demo voices.
                Label("Demo voices (add your own .m4a clips to VoiceNotes)", systemImage: "info.circle")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.horizontal, ThemeTokens.Spacing.tight)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(ThemeTokens.glassFill))
            }

            if stage == .revealed {
                cochlearToggle
            }
        }
        .padding(.top, ThemeTokens.Spacing.regular)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Phase 2 (Upgrade 1): Cochlear Loss Simulator

    /// A single calm pill that switches the 280 Hz cochlear-simulation filter.
    ///
    /// Placed in the header so it can be toggled *while* a voice is playing, which
    /// is the whole point: the judge hears the same clip transform from clear to
    /// muffled without leaving the moment.
    private var cochlearToggle: some View {
        Button {
            isCochlearSimulationOn.toggle()
            applyCochlearSimulation()
        } label: {
            HStack(spacing: ThemeTokens.Spacing.tight) {
                Image(systemName: isCochlearSimulationOn
                      ? "ear.badge.waveform"
                      : "ear")
                    .font(.system(size: 12, weight: .semibold))
                Text(isCochlearSimulationOn
                     ? "Hearing Loss Simulation: ON (280 Hz)"
                     : "Simulate Profound Hearing Loss")
                    .font(ThemeTokens.Typography.pill)
            }
            .foregroundStyle(isCochlearSimulationOn
                             ? ThemeTokens.accent(for: .anxiousTremor)
                             : ThemeTokens.textSecondary)
            .padding(.horizontal, ThemeTokens.Spacing.regular)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isCochlearSimulationOn
                          ? ThemeTokens.accent(for: .anxiousTremor).opacity(0.16)
                          : ThemeTokens.glassFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isCochlearSimulationOn
                                    ? ThemeTokens.accent(for: .anxiousTremor).opacity(0.5)
                                    : ThemeTokens.glassStroke,
                                    lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Simulate profound hearing loss")
        .accessibilityValue(isCochlearSimulationOn ? "On" : "Off")
        .accessibilityHint("Filters the voice at 280 hertz so you hear what profound sensorineural hearing loss sounds like.")
        .transition(.opacity)
    }

    /// Mirrors the toggle onto the audio graph.
    ///
    /// `ProsodyDSPEngine` owns the two 280 Hz EQ stages between the player and the
    /// mixer, so one assignment muffles both the bundled voice notes and the
    /// synthesized fallback, and the analyzer (tapped after the EQ) measures the
    /// muffled signal the judge is actually hearing.
    private func applyCochlearSimulation() {
        dspEngine.isCochlearSimulationEnabled = isCochlearSimulationOn
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(spacing: ThemeTokens.Spacing.regular) {
            ForEach(Array(orderedSamples.enumerated()), id: \.offset) { index, sample in
                voiceCard(index: index, sample: sample)
            }
        }
    }

    /// One Voice A/B/C card. Sterile in Stage 1, fully expressive in Stage 2.
    private func voiceCard(index: Int, sample: AudioSampleLoader.LoadedSample) -> some View {
        let isPlaying = playingVoice == index
        let activeFrame = frame(for: index)
        let accent = ThemeTokens.accent(for: sample.profile)

        return VStack(alignment: .leading, spacing: ThemeTokens.Spacing.tight) {
            HStack {
                Text("Voice \(voiceLetters[index])")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(stage == .revealed ? accent : ThemeTokens.textSecondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                if stage == .revealed {
                    Text(sample.profile.displayName)
                        .font(ThemeTokens.Typography.pill)
                        .foregroundStyle(accent)
                        .transition(.opacity)
                }
            }

            // The caption itself. In Stage 1 it is frozen, uniform, and mute; in
            // Stage 2 it is drawn glyph by glyph with live prosody.
            captionText(index: index, activeFrame: activeFrame)

            if let guess = guessedEmotion, tappedVoice == index, guessRevealed {
                // Name what they guessed, then state the fact the whole act rests
                // on: the caption was identical for all three. The true emotion is
                // revealed by Stage 2 replaying the voice, not by a quiz answer,
                // so it is deliberately withheld here.
                Text("You guessed \(guess.displayName). All three voices showed this same flat caption.")
                    .font(ThemeTokens.Typography.body)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(ThemeTokens.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(index: index, isPlaying: isPlaying, accent: accent))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                .stroke(isPlaying ? accent.opacity(0.7) : ThemeTokens.glassStroke, lineWidth: isPlaying ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
        .onTapGesture { handleTap(voice: index) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice \(voiceLetters[index])")
        .accessibilityValue(stage == .revealed ? sample.profile.displayName : "Flat caption")
        .accessibilityHint(stage == .mutedGuess
                           ? "Double tap to hear this voice, then guess its emotion."
                           : "Double tap to replay this emotional voice.")
        .accessibilityAddTraits(.isButton)
    }

    /// The caption glyphs, either sterile (Stage 1) or living (Stage 2).
    ///
    /// `@ViewBuilder` lets the two stages return structurally different views
    /// while the caller keeps a single `some View` call site.
    @ViewBuilder
    private func captionText(index: Int, activeFrame: ProsodyFrame) -> some View {
        if stage == .mutedGuess {
            // Stage 1: dead-flat caption. Uniform weight, 70% white, zero offset.
            // A tap flashes it brighter for a beat (the spec's sterile flash:
            // zero audio, zero motion - only a brightness pulse).
            Text(caption)
                .font(ThemeTokens.Typography.caption)
                .foregroundStyle(flashingVoice == index
                                 ? ThemeTokens.textPrimary
                                 : ThemeTokens.captionBaseline)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Stage 2: living typography driven by the live prosody frame.
            Text(caption)
                .font(ThemeTokens.Typography.hero)
                .foregroundStyle(ThemeTokens.textPrimary)
                .textRenderer(
                    ProsodyTextRenderer(
                        frame: activeFrame,
                        elapsedTime: elapsedTime,
                        reduceMotion: reduceMotion
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The card's glass surface, warming toward the emotion in Stage 2.
    private func cardBackground(index: Int, isPlaying: Bool, accent: Color) -> some View {
        RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
            .fill(ThemeTokens.glassFill)
            .overlay(
                RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                    .fill(stage == .revealed
                          ? accent.opacity(isPlaying ? 0.20 : 0.08)
                          : Color.clear)
            )
            .animation(reduceMotion ? nil : ThemeTokens.Motion.act, value: isPlaying)
    }

    // MARK: - Controls

    @ViewBuilder
    private var spacerAndControls: some View {
        switch stage {
        case .mutedGuess:
            mutedControls
        case .revealed:
            revealedControls
        }
    }

    /// Stage 1: the emotion guesses, then the unlock button once guessed.
    private var mutedControls: some View {
        VStack(spacing: ThemeTokens.Spacing.regular) {
            // §8 Act I layout: three emotion tags sit below the cards, always
            // visible so the judge knows the vocabulary before assigning it.
            VStack(spacing: ThemeTokens.Spacing.tight) {
                Text(tappedVoice == nil
                     ? "Assign each voice an emotion."
                     : "What did Voice \(voiceLetters[tappedVoice ?? 0]) really feel?")
                    .font(ThemeTokens.Typography.body)
                    .foregroundStyle(ThemeTokens.textSecondary)
                HStack(spacing: ThemeTokens.Spacing.tight) {
                    ForEach(EmotionalProfile.actOneChoices) { emotion in
                        emotionChip(emotion: emotion)
                            .disabled(tappedVoice == nil)
                            .opacity(tappedVoice == nil ? 0.45 : 1)
                    }
                }
            }

            if guessRevealed {
                Text("You cannot tell. Warm relief, quiet anxiety, and biting sarcasm all render as the exact same flat caption - standard subtitles strip away about 70% of human intent.")
                    .font(ThemeTokens.Typography.body)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            // Deliberately ungated: the reveal is always one tap away. A judge who
            // already understands the blindspot must never be walked through the
            // guessing game (or any animation) before the best material unlocks.
            unlockButton
        }
        .animation(reduceMotion ? nil : ThemeTokens.Motion.act, value: guessRevealed)
    }

    /// One emotion guess chip.
    private func emotionChip(emotion: EmotionalProfile) -> some View {
        let accent = ThemeTokens.accent(for: emotion)
        return Button {
            guess(emotion)
        } label: {
            Text(emotion.displayName)
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(accent)
                .padding(.horizontal, ThemeTokens.Spacing.regular)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.14))
                        .overlay(Capsule(style: .continuous).stroke(accent.opacity(0.4), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Guess \(emotion.displayName)")
        .accessibilityHint("Assign this emotion to the voice you tapped.")
    }

    /// The single glowing call to action that opens Stage 2.
    private var unlockButton: some View {
        Button {
            unlock()
        } label: {
            Text("Unlock Keller's Chord (Cross-Modal Prosody)")
                .font(ThemeTokens.Typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(ThemeTokens.obsidian)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ThemeTokens.Spacing.section)
                .padding(.vertical, ThemeTokens.Spacing.regular)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(ThemeTokens.accent(for: .warmRelief))
                )
                .shadow(color: ThemeTokens.accent(for: .warmRelief).opacity(0.55), radius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock Keller's Chord, cross-modal prosody")
        .accessibilityHint("Replays all three voices with living typography and tactile feedback.")
        .transition(.scale.combined(with: .opacity))
    }

    /// Stage 2: the continue button, unlocking after the reveal.
    private var revealedControls: some View {
        VStack(spacing: ThemeTokens.Spacing.regular) {
            Text("Every voice just played its true emotion through type and touch. That is the 70% flat captions erase.")
                .font(ThemeTokens.Typography.body)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                stopPlayback()
                onComplete()
            } label: {
                Text("Continue to Tactile Explorer")
                    .font(ThemeTokens.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(ThemeTokens.obsidian)
                    .padding(.horizontal, ThemeTokens.Spacing.section)
                    .padding(.vertical, ThemeTokens.Spacing.regular)
                    .frame(maxWidth: .infinity)
                    .background(Capsule(style: .continuous).fill(ThemeTokens.textPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue to tactile explorer")
            .accessibilityHint("Moves on to Act II, the Helen Keller tactile decoder.")
        }
    }

    // MARK: - Interaction logic

    /// Handles a tap on a Voice A/B/C card.
    ///
    /// In Stage 1 the card only flashes its sterile caption: no audio, no motion,
    /// exactly the emotional dead-end standard subtitles create. In Stage 2 the
    /// card plays its real voice note through the DSP engine.
    private func handleTap(voice: Int) {
        switch stage {
        case .mutedGuess:
            tappedVoice = voice
            guessedEmotion = nil
            guessRevealed = false
            // Deliberately no playback, no motion: the entire point is the
            // emotional dead-end. Only a sterile white flash marks the tap.
            flashingVoice = voice
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 140_000_000)
                if flashingVoice == voice { flashingVoice = nil }
            }
        case .revealed:
            playVoice(voice)
        }
    }

    /// Records the judge's guess and immediately reveals that it was a coin flip.
    private func guess(_ emotion: EmotionalProfile) {
        guessedEmotion = emotion
        withAnimation(reduceMotion ? nil : ThemeTokens.Motion.act) {
            guessRevealed = true
        }
    }

    /// Advances to Stage 2 and replays all three voices in sequence.
    ///
    /// Voice A plays, then B, then C, each lighting up and erupting into living
    /// typography while its prosody streams in. This is the authored reveal
    /// moment of Act I, so it runs itself rather than waiting on taps.
    private func unlock() {
        guard !orderedSamples.isEmpty else { return }
        withAnimation(reduceMotion ? nil : ThemeTokens.Motion.act) {
            stage = .revealed
        }
        runSequence(from: 0)
    }

    /// Plays voices `from...` in order, one after another.
    private func runSequence(from start: Int) {
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor in
            var index = start
            while index < orderedSamples.count, !Task.isCancelled {
                playVoice(index)
                // Hold for the sample's own length, then move to the next voice.
                let seconds = sampleDuration(index)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                index += 1
            }
            guard !Task.isCancelled else { return }
            // Leave the last card lit so its emotion keeps rendering.
            playingVoice = orderedSamples.count - 1
        }
    }

    /// The duration in seconds of a loaded sample, from its buffer length.
    private func sampleDuration(_ index: Int) -> Double {
        guard index < orderedSamples.count else { return 3.5 }
        let buffer = orderedSamples[index].buffer
        let rate = buffer.format.sampleRate
        guard rate > 0 else { return 3.5 }
        return Double(buffer.frameLength) / rate
    }

    /// Plays one voice's sample through the shared DSP engine.
    private func playVoice(_ index: Int) {
        guard index < orderedSamples.count else { return }
        playingVoice = index
        // Upgrade 1: the EQ stages sit in the playback graph, so the flag only has
        // to be current before `play` starts scheduling audio.
        applyCochlearSimulation()
        dspEngine.play(orderedSamples[index])
    }

    /// Tears down playback when leaving Act I.
    private func stopPlayback() {
        sequenceTask?.cancel()
        sequenceTask = nil
        playingVoice = nil
        dspEngine.stopPlayback()
    }
}
