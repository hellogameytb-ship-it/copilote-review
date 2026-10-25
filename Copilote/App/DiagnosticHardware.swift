import AppKit
import AVFoundation
import CopiloteKit

/// Explicit, bounded hardware recipe. Audio enters ONLY through the production device
/// callbacks. Playback fixtures are synthetic; no captured PCM or transcript is persisted.
@MainActor
enum DiagnosticHardware {
    private static var task: Task<Void, Never>?
    static func startIfAsked() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-RecetteHardware"), args.indices.contains(flag + 1) else { return false }
        let folder = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        let fixtures = folder.deletingLastPathComponent().appendingPathComponent("speech")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        task = Task { @MainActor in
            var checks: [[String: Any]] = []
            var observations: [[String: Any]] = []
            var stopLatencies: [String: Double] = [:]
            @MainActor func save(_ name: String, _ passed: Bool) {
                checks.append(["name": name, "passed": passed])
                let report: [String: Any] = ["checks": checks, "observations": observations,
                    "bundle": Bundle.main.bundleURL.path, "build": Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?",
                    "audioInput": "real AVAudioEngine microphone / ScreenCaptureKit system callbacks",
                    "provider": "local controlled response (no remote audio or transcript)", "capturedAudioSaved": false,
                    "transcriptSaved": false, "stopLatenciesSeconds": stopLatencies,
                    "date": ISO8601DateFormatter().string(from: Date())]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: folder.appendingPathComponent("hardware.json"), options: .atomic)
                }
            }
            guard #available(macOS 26, *) else { save("requires macOS 26", false); NSApp.terminate(nil); return }
            guard MicrophoneCapture.permission == .authorized, ScreenCapturer.hasPermission else {
                save("existing microphone permission", MicrophoneCapture.permission == .authorized)
                save("existing screen/system audio permission", ScreenCapturer.hasPermission)
                NSApp.terminate(nil); return
            }
            let suite = "org.example.copilote.hardware.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let settings = SettingsStore(defaults: defaults, loadCredentials: false)
            settings.baseFolder = folder.appendingPathComponent("nonexistent-fixture-base").path
            settings.keepHistory = false; settings.notesAtEnd = false; settings.selfReview = false
            let provider = HardwareProvider()
            let providers = ProviderController(settings: settings, injectedProvider: provider, observesEnvironment: false)
            let base = BaseController(settings: settings, providers: providers)
            let overlay = OverlayController(settings: settings)
            let answers = SessionController(settings: settings, overlay: overlay, capturer: ScreenCapturer(), providers: providers)
            let listening = ListeningController(settings: settings, providers: providers, base: base)
            listening.answers = answers
            let metrics = HardwareMetrics()
            listening.diagnosticAudioObserver = { speaker, buffer in metrics.append(buffer, speaker: speaker) }
            var automatic: [String] = []
            listening.onAutomaticAnswer = { topic in automatic.append("\(topic.id):\(topic.version)") }
            @MainActor func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
            @MainActor func play(_ name: String, ownProcess: Bool = false) async throws {
                let url = fixtures.appendingPathComponent(name + ".wav")
                if ownProcess {
                    let player = try AVAudioPlayer(contentsOf: url)
                    guard player.play() else { throw NSError(domain: "hardware-playback", code: 1) }
                    let deadline = Date().addingTimeInterval(15)
                    while player.isPlaying && Date() < deadline { await pause(0.1) }
                    player.stop()
                } else {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                    process.arguments = [url.path]
                    try process.run()
                    let deadline = Date().addingTimeInterval(15)
                    while process.isRunning && Date() < deadline { await pause(0.1) }
                    if process.isRunning { process.terminate() }
                    guard process.terminationStatus == 0 else { throw NSError(domain: "hardware-playback", code: 2) }
                }
            }
            @MainActor func start(_ channels: Set<Speaker>, name: String) async {
                metrics.reset(); automatic = []; answers.clear()
                save("starting \(name)", true)
                await listening.start(channels: channels)
                save("\(name): devices started", listening.isListening)
            }
            @MainActor func stop(_ name: String) async {
                let started = ProcessInfo.processInfo.systemUptime
                await listening.stop()
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                stopLatencies[name] = elapsed
                save("\(name): capture shutdown below five seconds", elapsed < 5)
                let count = metrics.count
                let autoCount = automatic.count
                await pause(1.5)
                save("\(name): stopped, no later buffers/transcript/automatic reply", !listening.isListening && listening.transcript.lines.isEmpty && metrics.count == count && automatic.count == autoCount && !answers.isAnswering)
            }
            @MainActor func observe(_ name: String, speakers: Set<Speaker>, expectedWords: [String], expectAuto: Bool) {
                let lines = listening.transcript.lines
                let perSpeaker = speakers.map { speaker -> [String: Any] in
                    let heard = lines.filter { $0.speaker == speaker }.map(\.text)
                    let text = heard.joined(separator: " ")
                    let phrases = expectedWords.map { word -> [String: Any] in
                        let expected = word == "binaire"
                            ? "Comment fonctionne une recherche dans un arbre binaire équilibré"
                            : "What is a hash table and how do you handle collisions"
                        let error = heard.map { Self.wordErrorRate(expected: expected, actual: $0) }.min() ?? 1
                        return ["fixtureLanguage": word == "binaire" ? "fr" : "en", "wordErrorRate": error]
                    }
                    return ["speaker": speaker.rawValue, "lineCount": lines.filter { $0.speaker == speaker }.count,
                        "expectedWordMatches": expectedWords.map { text.localizedCaseInsensitiveContains($0) },
                        "phraseMetrics": phrases]
                }
                observations.append(["phase": name, "audio": metrics.snapshot(), "transcription": perSpeaker,
                    "automaticCount": automatic.count, "topicCount": listening.topics.count])
                for speaker in speakers {
                    let text = lines.filter { $0.speaker == speaker }.map(\.text).joined(separator: " ")
                    save("\(name): \(speaker.rawValue) actual buffers", metrics.frames(speaker) > 0)
                    for word in expectedWords { save("\(name): \(speaker.rawValue) recognized \(word)", text.localizedCaseInsensitiveContains(word)) }
                }
                save("\(name): only selected channels transcribed", lines.allSatisfy { speakers.contains($0.speaker) })
                save("\(name): automatic reply policy", expectAuto ? (!automatic.isEmpty && answers.lastFinished != nil) : automatic.isEmpty)
                save("\(name): no duplicate automatic topic version", Set(automatic).count == automatic.count)
            }
            do {
                if !args.contains("-HardwareBrainOnly") {
                // Each device receives actual playback, not an appended fixture buffer.
                await start([.me], name: "microphone")
                try await play("fr"); await pause(3)
                try await play("en"); await pause(4)
                observe("microphone", speakers: [.me], expectedWords: ["binaire", "hash"], expectAuto: false)
                save("microphone: no interlocutor topic", listening.topics.isEmpty)
                await stop("microphone")

                await start([.them], name: "system")
                try await play("fr"); await pause(3)
                try await play("en"); await pause(4)
                observe("system", speakers: [.them], expectedWords: ["binaire", "hash"], expectAuto: true)
                await stop("system")

                await start([.me, .them], name: "combined")
                try await play("fr"); await pause(3)
                try await play("en"); await pause(4)
                observe("combined", speakers: [.me, .them], expectedWords: ["binaire", "hash"], expectAuto: true)
                let lineCount = listening.transcript.lines.count
                let autoCount = automatic.count
                listening.pauseOrResume()
                try await play("fr"); await pause(1)
                save("pause: no added transcript or answer during real playback", listening.isPaused && listening.transcript.lines.count == lineCount && automatic.count == autoCount)
                listening.pauseOrResume()
                try await play("resume"); await pause(4)
                save("resume: fresh real audio recognized", listening.transcript.lines.contains { $0.text.localizedCaseInsensitiveContains("récurs") })
                await stop("combined")

                // The app's own process is excluded by ScreenCaptureKit. Its sound may still
                // reach the physical mic acoustically; that must never trigger an answer.
                await start([.me, .them], name: "own output")
                try await play("fr", ownProcess: true); await pause(4)
                observe("own output", speakers: [.me], expectedWords: ["binaire"], expectAuto: false)
                save("own output: no system-channel speech or topic", !listening.transcript.lines.contains { $0.speaker == .them } && listening.topics.isEmpty)
                await stop("own output")

                await start([.me, .them], name: "interrupted speech")
                let player = try AVAudioPlayer(contentsOf: fixtures.appendingPathComponent("en.wav"))
                _ = player.play(); await pause(0.8)
                await stop("interrupted speech")
                player.stop()

                await start([.me, .them], name: "capture error")
                listening.interruptRecetteSystemCapture()
                for _ in 0..<100 {
                    if case .failed = listening.state { break }
                    await pause(0.1)
                }
                if case let .failed(message) = listening.state {
                    save("injected capture delegate error: surfaced and stopped", message.contains("Interruption contrôlée"))
                } else { save("injected capture delegate error: surfaced and stopped", false) }
                await start([.me, .them], name: "restart after injected error")
                await stop("restart after injected error")
                }
            } catch {
                save("hardware execution error: \(error.localizedDescription)", false)
                await listening.stop()
            }
            await verifyBrain(folder: folder, save: save)
            save("hardware recipe completed", true)
            defaults.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
        return true
    }

    /// Aggregate accuracy against public synthetic text; never persists actual recognized words.
    private static func wordErrorRate(expected: String, actual: String) -> Double {
        func words(_ text: String) -> [String] {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let reference = words(expected), hypothesis = words(actual)
        var previous = Array(0...hypothesis.count)
        for (i, word) in reference.enumerated() {
            var current = [i + 1]
            for (j, other) in hypothesis.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (word == other ? 0 : 1)))
            }
            previous = current
        }
        return Double(previous.last ?? reference.count) / Double(max(1, reference.count))
    }

    private static func sourceFiles(_ root: URL) -> [URL] {
        FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey])?.allObjects.compactMap { $0 as? URL } ?? []
    }

    private static func verifyBrain(folder: URL, save: (String, Bool) -> Void) async {
        do {
            let root = VaultPolicy.defaultRoot
            let index = try BaseIndex(url: BaseController.store.appendingPathComponent("index.sqlite"))
            let embedder: TextEmbedder = await ContextualEmbedder.prepare() ?? NoEmbedder()
            let indexer = BaseIndexer(index: index, embedder: embedder, store: BaseController.store)
            let report = try await indexer.run(BaseSource(root: root))
            save("Brain: actual vault indexed without read errors", report.problems.isEmpty)
            let items = try index.items().map(\.item)
            let base = PersonalBase(search: BaseSearch(index: index, embedder: embedder), index: index, root: root)
            await base.warmUp()
            save("Brain: index outside vault, matching root", !index.url.path.hasPrefix(root.path + "/") && index.meta("sourceRoot") == root.resolvingSymlinksInPath().path)
            save("Brain: indexed items satisfy sensitive exclusions", !items.isEmpty && items.allSatisfy { VaultPolicy.allows(path: $0.source) && !VaultPolicy.containsSecrets($0.text) })
            var sensitiveFiles = 0
            var sensitiveAbsent = true
            let sources = Set(items.map(\.source))
            do {
                for file in sourceFiles(root) {
                    let key = String(file.path.dropFirst(root.path.count + 1))
                    if !VaultPolicy.allows(path: key) {
                        sensitiveFiles += 1
                        sensitiveAbsent = sensitiveAbsent && !sources.contains(key)
                    } else if file.pathExtension.lowercased() == "md",
                              (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                              file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
                              let text = try? String(contentsOf: file, encoding: .utf8), VaultPolicy.containsSecrets(text) {
                        sensitiveFiles += 1
                        sensitiveAbsent = sensitiveAbsent && !sources.contains(key)
                    }
                }
            }
            save("Brain: actual sensitive files absent from indexed content", sensitiveFiles > 0 && sensitiveAbsent)
            var used = Set<String>()
            // Select existing CV/project notes locally; names and contents never enter the report.
            let candidates = items.filter { $0.kind == .cv || $0.kind == .project || $0.source.localizedCaseInsensitiveContains("cv") || $0.source.localizedCaseInsensitiveContains("projet") }
            var results: [[String: Any]] = []
            for item in candidates where used.count < 3 {
                guard used.insert(item.source).inserted else { continue }
                let query = item.kind == .cv ? "Résume mon CV et mon parcours professionnel" : "Que sais-tu de mon projet \(item.title) ?"
                let snippets = await base.snippets(for: query)
                let relevant = snippets.contains { $0.source.contains("(\(item.source))") }
                let bounded = snippets.count <= 5 && snippets.allSatisfy { $0.text.count <= 401 }
                let sourced = snippets.allSatisfy { snippet in items.contains { snippet.source == "\($0.label) (\($0.source))" } }
                results.append(["queryCategory": item.kind.rawValue, "snippetCount": snippets.count, "expectedSourceFound": relevant, "bounded": bounded, "allSourcesInIndex": sourced])
                save("Brain: representative retrieval \(used.count) relevant, bounded and sourced", relevant && bounded && sourced)
            }
            save("Brain: three distinct real source retrievals tested", used.count == 3)
            let disabled = await base.snippets(for: "Décris mon parcours professionnel", router: PersonalRouter(mode: .off))
            save("Brain: disabled mode yields no excerpts", disabled.isEmpty)
            let data = try JSONSerialization.data(withJSONObject: ["queries": results, "privateTextSaved": false, "providerCalls": 0, "itemCount": items.count, "sensitivePathsOrFilesExcluded": sensitiveFiles], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: folder.appendingPathComponent("brain-retrieval.json"), options: .atomic)
        } catch { save("Brain verification failed", false) }
    }
}

