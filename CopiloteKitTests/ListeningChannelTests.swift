import AVFoundation
import XCTest
@testable import CopiloteKit

/// The channel against a fake transcriber (the speech model is the boundary).
final class ListeningChannelTests: XCTestCase {
    func test_stoppingAnEmptyLiveChannelCancelsInsteadOfWaitingForFinalRecognition() async {
        let transcriber = CancellationTranscriber()
        let channel = ListeningChannel(speaker: .them, transcriber: transcriber) { _ in }
        await channel.finish(discardPending: true)
        XCTAssertEqual(transcriber.calls, ["cancel"])
    }

    func test_fileReplayStillFinalizesPendingRecognition() async {
        let transcriber = CancellationTranscriber()
        let channel = ListeningChannel(speaker: .them, transcriber: transcriber) { _ in }
        await channel.finish()
        XCTAssertEqual(transcriber.calls, ["finish"])
    }

    /// ScreenCaptureKit may stop delivering buffers while nothing plays: the end of speech
    /// must still be noticed, or the turn never ends.
    func test_whenAudioStopsArrivingTheSpeakerIsStillHeardStopping() async throws {
        let ended = expectation(description: "speech ended")
        let channel = ListeningChannel(speaker: .them, transcriber: SilentTranscriber()) { event in
            if case .speaking(.them, false) = event { ended.fulfill() }
        }

        channel.append(try XCTUnwrap(Self.buffer(Signal.silence(0.3) + Signal.tone(1.0))))
        // …and then nothing more, not even silence.

        await fulfillment(of: [ended], timeout: 3)
        await channel.finish()
    }

    static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: AudioResampler.outputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        buffer.floatChannelData![0].update(from: samples, count: samples.count)
        return buffer
    }
}

private final class CancellationTranscriber: Transcriber, @unchecked Sendable {
    let events: AsyncStream<TranscriberEvent>
    private let sink: AsyncStream<TranscriberEvent>.Continuation
    private let lock = NSLock()
    private var recorded: [String] = []
    var calls: [String] { lock.withLock { recorded } }
    init() { (events, sink) = AsyncStream.makeStream() }
    func append(_ buffer: AVAudioPCMBuffer, at time: TimeInterval) {}
    func finalize(through time: TimeInterval) async {}
    func finish() async { lock.withLock { recorded.append("finish") }; sink.finish() }
    func cancel() async { lock.withLock { recorded.append("cancel") }; sink.finish() }
}

private final class SilentTranscriber: Transcriber, @unchecked Sendable {
    let events: AsyncStream<TranscriberEvent>
    private let sink: AsyncStream<TranscriberEvent>.Continuation

    init() {
        (events, sink) = AsyncStream.makeStream()
    }

    func append(_ buffer: AVAudioPCMBuffer, at time: TimeInterval) {}
    func finalize(through time: TimeInterval) async {}
    func finish() async { sink.finish() }
}
