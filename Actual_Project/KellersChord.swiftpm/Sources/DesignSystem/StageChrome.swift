import AVFoundation
import SwiftUI

// MARK: - Wordmark bar
//
// The v1 chrome was a glass pill holding three tiny I / II / III buttons and a
// hairline progress rule. It said nothing about the product, and on an idle screen
// it was the only thing with any texture, so the eye went to the navigation
// instead of the idea.
//
// The v2 bar is a plain row: the wordmark in ember at the left, the three acts as
// real names in the middle, the live emotion and timecode at the right. No glass,
// no pill, no hairline: separation comes from a step in tone and from spacing.

struct WordmarkBar: View {
    /// The current act, for the selected state.
    var current: ActStage
    /// The live emotion, shown at the right as the app's status.
    var emotion: EmotionalProfile
    /// 0...1 through the whole experience.
    var progress: Double
    /// Jumps to another act immediately.
    var onSelect: (ActStage) -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text("KELLER'S CHORD")
                    .font(ThemeTokens.Text.wordmark)
                    .foregroundStyle(ThemeTokens.House.ember)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 12)

                HStack(spacing: 18) {
                    ForEach(ActStage.allCases) { stage in
                        actButton(stage)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Circle()
                        .fill(ThemeTokens.accent(for: emotion))
                        .frame(width: 7, height: 7)
                    Text(emotion.displayName)
                        .font(ThemeTokens.Text.label)
                        .foregroundStyle(ThemeTokens.textSecondary)
                    Text(current.timecode)
                        .font(ThemeTokens.Text.metric)
                        .foregroundStyle(ThemeTokens.textSecondary.opacity(0.8))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Live emotion \(emotion.displayName), \(current.timecode)")
            }

            // A progress rule is the one place a line earns its keep: it is a real
            // measurement, not decoration. It is filled, not stroked.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(ThemeTokens.Surface.level2)
                    Rectangle()
                        .fill(ThemeTokens.accent(for: emotion))
                        .frame(width: max(2, geometry.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 32)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(ThemeTokens.Surface.level0.opacity(0.55))
    }

    private func actButton(_ stage: ActStage) -> some View {
        let isCurrent = stage == current
        return Button {
            guard !isCurrent else { return }
            onSelect(stage)
        } label: {
            Text(stage.name)
                .font(ThemeTokens.Text.label)
                .foregroundStyle(isCurrent ? ThemeTokens.House.paper : ThemeTokens.textSecondary)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isCurrent ? ThemeTokens.House.ember : Color.clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stage.pillLabel)
        .accessibilityHint("Switches to this act immediately.")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Metric ladder
//
// Three real measurements from the current `ProsodyFrame`: pitch, loudness and
// air (4-8 kHz sibilance). v1 printed these as 13pt monospaced numbers in the
// corner, which nobody reads. A bar with the number beside it is readable at a
// glance and gives the right-hand column the weight it needs to balance the
// caption on the left.

struct MetricLadder: View {
    var frame: ProsodyFrame
    /// Colour of the current emotion, so the bars belong to the field behind them.
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("Pitch", value: Double(frame.normalizedPitch), detail: pitchDetail)
            row("Loudness", value: Double(frame.rmsAmplitude), detail: loudnessDetail)
            row("Air", value: Double(frame.sibilanceEnergy), detail: airDetail)
        }
        .accessibilityElement(children: .contain)
    }

    private var pitchDetail: String {
        frame.fundamentalPitchHz > 0
            ? "\(Int(frame.fundamentalPitchHz)) Hz"
            : "silent"
    }

    private var loudnessDetail: String {
        "\(Int(min(max(frame.rmsAmplitude, 0), 1) * 100))%"
    }

    private var airDetail: String {
        frame.hasConsonantSpark ? "spark" : "none"
    }

    private func row(_ name: String, value: Double, detail: String) -> some View {
        let clamped = min(max(value.isFinite ? value : 0, 0), 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(ThemeTokens.Text.label)
                    .foregroundStyle(ThemeTokens.textSecondary)
                Spacer(minLength: 8)
                Text(detail)
                    .font(ThemeTokens.Text.metric)
                    .foregroundStyle(ThemeTokens.House.paper)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Rectangle()
                        .fill(accent)
                        .frame(width: max(2, geometry.size.width * clamped))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(detail)")
    }
}

// MARK: - Wave ribbon
//
// A real waveform envelope read off the sample's own buffers - not a decorative
// squiggle. Three voices that share one flat caption still look different here,
// which is the whole point of Act I: the difference was always in the audio.

struct WaveRibbon: View {
    /// Normalised 0...1 envelope, oldest first.
    var envelope: [Float]
    var accent: Color
    /// 0...1 playhead, or nil when this voice is not playing.
    var progress: Double?

    var body: some View {
        Canvas { context, size in
            guard !envelope.isEmpty else { return }
            let mid = size.height / 2
            let step = size.width / CGFloat(max(envelope.count - 1, 1))

            var path = Path()
            for (index, value) in envelope.enumerated() {
                let x = CGFloat(index) * step
                let amplitude = CGFloat(min(max(value, 0), 1)) * mid * 0.94
                path.move(to: CGPoint(x: x, y: mid - amplitude))
                path.addLine(to: CGPoint(x: x, y: mid + amplitude))
            }
            context.stroke(
                path,
                with: .color(accent.opacity(progress == nil ? 0.55 : 0.9)),
                lineWidth: 1.6
            )

            if let progress {
                let x = size.width * CGFloat(min(max(progress, 0), 1))
                var playhead = Path()
                playhead.move(to: CGPoint(x: x, y: 0))
                playhead.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(playhead, with: .color(ThemeTokens.House.paper), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Envelope extraction

extension AudioSampleLoader {
    /// Normalised peak envelope of a buffer, `count` buckets wide.
    ///
    /// Read straight off the sample that will actually be played, so the ribbon is
    /// honest: a synthesized fallback voice draws its own shape, not a stock one.
    static func envelope(of sample: AudioSampleLoader.LoadedSample, count: Int = 96) -> [Float] {
        guard count > 0,
              let channel = sample.buffer.floatChannelData?[0] else { return [] }
        let frames = Int(sample.buffer.frameLength)
        guard frames > 0 else { return [] }

        let bucket = max(frames / count, 1)
        var peaks: [Float] = []
        peaks.reserveCapacity(count)
        var index = 0
        while index < frames && peaks.count < count {
            var peak: Float = 0
            let end = min(index + bucket, frames)
            var cursor = index
            while cursor < end {
                peak = max(peak, abs(channel[cursor]))
                cursor += 1
            }
            peaks.append(peak)
            index = end
        }
        let loudest = peaks.max() ?? 0
        guard loudest > 0.0001 else { return peaks.map { _ in 0 } }
        return peaks.map { min(max($0 / loudest, 0), 1) }
    }
}
