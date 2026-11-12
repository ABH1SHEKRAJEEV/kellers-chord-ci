//
//  ModelHarness/main.swift - frame-level invariants, run by plain `swiftc`
//
//  Why this is not an XCTest bundle any more
//  -----------------------------------------
//  `Package.swift` declared a `.testTarget` that `@testable import AppModule`-ed
//  the Swift Playgrounds App product. `xcodebuild test` on that manifest failed
//  before running a single assertion:
//
//      error: lstat(.../KellersChord_AppModule.bundle): No such file or directory
//      error: 'kellerschord.swiftpm': Invalid manifest
//
//  An `iOSApplication` target is a Playgrounds product, not a library: it has no
//  module bundle to host, so a test bundle that depends on it can never resolve.
//  Two consequences drove this file:
//
//   * SSC rule: the shipping `Package.swift` must not carry a declaration that
//     stops Swift Playgrounds opening the app, so the `.testTarget` is gone.
//   * The assertions still have to run every push, so they now compile with
//     `swiftc` against the same pure model sources the DSP harness uses - no
//     manifest, no product, no host app. Same idea as `Tests/DSPHarness`.
//
//  The assertion bodies are the originals, unchanged; only the XCTest spellings
//  are provided by the shims below (so a diff against the old file is readable).

import AVFoundation
import Foundation

// MARK: - Assertion shims

var checkCount = 0
var failureCount = 0

private func report(_ text: String, file: StaticString, line: UInt) {
    // `StaticString` is not bridgeable to `NSString` (run 6's harness error), but it
    // is `CustomStringConvertible`, so describe it and keep only the file name.
    let path = String(describing: file)
    let name = path.split(separator: "/").last.map(String.init) ?? path
    print("FAIL: \(text)  [\(name):\(line)]")
}

private func tally() { checkCount += 1 }

func XCTAssertTrue(
    _ value: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    if !value() {
        failureCount += 1
        report(message().isEmpty ? "expected true" : message(), file: file, line: line)
    }
}

func XCTAssertFalse(
    _ value: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    if value() {
        failureCount += 1
        report(message().isEmpty ? "expected false" : message(), file: file, line: line)
    }
}

func XCTAssertEqual<T: Equatable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    let a = first()
    let b = second()
    if a != b {
        failureCount += 1
        report("\(a) != \(b)" + (message().isEmpty ? "" : " - \(message())"), file: file, line: line)
    }
}

func XCTAssertEqual<T: FloatingPoint>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    accuracy: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    let a = first()
    let b = second()
    if !(abs(a - b) <= accuracy) {
        failureCount += 1
        report("\(a) != \(b) +/- \(accuracy)" + (message().isEmpty ? "" : " - \(message())"),
               file: file, line: line)
    }
}

func XCTAssertLessThan<T: Comparable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    if !(first() < second()) {
        failureCount += 1
        report("\(first()) !< \(second())" + (message().isEmpty ? "" : " - \(message())"),
               file: file, line: line)
    }
}

func XCTAssertLessThanOrEqual<T: Comparable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    if !(first() <= second()) {
        failureCount += 1
        report("\(first()) !<= \(second())" + (message().isEmpty ? "" : " - \(message())"),
               file: file, line: line)
    }
}

func XCTAssertGreaterThan<T: Comparable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    if !(first() > second()) {
        failureCount += 1
        report("\(first()) !> \(second())" + (message().isEmpty ? "" : " - \(message())"),
               file: file, line: line)
    }
}

func XCTAssertGreaterThanOrEqual<T: Comparable>(
    _ first: @autoclosure () -> T,
    _ second: @autoclosure () -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    tally()
    if !(first() >= second()) {
        failureCount += 1
        report("\(first()) !>= \(second())" + (message().isEmpty ? "" : " - \(message())"),
               file: file, line: line)
    }
}

enum HarnessError: Error { case unwrap(String) }

func XCTUnwrap<T>(
    _ value: T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let value else {
        failureCount += 1
        report("unwrap nil" + (message().isEmpty ? "" : " - \(message())"), file: file, line: line)
        throw HarnessError.unwrap(message())
    }
    return value
}

// MARK: - The suite (bodies carried over from the XCTest file)

struct KellersChordModelChecks {

    // MARK: Baseline

    func testSilentBaselineIsNeutral() {
        let silent = ProsodyFrame.silent
        XCTAssertEqual(silent.rmsAmplitude, 0, accuracy: 0.0001)
        XCTAssertEqual(silent.normalizedPitch, 0.5, accuracy: 0.001)
        XCTAssertEqual(silent.classifiedEmotion, .neutral)
        XCTAssertFalse(silent.isVoiced)
        XCTAssertFalse(silent.hasConsonantSpark)
        XCTAssertEqual(silent.terminalInflection, .steady)
    }

    func testVoicedThreshold() {
        var frame = ProsodyFrame.silent
        frame.rmsAmplitude = 0.06
        XCTAssertTrue(frame.isVoiced)
        frame.rmsAmplitude = 0.04
        XCTAssertFalse(frame.isVoiced)
    }

