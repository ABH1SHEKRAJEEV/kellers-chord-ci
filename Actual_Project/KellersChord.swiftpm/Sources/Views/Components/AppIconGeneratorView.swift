#if os(iOS)
import SwiftUI
import UIKit

/// The 1024 x 1024 Keller's Chord app icon, drawn as vectors.
///
/// This is the exact same composition as `Sources/Resources/AppIcon.svg`, kept in
/// two forms on purpose: the SVG is what you hand to a designer or open in a
/// browser, and this is what renders on device at full resolution with no
/// external tooling and no asset catalog.
///
/// Concept: a cymatic chord - three concentric nodal rings, one per emotion in the
/// app's own palette - collapsing into a single golden node, with the caption line
/// below it breaking into three bars. Sound becoming type you can read.
///
/// Colours come from `ThemeTokens` so the icon can never drift from the app.
struct AppIconArtwork: View {

    /// The app's own accent colours, reused rather than re-picked.
    private let amber = ThemeTokens.accent(for: .warmRelief)
    private let sky = ThemeTokens.accent(for: .anxiousTremor)
    private let crimson = ThemeTokens.accent(for: .sharpSarcasm)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            // All geometry is expressed as a fraction of the shorter side, so the
            // artwork is identical at 220 pt in the preview and at 1024 px on export.
            let center = CGPoint(x: geometry.size.width / 2, y: side * 0.425)
            let barY = side * 0.756

            ZStack {
                ThemeTokens.obsidian

                // Amber bloom behind the chord, so the rings sit in light.
                RadialGradient(
                    colors: [amber.opacity(0.30), amber.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0.445),
                    startRadius: 0,
                    endRadius: side * 0.55
                )

                // Cymatic chord: three nodal rings, one per emotion.
                ring(radius: 0.3223, color: sky, width: 0.0098, opacity: 0.28, side: side, center: center)
                ring(radius: 0.2393, color: crimson, width: 0.0117, opacity: 0.42, side: side, center: center)
                ring(radius: 0.1563, color: amber, width: 0.0176, opacity: 0.88, side: side, center: center)

                // The single resolved node.
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFD37A), amber],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: side * 0.1289, height: side * 0.1289)
                    .position(center)

                // Sound becoming type: the caption line breaking into bars.
                bar(width: 0.625, colors: [Color(hex: 0x23262E), Color(hex: 0x23262E)],
                    side: side, centerX: center.x, y: barY)
                bar(width: 0.469, colors: [Color(hex: 0x2C3038), Color(hex: 0x2C3038)],
                    side: side, centerX: center.x, y: barY + side * 0.0664)
                bar(width: 0.313, colors: [amber, Color(hex: 0xFFD37A)],
                    side: side, centerX: center.x, y: barY + side * 0.1328)
            }
        }
    }

    /// One nodal ring, sized as a fraction of the icon's side.
    private func ring(
        radius: CGFloat,
        color: Color,
        width: CGFloat,
        opacity: Double,
        side: CGFloat,
        center: CGPoint
    ) -> some View {
        let diameter = side * radius * 2
        return Circle()
            .stroke(color, lineWidth: max(side * width, 1))
            .frame(width: diameter, height: diameter)
            .opacity(opacity)
            .position(center)
    }

    /// One caption bar. The gold pair marks the bar that carries emotion rather
    /// than only text.
    private func bar(width: CGFloat, colors: [Color], side: CGFloat, centerX: CGFloat, y: CGFloat) -> some View {
        let height = side * 0.043
        return RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: side * width, height: height)
            .position(x: centerX, y: y + height / 2)
    }
}

/// Renders `AppIconArtwork` to a 1024 x 1024 PNG you can save straight to Photos.
///
/// **How to use it on device (no Mac required).** Temporarily point the app's root
/// view at this screen, run once, export the PNG, then revert:
///
/// ```swift
/// // Sources/KellersChordApp.swift
/// WindowGroup { AppIconGeneratorView() }   // was: RootCoordinatorView()
/// ```
///
/// It is deliberately *not* wired into the shipped choreography: an icon exporter
/// has no place in a judge's demo, and keeping it out means this screen cannot
/// break the experience.
struct AppIconGeneratorView: View {

    /// The export size Apple requires for a marketing icon.
    private static let side: CGFloat = 1024

    @State private var png: UIImage?
    @State private var failure: String?

    var body: some View {
        ZStack {
            ThemeTokens.obsidian.ignoresSafeArea()

            VStack(spacing: 28) {
                AppIconArtwork()
                    .frame(width: 220, height: 220)
                    // Apple masks the icon to a superellipse; approximate it so what
                    // you see is what lands on the home screen.
                    .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 50, style: .continuous)
                            .stroke(ThemeTokens.glassStroke, lineWidth: 1)
                    )

                Text("KELLER'S CHORD")
                    .font(ThemeTokens.Typography.pill)
                    .foregroundStyle(ThemeTokens.textSecondary)

                Button {
                    renderIcon()
                } label: {
                    Text("Render \(Int(Self.side)) x \(Int(Self.side)) PNG")
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
                }
                .buttonStyle(.plain)

                if let png {
                    ShareLink(
                        item: Image(uiImage: png),
                        preview: SharePreview("Keller's Chord icon", image: Image(uiImage: png))
                    ) {
                        Text("Save or Share the PNG")
                            .font(ThemeTokens.Typography.body)
                            .foregroundStyle(ThemeTokens.textPrimary)
                    }
                    .accessibilityHint("Opens the share sheet so you can save the 1024 pixel icon to Photos or Files.")

                    Text("\(Int(png.size.width)) x \(Int(png.size.height)) px, rendered on device")
                        .font(ThemeTokens.Typography.pill)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }

                if let failure {
                    Text(failure)
                        .font(ThemeTokens.Typography.pill)
                        .foregroundStyle(ThemeTokens.accent(for: .sharpSarcasm))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(ThemeTokens.Spacing.section)
            .frame(maxWidth: 520)
        }
        .preferredColorScheme(.dark)
    }

    /// Rasterises the artwork at exactly 1024 x 1024.
    ///
    /// `scale = 1` is what makes the output 1024 px rather than 1024 points at 3x
    /// (which would be 3072 px and rejected as a marketing icon).
    @MainActor
    private func renderIcon() {
        let renderer = ImageRenderer(
            content: AppIconArtwork().frame(width: Self.side, height: Self.side)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        guard let image = renderer.uiImage else {
            failure = "The icon could not be rendered on this device."
            return
        }
        png = image
        failure = nil
    }
}
#endif
