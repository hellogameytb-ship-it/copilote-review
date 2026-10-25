import AVFoundation

public enum TranscriberEvent: Sendable {
    /// Live text of the phrase being spoken (replaced as it changes; empty once finalized).
    case volatile(String)
    case final(ArbitratedText)
    case failure(String)
}

/// Speech to text for one audio channel. On-device today (`SpeechAnalyzerTranscriber`);
/// a cloud backend can implement the same protocol later.
public protocol Transcriber: AnyObject, Sendable {
    var events: AsyncStream<TranscriberEvent> { get }
    /// 16 kHz mono Float32 audio; `time` is the buffer start on the channel clock.
    func append(_ buffer: AVAudioPCMBuffer, at time: TimeInterval)
    /// Asks for final results up to `time` (the VAD heard the end of a phrase).
    func finalize(through time: TimeInterval) async
    /// No more audio: finalizes everything, then ends `events`.
    func finish() async
    /// Discards pending recognition when a live session is stopped.
    func cancel() async
}

public extension Transcriber {
    func cancel() async { await finish() }
}
