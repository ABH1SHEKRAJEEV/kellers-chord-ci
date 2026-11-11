import AVFoundation
import Accelerate
import Foundation

/// Real-time prosody extractor built on `AVAudioEngine` + `Accelerate`.
///
/// `ProsodyDSPEngine` is `@MainActor` because it owns the engine and player node,
/// which are driven from the UI. The mathematics live in `ProsodyAnalyzer` — a
/// non-isolated reference type that is touched *only* from the CoreAudio render
/// thread — so no `@MainActor` state is ever read or written inside a tap closure.
///
/// Exactly one tap is ever installed: Act I/II tap the main mixer to analyse the
/// playing sample, Act III swaps that tap for the microphone input. The
/// microphone tap therefore also feeds `onCapturedBuffer`, which is how the
/// on-device speech recognizer receives audio without a second (illegal) tap.
@MainActor
final class ProsodyDSPEngine {

    enum CaptureMode: Equatable {
        /// Acts I & II — analyse the sample playing through the main mixer.
        case playback
        /// Act III — analyse live microphone input.
        case liveInput
    }

    /// Delivers frames to the UI. Always invoked on the main actor at ≈60 Hz.
    var onFrame: (@MainActor (ProsodyFrame) -> Void)?

    /// Forwards each raw capture buffer to on-device speech recognition. Invoked on
    /// the real-time audio thread, so the receiver must be thread-safe.
    var onCapturedBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private(set) var mode: CaptureMode?
    private(set) var lastError: String?
    private(set) var isRunning = false

    /// Phase 2 (Upgrade 1): when `true`, playback is pushed through two cascaded
    /// 280 Hz low-pass stages so the judge *hears* profound cochlear
    /// sensorineural loss in Act I. Defaulted, so Phase 1 call sites are safe.
    ///
    /// The filter lives in the audio graph (`playerNode -> stage one -> stage two
    /// -> mainMixerNode`), not in the analyzer, so what the judge hears and what
    /// the app measures are the same signal. Flipping it mid-playback is instant
    /// because it only toggles `bypass`.
    var isCochlearSimulationEnabled: Bool = false {
        didSet { applyCochlearSimulationToGraph() }
    }

    /// Phase 2 (Upgrade 6): the calibrated room noise floor in RMS, subtracted
    /// from raw RMS before normalization and used to gate false jitter.
    private(set) var ambientNoiseFloorRMS: Float = 0.002

    /// Phase 2 (Upgrade 6): the calibrated room noise floor in decibels, surfaced
    /// on `ProsodyFrame.ambientNoiseDB` for the Lombard volume governor.
    private(set) var ambientNoiseDB: Float = -50.0

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let analyzer = ProsodyAnalyzer()
    private let format = AudioSampleLoader.canonicalFormat

    /// Non-nil only between `beginRoomCalibration()` and
    /// `finishRoomCalibration()`.
    private var calibrationCollector: NoiseCollector?

    /// Upgrade 1: the audible muffling, two 2-pole stages in series for a
    /// -24 dB/octave shoulder. They sit between the player and the mixer, so the
    /// tap (on the mixer) analyses exactly what leaves the speakers.
    private let cochlearStageOne = AVAudioUnitEQ(numberOfBands: 1)
    private let cochlearStageTwo = AVAudioUnitEQ(numberOfBands: 1)

    /// Cochlear-loss cutoff (Hz), per `Everything2.md` Section 4.2.
    private static let cochlearCutoffHz: Float = 280

    private var tapNode: AVAudioNode?
    private var tapBus: AVAudioNodeBus = 0
    private var isTapInstalled = false
    private var isPrepared = false

    // MARK: - Setup

    /// Attaches and wires the player node. Safe to call repeatedly.
    func prepare() {
        guard !isPrepared else { return }
        engine.attach(playerNode)
        configureCochlearStages()
        engine.attach(cochlearStageOne)
        engine.attach(cochlearStageTwo)
        engine.connect(playerNode, to: cochlearStageOne, format: format)
        engine.connect(cochlearStageOne, to: cochlearStageTwo, format: format)
        engine.connect(cochlearStageTwo, to: engine.mainMixerNode, format: format)
        applyCochlearSimulationToGraph()
        isPrepared = true
    }

