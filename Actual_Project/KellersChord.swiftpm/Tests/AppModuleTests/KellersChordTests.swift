//
//  KellersChordTests.swift — XCTest surface for the DSP model math
//
//  Deliberately split in two:
//
//  * The *heavy* signal-level suite (RMS normalization, autocorrelation F0,
//    spectral centroid, jitter gating, 4-8 kHz sibilance) lives in
//    `Tests/DSPHarness/main.swift`, which the CI workflow compiles with plain
//    `swiftc` against the engine sources. That path has no SwiftPM manifest, no
//    `@main` link, and no `AppleProductTypes` dependency, so it cannot fail for
//    packaging reasons.
//
//  * This file holds the cheap, deterministic, frame-level invariants. It runs
//    under `xcodebuild test` and is expected to link, but if the executable
//    target refuses to link into a test bundle the workflow treats that as a
//    packaging finding, not a math failure.
//

import AVFoundation
import XCTest

@testable import AppModule

final class KellersChordTests: XCTestCase {

    // MARK: - Baseline

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

    // MARK: - Lombard loudness band (single source of truth)

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

    // MARK: - Terminal inflection thresholds (Everything2.md 4.2)

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

    // MARK: - Interpolation

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

    // MARK: - Averaged take frame

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

    // MARK: - Act stage timing

    func testProgressAnchorsAreMonotonic() {
        let stages = ActStage.allCases
        for (index, stage) in stages.enumerated() where index > 0 {
            XCTAssertGreaterThan(stage.progressAnchor, stages[index - 1].progressAnchor)
        }
        XCTAssertEqual(stages.last?.progressAnchor ?? 0, 0.583, accuracy: 0.0001)
        let lastSpan = stages[stages.count - 1].progressSpan
        XCTAssertEqual(lastSpan.end, 1.0, accuracy: 0.0001)
    }

    // MARK: - One real signal through the real analyzer

    /// The autocorrelation estimate on a synthetic 200 Hz sine. This is the same
    /// assertion as the harness, kept here so `xcodebuild test` alone is enough
    /// to catch a pitch regression.
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
