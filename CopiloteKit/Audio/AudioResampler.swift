import AVFoundation

/// Converts whatever the device delivers (48 kHz stereo, Int16…) to 16 kHz mono Float32,
/// the format the VAD works on. One instance per channel, used from one thread.
public final class AudioResampler {
    public static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private var converter: AVAudioConverter?

    public init() {}

    /// Returns a new buffer the caller owns (the input may be a no-copy view of a system buffer).
    public func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: Self.outputFormat)
        }
        guard let converter else { return nil }
        return Self.convert(input, with: converter)
    }

    /// One buffer through a streaming converter. `.noDataNow` (not end of stream) keeps the
    /// converter's state, so consecutive buffers resample without clicks at their edges.
    static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard input.frameLength > 0 else { return nil }
        let ratio = converter.outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// Zeroed 16 kHz mono audio.
    public static func silence(seconds: TimeInterval) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * outputFormat.sampleRate)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frames),
              let data = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        data[0].update(repeating: 0, count: Int(frames))
        return buffer
    }
}

extension AVAudioPCMBuffer {
    /// Samples of a mono Float32 buffer.
    var monoSamples: [Float] {
        guard let data = floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(frameLength)))
    }
}
