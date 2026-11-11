//
//  main.swift — KellersChord DSP verification harness
//
//  Why this exists: the package is a Swift Playgrounds *App* package
//  (`AppleProductTypes` / `.iOSApplication`), and a `.testTarget` that links an
//  executable target is the single most fragile part of a zero-shot CI build.
//  This harness sidesteps SwiftPM entirely: the workflow hands `swiftc` the
//  engine sources plus this file, so the math is exercised against the real
//  Accelerate + AVFoundation frameworks on a macOS runner with no test bundle,
//  no `@main`, and no manifest resolution involved.
//
//  It compiles together with:
//      Sources/Models/ProsodyFrame.swift
//      Sources/Models/EmotionalProfile.swift
//      Sources/Models/WordProsodySnapshot.swift
//      Sources/Engine/AudioSampleLoader.swift
//      Sources/Engine/ProceduralVoiceSynthesizer.swift
//      Sources/Engine/ProsodyDSPEngine.swift
//
//  Exit code 0 = every check passed. Exit code 1 = at least one failed, and the
//  printed table names it with the measured value.
//

import AVFoundation
import Foundation

// MARK: - Tiny assertion record

struct Check {
    let name: String
    let passed: Bool
    let detail: String
}

var checks: [Check] = []

func expect(_ name: String, _ condition: Bool, _ detail: String) {
    checks.append(Check(name: name, passed: condition, detail: detail))
}

func expectIn(_ name: String, _ value: Float, _ lower: Float, _ upper: Float) {
    let ok = value.isFinite && value >= lower && value <= upper
    expect(name, ok, String(format: "measured %.4f, expected %.3f...%.3f", value, lower, upper))
}

// MARK: - Synthetic signal helpers

let sampleRate: Double = 44_100
let framesPerBuffer: Int = 1_024

/// One Hann-adjacent-free tone buffer: a pure sine, phase-continuous with the
/// caller's running sample index so successive buffers are one continuous signal.
func toneBuffer(hz: Float, amplitude: Float, startIndex: Int) -> AVAudioPCMBuffer? {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerBuffer)) else {
        return nil
    }
    buffer.frameLength = AVAudioFrameCount(framesPerBuffer)
    guard let channel = buffer.floatChannelData?[0] else { return nil }
    let twoPi = 2 * Float.pi
    for index in 0..<framesPerBuffer {
        let t = Float(startIndex + index) / Float(sampleRate)
        channel[index] = amplitude * sin(twoPi * hz * t)
    }
    return buffer
}

/// Feeds `count` consecutive buffers of the same tone and returns the last frame
/// the analyzer actually published (`process` throttles to ~60 fps).
@discardableResult
func feed(
    _ analyzer: ProsodyAnalyzer,
    hz: Float,
    amplitude: Float,
    count: Int,
    startingIndex: Int = 0
) -> ProsodyFrame {
    var index = startingIndex
    var last = ProsodyFrame.silent
    for _ in 0..<count {
        guard let buffer = toneBuffer(hz: hz, amplitude: amplitude, startIndex: index) else { break }
        index += framesPerBuffer
        if let frame = analyzer.process(buffer) { last = frame }
    }
    return last
}

/// Feeds `count` silent buffers.
@discardableResult
func feedSilence(_ analyzer: ProsodyAnalyzer, count: Int) -> ProsodyFrame {
    var last = ProsodyFrame.silent
    for _ in 0..<count {
        guard let buffer = toneBuffer(hz: 0, amplitude: 0, startIndex: 0) else { break }
        if let frame = analyzer.process(buffer) { last = frame }
    }
    return last
}

/// Enough buffers for the α = 0.22 exponential smoother to reach 99% of target
/// (0.78^40 ≈ 4.8e-5).
let convergenceBuffers = 40

// MARK: - 1. RMS loudness normalization → [-55 dB, -5 dB] mapped onto 0...1

