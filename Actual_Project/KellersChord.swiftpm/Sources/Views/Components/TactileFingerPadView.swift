import SwiftUI

/// The 3-Finger Helen Keller Sensory Pad.
///
/// Three concentric zones, modeled on the exact hand placement Helen Keller used
/// to read a speaker's voice:
/// 1. **Palm / Thumb** — laryngeal pitch `F0` (85 Hz...320 Hz) and low-frequency
///    pitch sweeps.
/// 2. **Middle Finger** — nasal and chest warmth (spectral centroid): harmonic
///    warmth at the bottom, metallic sharpness at the top.
/// 3. **Index Finger** — consonant airflow and cadence (`RMS` + jitter).
///
/// Dragging across a zone sculpts that metric of the emitted `ProsodyFrame`; the
/// pad reports the blended frame upward so `ProsodyTextRenderer` and
/// `TactileHapticEngine` react with zero re-wiring. The three zones are laid out
/// along a gentle arc to read as a hand, not a control panel.
struct TactileFingerPadView: View {

    /// The value the pad currently reports. Bound so the parent can hold it as
    /// `currentFrame` when the judge is scrubbing by hand.
    @Binding var sculptedFrame: ProsodyFrame
    /// Honours Reduce Motion: removes the idle breathing pulse and freezes the
    /// cymatic nodal field into its static contour ring.
    var reduceMotion: Bool
    /// Called on every meaningful change, so the parent can render haptics.
    var onFrameChanged: (ProsodyFrame) -> Void

    /// Which zone the finger is currently inside, for the focus glow.
    @State private var activeZone: Zone?
    /// Live drag positions per zone, in each zone's own local space.
    @State private var zoneValues: [Zone: CGPoint] = [:]

    /// The three anatomical zones of the pad.
    enum Zone: String, CaseIterable, Identifiable {
        case palm
        case middleFinger
        case indexFinger

        var id: String { rawValue }

        var title: String {
            switch self {
            case .palm: return "Palm"
            case .middleFinger: return "Middle"
            case .indexFinger: return "Index"
            }
        }

        var anatomical: String {
            switch self {
            case .palm: return "Laryngeal Pitch"
            case .middleFinger: return "Nasal & Chest Warmth"
            case .indexFinger: return "Consonant Airflow"
            }
        }

        var symbol: String {
            switch self {
            case .palm: return "hand.raised.fill"
            case .middleFinger: return "waveform.path"
            case .indexFinger: return "wind"
            }
        }

        var accessibilityHint: String {
            switch self {
            case .palm:
                return "Drag up and down to raise or lower vocal pitch from 85 to 320 hertz."
            case .middleFinger:
                return "Drag up and down to change vocal warmth from soft chest resonance to sharp metallic tone."
            case .indexFinger:
                return "Drag up and down to add consonant bursts and vocal tremor."
            }
        }
    }

    var body: some View {
        VStack(spacing: ThemeTokens.Spacing.regular) {
            padSurface
            metricReadout
        }
        .padding(.horizontal, ThemeTokens.Spacing.section)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Helen Keller three-finger sensory pad")
    }

    // MARK: - Pad surface

