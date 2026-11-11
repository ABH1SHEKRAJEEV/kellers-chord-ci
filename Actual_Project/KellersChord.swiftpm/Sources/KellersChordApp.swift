import SwiftUI

/// The `@main` entry point for Keller's Chord.
///
/// The app is a single, self-contained experience: `RootCoordinatorView` owns the
/// entire 180-second three-act choreography and every engine, so this entry point
/// only needs to present it. No scene delegates, no `URLSession`, no cloud, and
/// no external packages — a fully offline Swift Student Challenge playground.
@main
struct KellersChordApp: App {
    var body: some Scene {
        WindowGroup {
            RootCoordinatorView()
                .preferredColorScheme(.dark)
                .tint(ThemeTokens.accent(for: .warmRelief))
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif
    }
}