do {
    let analyzer = ProsodyAnalyzer()
    // Full-scale 200 Hz sine: RMS = 0.707 → -3.0 dB → above the -5 dB ceiling.
    let loud = feed(analyzer, hz: 200, amplitude: 1.0, count: convergenceBuffers)
    expectIn("RMS: full-scale tone clips to 1.0", loud.rmsAmplitude, 0.98, 1.0)
    expect("RMS: full-scale tone is voiced", loud.isVoiced, "isVoiced = \(loud.isVoiced)")

    let analyzer2 = ProsodyAnalyzer()
    // 0.02 amplitude → RMS 0.01414 → -37.0 dB. The engine subtracts the 0.002
    // ambient floor first, giving RMS 0.01214 → -38.3 dB → (16.7/50) ≈ 0.334.
    let quiet = feed(analyzer2, hz: 200, amplitude: 0.02, count: convergenceBuffers)
    expectIn("RMS: -38 dB tone maps mid-band", quiet.rmsAmplitude, 0.30, 0.38)
    expect("RMS: mapping is monotonic", quiet.rmsAmplitude < loud.rmsAmplitude,
           "quiet \(quiet.rmsAmplitude) < loud \(loud.rmsAmplitude)")

    let analyzer3 = ProsodyAnalyzer()
    // 1e-4 amplitude → -80 dB, below the -55 dB floor → 0.
    let inaudible = feed(analyzer3, hz: 200, amplitude: 0.0001, count: convergenceBuffers)
    expectIn("RMS: below -55 dB floor maps to 0", inaudible.rmsAmplitude, 0.0, 0.001)
    expect("RMS: inaudible tone is not voiced", !inaudible.isVoiced, "isVoiced = \(inaudible.isVoiced)")
}

// MARK: - 2. Autocorrelation F0 on a synthetic 200 Hz sine

do {
    let analyzer = ProsodyAnalyzer()
    let frame = feed(analyzer, hz: 200, amplitude: 0.5, count: convergenceBuffers)
    // Autocorrelation quantizes to integer lags: 44100/220 = 200.45 Hz,
    // 44100/221 = 199.55 Hz. ±2% covers both.
    expectIn("F0: 200 Hz sine estimated within 2%", frame.fundamentalPitchHz, 196, 204)
    // 85...320 Hz mapped onto 0...1 → (200-85)/235 = 0.489.
    expectIn("F0: normalizedPitch matches 85...320 Hz map", frame.normalizedPitch, 0.46, 0.52)

    let high = ProsodyAnalyzer()
    let highFrame = feed(high, hz: 300, amplitude: 0.5, count: convergenceBuffers)
    expectIn("F0: 300 Hz sine estimated within 3%", highFrame.fundamentalPitchHz, 291, 309)
    expect("F0: higher tone reads higher normalized pitch",
           highFrame.normalizedPitch > frame.normalizedPitch,
           "300 Hz \(highFrame.normalizedPitch) > 200 Hz \(frame.normalizedPitch)")
}

// MARK: - 3. Spectral centroid (warm vs. metallic)

do {
    let warm = ProsodyAnalyzer()
    let warmFrame = feed(warm, hz: 300, amplitude: 0.5, count: convergenceBuffers)
    // 300 Hz weighted mean centre / 1300 Hz reference ≈ 0.23.
    expectIn("Centroid: 300 Hz tone reads warm (< 0.35)", warmFrame.spectralCentroid, 0.10, 0.35)

    let bright = ProsodyAnalyzer()
    let brightFrame = feed(bright, hz: 4000, amplitude: 0.5, count: convergenceBuffers)
    expectIn("Centroid: 4 kHz tone reads metallic (>= 0.65)", brightFrame.spectralCentroid, 0.65, 1.0)
    expect("Centroid: rises with frequency",
           brightFrame.spectralCentroid > warmFrame.spectralCentroid,
           "4 kHz \(brightFrame.spectralCentroid) > 300 Hz \(warmFrame.spectralCentroid)")
    // Classifier ordering is checked on synthetic inputs, not on the measured
    // 4 kHz frame: a pure high tone has no stable period at 130-sample lags, so
    // its *jitter* reading is an artefact and must not drive this assertion.
    expect("Classifier: high centroid wins over neutral",
           EmotionalProfile.classify(centroid: 0.80, jitter: 0.10, pitchSlope: 0, rms: 0.5) == .sharpSarcasm,
           "\(EmotionalProfile.classify(centroid: 0.80, jitter: 0.10, pitchSlope: 0, rms: 0.5))")
    expect("Classifier: jitter outranks centroid",
           EmotionalProfile.classify(centroid: 0.80, jitter: 0.50, pitchSlope: 0, rms: 0.5) == .anxiousTremor,
           "\(EmotionalProfile.classify(centroid: 0.80, jitter: 0.50, pitchSlope: 0, rms: 0.5))")
}

