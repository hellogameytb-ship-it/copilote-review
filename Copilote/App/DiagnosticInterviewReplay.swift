import AppKit
import CopiloteKit

/// Opt-in local diagnostic. The caller supplies bounded speech fragments and an isolated index.
@MainActor
enum DiagnosticInterviewReplay {
    struct Scenario: Decodable {
        struct Line: Decodable { let me: Bool; let text: String }
        let id: Int
        let lines: [Line]
        let generate: Bool
    }

    static func run(folder: URL, settings: SettingsStore, session: SessionController, overlay: OverlayController,
                    providers: ProviderController, listening: ListeningController, fake: RecetteProvider,
                    live: Bool, record: (String, Bool) -> Void) async {
        do {
            let scenarios = try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: folder.appendingPathComponent("cases.json")))
            guard scenarios.count <= 24, scenarios.allSatisfy({ $0.lines.count <= 20 && $0.lines.allSatisfy { $0.text.count <= 400 } }) else { return }
            settings.baseFolder = UserDefaults.standard.string(forKey: "baseFolder") ?? VaultPolicy.defaultRoot.path
            settings.baseMode = UserDefaults.standard.string(forKey: "baseMode") ?? "show"
            settings.technicalInterviewActive = true
            settings.autoAnswer = false
            settings.answerInstructions = ""
            let root = URL(fileURLWithPath: settings.baseFolder)
            let index = try BaseIndex(url: folder.appendingPathComponent("index.sqlite"))
            guard index.meta("sourceRoot") == root.resolvingSymlinksInPath().path else { return }
            let personal = PersonalBase(search: BaseSearch(index: index, embedder: NoEmbedder()), index: index, root: root)
            let base = BaseController(settings: settings, providers: providers, personal: personal, evidenceDatabase: InterviewEvidenceStore.defaultDatabase)
            let assist = AssistController(settings: settings, session: session, base: base, overlay: overlay)
            assist.observe(listening)
            var server: CodexAppServer?
            defer { server?.terminateNow() }
            if live {
                guard UserDefaults.standard.string(forKey: "provider") != "anthropic", let exe = CodexAvailability.locate(), CodexAvailability.isReady(executable: exe) else { return }
                let transport = CodexAppServer(executable: exe, workingDirectory: folder.appendingPathComponent("empty-work"), privateDirectory: folder.appendingPathComponent("private-process"), loadUserConfig: { try CodexAvailability.userConfig() })
                server = transport
                await fake.use(CodexProvider(server: transport, answerModel: UserDefaults.standard.string(forKey: "codexModel") ?? CodexProvider.defaultModel, topicModel: CodexProvider.defaultModel, serviceTier: nil))
            }
            for scenario in scenarios where !live || scenario.generate {
                session.clearChat()
                listening.beginRecetteConversation()
                for (index, line) in scenario.lines.enumerated() {
                    let start = Double(index)
                    listening.receiveRecetteEvent(.line(TranscriptLine(speaker: line.me ? .me : .them, text: line.text, start: start, end: start + 0.5), language: "fixture", latency: 0))
                }
                let before = await fake.conversations.count
                assist.answerNow()
                for _ in 0..<1200 {
                    if await fake.conversations.count > before && !session.isAnswering { break }
                    try await Task.sleep(for: .milliseconds(live ? 100 : 10))
                }
                guard let result = session.lastFinished, await fake.conversations.count == before + 1,
                      let conversation = await fake.conversations.last else { throw CocoaError(.fileReadUnknown) }
                let wire = CodexPrompt.turnInput(for: conversation).compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
                let refs = assist.context.includedExtracts
                let proof: [String: Any] = ["refs": refs.map { ["source": $0.source, "text": $0.text] }, "answer": result.text,
                                            "allSent": refs.allSatisfy { wire.contains($0.text) }, "wireLength": wire.count]
                try JSONSerialization.data(withJSONObject: proof).write(to: folder.appendingPathComponent("case-\(scenario.id).json"), options: .atomic)
                record("Answer replay \(scenario.id)", !result.text.isEmpty && refs.allSatisfy { wire.contains($0.text) })
            }
            await listening.stop()
            record("injected replay finished offscreen", NSApp.windows.allSatisfy { !$0.isVisible })
        } catch {
            record("replay completed successfully", false)
        }
    }
}
