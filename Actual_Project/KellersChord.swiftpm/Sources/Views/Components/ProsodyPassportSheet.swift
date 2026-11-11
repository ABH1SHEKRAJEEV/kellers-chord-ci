import SwiftUI

/// The "Vocal Prosody Passport": a one-tap, Apple-Fitness-style radial summary of
/// everything the speaker's voice did during Act III.
///
/// Four concentric rings, each a single dimension of expressive speech that a deaf
/// or hard-of-hearing student has never been able to see about their own voice:
///
/// 1. **Pitch Expressiveness (`F0` range)** — how widely their pitch moved.
/// 2. **Harmonic Chest Warmth** — how much low-centroid resonance they carried.
/// 3. **Consonant Spark Clarity** — how often their `4-8 kHz` articulation landed.
/// 4. **Lombard Room-Volume Match** — how well their loudness suited the room.
///
/// Each ring fills to its own fraction, so the card reads as a signature rather
/// than a score. There is no grade, no percentage pass mark and no red cross: the
/// point is recognition, not judgement. The prominent **"Reset 3-Minute Judge
/// Tour"** button lets the next reviewer start clean.
struct ProsodyPassportSheet: View {

    /// Every frame captured during Act III, oldest first.
    var frames: [ProsodyFrame]
    /// The word snapshots, used for the consonant-spark ring.
    var wordSnapshots: [WordProsodySnapshot]
    /// The calibrated room noise floor in dB, for the Lombard ring's context line.
    var ambientNoiseDB: Float
    /// Closes the sheet without resetting.
    var onDismiss: () -> Void
    /// Resets Acts I, II and III for the next judge.
    var onResetTour: () -> Void

    /// Accessibility Reduce Motion: freezes the ring fill animation.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the one-shot fill animation from 0 to the measured value.
    @State private var revealProgress: Double = 0

    // MARK: - Measured signature

    /// One of the four passport rings.
    private struct Ring: Identifiable {
        let id: Int
        let title: String
        let detail: String
        /// `0...1` fill fraction.
        let value: Double
        let color: Color
    }

    /// The four measured rings, in reading order from outermost inward.
    private var rings: [Ring] {
        let voiced = frames.filter { $0.isVoiced }

        // 1 ── Pitch Expressiveness: the spread of normalized pitch, scaled so a
        //      0.35 spread (roughly a fifth of the full 85-320 Hz journey) reads
        //      as a full ring.
        let pitchSpread: Double
        if voiced.count >= 2 {
            let values = voiced.map { Double($0.normalizedPitch) }
            pitchSpread = (values.max() ?? 0) - (values.min() ?? 0)
        } else {
            pitchSpread = 0
        }

        // 2 ── Harmonic Chest Warmth: mean low-centroid resonance, inverted so a
        //      warm voice fills the ring (centroid 0.20 -> ~0.95).
        let warmth: Double
        if voiced.isEmpty {
            warmth = 0
        } else {
            let meanCentroid = voiced.reduce(0.0) { $0 + Double($1.spectralCentroid) } / Double(voiced.count)
            warmth = max(0, 1 - meanCentroid)
        }

        // 3 ── Consonant Spark Clarity: share of words that carried an air-burst.
        let sparkShare: Double
        if wordSnapshots.isEmpty {
            sparkShare = 0
        } else {
            let sparked = wordSnapshots.filter { $0.hasConsonantSpark }.count
            sparkShare = Double(sparked) / Double(wordSnapshots.count)
        }

        // 4 ── Lombard Room-Volume Match: share of voiced frames inside the
        //      room-adjusted band (the same band the haptic nudge uses).
        let band = ProsodyFrame.loudnessBand(ambientNoiseDB: ambientNoiseDB)
        let lowBand = Double(band.low)
        let highBand = Double(band.high)
        let matchShare: Double
        if voiced.isEmpty {
            matchShare = 0
        } else {
            let inBand = voiced.filter {
                let loudness = Double($0.rmsAmplitude)
                return loudness >= lowBand && loudness <= highBand
            }.count
            matchShare = Double(inBand) / Double(voiced.count)
        }

        return [
            Ring(
                id: 0,
                title: "Pitch Expressiveness",
                detail: pitchSpread > 0
                    ? "Range \(Int(pitchSpread * 100))% of the octave"
                    : "No voiced frames yet",
                value: min(pitchSpread / 0.35, 1),
                color: ThemeTokens.accent(for: .anxiousTremor)
            ),
            Ring(
                id: 1,
                title: "Harmonic Chest Warmth",
                detail: warmth > 0
                    ? (warmth > 0.65 ? "Warm chest resonance" : "Bright, less resonant")
                    : "No voiced frames yet",
                value: warmth,
                color: ThemeTokens.accent(for: .warmRelief)
            ),
            Ring(
                id: 2,
                title: "Consonant Spark Clarity",
                detail: wordSnapshots.isEmpty
                    ? "No words captured yet"
                    : "\(wordSnapshots.filter { $0.hasConsonantSpark }.count) of \(wordSnapshots.count) words crisp",
                value: sparkShare,
                color: Color(hex: 0xF8FAFC)
            ),
            Ring(
                id: 3,
                title: "Lombard Room-Volume Match",
                detail: voiced.isEmpty
                    ? "No voiced frames yet"
                    : "\(Int(matchShare * 100))% of speech suited this room",
                value: matchShare,
                color: Color(hex: 0x34D399)
            )
        ]
    }

