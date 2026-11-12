// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "KellersChord",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .iOSApplication(
            name: "KellersChord",
            targets: ["AppModule"],
            bundleIdentifier: "com.srm.kellerschord",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            // CI run 4 answered both icon questions with the same log:
            //   * the repair ladder resolved `.placeholder(icon: .star)` /
            //     `.presetColor(.orange)` — those two names are real;
            //   * `50-icon-probe.log` then reported that `.asset("AppIcon")`
            //     resolves too, with the catalog committed at
            //     `Sources/Resources/AppIcon.xcassets`.
            // So the manifest ships the real icon rather than a placeholder.
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft
            ],
            capabilities: [
                .microphone(purposeString: "KellersChord analyzes your vocal pitch, warmth, and cadence on-device to render living emotional typography and tactile feedback."),
                .speechRecognition(purposeString: "KellersChord transcribes your speech 100% offline to synchronize words with your vocal prosody.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        // NOTE: there is deliberately NO `.testTarget` here.
        //
        // A `.testTarget` that depends on this `iOSApplication` product cannot be
        // hosted: run 5's `xcodebuild test` died before running an assertion with
        //   lstat(.../KellersChord_AppModule.bundle): No such file or directory
        //   error: 'kellerschord.swiftpm': Invalid manifest
        // A Playgrounds App is not a library, so it has no module bundle to link a
        // test host against. The same declarations would also stop Swift Playgrounds
        // opening the bundle (SSC rule), so both frame-level suites now build as
        // standalone `swiftc` programs the workflow runs directly:
        //   Tests/DSPHarness/main.swift    - signal math (RMS, F0, sibilance)
        //   Tests/ModelHarness/main.swift  - frame invariants (bands, inflection)
    ]
)
