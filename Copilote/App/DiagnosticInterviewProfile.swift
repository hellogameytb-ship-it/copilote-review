import AppKit
import CopiloteKit

@MainActor
enum DiagnosticInterviewProfile {
    static func run(settings: SettingsStore, session: SessionController, fake: RecetteProvider, record: (String, Bool) -> Void) async {
        func pause() async { try? await Task.sleep(for: .milliseconds(250)) }
        func text(_ c: Conversation?) -> String { c?.messages.flatMap { $0["content"]?.arrayValue ?? [] }.compactMap { $0["text"]?.stringValue }.joined(separator: "\n") ?? "" }
        let topic = Topic(id: "profile-fixture", title: "Describe a linked list", excerpt: [], createdAt: Date(), updatedAt: Date())
        let question = AssistQuestion(action: .answer, mode: .meeting, question: topic.title, heard: [], context: AssistContext(), typed: true)
        settings.infosysInterviewActive = false
        settings.infosysInterviewContext = "SOURCE_FIXTURE: candidate built a fictional Swift application; application acceptance unknown."
        let saved = settings.infosysInterviewContext
        let emptySuite = "org.example.copilote.recette.missing-profile.\(UUID().uuidString)"
        let emptyDefaults = UserDefaults(suiteName: emptySuite)!
        let empty = SettingsStore(defaults: emptyDefaults, loadCredentials: false)
        empty.infosysInterviewActive = true
        record("missing Infosys facts remain explicitly unknown", empty.effectiveInstructions.contains("role, team, stack, application status and interview format are unknown") && empty.effectiveInstructions.contains("do not solve a supervised assessment"))
        emptyDefaults.removePersistentDomain(forName: emptySuite)
        let notes = session.stickyNotes.notes
        await fake.replyNext("NORMAL_DRAFT_MARKER")
        session.assist(question, label: "normal fixture", topic: topic); await pause()
        record("normal request has no saved profile injection", !text(await fake.conversations.last).contains("SOURCE_FIXTURE"))
        settings.answerLanguage = AnswerPreferences.Language.french.rawValue
        settings.infosysInterviewActive = true
        record("Infosys forces English without overwriting the normal language", settings.answerPreferences.language == .english && settings.answerLanguage == AnswerPreferences.Language.french.rawValue)
        record("Infosys scope cannot reuse normal cached answer", !session.hasCachedRequest(for: topic))
        await fake.replyNext("PROFILE_DRAFT_MARKER")
        session.assist(question, label: "Infosys fixture", topic: topic); await pause()
        let active = text(await fake.conversations.last)
        record("Infosys request includes bounded sourced profile and uncertainty rule", active.contains("SOURCE_FIXTURE") && active.contains("Never invent acceptance"))
        record("Infosys scope does not inherit normal assistant drafts", !active.contains("NORMAL_DRAFT_MARKER"))
        settings.infosysInterviewActive = false
        record("Normal restores the saved language", settings.answerPreferences.language == .french)
        record("normal scope restores its independent cached subject", session.showCachedAnswer(for: topic) && session.lastFinished?.text == "NORMAL_DRAFT_MARKER")
        session.assist(question, label: "normal again", topic: nil); await pause()
        let normal = text(await fake.conversations.last)
        record("deactivation removes profile instructions and profile-generated history", !normal.contains("SOURCE_FIXTURE") && !normal.contains("INFOSYS — TECHNICAL INTERVIEW PROFILE") && !normal.contains("PROFILE_DRAFT_MARKER"))
        record("deactivation preserves saved profile and manual notes", settings.infosysInterviewContext == saved && session.stickyNotes.notes == notes)
        record("saved profile survives settings reconstruction while inactive", SettingsStore(defaults: settings.defaults, loadCredentials: false).infosysInterviewContext == saved && !SettingsStore(defaults: settings.defaults, loadCredentials: false).infosysInterviewActive)
        settings.infosysInterviewContext = String(repeating: "x", count: 9000); settings.infosysInterviewActive = true
        record("profile context is bounded to 8000 characters", !settings.effectiveInstructions.contains(String(repeating: "x", count: 8001)))
        settings.infosysInterviewActive = false
        let payload: [String: Any] = ["notes": (1...4).map { ["stableKey": "fixture-\($0)", "title": "Title \($0)", "text": "Exact fixture text \($0)"] }]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let sticky = session.stickyNotes
        sticky.importPreparedNotes(data); sticky.importPreparedNotes(data)
        let imported = sticky.notes.filter { $0.profileID == "excel-interview" }
        record("four private pinned notes imported without duplicates", imported.count == 4 && imported.allSatisfy { $0.isPinned && !$0.includeInAI })
        record("Excel notes hidden in Normal", imported.allSatisfy { !sticky.applies($0) })
        settings.infosysInterviewActive = true
        record("Infosys never activates archived Excel notes", imported.allSatisfy { !sticky.applies($0) } && sticky.includedContext.isEmpty)
        sticky.toggleArchive()
        record("archive can be consulted independently of the interview profile", imported.allSatisfy { sticky.applies($0) })
        for note in imported { sticky.setIncluded(true, for: note.id) }
        record("archived notes remain excluded even after attempted AI opt-in", sticky.includedContext.isEmpty && sticky.notes.filter { $0.profileID == "excel-interview" }.allSatisfy { !$0.includeInAI })
        sticky.toggleArchive()
        settings.infosysInterviewActive = false
        let restored = StickyNotesController(settings: settings)
        record("four exact notes persist after normal return", restored.notes.filter { $0.profileID == "excel-interview" } == imported && restored.includedContext.isEmpty)
        settings.defaults.set("LEGACY_EXCEL_SOURCE", forKey: "excelInterviewContext")
        settings.defaults.set(true, forKey: "excelInterviewActive")
        let migrated = SettingsStore(defaults: settings.defaults, loadCredentials: false)
        record("migration keeps Excel context archived and deactivates its old selector", migrated.defaults.string(forKey: "excelInterviewContext") == "LEGACY_EXCEL_SOURCE" && !migrated.defaults.bool(forKey: "excelInterviewActive") && !migrated.effectiveInstructions.contains("LEGACY_EXCEL_SOURCE"))
        record("headless profile recipe opens no windows", NSApp.windows.allSatisfy { !$0.isVisible })
        session.clear()
    }
}
