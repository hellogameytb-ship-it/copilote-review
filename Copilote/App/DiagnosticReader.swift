import AppKit
import SwiftUI
import CopiloteKit

/// Fictional subjects, own windows and an isolated provider; no live capture.
@MainActor
enum DiagnosticReader {
    static func run(settings: SettingsStore, session: SessionController, listening: ListeningController,
                    assist: AssistController, overlay: OverlayController, mainWindow: MainWindowController,
                    fake: RecetteProvider, notes: NotesController, folder: URL, record: (String, Bool) -> Void) async {
        func pause(_ ms: Int = 250) async { try? await Task.sleep(for: .milliseconds(ms)) }
        notes.loadRecetteReport()
        let retainedNotes = notes.state
        // Reconstruct the old competing vertical constraints using the actual notes view.
        // This is a layout fixture, not a claim of having captured the user's screen.
        let legacy = OverlayPanel(size: NSSize(width: 600, height: 640))
        let legacyReader = NSTextField(labelWithString: "Answer reader constrained by session notes")
        legacy.contentView = FirstMouseHostingView(rootView: VStack(spacing: 0) {
            Text("Previous layout: subjects, context and controls").frame(height: 200)
            NotesArea(notes: notes)
            LegacyReader(view: legacyReader).frame(minHeight: 80)
        })
        legacy.orderFrontRegardless(); await pause(400)
        record("old notes layout competition reproduced with retained report", legacyReader.bounds.height < 180)
        DiagnosticSnapshot.write(to: folder.appendingPathComponent("legacy-notes-fixture"), spaceChanges: 0)
        legacy.orderOut(nil)
        session.clear(); settings.autoAnswer = true
        listening.beginRecetteConversation()
        let pipeline = TopicPipeline(segmenter: nil, segmenterName: "reader fixture") { update in
            DispatchQueue.main.async { listening.receiveRecetteEvent(.topics(update)) }
        }
        let cases = [("Explain India", "India: a fictional prepared answer about geography."),
                     ("Explain Israel", "Israel: a separate fictional prepared answer about geography."),
                     ("Who is your favourite president?", "I do not have the user's preference. Ask him or offer neutral comparison criteria.")]
        for (index, item) in cases.enumerated() {
            await fake.replyNext(item.1)
            if index == 1 { await fake.delayNext() }
            await pipeline.handle(Turn(speaker: .them, text: item.0, start: Double(index * 10), end: Double(index * 10 + 3)))
            await pause(index == 1 ? 100 : 400)
        }
        await pause(1000)
        let topics = listening.topics
        record("reader retains three independent subjects", topics.count == 3 && session.cardAnswers.count == 3)
        guard let india = topics.first(where: { $0.title.contains("India") }),
              let israel = topics.first(where: { $0.title.contains("Israel") }),
              let opinion = topics.first(where: { $0.title.contains("president") }) else { record("reader fixture topics found", false); return }
        record("new automatic subjects do not switch the first reader", session.answeringTopicID == india.id)
        let calls = await fake.conversations.count
        for topic in [israel, opinion, india] { assist.answer(topic); await pause() }
        let text = try? await (overlay.readingArea as? ResponseWebView)?.evaluateJavaScript("document.getElementById('answer').innerText") as? String
        let callsAfter = await fake.conversations.count
        record("return to India restores full central answer without new request", session.answeringTopicID == india.id && text?.contains("India:") == true && callsAfter == calls)
        record("president fixture retains unknown personal preference", session.cardAnswers[opinion.id]?.contains("do not have the user's preference") == true)
        let israelBefore = session.cardAnswers[israel.id]
        var followup = india; followup.version += 1; followup.excerpt.append("What about India's economy?")
        await fake.replyNext("## India follow-up\nA new, independent economy answer.\n\n### Key points\n- Separate historical context from current data.\n- State the period and source before using any statistic.\n- Do not infer the user's personal views.\n\n### Follow-up\nAsk which aspect of the economy the interviewer wants to discuss.")
        await fake.delayNext()
        let plan = AnswerPlan(format: AnswerFormat(kind: .none), extracts: [])
        let question = AssistQuestion.draft(for: followup, plan: plan, lines: listening.transcript.lines, mode: .meeting)
        session.answerAutomatically(question, label: followup.title, topic: followup)
        await pause(100)
        record("follow-up marks selected subject updated without switching", session.updatedTopicIDs.contains(india.id) && session.answeringTopicID == india.id)
        assist.answer(israel); await pause(100)
        assist.answer(opinion); await pause(1000)
        record("background follow-up completes without taking selected reader", session.answeringTopicID == opinion.id && session.cardAnswers[india.id]?.contains("economy") == true && session.cardAnswers[israel.id] == israelBefore)
        assist.answer(followup); await pause()
        record("updated subject restores its own latest answer", session.answeringTopicID == india.id && !session.updatedTopicIDs.contains(india.id))
        if let panel = NSApp.windows.first(where: { $0.windowNumber == overlay.windowNumbers[1] }) {
            let original = panel.frame
            var layouts: [[String: Any]] = []
            for size in [NSSize(width: 420, height: 540), NSSize(width: 760, height: 760)] {
                panel.setContentSize(size); panel.contentView?.layoutSubtreeIfNeeded(); await pause(400)
                let reader = overlay.readingArea
                let height = reader.bounds.height
                record("central reader has usable height at \(Int(size.width))x\(Int(size.height))", height >= size.height * 0.40 && reader.bounds.width >= size.width - 45)
                layouts.append(["width": size.width, "height": size.height, "readerHeight": height, "readerWidth": reader.bounds.width])
                DiagnosticSnapshot.write(to: folder.appendingPathComponent("reader-\(Int(size.width))"), spaceChanges: 0)
            }
            try? JSONSerialization.data(withJSONObject: layouts, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("reader-layout.json"))
            panel.setFrame(original, display: false)
        }
        record("main reader leaves existing session notes intact", notes.state == retainedNotes)
        mainWindow.show(); session.stickyNotes.add(); await pause()
        let noteBefore = session.stickyNotes.notes
        settings.requestStealth(false, from: .settings); if let request = settings.pendingStealthOff { settings.confirmStealthOff(request.id) }; await pause()
        record("stealth off updates all existing app panels", NSApp.activationPolicy() == .regular && NSApp.windows.filter { $0 is OverlayPanel }.allSatisfy { $0.sharingType == .readOnly })
        let createdOff = OverlayPanel(size: NSSize(width: 300, height: 200))
        record("new panels inherit stealth off", createdOff.sharingType == .readOnly)
        record("stealth off persists across settings reconstruction", !SettingsStore(defaults: settings.defaults, loadCredentials: false).stealth)
        settings.requestStealth(true, from: .settings); await pause()
        record("stealth on protects existing settings notes and new panels", NSApp.activationPolicy() == .accessory && NSApp.windows.filter { $0 is OverlayPanel }.allSatisfy { $0.sharingType == .none })
        record("stealth toggle preserves manual notes", session.stickyNotes.notes == noteBefore)
        record("stealth on persists across settings reconstruction", SettingsStore(defaults: settings.defaults, loadCredentials: false).stealth)
        mainWindow.close(); session.stickyNotes.closeAll(); await listening.stop(); session.clear()
    }
}

@MainActor
enum DiagnosticPrivacyPersistence {
    static func startIfAsked() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-PrivacyPersistence"), args.indices.contains(i + 1) else { return false }
        let folder = URL(fileURLWithPath: args[i + 1])
        let suite = "org.example.copilote.recette.privacy-relaunch"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults, loadCredentials: false)
        if args.contains("-SaveStealthOn") { settings.requestStealth(true, from: .settings) }
        if args.contains("-SaveStealthOff") { settings.requestStealth(false, from: .settings); if let request = settings.pendingStealthOff { settings.confirmStealthOff(request.id) } }
        WindowPrivacy.observe(settings)
        WindowPrivacy.authorizeFromUserGesture()
        let panel = OverlayPanel(); panel.title = "Privacy relaunch fixture"
        panel.contentView = NSTextField(labelWithString: settings.stealth ? "Stealth on" : "Stealth off")
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            DiagnosticSnapshot.write(to: folder, spaceChanges: 0)
            if args.contains("-ClearPrivacyFixture") { defaults.removePersistentDomain(forName: suite) }
            NSApp.terminate(nil)
        }
        return true
    }
}

private struct LegacyReader: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