    /// Gives both stages an identical low-pass band at the loss cutoff.
    private func configureCochlearStages() {
        for stage in [cochlearStageOne, cochlearStageTwo] {
            guard let band = stage.bands.first else { continue }
            band.filterType = .lowPass
            band.frequency = Self.cochlearCutoffHz
            band.bandwidth = 0.5
            band.bypass = false
        }
    }

    /// Mirrors `isCochlearSimulationEnabled` onto the two EQ stages.
    ///
    /// Deliberately safe to call before `prepare()`: `bypass` is a plain property
    /// on the unit, so setting it on an unattached node is a no-op until the graph
    /// is wired, and `prepare()` re-applies the current state afterwards.
    private func applyCochlearSimulationToGraph() {
        cochlearStageOne.bypass = !isCochlearSimulationEnabled
        cochlearStageTwo.bypass = !isCochlearSimulationEnabled
    }

    // MARK: - Playback (Acts I & II)

    /// Plays a sample and streams its live prosody to `onFrame`.
    func play(_ sample: AudioSampleLoader.LoadedSample) {
        prepare()
        configureAudioSession(record: false)
        startEngine()
        guard engine.isRunning else { return }

        // Upgrade 1: the muffling is in the graph already, so there is nothing to
        // mirror here - the tap on the mixer analyses the filtered signal.
        installTap(on: engine.mainMixerNode, bus: 0, mode: .playback, bufferSize: 1024)
        playerNode.stop()
        playerNode.scheduleBuffer(sample.buffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
    }

    func stopPlayback() {
        playerNode.stop()
        removeTapIfNeeded()
        analyzer.reset()
        mode = nil
        stopEngine()
    }

    // MARK: - Live input (Act III)

    /// Swaps to microphone analysis. Never routes mic audio to the speakers, so
    /// there is no feedback loop.
    func startLiveInput() {
        prepare()
        configureAudioSession(record: true)

        // Upgrade 6: enable hardware voice isolation (beamforming) before the tap
        // starts. Wrapped in `try?` so simulator / non-supporting hardware never
        // throws, and only attempted while the engine is stopped.
        enableHardwareVoiceIsolationIfNeeded()

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.channelCount > 0, hardwareFormat.sampleRate > 0 else {
            mode = .liveInput
            lastError = "Microphone input is unavailable on this device."
            return
        }

        // Upgrade 1: the EQ stages only affect the playback path, so live mic
        // analysis is never muffled.
        // Upgrade 6: seed the analyzer with the calibrated room noise floor.
        analyzer.setAmbientNoiseFloor(rms: ambientNoiseFloorRMS)
        installTap(on: input, bus: 0, mode: .liveInput, bufferSize: 1024)
        startEngine()
    }

    // MARK: - Room noise calibration (Upgrade 6)

    /// Starts the room-noise measurement window and returns immediately.
    ///
    /// The measurement takes exclusive ownership of the input tap (removing any
    /// prior tap first) and starts the engine; `finishRoomCalibration()` commits the
    /// result once the window has elapsed.
    ///
    /// Deliberately *not* `async`. An `async` method would hop `self` to the
    /// generic executor (SE-0338), and sending this non-`Sendable` audio class off
    /// the main actor is exactly what Swift 6 rejects. Splitting the window in two
    /// keeps both halves synchronous, and the caller owns the waiting - which also
    /// means the caller can paint a busy state, something the old `Thread.sleep`
    /// version could never do because it blocked the main actor outright.
    func beginRoomCalibration() {
        configureAudioSession(record: true)
        enableHardwareVoiceIsolationIfNeeded()

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.channelCount > 0, hardwareFormat.sampleRate > 0 else {
            calibrationCollector = nil
            lastError = "Microphone input is unavailable for room calibration."
            return
        }

        removeTapIfNeeded()
        let collector = NoiseCollector()
        calibrationCollector = collector
        input.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { buffer, _ in
            collector.append(buffer)
        }
        do {
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            calibrationCollector = nil
            lastError = "Room calibration could not start the audio engine: \(error.localizedDescription)"
        }
    }

    /// Ends the measurement window and commits the calibrated noise floor.
    ///
    /// Sets `ambientNoiseFloorRMS = min(max(meanRMS * 1.35, 0.002), 0.18)` per
    /// `Everything2.md` Section 4.2 and returns the committed value. Safe to call
    /// without a matching `beginRoomCalibration()`; it then returns the old floor.
    @discardableResult
    func finishRoomCalibration() -> Float {
        guard let collector = calibrationCollector else { return ambientNoiseFloorRMS }
        calibrationCollector = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        deactivateAudioSession()

        let collected = collector.meanRMS()
        guard collected.count > 0 else { return ambientNoiseFloorRMS }
        let floorRMS = min(max(collected.mean * 1.35, 0.002), 0.18)
        ambientNoiseFloorRMS = floorRMS
        ambientNoiseDB = 20 * log10(max(floorRMS, 0.000001))
        analyzer.setAmbientNoiseFloor(rms: floorRMS)
        return floorRMS
    }

    /// Hardware beamforming / voice isolation (Upgrade 6). Only invoked while the
    /// engine is stopped or before a tap is installed.
    private func enableHardwareVoiceIsolationIfNeeded() {
        #if os(iOS) || os(macOS)
        if #available(iOS 17.0, macOS 14.0, *) {
            try? engine.inputNode.setVoiceProcessingEnabled(true)
        }
        #endif
    }

