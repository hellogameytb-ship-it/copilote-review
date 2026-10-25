import AVFoundation
import os

/// What one channel (or the whole listening session) reports.
public enum ListeningEvent: Sendable {
    case speaking(Speaker, Bool)
    case failure(Speaker, String)
    case volatile(Speaker, String)
    /// A finalized phrase; `latency` is how long after the end of the phrase it arrived
    /// (only meaningful when audio is fed in real time).
    case line(TranscriptLine, language: String, latency: TimeInterval)
    case turn(Turn)
    case topics(TopicUpdate)
}

/// One audio channel: resample → VAD → transcriber → turns. Buffers are processed in order.
public final class ListeningChannel: Sendable {
    public let speaker: Speaker
    private let resampler = OSAllocatedUnfairLock(initialState: AudioResampler())
    private let buffers: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let worker: Task<Void, Never>
    private let state: ChannelState
    /// When audio last arrived (uptime), nil before the first buffer.
    private let lastAudio = OSAllocatedUnfairLock<TimeInterval?>(initialState: nil)
    private let heartbeat: Task<Void, Never>

    public init(speaker: Speaker, transcriber: any Transcriber, onEvent: @escaping @Sendable (ListeningEvent) -> Void) {
        self.speaker = speaker
        // Unbounded: dropping a buffer would shift this channel's clock against the other one.
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        buffers = continuation
        // System audio may stop delivering buffers while nothing plays: the VAD and the turn
        // clock would freeze mid-turn. Fill such gaps with silence.
        heartbeat = Task { [lastAudio] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let now = ProcessInfo.processInfo.systemUptime
                let gap: TimeInterval? = lastAudio.withLock { last in
                    guard let previous = last, now - previous >= 0.4 else { return nil }
                    last = now
                    return now - previous
                }
                if let gap, let silence = AudioResampler.silence(seconds: min(gap, 2)) { continuation.yield(silence) }
            }
        }
        let state = ChannelState(speaker: speaker, transcriber: transcriber, onEvent: onEvent)
        self.state = state
        worker = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await state.consumeTranscripts() }
                group.addTask {
                    for await buffer in stream { await state.process(buffer) }
                    await state.finishTranscribing()
                }
            }
            // Only once every final result has been read.
            await state.flush()
        }
    }

    /// Any format; converted right away (the input may be a view of a system buffer).
    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = resampler.withLock({ $0.convert(buffer) }) else { return }
        lastAudio.withLock { $0 = ProcessInfo.processInfo.systemUptime }
        buffers.yield(converted)
    }

    /// Ends the channel: remaining audio is processed and the last turn flushed.
    public func finish(discardPending: Bool = false) async {
        heartbeat.cancel()
        if discardPending { await state.cancel() }
        buffers.finish()
        await worker.value
    }
}

private actor ChannelState {
    let speaker: Speaker
    let transcriber: any Transcriber
    let onEvent: @Sendable (ListeningEvent) -> Void
    var vad = VoiceActivityDetector()
    var assembler: TurnAssembler
    private var cancelled = false
    /// Samples processed so far on this channel (an integer: no floating-point drift).
    var samples: Int64 = 0
    /// Audio time: seconds of audio processed so far on this channel.
    var clock: TimeInterval { Double(samples) / AudioResampler.outputFormat.sampleRate }
    /// Wall time when the first buffer arrived, to measure latency against.
    var startedAt: TimeInterval?
    /// Where the VAD last heard the voice stop: the honest start for "final text latency".
    var lastSpeechEnd: TimeInterval?
    /// Start of the current stretch of speech, or of the last forced finalization within it.
    var speechSince: TimeInterval?

    init(speaker: Speaker, transcriber: any Transcriber, onEvent: @escaping @Sendable (ListeningEvent) -> Void) {
        self.speaker = speaker
        self.transcriber = transcriber
        self.onEvent = onEvent
        assembler = TurnAssembler(speaker: speaker)
    }

    func cancel() async {
        cancelled = true
        await transcriber.cancel()
    }

    func finishTranscribing() async {
        if !cancelled { await transcriber.finish() }
    }

    func process(_ buffer: AVAudioPCMBuffer) async {
        guard !cancelled else { return }
        if startedAt == nil { startedAt = ProcessInfo.processInfo.systemUptime }
        let start = clock
        samples += Int64(buffer.frameLength)
        transcriber.append(buffer, at: start)
        for event in vad.process(buffer.monoSamples, startingAt: start) {
            assembler.handle(event)
            switch event {
            case let .speechStarted(time):
                speechSince = time
                onEvent(.speaking(speaker, true))
            case let .speechEnded(time):
                speechSince = nil
                lastSpeechEnd = time
                onEvent(.speaking(speaker, false))
                // Don't wait for the model's own endpointing: finalize what was just said.
                let transcriber = transcriber
                Task { await transcriber.finalize(through: time + 0.1) }
            }
        }
        // A monologue without pauses: ask for final text every 10 s so the turn can be cut.
        if let since = speechSince, clock - since >= 10 {
            speechSince = clock
            let transcriber = transcriber, now = clock
            Task { await transcriber.finalize(through: now) }
        }
        emitTurns(assembler.advance(to: clock))
    }

    func consumeTranscripts() async {
        for await event in transcriber.events {
            guard !cancelled else { continue }
            switch event {
            case let .failure(message):
                onEvent(.failure(speaker, message))
            case let .volatile(text):
                onEvent(.volatile(speaker, text))
            case let .final(text):
                assembler.addFinal(text.text, start: text.start, end: text.end)
                let elapsed = startedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? text.end
                // From the end of the voice (VAD) when this phrase ended with a pause, else from its last word.
                let voiceEnd = lastSpeechEnd.flatMap { abs($0 - text.end) < 1 ? $0 : nil } ?? text.end
                let line = TranscriptLine(speaker: speaker, text: text.text, start: text.start, end: text.end)
                onEvent(.line(line, language: text.language, latency: max(0, elapsed - voiceEnd)))
                emitTurns(assembler.advance(to: clock))
            }
        }
    }

    func flush() {
        guard !cancelled else { return }
        emitTurns(assembler.flush())
    }

    private func emitTurns(_ turns: [Turn]) {
        turns.forEach { onEvent(.turn($0)) }
    }
}