    // MARK: Lombard loudness band (single source of truth)

    func testLoudnessBandQuietRoom() {
        let band = ProsodyFrame.loudnessBand(ambientNoiseDB: -50)
        XCTAssertEqual(band.low, 0.24, accuracy: 0.001)
        XCTAssertEqual(band.high, 0.72, accuracy: 0.001)
    }

    func testLoudnessBandNoisyRoom() {
        let band = ProsodyFrame.loudnessBand(ambientNoiseDB: -15)
        XCTAssertEqual(band.low, 0.42, accuracy: 0.001)
        XCTAssertEqual(band.high, 0.90, accuracy: 0.001)
    }

    func testLoudnessBandClampsAndStaysOrdered() {
        for decibels in stride(from: Float(-90), through: Float(10), by: 5) {
            let band = ProsodyFrame.loudnessBand(ambientNoiseDB: decibels)
            XCTAssertLessThan(band.low, band.high, "band inverted at \(decibels) dB")
            XCTAssertLessThanOrEqual(band.high, 0.94)
            XCTAssertGreaterThanOrEqual(band.low, 0.24)
        }
    }

    func testLoudnessBandRejectsNonFiniteInput() {
        let nan = ProsodyFrame.loudnessBand(ambientNoiseDB: .nan)
        XCTAssertEqual(nan.low, 0.24, accuracy: 0.001)
        XCTAssertEqual(nan.high, 0.72, accuracy: 0.001)
    }

    // MARK: Terminal inflection thresholds (Everything2.md 4.2)

    func testTerminalInflectionThresholds() {
        var frame = ProsodyFrame.silent

        frame.terminalPitchSlope = 0.29
        XCTAssertEqual(frame.terminalInflection, .risingQuestion)

        frame.terminalPitchSlope = 0.28
        XCTAssertEqual(frame.terminalInflection, .steady)

        frame.terminalPitchSlope = -0.25
        XCTAssertEqual(frame.terminalInflection, .steady)

        frame.terminalPitchSlope = -0.26
        XCTAssertEqual(frame.terminalInflection, .groundedDrop)
    }

    // MARK: Interpolation

    func testInterpolationLerpsAndClamps() {
        var target = ProsodyFrame.silent
        target.rmsAmplitude = 0.8
        target.fundamentalPitchHz = 200
        target.terminalPitchSlope = 0.5

        let halfway = ProsodyFrame.silent.interpolated(toward: target, factor: 0.45)
        XCTAssertEqual(halfway.rmsAmplitude, 0.36, accuracy: 0.001)
        XCTAssertEqual(halfway.fundamentalPitchHz, 90, accuracy: 0.001)
        XCTAssertEqual(halfway.terminalPitchSlope, 0.225, accuracy: 0.001)

        let overshoot = ProsodyFrame.silent.interpolated(toward: target, factor: 4.0)
        XCTAssertEqual(overshoot.rmsAmplitude, 0.8, accuracy: 0.001)

        let negative = ProsodyFrame.silent.interpolated(toward: target, factor: -3.0)
        XCTAssertEqual(negative.rmsAmplitude, 0, accuracy: 0.001)
    }

    // MARK: Averaged take frame

    func testAveragedFrameOfEmptySnapshotsIsSilent() {
        XCTAssertEqual(LiveChallengeTake.averagedFrame(of: []), ProsodyFrame.silent)
    }

    func testAveragedFrameMeansEveryMetric() {
        var a = ProsodyFrame.silent
        a.rmsAmplitude = 0.2
        a.sibilanceEnergy = 0.1
        var b = ProsodyFrame.silent
        b.rmsAmplitude = 0.6
        b.sibilanceEnergy = 0.5

        let snapshots = [a, b].enumerated().map { index, frame in
            WordProsodySnapshot(
                word: "word\(index)",
                timestampOffset: Double(index) * 0.3,
                duration: 0.3,
                frames: [frame],
                dominantFrame: frame,
                hasConsonantSpark: frame.hasConsonantSpark,
                terminalInflection: frame.terminalInflection
            )
        }

        let averaged = LiveChallengeTake.averagedFrame(of: snapshots)
        XCTAssertEqual(averaged.rmsAmplitude, 0.4, accuracy: 0.001)
        XCTAssertEqual(averaged.sibilanceEnergy, 0.3, accuracy: 0.001)
    }

    // MARK: Act stage timing

    func testProgressAnchorsAreMonotonic() {
        let stages = ActStage.allCases
        for (index, stage) in stages.enumerated() where index > 0 {
            XCTAssertGreaterThan(stage.progressAnchor, stages[index - 1].progressAnchor)
        }
        XCTAssertEqual(stages.last?.progressAnchor ?? 0, 0.583, accuracy: 0.0001)
        let lastSpan = stages[stages.count - 1].progressSpan
        XCTAssertEqual(lastSpan.end, 1.0, accuracy: 0.0001)
        // The wordmark rail names the acts, so every act needs a real name.
        for stage in stages {
            XCTAssertTrue(!stage.name.isEmpty)
        }
    }