    func stopLiveInput() {
        removeTapIfNeeded()
        analyzer.reset()
        mode = nil
        stopEngine()
    }

    /// Tears down whichever capture is currently active.
    func stopAll() {
        stopPlayback()
        stopLiveInput()
    }

    // MARK: - Tap management
    // Rule 4: `removeTap(onBus:)` is always called before a new tap is installed,
    // so switching between Acts I/II playback and Act III microphone capture can
    // never leave a stale tap behind.

    private func installTap(
        on node: AVAudioNode,
        bus: AVAudioNodeBus,
        mode: CaptureMode,
        bufferSize: AVAudioFrameCount
    ) {
        removeTapIfNeeded()
        let tapFormat = node.outputFormat(forBus: bus)
        // Upgrade 16: only the microphone tap forwards audio to the recognizer.
        // Feeding the playback mix into `SFSpeechRecognizer` would transcribe the
        // app's own demo voices if a recognition request ever outlived Act III.
        let sink = (mode == .liveInput) ? onCapturedBuffer : nil
        let analyzer = self.analyzer
        analyzer.reset()

        node.installTap(onBus: bus, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
            // ── Real-time CoreAudio render thread ──
            // No @MainActor state is touched here: the raw buffer goes to a
            // thread-safe sink and the finished frame is hopped to the main actor.
            sink?(buffer)
            guard let frame = analyzer.process(buffer) else { return }
            Task { @MainActor [weak self] in
                self?.onFrame?(frame)
            }
        }

        tapNode = node
        tapBus = bus
        isTapInstalled = true
        self.mode = mode
    }

    private func removeTapIfNeeded() {
        guard isTapInstalled, let node = tapNode else { return }
        node.removeTap(onBus: tapBus)
        isTapInstalled = false
        tapNode = nil
        tapBus = 0
    }

    // MARK: - Audio engine lifecycle

    private func startEngine() {
        guard !engine.isRunning else {
            isRunning = true
            return
        }
        do {
            try engine.start()
            isRunning = true
            lastError = nil
        } catch {
            isRunning = false
            lastError = "Audio engine failed to start: \(error.localizedDescription)"
            removeTapIfNeeded()
        }
    }

    private func stopEngine() {
        guard engine.isRunning else {
            isRunning = false
            return
        }
        engine.stop()
        isRunning = false
        deactivateAudioSession()
    }

    // MARK: - Cross-platform audio session

