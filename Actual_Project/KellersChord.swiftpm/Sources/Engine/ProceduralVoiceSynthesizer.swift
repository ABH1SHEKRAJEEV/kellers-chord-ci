import AVFoundation
import Foundation

/// Pure-Swift harmonic/formant synthesizer.
///
/// This is the zero-crash fallback used whenever the user has not yet dropped
/// their three `.m4a` voice notes into `Resources/VoiceNotes/`. It renders
/// ~3.5-second acoustic buffers whose pitch contour, harmonic series, envelope
/// and jitter deliberately match the target metrics in the design specification,
/// so the app demonstrates all three emotional contours out of the box.
enum ProceduralVoiceSynthesizer {

    /// Length of every synthesized sample.
    static let duration: Double = 3.5

    /// Renders an emotional acoustic buffer into `format` (expected: canonical
    /// 44.1 kHz mono Float32). Returns `nil` only if the buffer cannot be allocated.
    ///
    /// No muffling happens here. `Everything2.md` Upgrade 1 is now an audible EQ
    /// stage in `ProsodyDSPEngine`'s playback graph, which covers both this
    /// synthesized fallback and the bundled `.m4a` notes with one mechanism.
    /// Baking the filter into the buffer could never work anyway: samples are
    /// loaded once at launch, before the judge can toggle the simulator.
    static func makeBuffer(for profile: EmotionalProfile, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return nil }

        let output = channels[0]
        let harmonics = harmonicSeries(for: profile)
        let normalization = max(harmonics.reduce(0) { $0 + $1.amplitude }, 0.0001)

        var phase = 0.0
        for index in 0..<Int(frameCount) {
            let time = Double(index) / sampleRate
            let f0 = fundamental(profile: profile, time: time)
            phase += 2 * Double.pi * f0 / sampleRate
            if phase > 2 * Double.pi { phase -= 2 * Double.pi }

            var sample = 0.0
            for harmonic in harmonics {
                sample += harmonic.amplitude * sin(phase * Double(harmonic.number))
            }
            sample /= normalization

            // Breath noise is what makes anxious tremor read as unstable air.
            if profile == .anxiousTremor {
                sample += Double.random(in: -0.025...0.025)
            }

            let envelope = amplitudeEnvelope(profile: profile, time: time)
            output[index] = Float(min(max(sample * envelope, -1), 1))
        }