// MARK: - 4. Pitch jitter (tremor detection) and the room-noise gate

do {
    let steady = ProsodyAnalyzer()
    let steadyFrame = feed(steady, hz: 200, amplitude: 0.5, count: convergenceBuffers)
    expectIn("Jitter: steady 200 Hz tone reads < 0.02", steadyFrame.pitchJitter, 0.0, 0.02)
    expect("Jitter: steady tone does not classify as anxious",
           steadyFrame.classifiedEmotion != .anxiousTremor,
           "profile = \(steadyFrame.classifiedEmotion)")

    let tremulous = ProsodyAnalyzer()
    var index = 0
    for step in 0..<14 {
        // 100 / 340 Hz: the widest alternation that stays inside the 85...320 Hz
        // autocorrelation search window (lags 441 and 130, both in range).
        let hz: Float = step.isMultiple(of: 2) ? 100 : 340
        if let buffer = toneBuffer(hz: hz, amplitude: 0.5, startIndex: index) {
            _ = tremulous.process(buffer)
        }
        index += framesPerBuffer
    }
    let tremFrame = feed(tremulous, hz: 200, amplitude: 0.5, count: 1, startingIndex: index)
    // SD/mean of alternating 100/340 around 220 ≈ 120/220 = 0.545.
    expectIn("Jitter: alternating 100/340 Hz reads > 0.35", tremFrame.pitchJitter, 0.35, 1.0)
    expect("Jitter: 0.545 jitter classifies as anxious tremor",
           EmotionalProfile.classify(centroid: 0.2, jitter: 0.545, pitchSlope: 0, rms: 0.4) == .anxiousTremor,
           "\(EmotionalProfile.classify(centroid: 0.2, jitter: 0.545, pitchSlope: 0, rms: 0.4))")

    // Regression guard (Appendix B finding): the room-noise gate must return 0,
    // not merely *hold* the last value, or a noisy room freezes anxious tremor
    // forever. Note the gate that fires here is the RMS gate: the quiet tone is
    // still periodic (so `pitch > 0`), but its RMS (0.00177) sits below
    // `ambientNoiseFloorRMS * 1.15` (0.0023).
    let gated = ProsodyAnalyzer()
    var tremorIndex = 0
    for step in 0..<14 {
        let hz: Float = step.isMultiple(of: 2) ? 100 : 340
        if let buffer = toneBuffer(hz: hz, amplitude: 0.5, startIndex: tremorIndex) {
            _ = gated.process(buffer)
        }
        tremorIndex += framesPerBuffer
    }
    let beforeGate = feed(gated, hz: 200, amplitude: 0.5, count: 1, startingIndex: tremorIndex)
    expect("Jitter: tremor established before the gate applies",
           beforeGate.pitchJitter > 0.35,
           "jitter = \(beforeGate.pitchJitter)")

    let afterGate = feed(gated, hz: 200, amplitude: 0.0025, count: convergenceBuffers)
    expectIn("Jitter: room-noise gate zeroes tremor (not held)", afterGate.pitchJitter, 0.0, 0.02)
}

// MARK: - 5. 4-8 kHz sibilance band detector

do {
    let vowel = ProsodyAnalyzer()
    let vowelFrame = feed(vowel, hz: 200, amplitude: 0.5, count: convergenceBuffers)
    // ZCR of 200 Hz ≈ 0.009, far below the 0.22 gate → exactly zero energy.
    expectIn("Sibilance: 200 Hz vowel reports 0", vowelFrame.sibilanceEnergy, 0.0, 0.01)
    expect("Sibilance: vowel does not earn a Consonant Spark",
           !vowelFrame.hasConsonantSpark,
           "sibilance = \(vowelFrame.sibilanceEnergy)")

    let fricative = ProsodyAnalyzer()
    let fricativeFrame = feed(fricative, hz: 6000, amplitude: 0.5, count: convergenceBuffers)
    // 6 kHz sits inside the 4-8 kHz band, and its ZCR (0.272) clears the gate.
    expectIn("Sibilance: 6 kHz fricative reports > 0.25", fricativeFrame.sibilanceEnergy, 0.25, 1.0)
    expect("Sibilance: fricative earns a Consonant Spark",
           fricativeFrame.hasConsonantSpark,
           "sibilance = \(fricativeFrame.sibilanceEnergy)")
}