private actor HardwareProvider: LLMProvider {
    nonisolated let kind = ProviderKind.codex
    nonisolated let label = "Réponse locale de validation matérielle"
    nonisolated var topicSegmenter: any TopicSegmenter { HardwareSegmenter() }
    nonisolated let topicSegmenterName = "local controlled"
    func warmUp() async {}
    func streamAnswer(to conversation: Conversation, onText: @escaping @Sendable (String) async -> Void) async throws -> CompletedMessage {
        try await Task.sleep(for: .milliseconds(100))
        let text = "Réponse locale contrôlée à la question captée."
        await onText(text)
        return CompletedMessage(content: [["type": "text", "text": .string(text)]], stopReason: "end_turn")
    }
    func complete(system: String, prompt: String, images: [CapturedImage], schema: JSONValue?) async throws -> String { "{}" }
}
private struct HardwareSegmenter: TopicSegmenter {
    func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision { .new(title: turn.text) }
}
private final class HardwareMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var frameCounts: [Speaker: Int] = [:]
    private var peaks: [Speaker: Float] = [:]
    var count: Int { lock.withLock { frameCounts.values.reduce(0, +) } }
    func frames(_ speaker: Speaker) -> Int { lock.withLock { frameCounts[speaker, default: 0] } }
    func reset() { lock.withLock { frameCounts = [:]; peaks = [:] } }
    func append(_ buffer: AVAudioPCMBuffer, speaker: Speaker) {
        var peak: Float = 0
        if let data = buffer.floatChannelData { for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[0][i])) } }
        lock.withLock { frameCounts[speaker, default: 0] += Int(buffer.frameLength); peaks[speaker] = max(peaks[speaker, default: 0], peak) }
    }
    func snapshot() -> [[String: Any]] {
        lock.withLock { [Speaker.me, .them].map { ["speaker": $0.rawValue, "frames": frameCounts[$0, default: 0], "peak": peaks[$0, default: 0]] } }
    }
}