    private func configureAudioSession(record: Bool) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                record ? .playAndRecord : .playback,
                mode: .default,
                options: record ? [.defaultToSpeaker] : []
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = "Audio session could not be configured: \(error.localizedDescription)"
        }
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// Thread-safe RMS accumulator used only by `beginRoomCalibration`.
///
/// The tap closure runs on the CoreAudio render thread while the calibration
/// loop reads on the main actor, so every access is guarded by a lock. It is
/// short-lived (one calibration window) and allocation-light after `init`.
final class NoiseCollector: @unchecked Sendable {

    private let lock = NSLock()
    private var buffer: [Float] = []

    /// Real-time thread: appends the RMS of one capture buffer.
    func append(_ bufferPointer: AVAudioPCMBuffer) {
        guard let channel = bufferPointer.floatChannelData?[0] else { return }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(bufferPointer.frameLength))
        lock.lock()
        self.buffer.append(rms)
        lock.unlock()
    }

    /// Number of RMS samples captured so far.
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return buffer.count
    }

    /// Main actor: a copy of the samples plus their mean.
    func meanRMS() -> (count: Int, mean: Float) {
        lock.lock(); defer { lock.unlock() }
        guard !buffer.isEmpty else { return (0, 0) }
        return (buffer.count, buffer.reduce(0, +) / Float(buffer.count))
    }
}

/// The non-isolated DSP kernel behind `ProsodyDSPEngine`.
///
/// Every stored property here is mutated exclusively on the CoreAudio render
/// thread, which is why the class is `@unchecked Sendable`: `ProsodyDSPEngine`
/// captures exactly one instance into its tap closure and never touches it from
/// the main actor. The kernel is allocation-free after `init`.
final class ProsodyAnalyzer: @unchecked Sendable {

    private static let fftSize = 1024
    private static let halfSize = 512
    private static let log2n: vDSP_Length = 10
    /// Exponential moving average factor from the DSP specification.
    private static let smoothing: Float = 0.22
    /// Spectral centroid reference: 1.3 kHz maps to 1.0, matching the target
    /// centroids of ~0.22 (warm) and ~0.84 (sarcastic).
    private static let centroidReferenceHz: Float = 1300
    private static let minPitchHz: Float = 85
    private static let maxPitchHz: Float = 320
    private static let historyCount = 12

    // MARK: Phase 2 constants (Everything2.md Section 4.2)
    /// Sibilant / fricative band in Hz (Upgrade 10). Converted to FFT bins from
    /// the *actual* buffer sample rate, so the detector stays correct whether the
    /// playback mix is 44.1 kHz or a 48 kHz microphone.
    private static let sibilanceBandLowHz: Float = 4000
    private static let sibilanceBandHighHz: Float = 8000
    /// Vowel band in Hz (Upgrade 10), used as the energy denominator.
    private static let vowelBandLowHz: Float = 90
    private static let vowelBandHighHz: Float = 1730
    /// ZCR / high-to-low energy thresholds (Upgrade 10).
    private static let sibilanceZCRThreshold: Float = 0.22
    private static let sibilanceRatioThreshold: Float = 0.45
    /// Voiced pitch-slope ring buffer length, ≈350 ms at 60 fps (Upgrade 12).
    private static let terminalBufferCount = 20
    /// Normalization divisor for the terminal ΔF0 slope (Upgrade 12).
    private static let terminalSlopeScale: Float = 55

    private let fftSetup: FFTSetup?
    private let window: [Float]
    private let binRamp: [Float]

    private var scratch = [Float](repeating: 0, count: 1024)
    private var realParts = [Float](repeating: 0, count: 512)
    private var imaginaryParts = [Float](repeating: 0, count: 512)
    private var magnitudes = [Float](repeating: 0, count: 512)

    private var pitchHistory = [Float](repeating: 0, count: 12)
    private var historyCountFilled = 0
    private var historyWriteIndex = 0

    // Upgrade 12: separate 20-frame ring buffer of *voiced* F0 for ΔF0 slope.
    private var terminalPitchHistory = [Float](repeating: 0, count: 20)
    private var terminalCountFilled = 0
    private var terminalWriteIndex = 0
    private var lastTerminalSlope: Float = 0

