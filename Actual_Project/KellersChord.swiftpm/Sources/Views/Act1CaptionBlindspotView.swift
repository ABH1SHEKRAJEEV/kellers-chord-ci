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
    /// CI only (`--ci-act1-unlocked`): open with the chord already unlocked.
    ///
    /// A screenshot cannot tap through the guessing game, so this jumps straight to
    /// the authored reveal and plays the three voices. Defaulted, so the shipping
    /// path never sees it.
    var initiallyUnlocked: Bool = false
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

    /// Waveform envelopes read once from the three samples.
    ///
    /// Act I's whole argument is that three voices share one caption, so the
    /// difference has to be *visible* before it is audible. The ribbon is drawn
    /// from the real buffer, so a synthesized fallback shows its own shape.
    @State private var envelopes: [[Float]] = []

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > 780

            Group {
                if isWide {
                    HStack(alignment: .top, spacing: 36) {
                        captionColumn
                            .frame(maxWidth: .infinity, alignment: .leading)
                        sideColumn
                            .frame(width: 340, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        captionColumn
                        sideColumn
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .task {
            if envelopes.isEmpty {
                envelopes = orderedSamples.map { AudioSampleLoader.envelope(of: $0) }
            }
            if initiallyUnlocked, stage == .mutedGuess {
                unlock()
            }
        }
        .onDisappear(perform: stopPlayback)
    }

    // MARK: - The caption stage (left: the one big thing)

    /// The hero of the act: the shared caption, at display size, on the emotional
    /// field of whichever voice is speaking.
    ///
    /// v1 repeated this identical sentence in three identical grey cards, so the
    /// screen's dominant element was its least informative one. It now appears once,
    /// large, and the rows beside it are three *different* voices.
    private var captionColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(stage == .mutedGuess
                 ? "Three voices. One caption. Guess the feeling."
                 : "Same words. Now you can feel the difference.")
                .font(ThemeTokens.Text.headline)
                .foregroundStyle(ThemeTokens.House.paper)
                .fixedSize(horizontal: false, vertical: true)

            // The field: a flat colour block, not a glass card. The emotion IS the
            // background, so the caption sits inside the feeling instead of on a
            // grey rectangle.
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(fieldColor)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(activeVoiceLabel)
                            .font(ThemeTokens.Text.label)
                            .foregroundStyle(ThemeTokens.House.paper.opacity(0.75))
                        Spacer(minLength: 0)
                        Text(stage == .mutedGuess ? "flat caption" : activeEmotion.displayName)
                            .font(ThemeTokens.Text.label)
                            .foregroundStyle(ThemeTokens.House.paper.opacity(0.95))
                    }
                    .padding(.bottom, 18)

                    captionText()
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 20)

                    MetricLadder(frame: stageFrame, accent: ThemeTokens.House.paper.opacity(0.85))
                        .frame(maxWidth: 320)
                }
                .padding(28)
            }
            .frame(minHeight: 320)
            .animation(reduceMotion ? nil : ThemeTokens.Motion.act, value: activeEmotion)

            HStack(spacing: 10) {
                ForEach(Array(orderedSamples.enumerated()), id: \.offset) { index, sample in
                    Circle()
                        .fill(playingVoice == index
                              ? ThemeTokens.accent(for: sample.profile)
                              : ThemeTokens.textSecondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
                Text(stage == .mutedGuess
                     ? "Every voice shows this exact sentence."
                     : "Colour, weight and motion carry what the words cannot.")
                    .font(ThemeTokens.Text.label)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
        }
    }

    /// The colour of the caption field: neutral ink while guessing, the speaking
    /// voice's own emotion once the chord unlocks.
    private var fieldColor: Color {
        guard stage == .revealed else { return ThemeTokens.Surface.level2 }
        let first = ThemeTokens.Palette.colors(for: activeEmotion).first
        return (first ?? ThemeTokens.Surface.level2)
            .opacity(playingVoice == nil ? 0.20 : 0.34)
    }

    private var activeEmotion: EmotionalProfile {
        guard stage == .revealed,
              let index = playingVoice,
              index < orderedSamples.count else { return .neutral }
        return orderedSamples[index].profile
    }

    private var activeVoiceLabel: String {
        guard let index = playingVoice, index < orderedSamples.count else {
            return "Voice A / B / C"
        }
        return "Voice \(voiceLetters[index])"
    }

    private var stageFrame: ProsodyFrame {
        guard stage == .revealed, playingVoice != nil else { return .silent }
        return liveFrame
    }

    /// The caption glyphs: sterile in Stage 1, living in Stage 2.
    @ViewBuilder
    private func captionText() -> some View {
        if stage == .mutedGuess {
            // Stage 1: dead-flat caption, uniform weight, 70% white, zero motion.
            Text(caption)
                .font(ThemeTokens.Text.display(56))
                .foregroundStyle(ThemeTokens.captionBaseline)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(caption)
                .font(ThemeTokens.Text.display(56))
                .foregroundStyle(ThemeTokens.House.paper)
                .textRenderer(
                    ProsodyTextRenderer(
                        frame: stageFrame,
                        elapsedTime: elapsedTime,
                        reduceMotion: reduceMotion
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The side column (right: balances the caption)

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(stage == .mutedGuess ? "Hear it, then call it." : "Replay any voice.")
                .font(ThemeTokens.Text.subhead)
                .foregroundStyle(ThemeTokens.textSecondary)

            VStack(spacing: 10) {
                ForEach(Array(orderedSamples.enumerated()), id: \.offset) { index, sample in
                    voiceRow(index: index, sample: sample)
                }
            }

            spacerAndControls

            sideFooter

            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer (hearing-loss simulation + honesty note)

    /// The cochlear-implant simulation toggle and the note about the demo voices.
    ///
    /// Both lived in v1, and both are load-bearing: the toggle is Upgrade 1 of the
    /// accessibility story, and the note is what stops a judge thinking the three
    /// voices are the ones in `VoiceNotes/`.
    private var sideFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stage == .revealed {
                Toggle(isOn: $isCochlearSimulationOn) {
                    Text("Simulate profound hearing loss")
                        .font(ThemeTokens.Text.label)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
                .toggleStyle(.switch)
                .tint(ThemeTokens.House.ember)
                .onChange(of: isCochlearSimulationOn) { _, _ in
                    applyCochlearSimulation()
                }
                .accessibilityLabel("Simulate profound hearing loss")
                .accessibilityValue(isCochlearSimulationOn ? "On" : "Off")
                .accessibilityHint("Narrows the audio to the 280 hertz cochlear implant band.")
            }

            if usesSynthesizedAudio {
                Text("Demo voices are synthesized. Add your own .m4a clips to VoiceNotes to hear real prosody.")
                    .font(ThemeTokens.Text.label)
                    .foregroundStyle(ThemeTokens.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One voice: a real waveform, its letter, and its emotion once revealed.
    ///
    /// Not a card. Three identical bordered rectangles were the clearest generated
    /// -layout tell on the v1 screen. These are rows in one column, separated by a
    /// step in tone, each identified by its own waveform.
    private func voiceRow(index: Int, sample: AudioSampleLoader.LoadedSample) -> some View {
        let isPlaying = playingVoice == index
        let isTapped = tappedVoice == index
        let accent = ThemeTokens.accent(for: sample.profile)
        let envelope = index < envelopes.count ? envelopes[index] : []

        return Button {
            handleTap(voice: index)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Voice \(voiceLetters[index])")
                        .font(ThemeTokens.Text.label)
                        .foregroundStyle(isPlaying || isTapped
                                         ? ThemeTokens.House.paper
                                         : ThemeTokens.textSecondary)
                    Spacer(minLength: 0)
                    if stage == .revealed {
                        Text(sample.profile.displayName)
                            .font(ThemeTokens.Text.label)
                            .foregroundStyle(accent)
                    } else if isTapped {
                        Text("tapped")
                            .font(ThemeTokens.Text.label)
                            .foregroundStyle(ThemeTokens.textSecondary)
                    }
                }

                WaveRibbon(
                    envelope: envelope,
                    accent: stage == .revealed ? accent : ThemeTokens.textSecondary,
                    progress: nil
                )
                .frame(height: 26)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTapped || isPlaying
                          ? ThemeTokens.Surface.level3
                          : ThemeTokens.Surface.level1)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isTapped || isPlaying ? accent : Color.clear)
                    .frame(width: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice \(voiceLetters[index])")
        .accessibilityValue(stage == .revealed ? sample.profile.displayName : "Flat caption")
        .accessibilityHint(stage == .mutedGuess
                           ? "Double tap to hear this voice, then guess its emotion."
                           : "Double tap to replay this emotional voice.")
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
        VStack(alignment: .leading, spacing: 14) {
            // The vocabulary is always visible, so a judge knows the three options
            // before assigning one. Full-width rows: at 340pt the three names on one
            // line overflowed, which is what collapsed the v1 chip row.
            VStack(alignment: .leading, spacing: 8) {
                Text(tappedVoice == nil
                     ? "Assign each voice an emotion."
                     : "What did Voice \(voiceLetters[tappedVoice ?? 0]) really feel?")
                    .font(ThemeTokens.Text.body)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(EmotionalProfile.actOneChoices) { emotion in
                    emotionChip(emotion: emotion)
                        .disabled(tappedVoice == nil)
                        .opacity(tappedVoice == nil ? 0.5 : 1)
                }
            }

            if guessRevealed {
                Text("All three render as this exact caption. Standard subtitles erase about 70% of human intent.")
                    .font(ThemeTokens.Text.label)
                    .foregroundStyle(ThemeTokens.textSecondary)
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

    /// One emotion guess chip: a full-width row that names its own colour.
    private func emotionChip(emotion: EmotionalProfile) -> some View {
        let accent = ThemeTokens.accent(for: emotion)
        return Button {
            guess(emotion)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 14, height: 14)
                Text(emotion.displayName)
                    .font(ThemeTokens.Text.body)
                    .foregroundStyle(ThemeTokens.House.paper)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Guess \(emotion.displayName)")
        .accessibilityHint("Assign this emotion to the voice you tapped.")
    }

    /// The one action that opens Stage 2.
    ///
    /// Flat ember, radius 12, no glow: the v1 pill's 18pt shadow was the only
    /// "premium" gesture on the screen, which made everything around it look
    /// unfinished by comparison.
    private var unlockButton: some View {
        Button {
            unlock()
        } label: {
            HStack(spacing: 8) {
                Text("Unlock Keller's Chord")
                    .font(ThemeTokens.Text.body)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(ThemeTokens.obsidian)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ThemeTokens.House.ember)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock Keller's Chord, cross-modal prosody")
        .accessibilityHint("Replays all three voices with living typography and tactile feedback.")
        .transition(.opacity)
    }

    /// Stage 2: the continue button, revealed once the chord has played.
    private var revealedControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Every voice just played its real emotion through type and touch.")
                .font(ThemeTokens.Text.label)
                .foregroundStyle(ThemeTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                stopPlayback()
                onComplete()
            } label: {
                HStack(spacing: 8) {
                    Text("Tactile Explorer")
                        .font(ThemeTokens.Text.body)
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(ThemeTokens.House.paper)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ThemeTokens.Surface.level3)
                )
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

    /// Mirrors the toggle into the audio graph.
    ///
    /// The two 280 Hz low-pass stages live between the player and the mixer, so the
    /// judge hears the muffled signal the analyzer also measures. The flag is set
    /// before `play` schedules audio, so a replay never leaks an un-filtered buffer.
    private func applyCochlearSimulation() {
        dspEngine.isCochlearSimulationEnabled = isCochlearSimulationOn
    }

    /// Tears down playback when leaving Act I.
    private func stopPlayback() {
        sequenceTask?.cancel()
        sequenceTask = nil
        playingVoice = nil
        dspEngine.stopPlayback()
    }
}
