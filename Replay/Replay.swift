import AVFoundation
import CopiloteKit
import Foundation

/// `make replay FILE=<wav>`: plays a recording through VAD → transcription → topic segmentation
/// and prints the topic cases as they change. Mono = the others ("Eux"); stereo = left "Eux",
/// right "Moi". Topic decisions: Codex with `--provider codex`, Claude Haiku when ANTHROPIC_API_KEY
/// is set, the keyword fallback otherwise (or with `--offline`).
///
///   copilote-replay <file.wav> [--provider codex|anthropic] [--offline] [--speed N]
///                   [--base <index store> --base-dir <base folder> [--today AAAA-MM-JJ]]
///   copilote-replay ask [--provider codex|anthropic] [--image f.jpg]… [--repeat N] "question"
///   (with --image the question is not sent: captures get the app's own prompt, as with ⌘↩)
@main
struct Replay {
    /// Stopped before exiting: its private logs (they hold the prompts) go with it.
    nonisolated(unsafe) static var codexServer: CodexAppServer?

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            if arguments.first == "ask" {
                try await ask(Array(arguments.dropFirst()))
                quit(0)
            }
            if arguments.first == "notes" {
                try await notes(Array(arguments.dropFirst()))
                quit(0)
            }
            guard let path = arguments.first(where: { !$0.hasPrefix("--") && Double($0) == nil && !["codex", "anthropic"].contains($0) }) else {
                print("usage: copilote-replay <file.wav> [--provider codex|anthropic] [--offline] [--speed N]")
                exit(2)
            }
            let speed = value(of: "--speed", in: arguments).flatMap(Double.init) ?? 1
            let provider = arguments.contains("--offline") ? nil : try makeProvider(value(of: "--provider", in: arguments))
            var base: ReplayBase?
            if let store = value(of: "--base", in: arguments) {
                base = try await ReplayBase(
                    store: URL(fileURLWithPath: store), root: URL(fileURLWithPath: value(of: "--base-dir", in: arguments) ?? "fixtures/base-demo"),
                    today: value(of: "--today", in: arguments).flatMap(CalendarDay.init(iso:)) ?? .today()
                )
            }
            try await run(URL(fileURLWithPath: path), provider: provider, speed: speed, base: base)
            quit(0)
        } catch {
            print("échec : \((error as? CodexFailure)?.userMessage ?? (error as? APIFailure)?.userMessage ?? "\(error)")")
            quit(1)
        }
    }

    static func quit(_ status: Int32) -> Never {
        codexServer?.terminateNow()
        exit(status)
    }

    /// nil when no provider can be used (no codex, no key): keywords then.
    static func makeProvider(_ name: String?) throws -> (any LLMProvider)? {
        switch name {
        case "codex":
            guard let executable = CodexAvailability.locate() else { throw CodexFailure(message: "codex introuvable") }
            guard CodexAvailability.isReady(executable: executable) else { throw CodexFailure(message: "codex n'est pas connecté (codex login)") }
            let server = CodexAppServer(
                executable: executable, workingDirectory: CodexAvailability.workingDirectory,
                // Its own directory: the app may be running Codex in the shared one.
                privateDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("copilote-replay-codex-private"),
                loadUserConfig: { try CodexAvailability.userConfig() }
            )
            codexServer = server
            return CodexProvider(server: server, answerModel: CodexProvider.defaultModel, topicModel: CodexProvider.defaultModel, serviceTier: "priority")
        default:
            guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
                if name == "anthropic" { throw APIFailure(type: "authentication_error", message: "ANTHROPIC_API_KEY absent") }
                return nil
            }
            return AnthropicProvider(client: AnthropicClient(), apiKey: key, settings: ModelSettings(model: ModelSettings.defaultModel))
        }
    }

    static func value(of option: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: option).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    static func run(_ url: URL, provider: (any LLMProvider)?, speed: Double, base: ReplayBase? = nil) async throws {
        let file = try AVAudioFile(forReading: url)
        let speakers: [Speaker] = file.processingFormat.channelCount >= 2 ? [.them, .me] : [.them]
        let printer = Printer(realtime: speed == 1)

        print("Copilote replay · \(url.lastPathComponent) · \(String(format: "%.1f", Double(file.length) / file.processingFormat.sampleRate)) s")
        print("Canaux : \(speakers.map(\.rawValue).joined(separator: " + ")) · transcription : SpeechAnalyzer fr_FR + en_US (sur l'appareil)")
        let segmenterName = provider?.topicSegmenterName ?? "lexical"
        print("Découpage : \(provider == nil ? "mots-clés (hors ligne)" : segmenterName) · vitesse ×\(speed)")
        if let base { print("Base perso : \(base.summary) · fiche directe sans LLM sur les questions perso") }
        print(String(repeating: "─", count: 72))
        await provider?.warmUp()

        var transcribers: [(Speaker, any Transcriber)] = []
        for speaker in speakers { transcribers.append((speaker, try await SpeechAnalyzerTranscriber())) }
        let audioStart = ContinuousClock.now
        await printer.startAudio(at: audioStart, speed: speed)
        // As in the app: case 1 gets its answer drafted by itself (with a provider).
        let drafter = provider.map { Drafter(provider: $0, base: base?.base, today: base?.today ?? .today(), audioStart: audioStart, speed: speed) }
        let (events, eventSink) = AsyncStream<(ListeningEvent, ContinuousClock.Instant)>.makeStream()
        let printing = Task {
            for await (event, instant) in events {
                await printer.print(event, at: instant)
                await drafter?.handle(event, at: instant)
            }
        }
        let session = ListeningSession(transcribers: transcribers, segmenter: provider?.topicSegmenter, segmenterName: segmenterName) { event in
            eventSink.yield((event, ContinuousClock.now))
            // As in the app: the others' turn goes to the base at once, in parallel with the segmenter.
            if case let .turn(turn) = event, turn.speaker == .them, let base {
                let heard = ContinuousClock.now
                let voiceEnded = audioInstant(audioStart, turn.end, speed: speed)
                Task { await printer.fiche(await base.route(turn.text), sinceTurn: ContinuousClock.now - heard, sinceVoice: ContinuousClock.now - voiceEnded) }
            }
        }

        try await feed(file, speakers: speakers, to: session, speed: speed)
        await session.finish()
        eventSink.finish()
        await printing.value
        await drafter?.finish()
        await printer.summary(board: await session.pipeline.board)
        await drafter?.summary()
    }

    /// `make notes FILE=…`: the recording transcribed on the device, then the end-of-meeting
    /// notes, the follow-up email (and the self-review with --review) through the provider.
    static func notes(_ arguments: [String]) async throws {
        guard let path = arguments.first(where: { !$0.hasPrefix("--") && Double($0) == nil && !["codex", "anthropic"].contains($0) && MeetingMode(rawValue: $0) == nil }) else {
            print("usage: copilote-replay notes <file.wav> [--provider codex|anthropic] [--mode reunion|technique|potes|presentation] [--review]")
            quit(2)
        }
        guard let provider = try makeProvider(value(of: "--provider", in: arguments) ?? "codex") else {
            throw APIFailure(type: "authentication_error", message: "aucun fournisseur : --provider codex ou ANTHROPIC_API_KEY")
        }
        let mode = value(of: "--mode", in: arguments).flatMap(MeetingMode.init(rawValue:)) ?? .meeting
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let speakers: [Speaker] = file.processingFormat.channelCount >= 2 ? [.them, .me] : [.them]
        print("Copilote notes · \(URL(fileURLWithPath: path).lastPathComponent) · mode \(mode.name) · \(provider.label)")
        let lines = LineCollector()
        var transcribers: [(Speaker, any Transcriber)] = []
        for speaker in speakers { transcribers.append((speaker, try await SpeechAnalyzerTranscriber())) }
        let session = ListeningSession(transcribers: transcribers, segmenter: nil, segmenterName: "lexical") { event in
            if case let .line(line, _, _) = event { lines.add(line) }
        }
        try await feed(file, speakers: speakers, to: session, speed: value(of: "--speed", in: arguments).flatMap(Double.init) ?? 1)
        await session.finish()
        let transcript = lines.all
        print("Transcript : \(transcript.count) phrases (\(transcript.filter { $0.speaker == .me }.count) de Moi)")
        for line in transcript { print("  \(line.labeled)") }
        print(String(repeating: "─", count: 72))
        let started = ContinuousClock.now
        let notes = try await provider.meetingNotes(transcript: transcript, mode: mode)
        print("# \(notes.title.isEmpty ? "Notes" : notes.title)\n")
        print(notes.markdown)
        let email = notes.email(mode: mode)
        print("\n## E-mail de suivi\n**Objet :** \(email.subject)\n\n\(email.body)")
        if arguments.contains("--review") {
            print("\n## Bilan sur mes réponses\n" + (try await provider.selfReview(transcript: transcript)).markdown)
        }
        print(String(repeating: "─", count: 72))
        print(String(format: "Notes en %.1f s via %@", (ContinuousClock.now - started).seconds, provider.label))
    }

    /// Latency of one answer: first word and total, text only or with captures.
    static func ask(_ arguments: [String]) async throws {
        guard let provider = try makeProvider(value(of: "--provider", in: arguments)) else {
            throw APIFailure(type: "authentication_error", message: "aucun fournisseur : --provider codex ou ANTHROPIC_API_KEY")
        }
        var images: [CapturedImage] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--image", arguments.indices.contains(index + 1) {
                let data = try Data(contentsOf: URL(fileURLWithPath: arguments[index + 1]))
                images.append(CapturedImage(data: data, mediaType: "image/jpeg", pixelWidth: 0, pixelHeight: 0))
                index += 1
            }
            index += 1
        }
        let repeats = max(1, value(of: "--repeat", in: arguments).flatMap(Int.init) ?? 1)
        let optionValues = Set(["--provider", "--image", "--repeat"].compactMap { option in arguments.firstIndex(of: option).map { $0 + 1 } })
        let question = arguments.enumerated().last { !$0.element.hasPrefix("--") && !optionValues.contains($0.offset) && !arguments[max(0, $0.offset - 1)].hasPrefix("--image") }?.element
        var conversation = Conversation()
        conversation.appendUser(images.isEmpty ? .clipboardText(question ?? "Bonjour") : .screenshots(images))
        print("\(provider.label) · \(images.isEmpty ? "texte" : "\(images.count) captures") · \(repeats) essai(s)")
        await provider.warmUp()
        var firsts: [Double] = [], totals: [Double] = []
        for attempt in 1...repeats {
            let started = ContinuousClock.now
            let first = FirstWord()
            let answer = try await provider.streamAnswer(to: conversation) { _ in await first.mark(started) }
            let total = (ContinuousClock.now - started).seconds
            let firstWord = await first.value ?? total
            firsts.append(firstWord); totals.append(total)
            let text = answer.content.compactMap { $0["text"]?.stringValue }.joined()
            print(String(format: "  #%d · 1er mot %.2f s · total %.2f s · %d caractères · %@", attempt, firstWord, total, text.count, String(text.prefix(60)).replacingOccurrences(of: "\n", with: " ")))
        }
        print(String(format: "Médianes : 1er mot %.2f s (max %.2f) · total %.2f s (max %.2f)", firsts.median, firsts.max()!, totals.median, totals.max()!))
    }

    /// Reads 50 ms chunks at real-time pace (× speed), then 1.5 s of silence so the last turn ends naturally.
    static func feed(_ file: AVAudioFile, speakers: [Speaker], to session: ListeningSession, speed: Double) async throws {
        let format = file.processingFormat
        let chunk = AVAudioFrameCount(format.sampleRate / 20) // 50 ms, like live capture buffers
        let started = ContinuousClock.now
        var position: Double = 0
        func pace() async throws {
            let due = started + .milliseconds(Int(position / speed * 1000))
            try await Task.sleep(until: due, clock: .continuous)
        }
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return }
            try file.read(into: buffer, frameCount: chunk)
            for (index, speaker) in speakers.enumerated() {
                if let mono = buffer.channel(index) { session.append(mono, from: speaker) }
            }
            position += Double(buffer.frameLength) / format.sampleRate
            try await pace()
        }
        for _ in 0..<30 {
            for (index, speaker) in speakers.enumerated() {
                if let silence = AVAudioPCMBuffer.silence(format: format, frames: chunk)?.channel(index) {
                    session.append(silence, from: speaker)
                }
            }
            position += Double(chunk) / format.sampleRate
            try await pace()
        }
    }
}