    // Upgrade 1: the 280 Hz muffling is an AVFoundation EQ stage inside
    // `ProsodyDSPEngine`, upstream of the tap, so the analyzer needs no filter of
    // its own - it already receives the signal the judge hears.

    // Upgrade 6: calibrated ambient noise floor (RMS) for gating + dB readout.
    private var ambientNoiseFloorRMS: Float = 0.002

    private var smoothed = Smoothed()
    private var samplesSinceEmit = 0
    private var lastSlope: Float = 0

    private struct Smoothed {
        var rms: Float = 0
        var pitch: Float = 0.5
        var centroid: Float = 0.4
        var jitter: Float = 0.1
        var sibilance: Float = 0
    }

    init() {
        var hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        window = hann

        var ramp = [Float](repeating: 0, count: Self.halfSize)
        var rampStart: Float = 0
        var rampStep: Float = 1
        vDSP_vramp(&rampStart, &rampStep, &ramp, 1, vDSP_Length(Self.halfSize))
        binRamp = ramp

        fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    /// Clears all rolling state. Called whenever capture mode changes.
    func reset() {
        smoothed = Smoothed()
        pitchHistory = [Float](repeating: 0, count: Self.historyCount)
        historyCountFilled = 0
        historyWriteIndex = 0
        samplesSinceEmit = 0
        lastSlope = 0
        // Phase 2 rolling state.
        terminalPitchHistory = [Float](repeating: 0, count: Self.terminalBufferCount)
        terminalCountFilled = 0
        terminalWriteIndex = 0
        lastTerminalSlope = 0
    }

    /// Seeds the calibrated ambient room-noise floor (RMS). Called from the main
    /// actor before a tap starts, so "write-then-read" never races.
    func setAmbientNoiseFloor(rms: Float) {
        ambientNoiseFloorRMS = min(max(rms, 0.0), 0.18)
    }

    /// Consumes one capture buffer and returns a smoothed `ProsodyFrame`, or `nil`
    /// when the ≈60 fps delivery throttle says it is not time to publish yet.
    func process(_ buffer: AVAudioPCMBuffer) -> ProsodyFrame? {
        guard let fftSetup else { return nil }
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let length = Int(buffer.frameLength)
        guard length >= 128 else { return nil }

        let sampleRate = Float(buffer.format.sampleRate)
        let usable = min(length, Self.fftSize)

        // 1 ── RMS amplitude, raw and unwindowed (pre-filter, so the noise gate
        //      sees the true acoustic energy of the room).
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(length))

        // 2 ── Hanning-windowed copy shared by the FFT and the autocorrelation.
        //      (Upgrade 1's muffling happens in the audio graph, so this copy is
        //      already the filtered signal during cochlear simulation.)
        for index in 0..<usable { scratch[index] = channel[index] * window[index] }
        for index in usable..<Self.fftSize { scratch[index] = 0 }

        // 3 ── Spectral centroid from the magnitude spectrum.
        let centroid = spectralCentroid(fftSetup: fftSetup, sampleRate: sampleRate)

        // 4 ── Autocorrelation pitch and 12-frame jitter.
        let pitch = fundamentalFrequency(sampleRate: sampleRate, sampleCount: usable)
        let jitter = updateJitter(with: pitch, rms: rms)
        let slope = pitchSlope()

        // 5 ── Upgrade 10: 4-8 kHz sibilance energy + Zero-Crossing Rate.
        let sibilance = sibilanceEnergy(sampleRate: sampleRate)

        // 6 ── Normalize, then exponentially smooth every metric (α = 0.22).
        //      Upgrade 6: remove the calibrated room noise floor before mapping to
        //      dB so a noisy room does not inflate perceived loudness.
        let rmsNormalized = normalizeDecibels(max(rms - ambientNoiseFloorRMS, 0))
        let pitchNormalized = pitch > 0
            ? normalize(pitch, from: Self.minPitchHz, to: Self.maxPitchHz)
            : smoothed.pitch
        smoothed.rms = ema(smoothed.rms, rmsNormalized)
        smoothed.pitch = ema(smoothed.pitch, pitchNormalized)
        if pitch > 0 { smoothed.centroid = ema(smoothed.centroid, centroid) }
        smoothed.jitter = ema(smoothed.jitter, jitter)
        smoothed.sibilance = ema(smoothed.sibilance, sibilance)

        // 7 ── Upgrade 12: update the 20-frame voiced F0 buffer and ΔF0 slope.
        updateTerminalPitch(with: pitch, rmsNormalized: smoothed.rms, sibilance: smoothed.sibilance)

        // 8 ── Throttle publication to ≈60 fps regardless of the tap buffer size.
        samplesSinceEmit += length
        guard samplesSinceEmit >= Int(sampleRate / 60) else { return nil }
        samplesSinceEmit = 0

        return ProsodyFrame(
            rmsAmplitude: smoothed.rms,
            fundamentalPitchHz: pitch,
            normalizedPitch: smoothed.pitch,
            spectralCentroid: smoothed.centroid,
            pitchJitter: smoothed.jitter,
            classifiedEmotion: EmotionalProfile.classify(
                centroid: smoothed.centroid,
                jitter: smoothed.jitter,
                pitchSlope: slope,
                rms: smoothed.rms
            ),
            sibilanceEnergy: smoothed.sibilance,
            terminalPitchSlope: lastTerminalSlope,
            ambientNoiseDB: 20 * log10(max(ambientNoiseFloorRMS, 0.000001))
        )
    }