        assert(buffer.frameLength == frameCount, "Procedural synthesis produced a short buffer")
        return buffer
    }

    /// A deterministic prosody frame for Act III's "Simulate Live Voice" toggle and
    /// for the denied-permission fallback. Touches no audio hardware, so judges can
    /// demo the vocal mirror in a silent room.
    static func simulatedFrame(profile: EmotionalProfile, elapsed: Double) -> ProsodyFrame {
        let slow = sin(elapsed * 1.7)
        let fast = sin(elapsed * 6.5)
        let spike = fast > 0.45 ? 1.0 : 0.0

        let rms: Double
        let centroid: Double
        let jitter: Double
        let pitch: Double

        switch profile {
        case .warmRelief:
            rms = 0.55 + 0.10 * slow
            centroid = 0.22 + 0.05 * slow
            jitter = 0.05 + 0.02 * abs(fast)
            pitch = 0.58 - 0.18 * (0.5 - 0.5 * cos(elapsed * 0.8))
        case .anxiousTremor:
            rms = 0.45 + 0.22 * fast
            centroid = 0.48 + 0.06 * slow
            jitter = 0.72 + 0.12 * abs(fast)
            pitch = 0.70 + 0.06 * slow
        case .sharpSarcasm:
            rms = 0.58 + 0.35 * spike
            centroid = 0.84 + 0.08 * slow
            jitter = 0.30 + 0.08 * abs(slow)
            pitch = 0.30 + 0.38 * spike
        case .neutral:
            rms = 0.35
            centroid = 0.45
            jitter = 0.10
            pitch = 0.50
        }

        let normalizedPitch = Float(min(max(pitch, 0), 1))
        let rmsValue = Float(min(max(rms, 0), 1))
        let centroidValue = Float(min(max(centroid, 0), 1))
        let jitterValue = Float(min(max(jitter, 0), 1))
        let slope = Float(cos(elapsed * 1.1) * 0.25)

        // Phase 2 (Everything2.md 4.1): derive consonant spark, terminal
        // inflection and a plausible room floor so simulated Act III mode drives
        // the Consonant Spark, Question Glide and Lombard features too.
        let sibilance: Double
        let terminalSlope: Double
        let ambientDB: Double
        switch profile {
        case .warmRelief:
            sibilance = 0.18 + 0.06 * abs(slow)
            terminalSlope = -0.32 + 0.05 * slow          // grounded statement drop
            ambientDB = -50
        case .anxiousTremor:
            sibilance = 0.42 + 0.12 * abs(fast)
            terminalSlope = 0.10 + 0.08 * slow            // hesitant, ~steady
            ambientDB = -46
        case .sharpSarcasm:
            sibilance = 0.68 + 0.22 * spike               // strong S/SH/T/K sparks
            terminalSlope = 0.36 + 0.08 * slow            // mock question rise
            ambientDB = -58
        case .neutral:
            sibilance = 0.22
            terminalSlope = 0
            ambientDB = -50
        }

        return ProsodyFrame(
            rmsAmplitude: rmsValue,
            fundamentalPitchHz: 85 + normalizedPitch * (320 - 85),
            normalizedPitch: normalizedPitch,
            spectralCentroid: centroidValue,
            pitchJitter: jitterValue,
            classifiedEmotion: EmotionalProfile.classify(
                centroid: centroidValue,
                jitter: jitterValue,
                pitchSlope: slope,
                rms: rmsValue
            ),
            sibilanceEnergy: Float(min(max(sibilance, 0), 1)),
            terminalPitchSlope: Float(min(max(terminalSlope, -1), 1)),
            ambientNoiseDB: Float(ambientDB)
        )
    }

    // MARK: - Private acoustic model

    private struct Harmonic {
        let number: Int
        let amplitude: Double
    }

    /// Instantaneous fundamental frequency in Hz across the sample's lifetime.
    private static func fundamental(profile: EmotionalProfile, time: Double) -> Double {
        switch profile {
        case .warmRelief:
            // Smooth downward glide 190 Hz → 135 Hz over the first two seconds.
            let progress = min(time / 2.0, 1.0)
            let eased = 0.5 - 0.5 * cos(Double.pi * progress)
            return 190 - 55 * eased
        case .anxiousTremor:
            // Elevated base pitch with a 6.5 Hz vibrato tremor of ±18 Hz.
            return 235 + 18 * sin(2 * Double.pi * 6.5 * time)
        case .sharpSarcasm:
            // Abrupt narrow-band spike on word 2 ("FINE" at 290 Hz), then a flat drop.
            if time < 0.95 { return 225 }
            if time < 1.50 { return 290 }
            return 115
        case .neutral:
            return 165
        }
    }

    /// Harmonic series tuned to hit each emotional target spectral centroid.
    private static func harmonicSeries(for profile: EmotionalProfile) -> [Harmonic] {
        switch profile {
        case .warmRelief:
            // Rich low-harmonic fundamental + 2nd harmonic → warm chest resonance.
            return [Harmonic(number: 1, amplitude: 1.00),
                    Harmonic(number: 2, amplitude: 0.45),
                    Harmonic(number: 3, amplitude: 0.12)]
        case .anxiousTremor:
            return [Harmonic(number: 1, amplitude: 1.00),
                    Harmonic(number: 2, amplitude: 0.30),
                    Harmonic(number: 3, amplitude: 0.16),
                    Harmonic(number: 4, amplitude: 0.08)]
        case .sharpSarcasm:
            // Strong odd harmonics (3rd, 5th, 7th) → biting metallic centroid.
            return [Harmonic(number: 1, amplitude: 0.70),
                    Harmonic(number: 3, amplitude: 0.60),
                    Harmonic(number: 5, amplitude: 0.45),
                    Harmonic(number: 7, amplitude: 0.30)]
        case .neutral:
            return [Harmonic(number: 1, amplitude: 1.00),
                    Harmonic(number: 2, amplitude: 0.20)]
        }
    }

    private static func amplitudeEnvelope(profile: EmotionalProfile, time: Double) -> Double {
        switch profile {
        case .warmRelief:
            return cosineEnvelope(time, attack: 0.18, release: 0.90)
        case .anxiousTremor:
            return cosineEnvelope(time, attack: 0.10, release: 0.45) * syllableGate(time)
        case .sharpSarcasm:
            return harshEnvelope(time)
        case .neutral:
            return cosineEnvelope(time, attack: 0.10, release: 0.45)
        }
    }

    private static func cosineEnvelope(_ time: Double, attack: Double, release: Double) -> Double {
        let attackTime = max(attack, 0.0001)
        let releaseTime = max(release, 0.0001)
        if time < attackTime { return 0.5 - 0.5 * cos(Double.pi * time / attackTime) }
        if time > duration - releaseTime { return 0.5 - 0.5 * cos(Double.pi * (duration - time) / releaseTime) }
        return 1.0
    }

    /// Fragmented amplitude syllables with hesitation pauses (quiet anxiety).
    private static func syllableGate(_ time: Double) -> Double {
        let syllables: [(start: Double, length: Double)] = [
            (0.10, 0.42), (0.72, 0.38), (1.34, 0.44), (2.02, 0.40), (2.62, 0.48)
        ]
        for syllable in syllables where time >= syllable.start && time <= syllable.start + syllable.length {
            let local = (time - syllable.start) / syllable.length
            return sin(Double.pi * local)
        }
        return 0
    }

    /// Harsh staccato transients with razor-thin attacks (biting sarcasm).
    private static func harshEnvelope(_ time: Double) -> Double {
        let words: [(start: Double, length: Double)] = [
            (0.04, 0.52), (0.98, 0.44), (1.54, 0.62), (2.36, 0.78)
        ]
        var gate = 0.0
        for word in words where time >= word.start && time <= word.start + word.length {
            let local = (time - word.start) / word.length
            gate = local < 0.08 ? (local / 0.08) : pow(max(0, 1 - local), 0.5)
        }
        let tail = time > duration - 0.35 ? max(0, (duration - time) / 0.35) : 1
        return gate * tail
    }
}