// MARK: - 6. Lombard loudness band (pure model math, no audio)

do {
    let quiet = ProsodyFrame.loudnessBand(ambientNoiseDB: -50)
    expectIn("Lombard: -50 dB room lower edge", quiet.low, 0.235, 0.245)
    expectIn("Lombard: -50 dB room upper edge", quiet.high, 0.715, 0.725)

    let noisy = ProsodyFrame.loudnessBand(ambientNoiseDB: -15)
    expectIn("Lombard: -15 dB room lower edge", noisy.low, 0.415, 0.425)
    expectIn("Lombard: -15 dB room upper edge", noisy.high, 0.895, 0.905)

    let absurd = ProsodyFrame.loudnessBand(ambientNoiseDB: -5)
    expect("Lombard: band never exceeds 0.94 and stays ordered",
           absurd.high <= 0.94 && absurd.low < absurd.high,
           "low \(absurd.low), high \(absurd.high)")

    let nan = ProsodyFrame.loudnessBand(ambientNoiseDB: .nan)
    expectIn("Lombard: non-finite input falls back to -50 dB", nan.low, 0.235, 0.245)
}

// MARK: - 7. Terminal inflection thresholds (Everything2.md 4.2)

do {
    var rising = ProsodyFrame.silent
    rising.terminalPitchSlope = 0.29
    var falling = ProsodyFrame.silent
    falling.terminalPitchSlope = -0.26
    var steady = ProsodyFrame.silent
    steady.terminalPitchSlope = 0.0

    expect("Inflection: +0.29 reads rising question", rising.terminalInflection == .risingQuestion,
           "\(rising.terminalInflection)")
    expect("Inflection: -0.26 reads statement drop", falling.terminalInflection == .groundedDrop,
           "\(falling.terminalInflection)")
    expect("Inflection: 0.00 reads steady", steady.terminalInflection == .steady,
           "\(steady.terminalInflection)")
}

// MARK: - 8. Baseline + interpolation invariants

do {
    let silent = ProsodyFrame.silent
    expectIn("Silent baseline: rms is 0", silent.rmsAmplitude, 0.0, 0.0001)
    expectIn("Silent baseline: normalizedPitch centred at 0.5", silent.normalizedPitch, 0.499, 0.501)
    expect("Silent baseline: neutral profile", silent.classifiedEmotion == .neutral, "\(silent.classifiedEmotion)")
    expect("Silent baseline: no Consonant Spark", !silent.hasConsonantSpark, "sibilance = \(silent.sibilanceEnergy)")

    var target = ProsodyFrame.silent
    target.rmsAmplitude = 0.8
    target.sibilanceEnergy = 0.9
    let halfway = ProsodyFrame.silent.interpolated(toward: target, factor: 0.45)
    expectIn("Interpolation: 0.45 lerp of 0.8 rms", halfway.rmsAmplitude, 0.359, 0.361)

    let clamped = ProsodyFrame.silent.interpolated(toward: target, factor: 4.0)
    expectIn("Interpolation: factor clamps at 1.0", clamped.rmsAmplitude, 0.799, 0.801)
}

// MARK: - Report

let failures = checks.filter { !$0.passed }
let width = checks.map(\.name.count).max() ?? 40

print("")
print("──────────────────────────────────────────────────────────────────────────────")
print(" KellersChord DSP harness — \(checks.count) checks, \(failures.count) failed")
print("──────────────────────────────────────────────────────────────────────────────")
for check in checks {
    let mark = check.passed ? "PASS" : "FAIL"
    let padded = check.name.padding(toLength: width, withPad: " ", startingAt: 0)
    print(" \(mark)  \(padded)  \(check.detail)")
}
print("──────────────────────────────────────────────────────────────────────────────")

if failures.isEmpty {
    print(" ALL CHECKS PASSED")
    exit(0)
} else {
    print(" \(failures.count) CHECK(S) FAILED:")
    for failure in failures {
        print("   • \(failure.name): \(failure.detail)")
    }
    exit(1)
}