    /// CI launch flags must always resolve to a real act, and the default (no
    /// flags) must be Act I so the judge's path is untouched.
    func testLaunchIntentFlags() {
        let judge = LaunchIntent.current(arguments: ["KellersChord"])
        XCTAssertEqual(judge.act, .act1Blindspot)
        XCTAssertFalse(judge.opensActOneUnlocked)
        XCTAssertFalse(judge.opensInDuet)
        XCTAssertTrue(judge.actTwoFrame == nil)

        let unlocked = LaunchIntent.current(arguments: ["KellersChord", "--ci-act1-unlocked"])
        XCTAssertTrue(unlocked.opensActOneUnlocked)
        XCTAssertEqual(unlocked.act, .act1Blindspot)

        let chladni = LaunchIntent.current(arguments: ["KellersChord", "--ci-act2-chladni"])
        XCTAssertEqual(chladni.act, .act2TactileDecoder)
        XCTAssertEqual(chladni.actTwoFrame?.classifiedEmotion, .warmRelief)
        XCTAssertTrue(chladni.actTwoFrame?.isVoiced ?? false)

        let duet = LaunchIntent.current(arguments: ["KellersChord", "--ci-act3-duet"])
        XCTAssertEqual(duet.act, .act3VocalMirror)
        XCTAssertTrue(duet.opensInDuet)

        // Preview frames must be inside the matrix bands, or the screenshot would
        // photograph a state the classifier can never produce.
        for profile in EmotionalProfile.actOneChoices {
            let frame = ProsodyFrame.preview(profile)
            XCTAssertEqual(frame.classifiedEmotion, profile)
            XCTAssertTrue(frame.isVoiced)
            XCTAssertTrue(frame.normalizedPitch >= 0 && frame.normalizedPitch <= 1)
            XCTAssertTrue(frame.spectralCentroid >= 0 && frame.spectralCentroid <= 1)
        }
    }

    // MARK: One real signal through the real analyzer

    /// The autocorrelation estimate on a synthetic 200 Hz sine.
    func testFundamentalPitchOnSyntheticTwoHundredHertz() throws {
        let sampleRate: Double = 44_100
        let frames = 1_024
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let analyzer = ProsodyAnalyzer()
        var last = ProsodyFrame.silent

        for bufferIndex in 0..<40 {
            let buffer = try XCTUnwrap(
                AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
            )
            buffer.frameLength = AVAudioFrameCount(frames)
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<frames {
                let sample = bufferIndex * frames + index
                channel[index] = 0.5 * sin(2 * Float.pi * 200 * Float(sample) / Float(sampleRate))
            }
            if let frame = analyzer.process(buffer) { last = frame }
        }

        XCTAssertEqual(last.fundamentalPitchHz, 200, accuracy: 4)
        XCTAssertEqual(last.normalizedPitch, 0.4894, accuracy: 0.03)
        XCTAssertGreaterThan(last.rmsAmplitude, 0.5)
        XCTAssertLessThan(last.sibilanceEnergy, 0.01)
    }
}

// MARK: - Runner

let suite = KellersChordModelChecks()

let orderedChecks: [(String, () throws -> Void)] = [
    ("silent baseline is neutral", suite.testSilentBaselineIsNeutral),
    ("voiced threshold", suite.testVoicedThreshold),
    ("loudness band, quiet room", suite.testLoudnessBandQuietRoom),
    ("loudness band, noisy room", suite.testLoudnessBandNoisyRoom),
    ("loudness band clamps + order", suite.testLoudnessBandClampsAndStaysOrdered),
    ("loudness band rejects NaN", suite.testLoudnessBandRejectsNonFiniteInput),
    ("terminal inflection thresholds", suite.testTerminalInflectionThresholds),
    ("interpolation lerps + clamps", suite.testInterpolationLerpsAndClamps),
    ("averaged frame of no snapshots", suite.testAveragedFrameOfEmptySnapshotsIsSilent),
    ("averaged frame means metrics", suite.testAveragedFrameMeansEveryMetric),
    ("progress anchors monotonic", suite.testProgressAnchorsAreMonotonic),
    ("CI launch intent flags", suite.testLaunchIntentFlags),
    ("autocorrelation on 200 Hz sine", suite.testFundamentalPitchOnSyntheticTwoHundredHertz),
]

for (name, check) in orderedChecks {
    let before = failureCount
    do {
        try check()
    } catch {
        failureCount += 1
        print("FAIL: \(name) threw \(error)")
    }
    print(failureCount == before ? "PASS: \(name)" : "FAIL: \(name)")
}

print("")
print(" \(checkCount) CHECK\(checkCount == 1 ? "" : "S"), \(failureCount) FAILED")
exit(failureCount == 0 ? 0 : 1)