/// The personal base on the replay's turns, through the same Kit call as the app.
struct ReplayBase {
    let base: PersonalBase
    let today: CalendarDay

    init(store: URL, root: URL, today: CalendarDay) async throws {
        let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
        let embedder: TextEmbedder = await ContextualEmbedder.prepare() ?? NoEmbedder()
        base = PersonalBase(search: BaseSearch(index: index, embedder: embedder), index: index, root: root)
        self.today = today
        await base.warmUp()
    }

    var summary: String { "\(base.index.itemCount) éléments" }

    func route(_ question: String) async -> PersonalBase.Found? {
        await base.fiche(for: question, today: today)
    }
}

/// Prints events in arrival order with the audio time they refer to.
actor Printer {
    let realtime: Bool
    private var latencies: [TimeInterval] = []
    private var decisions: [TimeInterval] = []
    private var instantCases: [(sinceTurn: Double, sinceVoice: Double)] = []
    /// When the audio started playing, to time events from the last syllable.
    private var audioStart: ContinuousClock.Instant?
    private var speed = 1.0

    func startAudio(at instant: ContinuousClock.Instant, speed: Double) {
        audioStart = instant
        self.speed = speed
    }
    private var fiches: [(sinceTurn: Double, sinceVoice: Double)] = []

    init(realtime: Bool) {
        self.realtime = realtime
    }

    func print(_ event: ListeningEvent, at instant: ContinuousClock.Instant = .now) {
        switch event {
        case let .failure(speaker, message):
            Swift.print("Transcription \(speaker): \(message)")
        case let .line(line, language, latency):
            latencies.append(latency)
            let delay = realtime ? String(format: " · texte final +%.0f ms", latency * 1000) : ""
            Swift.print("[\(Self.time(line.start))] \(line.speaker.rawValue) (\(language)) « \(line.text) »\(delay)")
        case let .turn(turn):
            Swift.print("  ↳ fin de tour \(turn.speaker.rawValue) [\(Self.time(turn.start)) → \(Self.time(turn.end))]")
        case let .topics(update):
            guard let turn = update.turn else { return }
            let decided = String(format: "%@, +%.0f ms après la fin du tour", update.source, update.latency * 1000)
            if update.isFinal { decisions.append(update.latency) }
            let title = { (id: String) in update.topics.first { $0.id == id }.map { " « \($0.title) »" } ?? "" }
            switch update.change {
            case let .created(id) where !update.isFinal:
                let sinceVoice = audioStart.map { (instant - audioInstant($0, turn.end, speed: speed)).seconds } ?? 0
                instantCases.append((update.latency, sinceVoice))
                Swift.print(String(format: "  ⚡ case instantanée %@%@ (%@, %.2f s après la dernière syllabe)", id, title(id), decided, sinceVoice))
            case let .updated(id) where !update.isFinal: Swift.print("  ⚡ case \(id) complétée (\(decided))")
            case let .created(id): Swift.print("  → nouveau sujet \(id)\(title(id)) (\(decided))")
            case let .updated(id): Swift.print("  → sujet \(id) mis à jour\(title(id)) (\(decided))")
            case let .confirmed(id): Swift.print("  → \(id) confirmée\(title(id)) (\(decided))")
            case let .merged(from, into): Swift.print("  → \(from) fusionnée dans \(into)\(title(into)) (\(decided))")
            case let .withdrawn(id): Swift.print("  → \(id) retirée : rien à répondre (\(decided))")
            case .ignored: Swift.print("  → ignoré : « \(turn.text.prefix(40)) » (\(decided))")
            case .dropped: Swift.print("  → 4 cases épinglées, sujet non affiché (\(decided))")
            case .pinned: break
            }
            if update.change != .ignored { printBoard(update.topics) }
        case .speaking, .volatile:
            break
        }
    }

    func fiche(_ found: PersonalBase.Found?, sinceTurn: Duration, sinceVoice: Duration) {
        let turn = sinceTurn.seconds * 1000, voice = sinceVoice.seconds
        switch found?.decision.action ?? .llm {
        case .show, .suggest:
            guard let found else { return }
            let fiche = found.fiche
            if found.decision.action == .show { fiches.append((turn, voice)) }
            let what: String
            switch fiche.content {
            case .project: what = "carte projet"
            case let .trip(card): what = "voyage + \(card.photos.count) photos"
            case let .photos(grid): what = "grille de \(grid.photos.count) photos"
            case .extract: what = "extrait"
            }
            let verb = found.decision.action == .show ? "FICHE DIRECTE" : "fiche suggérée"
            Swift.print(String(format: "  ⚡ %@ : %@ (%@) · +%.0f ms après la fin du tour, %.2f s après la dernière syllabe · sans LLM",
                               verb, fiche.title, what, turn, voice))
        case .llm:
            Swift.print(String(format: "  · base : pas une question perso → chemin LLM (%.0f ms)", turn))
        }
    }

    func summary(board: TopicBoard) {
        Swift.print(String(repeating: "─", count: 72))
        Swift.print("Cases finales :")
        printBoard(board.topics)
        if realtime, !latencies.isEmpty {
            let sorted = latencies.sorted()
            Swift.print(String(
                format: "Texte final après la fin de phrase : médiane %.0f ms, max %.0f ms (%d phrases)",
                sorted[sorted.count / 2] * 1000, sorted.last! * 1000, sorted.count
            ))
        }
        if !fiches.isEmpty {
            Swift.print(String(
                format: "Fiches directes : %d, après la fin du tour médiane %.0f ms (max %.0f ms) · après la dernière syllabe médiane %.2f s (max %.2f s)",
                fiches.count, fiches.map(\.sinceTurn).median, fiches.map(\.sinceTurn).max()!, fiches.map(\.sinceVoice).median, fiches.map(\.sinceVoice).max()!
            ))
        }
        if !instantCases.isEmpty {
            Swift.print(String(
                format: "Cases instantanées : %d, après la fin du tour médiane %.0f ms (max %.0f ms) · après la dernière syllabe médiane %.2f s (max %.2f s)",
                instantCases.count, instantCases.map(\.sinceTurn).median * 1000, instantCases.map(\.sinceTurn).max()! * 1000,
                instantCases.map(\.sinceVoice).median, instantCases.map(\.sinceVoice).max()!
            ))
        }
        if let slowest = decisions.max() {
            Swift.print(String(format: "Découpage final : %d décisions, après la fin du tour médiane %.0f ms, max %.0f ms", decisions.count, decisions.median * 1000, slowest * 1000))
        }
    }

    private func printBoard(_ topics: [Topic]) {
        for (index, topic) in topics.enumerated() {
            let pin = topic.isPinned ? " · épinglé" : ""
            let updates = topic.version > 1 ? " · \(topic.version - 1) mise(s) à jour" : ""
            let provisional = topic.isProvisional ? " · provisoire" : ""
            Swift.print("     \(index + 1). \(topic.title)  (\(topic.id)\(updates)\(pin)\(provisional))")
        }
    }

    private static func time(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}

extension AVAudioPCMBuffer {
    /// One channel of a deinterleaved Float32 buffer, as a mono buffer.
    func channel(_ index: Int) -> AVAudioPCMBuffer? {
        guard let data = floatChannelData, index < Int(format.channelCount),
              let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameLength) else { return nil }
        mono.frameLength = frameLength
        mono.floatChannelData![0].update(from: data[index], count: Int(frameLength))
        return mono
    }

    static func silence(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) { data[channel].update(repeating: 0, count: Int(frames)) }
        return buffer
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

actor FirstWord {
    private(set) var value: Double?
    func mark(_ started: ContinuousClock.Instant) {
        if value == nil { value = (ContinuousClock.now - started).seconds }
    }
}

/// When a moment of the recording (seconds into it) was played, at this speed.
func audioInstant(_ start: ContinuousClock.Instant, _ time: TimeInterval, speed: Double) -> ContinuousClock.Instant {
    start + .milliseconds(Int(time / speed * 1000))
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

extension Array where Element == Double {
    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = sorted()
        return count.isMultiple(of: 2) ? (sorted[count / 2 - 1] + sorted[count / 2]) / 2 : sorted[count / 2]
    }
}

/// The finalized phrases, in arrival order (added from the session's callback, synchronously).
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [TranscriptLine] = []

    func add(_ line: TranscriptLine) {
        lock.withLock { lines.append(line) }
    }

    var all: [TranscriptLine] {
        lock.withLock { lines }
    }
}