    /// The three zones laid along a shallow arc so they read as fingertips on a
    /// palm rather than a row of sliders.
    ///
    /// Phase 2 (Upgrade 2): the cymatic `ChladniWaveCanvas` fills the pad's glass
    /// plate *behind* the zones, so the standing-wave nodal geometry a real voice
    /// would print on a driven plate is literally under the fingertips.
    private var padSurface: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                // The palm's implied surface: a soft glass plate.
                RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                    .fill(ThemeTokens.glassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous)
                            .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                    )

                // Phase 2 (Upgrade 2): the cymatic nodal field, sized to the plate
                // and dimmed so it enriches the surface without competing with the
                // three zones for attention.
                ChladniWaveCanvas(
                    frame: sculptedFrame,
                    reduceMotion: reduceMotion,
                    diameter: min(size.width, size.height) * 0.92,
                    accent: ThemeTokens.accent(for: sculptedFrame.classifiedEmotion)
                )
                .opacity(0.30)

                ForEach(Array(Zone.allCases.enumerated()), id: \.element.id) { index, zone in
                    zoneNode(zone: zone, index: index, in: size)
                }
            }
        }
        .frame(height: 260)
    }

    /// One draggable zone, positioned on the arc.
    private func zoneNode(zone: Zone, index: Int, in size: CGSize) -> some View {
        let layout = zoneLayout(index: index, in: size)
        let value = zoneValues[zone] ?? CGPoint(x: 0.5, y: 0.5)
        let isActive = activeZone == zone

        return ZonePad(
            zone: zone,
            value: value,
            color: ThemeTokens.accent(for: zoneEmotion(zone)),
            isActive: isActive,
            reduceMotion: reduceMotion,
            diameter: layout.diameter,
            // Phase 2 (Upgrade 10): the index finger is the airflow zone, so it is
            // the one that carries the Consonant Spark indicator.
            showsSpark: zone == .indexFinger && sculptedFrame.hasConsonantSpark
        )
        .position(x: layout.center.x, y: layout.center.y)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    activeZone = zone
                    update(zone: zone, from: drag.location, diameter: layout.diameter)
                }
                .onEnded { _ in
                    activeZone = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel("\(zone.anatomical) zone")
        .accessibilityValue(accessibilityValue(for: zone))
        .accessibilityHint(zone.accessibilityHint)
    }

    /// Positions the three zones along a shallow arc: the palm sits lowest and
    /// largest, the two fingers rise to either side.
    private func zoneLayout(index: Int, in size: CGSize) -> (center: CGPoint, diameter: CGFloat) {
        let midY = size.height * 0.56
        switch Zone.allCases[index] {
        case .palm:
            return (CGPoint(x: size.width * 0.24, y: midY + 26), 132)
        case .middleFinger:
            return (CGPoint(x: size.width * 0.52, y: midY - 22), 116)
        case .indexFinger:
            return (CGPoint(x: size.width * 0.80, y: midY + 6), 108)
        }
    }

    // MARK: - Metric readout

    /// A calm three-column readout of the sculpted values, so the judge sees the
    /// numbers behind the felt emotion.
    ///
    /// Deliberately flat: hairline dividers instead of three more glass cards, so
    /// the pad stays the focal point and the surface does not nest cards.
    private var metricReadout: some View {
        HStack(spacing: 0) {
            readoutColumn(
                label: "Pitch F0",
                value: sculptedFrame.fundamentalPitchHz > 0
                    ? "\(Int(sculptedFrame.fundamentalPitchHz)) Hz"
                    : "—"
            )
            divider
            readoutColumn(
                label: "Warmth",
                value: warmthLabel(sculptedFrame.spectralCentroid)
            )
            divider
            readoutColumn(
                label: "Tremor",
                value: "\(Int(sculptedFrame.pitchJitter * 100))%"
            )
        }
        .padding(.vertical, ThemeTokens.Spacing.tight)
    }

    private var divider: some View {
        Rectangle()
            .fill(ThemeTokens.glassStroke)
            .frame(width: 1, height: 26)
    }

    private func readoutColumn(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(ThemeTokens.Typography.pill)
                .foregroundStyle(ThemeTokens.textSecondary)
                .textCase(.uppercase)
            Text(value)
                .font(ThemeTokens.Typography.metric)
                .foregroundStyle(ThemeTokens.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func warmthLabel(_ centroid: Float) -> String {
        switch centroid {
        case ..<0.35: return "Warm"
        case ..<0.65: return "Neutral"
        default: return "Sharp"
        }
    }

    // MARK: - Sculpting

    /// Converts a finger position inside a zone into that zone's metric and
    /// blends the result into the emitted frame.
    ///
    /// `y = 0` is the top of the zone (maximum) and `y = 1` its bottom (minimum),
    /// so dragging upward raises pitch, brightness or airflow intuitively.
    private func update(zone: Zone, from location: CGPoint, diameter: CGFloat) {
        let normalized = min(max(location.y / max(diameter, 1), 0), 1)
        let rise = Float(1 - normalized)

        var frame = sculptedFrame
        switch zone {
        case .palm:
            // F0 across 85 Hz...320 Hz, with a low-frequency pitch sweep feel.
            let hz = 85 + rise * (320 - 85)
            frame.fundamentalPitchHz = hz
            frame.normalizedPitch = min(max((hz - 85) / (320 - 85), 0), 1)
        case .middleFinger:
            // Spectral centroid: warm chest resonance at the bottom, metallic at
            // the top, exactly matching the glyph bloom/shear behavior.
            frame.spectralCentroid = rise
        case .indexFinger:
            // Consonant airflow drives amplitude plus a tremor component, and the
            // top of the travel is where a real fricative air-burst begins, so it
            // also raises the `4-8 kHz` sibilance energy (Upgrade 10). That is what
            // lights the Consonant Spark indicator on this zone.
            frame.rmsAmplitude = max(frame.rmsAmplitude, rise)
            frame.pitchJitter = rise > 0.7 ? (rise - 0.7) / 0.3 * 0.8 : 0.1
            frame.sibilanceEnergy = rise > 0.55 ? min(max((rise - 0.55) / 0.45, 0), 1) : 0
        }

        // Reclassify from the raw metrics so the pad is self-consistent.
        frame.classifiedEmotion = EmotionalProfile.classify(
            centroid: frame.spectralCentroid,
            jitter: frame.pitchJitter,
            pitchSlope: 0,
            rms: frame.rmsAmplitude
        )

        // Glide instead of snapping: drag samples arrive at display rate, so a
        // short lerp removes the stair-stepping the glyph bloom and the cymatic
        // field would otherwise show while the finger moves.
        let smoothed = sculptedFrame.interpolated(toward: frame, factor: 0.45)

        zoneValues[zone] = location
        sculptedFrame = smoothed
        onFrameChanged(smoothed)
    }

    /// The emotion a zone's current value leans toward, used only for its glow.
    private func zoneEmotion(_ zone: Zone) -> EmotionalProfile {
        let value = zoneValues[zone] ?? CGPoint(x: 0.5, y: 0.5)
        let rise = Float(1 - min(max(value.y, 0), 1))
        switch zone {
        case .palm:
            return rise > 0.55 ? .anxiousTremor : .warmRelief
        case .middleFinger:
            return rise > 0.55 ? .sharpSarcasm : .warmRelief
        case .indexFinger:
            return rise > 0.7 ? .anxiousTremor : .warmRelief
        }
    }

    private func accessibilityValue(for zone: Zone) -> String {
        switch zone {
        case .palm:
            return sculptedFrame.fundamentalPitchHz > 0
                ? "Pitch \(Int(sculptedFrame.fundamentalPitchHz)) hertz"
                : "No pitch set"
        case .middleFinger:
            return "Warmth \(warmthLabel(sculptedFrame.spectralCentroid))"
        case .indexFinger:
            return "Tremor \(Int(sculptedFrame.pitchJitter * 100)) percent"
        }
    }
}

// MARK: - Zone pad

/// One glowing concentric touch zone.
///
/// Renders as a set of concentric rings with a live fill level, a soft bloom when
/// active, and an idle breathing pulse (suppressed under Reduce Motion). Uses the
/// emotion accent color so the pad's language matches the aura and the type.
private struct ZonePad: View {

    let zone: TactileFingerPadView.Zone
    let value: CGPoint
    let color: Color
    let isActive: Bool
    let reduceMotion: Bool
    let diameter: CGFloat
    /// Phase 2 (Upgrade 10): draws a small Ice White spark above the zone when the
    /// live `4-8 kHz` sibilance band is strong enough to count as a consonant
    /// air-burst. Only the index (airflow) zone ever sets this.
    let showsSpark: Bool

    /// A slow idle pulse phase, driven by a timeline-free repeating animation.
    @State private var breathe = false

    /// The fraction the current finger position implies (0 at bottom, 1 at top).
    private var level: Double {
        Double(1 - min(max(value.y, 0), 1))
    }

    var body: some View {
        ZStack {
            // Outer glass ring.
            Circle()
                .fill(ThemeTokens.glassFill)
                .overlay(
                    Circle().stroke(ThemeTokens.glassStroke, lineWidth: 1)
                )
                .frame(width: diameter, height: diameter)

            // Live fill: rises from the bottom as the value grows.
            Circle()
                .fill(color.opacity(0.28))
                .frame(width: diameter - 14, height: diameter - 14)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: (diameter - 14) * CGFloat(level))
                }

            // Active bloom ring.
            Circle()
                .stroke(color, lineWidth: isActive ? 3 : 1.5)
                .frame(width: diameter, height: diameter)
                .opacity(isActive ? 1 : 0.5)
                .shadow(color: color.opacity(isActive ? 0.7 : 0.25), radius: isActive ? 16 : 6)

            // Zone glyph + label.
            VStack(spacing: 4) {
                Image(systemName: zone.symbol)
                    .font(.system(size: diameter * 0.18, weight: .semibold))
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text(zone.title)
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text(zone.anatomical)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: diameter * 0.8)

            // Phase 2 (Upgrade 10): the Consonant Spark indicator, sat above the
            // zone's cap like the same accent in the living typography, so the eye
            // links the tick to the letter it belongs to.
            if showsSpark {
                Image(systemName: "sparkle")
                    .font(.system(size: diameter * 0.13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xF8FAFC))
                    .shadow(color: Color(hex: 0xF8FAFC).opacity(0.8), radius: 6)
                    .offset(y: -diameter * 0.46)
                    .transition(.scale.combined(with: .opacity))
                    .animation(reduceMotion ? nil : ThemeTokens.Motion.snappy, value: showsSpark)
            }
        }
        .scaleEffect(isActive ? 1.04 : (breathe && !reduceMotion ? 1.015 : 1.0))
        .animation(ThemeTokens.Motion.snappy, value: isActive)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(ThemeTokens.Motion.ambience.repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .allowsHitTesting(false)
    }
}
