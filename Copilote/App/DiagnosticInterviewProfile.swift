import AppKit
import CopiloteKit

@MainActor
enum DiagnosticInterviewProfile {
    static func run(folder: URL, settings: SettingsStore, session: SessionController, overlay: OverlayController, providers: ProviderController, fake: RecetteProvider, record: (String, Bool) -> Void) async {
        func pause() async { try? await Task.sleep(for: .milliseconds(250)) }
        func text(_ c: Conversation?) -> String { c?.messages.flatMap { $0["content"]?.arrayValue ?? [] }.compactMap { $0["text"]?.stringValue }.joined(separator: "\n") ?? "" }
        let suite = "org.example.copilote.recette.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secret = "ARCHIVED_EMPLOYER_MARKER"
        defaults.set(true, forKey: "infosysInterviewActive")
        defaults.set(secret, forKey: "infosysInterviewContext")
        let migrated = SettingsStore(defaults: defaults, loadCredentials: false)
        record("old active switch migrates to the generic scope", migrated.technicalInterviewActive && migrated.interviewScope == "technical-interview")
        migrated.technicalInterviewActive = false
        let reopened = SettingsStore(defaults: defaults, loadCredentials: false)
        record("new inactive preference wins over the old active switch", !reopened.technicalInterviewActive && reopened.interviewScope == "normal")
        record("archived source survives migration untouched", defaults.string(forKey: "infosysInterviewContext") == secret)
        defaults.removeObject(forKey: "technicalInterviewActive")
        defaults.set(false, forKey: "infosysInterviewActive")
        record("old inactive switch migrates to Normal", !SettingsStore(defaults: defaults, loadCredentials: false).technicalInterviewActive)
        defaults.removeObject(forKey: "technicalInterviewActive")
        defaults.removeObject(forKey: "infosysInterviewActive")
        record("fresh profile defaults to Normal", !SettingsStore(defaults: defaults, loadCredentials: false).technicalInterviewActive)

        let topic = Topic(id: "profile-fixture", title: "Describe your project", excerpt: [], createdAt: Date(), updatedAt: Date())
        let question = AssistQuestion(action: .answer, mode: .meeting, question: topic.title, heard: [], context: AssistContext(), typed: true, format: AnswerFormat(kind: .personal))
        let notes = session.stickyNotes.notes
        settings.defaults.set(secret, forKey: "infosysInterviewContext")
        settings.answerLanguage = AnswerPreferences.Language.french.rawValue
        settings.technicalInterviewActive = false
        await fake.replyNext("NORMAL_DRAFT_MARKER")
        session.assist(question, label: "Normal fixture", topic: topic)
        await pause()
        let firstNormal = text(await fake.conversations.last)
        record("normal prompt uses saved language and omits archived employer", settings.answerPreferences.language == .french && !firstNormal.contains(secret) && firstNormal.contains("Mode: Meeting"))

        settings.technicalInterviewActive = true
        record("technical interview forces English without overwriting normal language", settings.answerPreferences.language == .english && settings.answerLanguage == AnswerPreferences.Language.french.rawValue)
        record("technical scope cannot reuse normal cached answer", !session.hasCachedRequest(for: topic))
        await fake.replyNext("PROFILE_DRAFT_MARKER")
        session.assist(question, label: "Technical interview fixture", topic: topic)
        await pause()
        let conversation = await fake.conversations.last
        let active = text(conversation)
        let wire = conversation.map { CodexPrompt.turnInput(for: $0).compactMap { $0["text"]?.stringValue }.joined(separator: "\n") } ?? ""
        record("both provider payloads contain the English evidence and missing-source instructions", !active.isEmpty && wire == active && active.contains("Mode: Technical") && active.contains("Answer in English") && active.contains("cite each supporting source") && active.contains("missing, insufficient or conflict"))
        record("technical prompt excludes archived employer name and source marker", !active.localizedCaseInsensitiveContains("Infosys") && !active.contains(secret) && active.contains("source excerpts needed") && !active.contains("Use only personal facts explicitly stated by Me"))
        record("technical scope does not inherit normal assistant drafts", !active.contains("NORMAL_DRAFT_MARKER"))

        let snippet = BaseSnippet(source: "Fixture CV (CV.md)", text: "CV_FIXTURE: built the fictitious Atlas scheduling tool.")
        session.assist(question, label: "Technical source fixture", topic: nil, plan: {
            AnswerPlan(format: AnswerFormat(kind: .personal), extracts: [snippet])
        })
        await pause()
        let sourced = text(await fake.conversations.last)
        record("retrieved evidence reaches provider with source attribution", sourced.contains("[1] Fixture CV (CV.md)") && sourced.contains("CV_FIXTURE") && !sourced.contains(secret))

        settings.technicalInterviewActive = false
        record("normal restores the saved language", settings.answerPreferences.language == .french)
        record("normal scope restores its independent cached subject", session.showCachedAnswer(for: topic) && session.lastFinished?.text == "NORMAL_DRAFT_MARKER")
        session.assist(question, label: "Normal again", topic: nil)
        await pause()
        let normal = text(await fake.conversations.last)
        record("deactivation removes technical instructions and scoped history", !normal.contains("cite each supporting source") && !normal.contains("PROFILE_DRAFT_MARKER") && !normal.contains(secret))
        record("deactivation preserves manual notes", session.stickyNotes.notes == notes)
        let payload: [String: Any] = ["notes": (1...4).map { ["stableKey": "fixture-\($0)", "title": "Title \($0)", "text": "Exact fixture text \($0)"] }]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let sticky = session.stickyNotes
        sticky.importPreparedNotes(data); sticky.importPreparedNotes(data)
        let imported = sticky.notes.filter { $0.profileID == "excel-interview" }
        record("four private pinned notes imported without duplicates", imported.count == 4 && imported.allSatisfy { $0.isPinned && !$0.includeInAI })
        record("Excel notes hidden in Normal", imported.allSatisfy { !sticky.applies($0) })
        settings.technicalInterviewActive = true
        record("Technical interview keeps archived notes excluded", imported.allSatisfy { !sticky.applies($0) } && sticky.includedContext.isEmpty)
        sticky.toggleArchive()
        record("archive can be consulted independently of the interview profile", imported.allSatisfy { sticky.applies($0) })
        for note in imported { sticky.setIncluded(true, for: note.id) }
        record("archived notes remain excluded even after attempted AI opt-in", sticky.includedContext.isEmpty && sticky.notes.filter { $0.profileID == "excel-interview" }.allSatisfy { !$0.includeInAI })
        sticky.toggleArchive()
        settings.technicalInterviewActive = false
        let restored = StickyNotesController(settings: settings)
        record("four exact notes persist after normal return", restored.notes.filter { $0.profileID == "excel-interview" } == imported && restored.includedContext.isEmpty)
        settings.defaults.set("LEGACY_EXCEL_SOURCE", forKey: "excelInterviewContext")
        settings.defaults.set(true, forKey: "excelInterviewActive")
        let restoredSettings = SettingsStore(defaults: settings.defaults, loadCredentials: false)
        record("archived preferences remain intact and inactive in prompts", restoredSettings.defaults.string(forKey: "excelInterviewContext") == "LEGACY_EXCEL_SOURCE" && restoredSettings.defaults.bool(forKey: "excelInterviewActive") && !restoredSettings.effectiveInstructions.contains("LEGACY_EXCEL_SOURCE"))
        record("headless profile recipe opens no windows", NSApp.windows.allSatisfy { !$0.isVisible })
        var submittedPrompts: [[String: Any]] = []
        settings.technicalInterviewActive = true
        for hasEvidence in [true, false] {
            session.clear()
            do {
                let root = folder.appendingPathComponent(hasEvidence ? "documented/Brain" : "undocumented/Brain")
                let projects = root.appendingPathComponent("projet")
                try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
                let overview = "# Atlas\n## Engineering\n" + String(repeating: "The scheduler handles queued entries. ", count: 25)
                let projectStory = " An outage interrupted a scheduled import. I added a retry budget to restore it."
                let cvStory = " I diagnosed a queue incident and recovered the pending entries."
                try (overview + (hasEvidence ? projectStory : "")).write(to: projects.appendingPathComponent("Atlas.md"), atomically: true, encoding: .utf8)
                try ("# CV\n## Experience\nInternship in software development." + (hasEvidence ? cvStory : "")).write(to: root.appendingPathComponent("CV.md"), atomically: true, encoding: .utf8)
                let note = root.appendingPathComponent("Interview notes.md")
                let episode = "A release failed during my shift. I traced the missing dependency and rebuilt the package. As a result the deployment resumed."
                let mention = "The challenge was keeping work centralized."
                let draft = "Hypothetical example: if deployment failed, I would rebuild the package."
                try (hasEvidence ? episode : draft).write(to: note, atomically: true, encoding: .utf8)
                for index in 0..<25 {
                    try mention.write(to: projects.appendingPathComponent("Planning-\(index).md"), atomically: true, encoding: .utf8)
                }
                let unconfirmed = "**A challenge — à confirmer**\n> A transfer failed. I corrected the address. The transfer resumed."
                try unconfirmed.write(to: root.appendingPathComponent("Entretien.md"), atomically: true, encoding: .utf8)
                let store = root.deletingLastPathComponent().appendingPathComponent("cache")
                let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
                _ = try await BaseIndexer(index: index, embedder: NoEmbedder(), store: store).run(BaseSource(root: root))
                let personal = PersonalBase(search: BaseSearch(index: index, embedder: NoEmbedder()), index: index, root: root)
                let base = BaseController(settings: settings, providers: providers, personal: personal)
                let assist = AssistController(settings: settings, session: session, base: base, overlay: overlay)
                let asked = "Tell me about a time you faced a challenge."
                let count = await fake.conversations.count
                assist.askText = asked
                assist.submitAsk()
                for _ in 0..<400 {
                    if await fake.conversations.count > count && !session.isAnswering { break }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                let sent = await fake.conversations.last
                let wire = sent.map { CodexPrompt.turnInput(for: $0).compactMap { $0["text"]?.stringValue }.joined(separator: "\n") } ?? ""
                submittedPrompts.append(["question": asked, "availableStory": hasEvidence, "excerpts": assist.context.includedExtracts.count, "codexInputText": wire])
                let oneRequest = await fake.conversations.count == count + 1
                record("Ask submits the exact behavioral question once with technical mode selected (evidence: \(hasEvidence))",
                       oneRequest && wire.contains(asked) && wire.contains("choose one documented episode") && wire.contains("Mode: Technical") && sent?.preferences.language == .english && !wire.contains(secret))
                if hasEvidence {
                    record("Ask selects a single documented incident, action and outcome ahead of vague project mentions",
                           assist.context.includedExtracts.count == 1 && wire.contains("Interview notes.md") && wire.contains("rebuilt the package") && wire.contains("deployment resumed") && !wire.contains(mention) && !wire.contains("corrected the address"))
                    let paraphrase = "How did you overcome a setback during a project?"
                    session.clear()
                    let previousCount = await fake.conversations.count
                    assist.askText = paraphrase
                    assist.submitAsk()
                    for _ in 0..<400 {
                        if await fake.conversations.count > previousCount && !session.isAnswering { break }
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                    let follow = (await fake.conversations.last).map { CodexPrompt.turnInput(for: $0).compactMap { $0["text"]?.stringValue }.joined(separator: "\n") } ?? ""
                    submittedPrompts.append(["question": paraphrase, "availableStory": true, "excerpts": assist.context.includedExtracts.count, "codexInputText": follow])
                    record("a differently phrased behavioral Ask retrieves the documented event without the word challenge",
                           follow.contains(paraphrase) && follow.contains("rebuilt the package") && !assist.context.includedExtracts.isEmpty)
                } else {
                    record("Ask identifies missing evidence despite an available unrelated CV and project",
                           assist.context.includedExtracts.isEmpty && wire.contains("source excerpts needed") && !wire.contains("Internship in software development.") && !wire.contains("The scheduler handles queued entries.") && !wire.contains("corrected the address"))
                }
            } catch {
                record("behavioral Ask fixture completes (evidence: \(hasEvidence))", false)
            }
        }
        try? JSONSerialization.data(withJSONObject: submittedPrompts, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("synthetic-ask-inputs.json"))
        settings.technicalInterviewActive = false
        session.clear()
    }
}