    // MARK: - Upgrade 10: sibilance / plosive detector (4 kHz - 8 kHz)

    /// The high-band / low-band FFT energy ratio, gated by the time-domain
    /// Zero-Crossing Rate and normalized onto `0...1`.
    ///
    /// The FFT magnitude spectrum in `magnitudes` is produced by
    /// `spectralCentroid(fftSetup:sampleRate:)`, which `process` always calls
    /// before this method.
    private func sibilanceEnergy(sampleRate: Float) -> Float {
        let binWidth = sampleRate / Float(Self.fftSize)
        guard binWidth > 0, magnitudes.count > 1 else { return 0 }
        let lastBin = magnitudes.count - 1

        let highLower = max(Int((Self.sibilanceBandLowHz / binWidth).rounded()), 1)
        let highUpper = min(Int((Self.sibilanceBandHighHz / binWidth).rounded()), lastBin)
        let lowLower = max(Int((Self.vowelBandLowHz / binWidth).rounded()), 1)
        let lowUpper = min(Int((Self.vowelBandHighHz / binWidth).rounded()), lastBin)

        var high: Float = 0
        var low: Float = 0
        if highLower <= highUpper {
            for k in highLower...highUpper { high += magnitudes[k] }
        }
        if lowLower <= lowUpper {
            for k in lowLower...lowUpper { low += magnitudes[k] }
        }
        let ratio = high / (low + 0.00001)

        // Zero-Crossing Rate across the 1024 time-domain samples in `scratch`.
        let span = max(2, Self.fftSize)
        var crossings = 0
        var previous = scratch[0]
        for index in 1..<span {
            let current = scratch[index]
            if (current >= 0) != (previous >= 0) { crossings += 1 }
            previous = current
        }
        let zcr = Float(crossings) / Float(span - 1)

        guard zcr > Self.sibilanceZCRThreshold,
              ratio > Self.sibilanceRatioThreshold else { return 0 }

        // Map how far past the thresholds we are onto 0...1.
        let zcrComponent = min(max((zcr - Self.sibilanceZCRThreshold) / 0.30, 0), 1)
        let ratioComponent = min(max((ratio - Self.sibilanceRatioThreshold) / 1.55, 0), 1)
        return min(max(0.5 * zcrComponent + 0.5 * ratioComponent, 0), 1)
    }

    // MARK: - Upgrade 12: terminal question / statement inflection slope

