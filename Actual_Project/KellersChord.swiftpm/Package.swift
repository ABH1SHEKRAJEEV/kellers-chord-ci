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
            appIcon: .placeholder(icon: .waveform),
            accentColor: .presetColor(.amber),
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
        // Frame-level DSP invariants, run by `xcodebuild test` on the macOS CI
        // runner. `Tests/DSPHarness/` is deliberately NOT a target: it is a
        // standalone `swiftc` program the workflow compiles directly against the
        // engine sources, so the heavy signal tests cannot fail for packaging
        // reasons.
        .testTarget(
            name: "KellersChordTests",
            dependencies: ["AppModule"],
            path: "Tests/AppModuleTests"
        )
    ]
)