    /// The room description used in the footer context line.
    private var roomLabel: String {
        switch ambientNoiseDB {
        case ..<(-45): return "Quiet Room"
        case ..<(-30): return "Normal Room"
        default: return "Noisy Hall"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: ThemeTokens.Spacing.section) {
            header
            ringStack
            legend
            dismissButton
            resetButton
        }
        .padding(ThemeTokens.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeTokens.obsidian.opacity(0.96))
        .onAppear {
            if reduceMotion {
                revealProgress = 1
            } else {
                withAnimation(ThemeTokens.Motion.reveal.delay(0.15)) {
                    revealProgress = 1
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("VOCAL PROSODY PASSPORT")
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
                .textCase(.uppercase)
            Text("Your Voice Signature")
                .font(ThemeTokens.Typography.title)
                .foregroundStyle(ThemeTokens.textPrimary)
            Text("This is what your voice carried that the words alone never showed.")
                .font(ThemeTokens.Typography.body)
                .foregroundStyle(ThemeTokens.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The four concentric rings, drawn outermost-in.
    private var ringStack: some View {
        let ringData = rings
        return ZStack {
            ForEach(ringData) { ring in
                let inset = CGFloat(ring.id) * 26
                Circle()
                    .stroke(ThemeTokens.glassStroke, lineWidth: 12)
                    .padding(inset)

                Circle()
                    .trim(from: 0, to: ring.value * revealProgress)
                    .stroke(
                        ring.color,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                    .shadow(color: ring.color.opacity(0.5), radius: 6)
            }

            // The centre: the room the speaker was judged in.
            VStack(spacing: 2) {
                Text(roomLabel)
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(Int(ambientNoiseDB)) dB")
                    .font(ThemeTokens.Typography.metric)
                    .foregroundStyle(ThemeTokens.textSecondary)
            }
            .padding(.horizontal, 10)
        }
        .frame(width: 260, height: 260)
        .accessibilityLabel("Four ring vocal prosody signature")
        .accessibilityValue(rings.map { "\($0.title) \(Int($0.value * 100)) percent" }.joined(separator: ", "))
    }

    /// The ring legend, one row per dimension with its measured detail.
    private var legend: some View {
        VStack(spacing: ThemeTokens.Spacing.tight) {
            ForEach(rings) { ring in
                HStack(spacing: ThemeTokens.Spacing.tight) {
                    Circle()
                        .fill(ring.color)
                        .frame(width: 8, height: 8)
                    Text(ring.title)
                        .font(ThemeTokens.Typography.body)
                        .foregroundStyle(ThemeTokens.textPrimary)
                    Spacer(minLength: 0)
                    Text(ring.detail)
                        .font(ThemeTokens.Typography.pill)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(ring.title)
                .accessibilityValue(ring.detail)
            }
        }
        .padding(ThemeTokens.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.Radius.chip, style: .continuous)
                .fill(ThemeTokens.glassFill)
        )
    }

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Back to the Mirror")
                .font(ThemeTokens.Typography.body)
                .foregroundStyle(ThemeTokens.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to the vocal mirror")
    }

    /// The prominent judge-tour reset, per Section 4.5 Upgrade 13.
    private var resetButton: some View {
        Button {
            onResetTour()
        } label: {
            Text("Reset 3-Minute Judge Tour")
                .font(ThemeTokens.Typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(ThemeTokens.obsidian)
                .padding(.horizontal, ThemeTokens.Spacing.section)
                .padding(.vertical, ThemeTokens.Spacing.regular)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(ThemeTokens.accent(for: .warmRelief))
                )
                .shadow(color: ThemeTokens.accent(for: .warmRelief).opacity(0.45), radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset three minute judge tour")
        .accessibilityHint("Clears every act so the next reviewer starts from the beginning.")
    }
}