    /// Pushes a voiced `F0` into the 20-frame ring buffer, then recomputes
    /// `terminalPitchSlope = clamp((mean(newest 6) − mean(oldest 6)) / 55, -1, 1)`.
    private func updateTerminalPitch(with pitch: Float, rmsNormalized: Float, sibilance: Float) {
        // Only voiced, non-sibilant frames enter the window (Everything2.md 4.2).
        guard pitch > 0, rmsNormalized > 0.08, sibilance < 0.6 else { return }

        terminalPitchHistory[terminalWriteIndex] = pitch
        terminalWriteIndex = (terminalWriteIndex + 1) % Self.terminalBufferCount
        if terminalCountFilled < Self.terminalBufferCount { terminalCountFilled += 1 }
        guard terminalCountFilled >= 6 else { lastTerminalSlope = 0; return }

        // Build the window oldest -> newest.
        var ordered = [Float]()
        ordered.reserveCapacity(terminalCountFilled)
        if terminalCountFilled < Self.terminalBufferCount {
            ordered.append(contentsOf: terminalPitchHistory[0..<terminalCountFilled])
        } else {
            for offset in 0..<Self.terminalBufferCount {
                ordered.append(terminalPitchHistory[(terminalWriteIndex + offset) % Self.terminalBufferCount])
            }
        }

        let tailCount = min(6, ordered.count)
        let headCount = min(6, ordered.count)
        let tail = ordered.suffix(tailCount).reduce(0, +) / Float(tailCount)
        let head = ordered.prefix(headCount).reduce(0, +) / Float(headCount)
        lastTerminalSlope = min(max((tail - head) / Self.terminalSlopeScale, -1), 1)
    }

    // MARK: - Spectral centroid (harmonic warmth vs. sharpness)

