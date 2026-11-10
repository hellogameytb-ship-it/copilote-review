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
        let question = live ? "Tell me about your machine learning project dealing with class imbalance." : "Tell me about a time you faced a challenge."
        let role = "What did you personally do?"
        let label = "Possible answer — use only if accurate"
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
            func hasConcreteProposal(_ reply: String) -> Bool {
                guard let range = reply.range(of: "only if accurate") else { return false }
                let proposal = String(reply[range.upperBound...])
                let actions = ["compar", "check", "inspect", "measur", "verif", "evaluat", "trac", "analy", "test", "isolat", "review", "adjust", "train", "split", "apply", "select", "validat", "diagnos", "monitor", "examin", "log", "debug", "investigat", "reproduc", "retry", "identif", "restart", "weight"]
                return BaseText.tokens(of: proposal).count >= 8 && actions.contains(where: proposal.contains) && !proposal.contains("[insert") && !proposal.contains("[your")
            }
            // This live fixture documents team ownership only. Check the proposal itself:
            // an advisory heading or an unrelated “I would” later cannot qualify a past claim.
            func claimsIndividualWork(_ reply: String) -> Bool {
                let patterns = [
                    #"\b(?:i|you) (?:personally |specifically )?(?:implemented|built|designed|trained|tested|evaluated|optimized|changed|configured|reduced|increased|resolved|fixed|rerouted|diagnosed|wrote|owned|led|handled|was responsible|were responsible)\b"#,
                    #"\b(?:my|your) (?:specific |individual |personal )?(?:contribution|role|responsibility|part) (?:was|included|involved|consisted)\b"#,
                    #"\bi worked[^.!?\n]{0,220}, (?:implementing|building|designing|training|testing|evaluating)\b"#
                ]
                return patterns.contains { reply.range(of: $0, options: .regularExpression) != nil }
            }
            func startsWithConditional(_ reply: String) -> Bool {
                guard let end = reply.range(of: "only if accurate")?.upperBound else { return false }
                let spoken = reply[end...].drop(while: { !$0.isLetter })
                return spoken.hasPrefix("i would ") || spoken.hasPrefix("i could ") || spoken.hasPrefix("i’d ") || spoken.hasPrefix("i'd ")
            }
            record("live initial description keeps implementation attributed to the team", !claimsIndividualWork(spoken))
            guard !answer.isEmpty else { return }
            let linked = await ask(role)
            let roleAnswer = session.lastFinished?.text.lowercased() ?? ""
            record("live personal-role follow-up carries the exact revalidated ML episode and the preceding answer",
                   assist.context.includedExtracts == approved && linked.contains(approved[0].text) && linked.contains(String(answer.prefix(80))))
            let lines = roleAnswer.split(whereSeparator: \.isNewline).map(String.init)
            let options = lines.filter { $0.contains("if you ") }
            let optionPattern = #"^[\s>*•–-]*if you [^:\n]+:\s*[*_]*\s*["“]i (?:[a-z]+ed|built|wrote|ran|led|chose|set|put|did|made|took)\b"#
            let everyQuoteIsConditional = options.allSatisfy { $0.range(of: optionPattern, options: .regularExpression) != nil }
            let outsideOptions = lines.filter { !$0.contains("if you ") }.joined(separator: " ")
            record("one or two short past-tense role options with a condition before each quote",
                   (1...2).contains(options.count) && everyQuoteIsConditional && !roleAnswer.contains("i would") && !roleAnswer.contains("i could"))
            record("role reply cites team evidence without assigning an individual action outside a condition",
                   roleAnswer.contains("[1]") && !claimsIndividualWork(outsideOptions) && !outsideOptions.contains("“i "))
            record("role options stay concise and use episode vocabulary",
                   outsideOptions.split(whereSeparator: \.isWhitespace).count <= 16 && options.allSatisfy {
                       $0.split(whereSeparator: \.isWhitespace).count <= 25 && !$0.contains("[1]") &&
                       ["imbalanc", "weight", "minority", "rarest", "recall", "macro", "loss", "cross-validation"].contains(where: $0.contains) &&
                       !substantive.intersection(BaseText.tokens(of: $0)).isEmpty
                   } && (!roleAnswer.contains("stratified") || evidence.contains("stratified")))
            record("live follow-up does not introduce an unsupported numerical result", numbers(roleAnswer).isSubset(of: numbers(evidence)))
            settings.technicalInterviewActive = false
            session.clear()
            let noSource = await ask("Tell me about a time you resolved a stalled import.")
            let proposal = session.lastFinished?.text.lowercased() ?? ""
            record("live Normal without evidence provides a concrete conditional option",
                   assist.context.includedExtracts.isEmpty && !noSource.contains(approved[0].text) &&
                   proposal.contains("possible answer") && proposal.contains("only if accurate") &&
                   (proposal.contains("would") || proposal.contains("could") || proposal.contains("if ")))
            record("live no-source suggestion gives a specific actionable step", hasConcreteProposal(proposal) && !claimsIndividualWork(proposal) && startsWithConditional(proposal))
            session.clear()
            listening.beginRecetteConversation()
            let documented = "For the Cedar import project, I wrote the duplicate-record check."
            listening.receiveRecetteEvent(.line(TranscriptLine(speaker: .me, text: documented, start: 1, end: 2), language: "fixture", latency: 0))
            let knownWire = await ask(role)
            let direct = session.lastFinished?.text.lowercased() ?? ""
            record("an explicitly stated role yields one short direct spoken answer",
                   knownWire.contains(documented) && direct.contains("i wrote") && direct.contains("duplicate") &&
                   !direct.contains("if you") && !direct.contains("i would") && direct.split(whereSeparator: \.isWhitespace).count <= 24)
            await listening.stop()
            record("live run has no visible app windows or ongoing listening", !listening.isListening && NSApp.windows.allSatisfy { !$0.isVisible })
            session.clear()
            return
        }

        await fake.replyNext("PRIVATE_PREVIOUS_ANSWER_MARKER")
        let initial = await ask(question)
        record("Ask cites recruiter CV with grouped team and simulation evidence", initial.contains("Recruiter CV") && initial.contains("simulated delay") && initial.contains("team tested") && !initial.contains("UNRELATED_DIPLOMA"))
        let linked = await ask(role)
        record("Ask follows the prior team episode and supplies conditional guidance",
               linked.contains("simulated delay") && linked.contains("PRIVATE_PREVIOUS_ANSWER_MARKER") && linked.contains("condition BEFORE the spoken quote"))
        let again = await ask("And what was the outcome?")
        record("chained follow-up stays on the original episode", again.contains("simulated delay") && assist.context.includedExtracts.count == 1)
        if let first = assist.context.items.first(where: { $0.kind == .extract }) { assist.toggle(first.id) }
        let excluded = await ask(role)
        record("excluded CV stays out of Ask and previous answer continuity", !excluded.isEmpty && !excluded.contains("team tested") && !excluded.contains("PRIVATE_PREVIOUS_ANSWER_MARKER"))
        let general = await ask("Explain how a binary heap works.")
        record("general question goes through without a CV passage", general.contains("binary heap") && !general.contains("simulated delay"))
        let afterChange = await ask(role)
        record("a subject change does not revive the old episode", !afterChange.contains("team tested") && assist.context.includedExtracts.isEmpty)
        _ = await ask(question)
        record("CV exclusion survives an intervening general question", assist.context.includedExtracts.isEmpty)
        assist.includeAll()
        session.clearChat()
        listening.beginRecetteConversation()
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker: .them, text: question, start: 1, end: 2), language: "fixture", latency: 0))
        let count = await fake.conversations.count
        assist.answerNow()
        let answer = await wait(after: count)
        record("Answer uses fresh frozen conversation and the same verified CV source", answer.contains("AT THE CLICK") && answer.contains("Recruiter CV") && answer.contains("simulated delay") && assist.context.includedExtracts.count == 1)
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker: .them, text: role, start: 3, end: 4), language: "fixture", latency: 0))
        let nextCount = await fake.conversations.count
        assist.answerNow()
        let spoken = await wait(after: nextCount)
        record("Answer revalidates the prior episode for a spoken personal-role follow-up", spoken.contains("simulated delay") && spoken.contains("condition BEFORE the spoken quote"))
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker: .them, text: "New topic: explain database isolation.", start: 5, end: 6), language: "fixture", latency: 0))
        let moved = await ask(role)
        record("a new spoken subject prevents a typed follow-up from reusing the older project",
               !moved.contains("team tested") && assist.context.includedExtracts.isEmpty)
        session.clearChat()
        let cleared = await ask(role)
        record("Clear removes the episode but retains conditional response guidance", !cleared.contains("team tested") && cleared.contains(label))
        await listening.stop()
        session.clear()
        let note = await ask("What academic setback or failure did you overcome?")
        record("preparation note is labeled separately from recruiter CV", note.contains("Interview preparation note") && note.contains("retook") && !note.contains("simulated delay"))
        settings.technicalInterviewActive = false
        session.clear()
        let normal = await ask(question)
        record("Normal mode does not read interview evidence into Ask", !normal.isEmpty && !normal.contains("simulated delay") && !normal.contains("retook"))
        settings.technicalInterviewActive = true
        let returned = await ask(role)
        record("returning to Technical interview cannot revive an earlier profile episode", !returned.contains("retook") && !returned.contains("team tested"))
        settings.baseMode = "off"
        let off = await ask(question)
        record("base off does not attach private interview evidence", !off.isEmpty && assist.context.includedExtracts.isEmpty)
        session.clear()
    }
}
