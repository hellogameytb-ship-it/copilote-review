import AVFoundation

/// A listening session: one channel per speaker feeding the topic pipeline.
/// Shared by the app (live audio) and `copilote-replay` (a WAV file).
public final class ListeningSession: Sendable {
    public let pipeline: TopicPipeline
    private let channels: [ListeningChannel]
    private let pipelineInput: AsyncStream<PipelineInput>.Continuation
    private let pipelineWorker: Task<Void, Never>

    private enum PipelineInput: Sendable {
        case line(TranscriptLine)
        case turn(Turn)
        case reset(TimeInterval)
    }

    public init(
        transcribers: [(Speaker, any Transcriber)],
        segmenter: (any TopicSegmenter)?,
        segmenterName: String,
        onEvent: @escaping @Sendable (ListeningEvent) -> Void
    ) {
        let pipeline = TopicPipeline(segmenter: segmenter, segmenterName: segmenterName) { onEvent(.topics($0)) }
        self.pipeline = pipeline
        let (stream, input) = AsyncStream<PipelineInput>.makeStream()
        pipelineInput = input
        // One ordered stream: a phrase reaches the transcript before the turn it ends.
        pipelineWorker = Task {
            for await item in stream {
                switch item {
                case let .line(line): await pipeline.add(line)
                case let .turn(turn): await pipeline.handle(turn)
                case let .reset(boundary): await pipeline.resetContext(after: boundary)
                }
            }
        }
        channels = transcribers.map { speaker, transcriber in
            ListeningChannel(speaker: speaker, transcriber: transcriber) { event in
                onEvent(event)
                switch event {
                case let .line(line, _, _): input.yield(.line(line))
                case let .turn(turn): input.yield(.turn(turn))
                default: break
                }
            }
        }
    }

    public func resetContext(after boundary: TimeInterval) { pipelineInput.yield(.reset(boundary)) }

    public func append(_ buffer: AVAudioPCMBuffer, from speaker: Speaker) {
        channels.first { $0.speaker == speaker }?.append(buffer)
    }

    /// Processes what is left, decides the last turns (the model's word included), then returns.
    public func finish(discardPending: Bool = false) async {
        for channel in channels { await channel.finish(discardPending: discardPending) }
        pipelineInput.finish()
        await pipelineWorker.value
        await pipeline.waitForModel()
    }
}
