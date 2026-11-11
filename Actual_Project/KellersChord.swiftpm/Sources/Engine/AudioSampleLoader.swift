import AVFoundation
import Foundation

/// Resolves the three user voice notes out of `Bundle.module` and converts them
/// into a canonical analysis format. When a note is missing — i.e. the user has
/// not yet dropped the `.m4a` files into `Resources/VoiceNotes/` — the loader
/// transparently falls back to `ProceduralVoiceSynthesizer`, so the app always
/// runs and never crashes on an empty folder.
final class AudioSampleLoader {

    /// Where a loaded buffer came from.
    enum Origin: Equatable {
        case bundled(fileName: String)
        case synthesized
    }

    struct LoadedSample {
        let profile: EmotionalProfile
        let buffer: AVAudioPCMBuffer
        let origin: Origin

        var isSynthesized: Bool { origin == .synthesized }
    }

    /// The one format every consumer (player node, DSP tap, haptics) can rely on.
    static let canonicalFormat: AVAudioFormat = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 1
    ) ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    /// Exact filenames the user drops into `Sources/Resources/VoiceNotes/`.
    private static let resourceNames: [EmotionalProfile: String] = [
        .warmRelief: "voice_warm_relief",
        .anxiousTremor: "voice_anxious_tremor",
        .sharpSarcasm: "voice_sharp_sarcasm"
    ]

    /// `.process("Resources")` may flatten or preserve the VoiceNotes folder
    /// depending on the toolchain, so all three extensions are probed.
    private static let searchExtensions = ["m4a", "wav", "mp3"]

    /// Loads all three emotional samples.
    ///
    /// Never throws and never returns fewer than three samples: a missing file is
    /// replaced by an in-memory synthesized buffer.
    func loadAll() -> [LoadedSample] {
        EmotionalProfile.actOneChoices.map { profile in
            let resourceName = Self.resourceNames[profile] ?? ""
            if let url = Self.locateResource(named: resourceName),
               let buffer = Self.readBuffer(at: url) {
                return LoadedSample(profile: profile, buffer: buffer, origin: .bundled(fileName: url.lastPathComponent))
            }
            if let buffer = ProceduralVoiceSynthesizer.makeBuffer(for: profile, format: Self.canonicalFormat) {
                return LoadedSample(profile: profile, buffer: buffer, origin: .synthesized)
            }
            return LoadedSample(profile: profile, buffer: Self.silentBuffer(), origin: .synthesized)
        }
    }

    // MARK: - Bundle resolution

    /// Probes `Bundle.module` for `name` with every supported extension, at the
    /// bundle root and inside the VoiceNotes sub-paths used by SwiftPM's
    /// resource processing.
    private static func locateResource(named name: String) -> URL? {
        guard !name.isEmpty else { return nil }
        for fileExtension in searchExtensions {
            if let url = Bundle.module.url(forResource: name, withExtension: fileExtension) {
                return url
            }
            for subdirectory in ["VoiceNotes", "Resources/VoiceNotes"] {
                if let url = Bundle.module.url(
                    forResource: name,
                    withExtension: fileExtension,
                    subdirectory: subdirectory
                ) {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: - Decoding & conversion

    /// Reads a bundled audio file and converts it into `canonicalFormat`.
    private static func readBuffer(at url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return nil
        }
        guard (try? file.read(into: sourceBuffer)) != nil else { return nil }
        sourceBuffer.frameLength = frameCount

        if file.processingFormat == canonicalFormat { return sourceBuffer }
        return convert(sourceBuffer, to: canonicalFormat)
    }

    /// Sample-rate / channel conversion via `AVAudioConverter`.
    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, statusOut in
            if consumed {
                statusOut.pointee = .endOfStream
                return nil
            }
            consumed = true
            statusOut.pointee = .haveData
            return buffer
        }
        return conversionError == nil ? output : nil
    }

    /// A valid but silent buffer, used only if even synthesis were to fail.
    private static func silentBuffer() -> AVAudioPCMBuffer {
        let format = canonicalFormat
        let capacity = AVAudioFrameCount(format.sampleRate * 0.5)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
              let data = buffer.floatChannelData?[0] else {
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        }
        buffer.frameLength = capacity
        memset(data, 0, Int(capacity) * MemoryLayout<Float>.size)
        return buffer
    }
}
