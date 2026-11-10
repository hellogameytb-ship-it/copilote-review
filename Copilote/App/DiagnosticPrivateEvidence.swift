import AppKit
import CopiloteKit

/// Invoked only by the explicit headless evidence recipe. The live run records checks only.
@MainActor
enum DiagnosticPrivateEvidence {
    static func run(folder: URL, live: Bool, settings: SettingsStore, session: SessionController,
                    overlay: OverlayController, providers: ProviderController, listening: ListeningController,
                    fake: RecetteProvider, record: (String, Bool) -> Void) async {
        guard DiagnosticAnchorFixture.isRequested else { return }
        let database = live ? InterviewEvidenceStore.defaultDatabase : folder.appendingPathComponent("evidence.sqlite")
        settings.baseFolder = live
            ? (UserDefaults.standard.string(forKey: "baseFolder") ?? VaultPolicy.defaultRoot.path)
            : folder.appendingPathComponent("Brain").path
        settings.baseMode = live ? (UserDefaults.standard.string(forKey: "baseMode") ?? "show") : "show"
        settings.answerInstructions = ""
        settings.technicalInterviewActive = true
        let base = BaseController(settings: settings, providers: providers, evidenceDatabase: database)
        let assist = AssistController(settings: settings, session: session, base: base, overlay: overlay)
        assist.observe(listening)
        let question = "Tell me about a time you faced a challenge."
        func wait(after count: Int) async -> String {
            for _ in 0..<(live ? 600 : 300) {
                if await fake.conversations.count > count && !session.isAnswering { break }
                try? await Task.sleep(for: .milliseconds(live ? 200 : 10))
            }
            guard await fake.conversations.count == count + 1, let last = await fake.conversations.last else { return "" }
            return CodexPrompt.turnInput(for: last).compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
        }
        func ask(_ q: String) async -> String {
            let n = await fake.conversations.count
            assist.askText = q
            assist.submitAsk()
            return await wait(after: n)
        }
        if live {
            let approved = InterviewEvidenceStore(database: database, root: base.root).snippets(for: question)
            guard settings.baseMode != "off", approved.count == 1, approved[0].source.hasPrefix("Recruiter CV"),
                  let executable = CodexAvailability.locate(), CodexAvailability.isReady(executable: executable) else {
                record("live CV request has an available verified source and configured Codex", false)
                return
            }
            guard UserDefaults.standard.string(forKey: "provider") != "anthropic" else {
                record("configured provider is Codex for this live check", false)
                return
            }
            let server = CodexAppServer(executable: executable, workingDirectory: folder.appendingPathComponent("empty-work"),
                                        privateDirectory: folder.appendingPathComponent("private-process"),
                                        loadUserConfig: { try CodexAvailability.userConfig() })
            defer { server.terminateNow() }
            let model = UserDefaults.standard.string(forKey: "codexModel") ?? CodexProvider.defaultModel
            let fast = UserDefaults.standard.object(forKey: "codexFast") as? Bool ?? CodexLaunch.prefersFastTier(userConfig: try? CodexAvailability.userConfig())
            await fake.use(CodexProvider(server: server, answerModel: model, topicModel: CodexProvider.defaultModel, serviceTier: fast ? "priority" : nil))
            let wire = await ask(question)
            let answer = session.lastFinished?.text ?? ""
            record("live manual Ask submitted one bounded verified recruiter-CV entry", assist.context.includedExtracts == approved && wire.contains(approved[0].text))
            record("live answer completed with source citation", !answer.isEmpty && answer.contains("[1]"))
            let evidence = (approved[0].source + " " + approved[0].text).lowercased()
            let spoken = answer.lowercased()
            let substantive = Set(BaseText.tokens(of: evidence).filter { $0.count >= 5 })
            let overlap = substantive.intersection(BaseText.tokens(of: spoken))
            record("live answer uses substantive terms from its verified source", overlap.count >= 3)
            func numbers(_ text: String) -> Set<String> {
                let clean = text.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
                let regex = try! NSRegularExpression(pattern: #"\b\d+(?:[.,]\d+)?\b"#)
                return Set(regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).compactMap {
                    Range($0.range, in: clean).map { String(clean[$0]).replacingOccurrences(of: ",", with: ".") }
                })
            }
            record("numerical statements in the live answer are present in the source", numbers(spoken).isSubset(of: numbers(evidence)))
            record("live answer preserves simulation or cross-validation when reported",
                   (!evidence.contains("simulation") || spoken.contains("simulat")) &&
                   (!evidence.contains("fold cv") || spoken.contains("cross-validation") || spoken.contains("cross validation") || spoken.contains("fold")))
            record("live answer preserves team attribution when source specifies a team",
                   !evidence.contains("team") || spoken.contains("team") || spoken.contains("we ") || spoken.contains("our "))
            record("live run has no visible app windows or ongoing listening", !listening.isListening && NSApp.windows.allSatisfy { !$0.isVisible })
            session.clear()
            return
        }

        await fake.replyNext("PRIVATE_PREVIOUS_ANSWER_MARKER")
        let initial = await ask(question)
        record("Ask cites recruiter CV with grouped team and simulation evidence", initial.contains("Recruiter CV") && initial.contains("simulated delay") && initial.contains("team tested") && !initial.contains("UNRELATED_DIPLOMA"))
        if let first = assist.context.items.first(where: { $0.kind == .extract }) { assist.toggle(first.id) }
        let excluded = await ask(question)
        record("excluded CV stays out of Ask and previous answer continuity", !excluded.isEmpty && !excluded.contains("team tested") && !excluded.contains("PRIVATE_PREVIOUS_ANSWER_MARKER"))
        let general = await ask("Explain how a binary heap works.")
        record("general question goes through without a CV passage", general.contains("binary heap") && !general.contains("simulated delay"))
        _ = await ask(question)
        record("CV exclusion survives an intervening general question", assist.context.includedExtracts.isEmpty)
        assist.includeAll()
        session.clear()
        listening.beginRecetteConversation()
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker: .them, text: question, start: 1, end: 2), language: "fixture", latency: 0))
        let count = await fake.conversations.count
        assist.answerNow()
        let answer = await wait(after: count)
        record("Answer uses fresh frozen conversation and the same verified CV source", answer.contains("AT THE CLICK") && answer.contains("Recruiter CV") && answer.contains("simulated delay"))
        await listening.stop()
        session.clear()
        let note = await ask("What academic setback or failure did you overcome?")
        record("preparation note is labeled separately from recruiter CV", note.contains("Interview preparation note") && note.contains("retook") && !note.contains("simulated delay"))
        settings.technicalInterviewActive = false
        session.clear()
        let normal = await ask(question)
        record("Normal mode does not read interview evidence into Ask", !normal.isEmpty && !normal.contains("simulated delay") && !normal.contains("retook"))
        settings.technicalInterviewActive = true
        settings.baseMode = "off"
        let off = await ask(question)
        record("base off does not attach private interview evidence", !off.isEmpty && assist.context.includedExtracts.isEmpty)
        session.clear()
    }
}