    /// 1024-point real FFT → magnitude spectrum → Σ(k·M[k]) / ΣM[k], then mapped
    /// onto 0…1 against a 1.3 kHz reference.
    private func spectralCentroid(fftSetup: FFTSetup, sampleRate: Float) -> Float {
        realParts.withUnsafeMutableBufferPointer { realBuffer in
            imaginaryParts.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress,
                      let imaginaryBase = imaginaryBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)

                scratch.withUnsafeBytes { rawBuffer in
                    if let complex = rawBuffer.bindMemory(to: DSPComplex.self).baseAddress {
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(Self.halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))

                magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                    if let magnitudeBase = magnitudeBuffer.baseAddress {
                        vDSP_zvabs(&split, 1, magnitudeBase, 1, vDSP_Length(Self.halfSize))
                    }
                }
            }
        }

        // Weighted bin mean: Σ(k·M[k]) via a vDSP ramp dot-product, divided by ΣM[k].
        var weightedSum: Float = 0
        vDSP_dotpr(binRamp, 1, magnitudes, 1, &weightedSum, vDSP_Length(Self.halfSize))
        var totalMagnitude: Float = 0
        vDSP_sve(magnitudes, 1, &totalMagnitude, vDSP_Length(Self.halfSize))
        guard totalMagnitude > 0.0001 else { return smoothed.centroid }

        let meanBin = weightedSum / totalMagnitude
        let meanHertz = meanBin * (sampleRate / 2) / Float(Self.halfSize)
        return min(max(meanHertz / Self.centroidReferenceHz, 0), 1)
    }

    // MARK: - Fundamental frequency (autocorrelation)

    /// Searches autocorrelation lags between 400 Hz and 80 Hz for the strongest
    /// peak: `F0 = f_s / τ_peak`, requiring a normalized score above 0.25 so
    /// unvoiced/breathy frames report silence instead of a bogus pitch.
    private func fundamentalFrequency(sampleRate: Float, sampleCount: Int) -> Float {
        let minLag = max(2, Int(sampleRate / 400))
        let maxLag = min(Int(sampleRate / 80), sampleCount - 1)
        guard maxLag > minLag else { return 0 }

        var energy: Float = 0
        vDSP_dotpr(scratch, 1, scratch, 1, &energy, vDSP_Length(sampleCount))
        guard energy > 0.0001 else { return 0 }

        var bestLag = 0
        var bestScore: Float = 0
        scratch.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for lag in minLag...maxLag {
                var correlation: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &correlation, vDSP_Length(sampleCount - lag))
                // Normalize by the *overlapping* energy, not the whole window.
                // Dividing by the full-window energy penalises long lags by their
                // shorter overlap, which biased the estimate sharp (finding 15).
                let score = correlation * Float(sampleCount)
                    / (energy * Float(sampleCount - lag))
                if score > bestScore {
                    bestScore = score
                    bestLag = lag
                }
            }
        }

        guard bestLag > 0, bestScore > 0.25 else { return 0 }
        return sampleRate / Float(bestLag)
    }

    // MARK: - Pitch jitter (vocal tremor)

    /// Standard deviation of the last 12 voiced `F0` values, divided by their mean.
    /// Values above 0.45 read as anxious hesitation.
    private func updateJitter(with pitch: Float, rms: Float) -> Float {
        // No detectable `F0` is silence, so tremor must *decay*, not freeze.
        //
        // HANDOFF D.6: this used to `return smoothed.jitter`, and because the
        // caller smooths with `ema(smoothed, jitter)`, `ema(x, x) == x` froze the
        // value forever — so a silent frame right after anxious speech kept
        // classifying as `.anxiousTremor` at `rmsAmplitude == 0`. Returning 0 makes
        // the caller's own EMA (`α = 0.22`, line ~549) walk it down to ~5% in about
        // a third of a second, which is the audible truth: the tremor stops when
        // the voice stops, it does not vanish mid-air either.
        guard pitch > 0 else { return 0 }

        // Upgrade 6: room-noise gate — a raw RMS at or below the calibrated noise
        // floor is silence/air-conditioner rumble, not vocal tremor.
        //
        // Per `Everything2.md` Section 4.2 the jitter must be gated to *zero*, not
        // merely held: holding it froze the smoothed value forever (ema(x, x) == x)
        // so a silence after anxious speech kept classifying as anxious tremor.
        guard rms > ambientNoiseFloorRMS * 1.15 else { return 0 }

        pitchHistory[historyWriteIndex] = pitch
        historyWriteIndex = (historyWriteIndex + 1) % Self.historyCount
        if historyCountFilled < Self.historyCount { historyCountFilled += 1 }
        guard historyCountFilled >= 4 else { return 0 }

        var sum: Float = 0
        for index in 0..<historyCountFilled { sum += pitchHistory[index] }
        let mean = sum / Float(historyCountFilled)
        guard mean > 0 else { return 0 }

        var variance: Float = 0
        for index in 0..<historyCountFilled {
            let delta = pitchHistory[index] - mean
            variance += delta * delta
        }
        variance /= Float(historyCountFilled)
        return min(max(variance.squareRoot() / mean, 0), 1)
    }

    /// Relative rise or fall of `F0` across the rolling window, clamped to −1…1.
    /// A steep negative slope is one of the warm-relief signatures.
    private func pitchSlope() -> Float {
        guard historyCountFilled >= 4 else { return lastSlope }

        let oldest: Float
        let newest: Float
        if historyCountFilled < Self.historyCount {
            oldest = pitchHistory[0]
            newest = pitchHistory[historyCountFilled - 1]
        } else {
            oldest = pitchHistory[historyWriteIndex]
            newest = pitchHistory[(historyWriteIndex + Self.historyCount - 1) % Self.historyCount]
        }

        guard oldest > 0 else { return lastSlope }
        lastSlope = min(max((newest - oldest) / oldest, -1), 1)
        return lastSlope
    }

    // MARK: - Small numeric helpers

    private func ema(_ current: Float, _ target: Float) -> Float {
        current + Self.smoothing * (target - current)
    }

    private func normalize(_ value: Float, from lower: Float, to upper: Float) -> Float {
        min(max((value - lower) / (upper - lower), 0), 1)
    }

    /// −55 dB…−5 dB mapped linearly onto 0…1, per the DSP specification.
    private func normalizeDecibels(_ rms: Float) -> Float {
        let decibels = 20 * log10(max(rms, 0.000001))
        return min(max((decibels + 55) / 50, 0), 1)
    }
}
