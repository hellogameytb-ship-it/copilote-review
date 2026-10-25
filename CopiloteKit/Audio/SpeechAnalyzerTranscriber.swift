import AVFoundation
import os
import Speech

/// On-device transcription with SpeechAnalyzer (macOS 26+). French and English transcribers
/// run side by side on the same audio and `LanguageArbiter` keeps the more confident one,
/// since SpeechTranscriber has no language detection of its own.
@available(macOS 26, *)
public final class SpeechAnalyzerTranscriber: Transcriber, @unchecked Sendable {
    public static let defaultLocales = [Locale(identifier: "fr_FR"), Locale(identifier: "en_US")]

    public let events: AsyncStream<TranscriberEvent>
    private let eventSink: AsyncStream<TranscriberEvent>.Continuation
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let analyzer: SpeechAnalyzer
    private let analyzerFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let arbiter: OSAllocatedUnfairLock<LanguageArbiter>
    private var resultTasks: [Task<Void, Never>] = []
    private var timeoutTask: Task<Void, Never>?

    /// Downloads the FR / EN models first if the system doesn't have them yet.
    public init(locales: [Locale] = SpeechAnalyzerTranscriber.defaultLocales) async throws {
        let modules = locales.map { locale in
            (Self.language(of: locale), SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence]
            ))
        }
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules.map(\.1)) {
            try await installation.downloadAndInstall()
        }
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules.map(\.1)) ?? AudioResampler.outputFormat
        converter = analyzerFormat == AudioResampler.outputFormat ? nil : AVAudioConverter(from: AudioResampler.outputFormat, to: analyzerFormat)
        arbiter = OSAllocatedUnfairLock(initialState: LanguageArbiter(languages: modules.map(\.0)))
        (events, eventSink) = AsyncStream.makeStream()
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        analyzer = SpeechAnalyzer(modules: modules.map(\.1))
        try await analyzer.start(inputSequence: stream)

        for (language, module) in modules {
            resultTasks.append(Task { [weak self] in
                do {
                    for try await result in module.results { self?.handle(result, language: language) }
                } catch { self?.eventSink.yield(.failure("Transcription \(language) : \(error.localizedDescription)")) }
            })
        }
        // Lets a passage through when one language never answers for it.
        timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                emit(arbiter.withLock { $0.advance(to: Self.now) })
            }
        }
    }

    deinit {
        timeoutTask?.cancel()
        resultTasks.forEach { $0.cancel() }
        input.finish()
    }

    public func append(_ buffer: AVAudioPCMBuffer, at time: TimeInterval) {
        guard let converted = convert(buffer) else { return }
        // No explicit start time: the channel's audio is contiguous, and timestamps rebuilt from
        // floating-point seconds can land a sample early ("input timestamp overlaps", error 17).
        // Result ranges then count from the channel's first sample, like the channel clock.
        input.yield(AnalyzerInput(buffer: converted))
    }

    public func finalize(through time: TimeInterval) async {
        try? await analyzer.finalize(through: CMTime(seconds: time, preferredTimescale: 16_000))
    }

    public func finish() async {
        input.finish()
        do { try await analyzer.finalizeAndFinishThroughEndOfInput() }
        catch { eventSink.yield(.failure("Fin de transcription : \(error.localizedDescription)")) }
        for task in resultTasks { await task.value }
        timeoutTask?.cancel()
        await timeoutTask?.value
        emit(arbiter.withLock { $0.advance(to: .infinity) })
        eventSink.finish()
    }

    public func cancel() async {
        input.finish()
        timeoutTask?.cancel()
        resultTasks.forEach { $0.cancel() }
        eventSink.finish()
        await analyzer.cancelAndFinishNow()
    }

    private func handle(_ result: SpeechTranscriber.Result, language: String) {
        // Silence before a phrase sometimes comes out as "-..." at the start.
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { "-–—.… ".contains($0) }.description
        guard result.isFinal else {
            if arbiter.withLock({ $0.preferredLanguage }) == language { eventSink.yield(.volatile(text)) }
            return
        }
        let confidences = result.text.runs.compactMap(\.transcriptionConfidence)
        let candidate = TranscriptCandidate(
            language: language,
            text: text,
            start: result.range.start.seconds,
            end: result.range.end.seconds,
            confidence: confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        )
        emit(arbiter.withLock { $0.add(candidate, receivedAt: Self.now) })
    }

    private func emit(_ texts: [ArbitratedText]) {
        for text in texts where !text.text.isEmpty {
            eventSink.yield(.final(text))
            eventSink.yield(.volatile(""))
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        return AudioResampler.convert(buffer, with: converter)
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static func language(of locale: Locale) -> String {
        locale.language.languageCode?.identifier ?? locale.identifier
    }
}
