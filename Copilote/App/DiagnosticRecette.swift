import AppKit
import AVFoundation
import SwiftUI
import WebKit
import CopiloteKit

/// Opt-in recipe using the production views/controllers and own windows. Synthetic input is
/// delivered inside this process only. It never reads the clipboard or captures the desktop.
@MainActor
enum DiagnosticRecette {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-CopiloteRecette") || ProcessInfo.processInfo.arguments.contains("-RecetteHardware") }
    static var onReopen: (() -> Void)?
    private static var task: Task<Void, Never>?

    /// Events addressed to one of our own windows only; never posted to the desktop.
    private static func clickAsk() -> Bool {
        guard let panel = NSApp.windows.first(where: { $0.isVisible && $0 is OverlayPanel && !($0 is PillPanel) }), let view = panel.contentView else { return false }
        func marker(in root: NSView) -> NSView? {
            if root.identifier?.rawValue == "CopiloteAskBounds" { return root }
            return root.subviews.lazy.compactMap { marker(in: $0) }.first
        }
        guard let target = marker(in: view) else { return false }
        let point = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { return false }
            panel.sendEvent(event)
        }
        return true
    }

    static func startIfAsked() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if DiagnosticHardware.startIfAsked() { return true }
        if DiagnosticStickyPersistence.startIfAsked() { return true }
        guard let i = args.firstIndex(of: "-CopiloteRecette"), args.indices.contains(i + 1) else { return false }
        let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        let suite = "org.example.copilote.recette.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults, loadCredentials: false)
        settings.baseFolder = folder.appendingPathComponent("unused-fixture-base").path
        settings.notesAtEnd = false; settings.keepHistory = false
        let fake = RecetteProvider()
        let providers = ProviderController(settings: settings, injectedProvider: fake, observesEnvironment: false)
        let base = BaseController(settings: settings, providers: providers)
        let overlay = OverlayController(settings: settings)
        let session = SessionController(settings: settings, overlay: overlay, capturer: ScreenCapturer(), providers: providers)
        let listening = ListeningController(settings: settings, providers: providers, base: base)
        listening.answers = session
        let assist = AssistController(settings: settings, session: session, base: base, overlay: overlay)
        let notes = NotesController(settings: settings, providers: providers)
        assist.observe(listening)
        listening.onTopicChosen = assist.answer
        var automaticVersions: [String] = []
        listening.onAutomaticAnswer = { topic in
            automaticVersions.append("\(topic.id):\(topic.version)")
            assist.select(topic)
        }
        let history = HistoryController(settings: settings)
        let mainWindow = MainWindowController(rootView: MainView(settings: settings, session: session, listening: listening, providers: providers, base: base, history: history, onStealth: { settings.stealth = $0 }), autosave: false)
        onReopen = { AppDelegate.reopen(overlay: overlay, mainWindow: mainWindow, stealth: settings.stealth) }
        let menu = PillMenuController()
        let welcome = OnboardingController(settings: settings, providers: providers, base: base)
        welcome.anchor = { overlay.pillFrame }
        overlay.attach(
            panelBody: OverlayBody(listening: listening, session: session, base: base, assist: assist, notes: notes, overlay: overlay.model, webView: overlay.readingArea, onStartTyping: overlay.startTyping, onEndTyping: overlay.endTyping),
            pillBody: PillHost(listening: listening, assist: assist, providers: providers, overlay: overlay.model, onAsk: overlay.startTyping, settings: settings, onStealth: { settings.stealth.toggle(); NSApp.setActivationPolicy(settings.stealth ? .accessory : .regular) }, onUnfold: overlay.pillClicked, onMenu: { state, rect in menu.toggle(PillMenuContent.menu(for: state), anchor: overlay.screenRect(fromPill: rect)) { _ in } })
        )
        NSApp.setActivationPolicy(.accessory)
        overlay.start()
        overlay.onPresentationChange = { session.stickyNotes.setHiddenWithOverlay($0 == .hidden) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        task = Task { @MainActor in
            var checks: [[String: Any]] = []
            var realProviderUsed = false
            var server: CodexAppServer?
            func record(_ name: String, _ ok: Bool) {
                checks.append(["name": name, "passed": ok])
                let result: [String: Any] = ["checks": checks, "realAppWindows": true, "productionControllers": true, "provider": realProviderUsed ? "controlled fixture then real Codex" : "controlled fixture", "desktopEvents": false, "bundle": Bundle.main.bundleURL.path, "version": Bundle.main.infoDictionary?["CFBundleVersion"] ?? "unknown"]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: folder.appendingPathComponent("recette.json"), options: .atomic) }
            }
            func pause(_ ms: Int = 450) async { try? await Task.sleep(for: .milliseconds(ms)) }
            @MainActor func fieldEditor() -> NSTextView? { NSApp.windows.first { $0.isVisible && $0.isKeyWindow && $0 is OverlayPanel }?.firstResponder as? NSTextView }
            await pause()
            await DiagnosticWorkspace.run(folder: folder, overlay: overlay, settings: settings)
            record("pill visible", overlay.isVisible)
            for iteration in 1...(args.contains("-RecetteTypingStress") ? 60 : 15) {
                let beforeCount = session.history.count
                overlay.startTyping(); await pause()
                record("ask \(iteration) owns field editor", fieldEditor() != nil)
                if fieldEditor() == nil {
                    record("focus diagnostics typing=\(overlay.model.isTyping) key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none") active=\(NSApp.isActive)", false)
                }
                if let editor = fieldEditor() {
                    editor.insertText("Question fictive AZERTY : éèàù ê [test] ?", replacementRange: NSRange(location: NSNotFound, length: 0))
                    record("ask \(iteration) binding accents", assist.askText.contains("éèàù ê [test]"))
                    if iteration == 1 { DiagnosticSnapshot.write(to: folder.appendingPathComponent("ask"), spaceChanges: 0) }
                    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                }
                await pause()
                record("ask \(iteration) submitted and released", !overlay.model.isTyping && !session.isAnswering && session.lastFinished != nil && session.history.count == beforeCount + 1)
                overlay.endTyping(); overlay.pillClicked()
            }
            if args.contains("-RecetteTypingStress") {
                record("typing stress completed", true)
                session.clear(); overlay.hide(); defaults.removePersistentDomain(forName: suite)
                NSApp.terminate(nil); return
            }
            overlay.reveal(); await pause(150)
            let pressed = clickAsk()
            await pause()
            record("Demander own-window mouse click focuses native editor", pressed && fieldEditor() != nil)
            if let editor = fieldEditor() {
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("CopiloteRecettePaste-\(UUID().uuidString)"))
                Clipboard.copy("Collage fictif : éèàù ê [] {}", to: pasteboard)
                record("native paste into ask", editor.readSelection(from: pasteboard) && assist.askText.contains("Collage fictif"))
                pasteboard.releaseGlobally()
            }
            overlay.startTyping(); await pause()
            fieldEditor()?.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            await pause(100); record("escape releases keyboard", !overlay.model.isTyping)
            await fake.failNext()
            assist.askText = "Explique une table de hachage"; assist.submitAsk(); await pause()
            record("provider failure surfaced", session.history.first?.note?.contains("recette") == true)
            session.retry(); await pause()
            record("retry succeeds", !session.isAnswering && session.history.first?.text.contains("Controlled fixture answer") == true)
            for action in [AssistAction.whatToSay, .questions, .notes] {
                assist.run(action); await pause()
                record("action \(action.rawValue)", session.lastFinished?.action == action && !session.isAnswering)
            }
            welcome.start()
            for step in 0..<6 {
                await pause(450)
                record("welcome step \(step + 1)", welcome.isRunning && welcome.onboarding.step.rawValue == step)
                DiagnosticSnapshot.write(to: folder.appendingPathComponent("welcome-\(step + 1)"), spaceChanges: 0)
                welcome.next()
            }
            record("welcome completed", !welcome.isRunning && settings.onboardingDone)
            menu.toggle(PillMenuContent.menu(for: PillState()), anchor: overlay.pillFrame) { action in
                if case let .mode(mode) = action { assist.mode = mode }
            }
            await pause(150); record("gear opens", menu.isOpen)
            DiagnosticSnapshot.write(to: folder.appendingPathComponent("gear"), spaceChanges: 0)
            menu.close(restoringKeyboard: true); record("gear closes", !menu.isOpen)
            for mode in MeetingMode.allCases {
                menu.toggle(PillMenuContent.menu(for: PillState()), anchor: overlay.pillFrame) { action in
                    if case let .mode(chosen) = action { assist.mode = chosen }
                }
                menu.choose(PillMenuAction.mode(mode).id)
                record("gear mode \(mode.rawValue)", !menu.isOpen && assist.mode == mode)
            }
            assist.mode = .meeting
            menu.toggle(PillMenuContent.menu(for: PillState()), anchor: overlay.pillFrame) { action in
                if action == .openApp { NSApp.setActivationPolicy(.regular); mainWindow.show() }
            }
            menu.choose(PillMenuAction.openApp.id); await pause()
            record("gear opens real settings window", NSApp.windows.contains { $0.isVisible && $0.title == "Copilote" && !($0 is OverlayPanel) })
            DiagnosticSnapshot.write(to: folder.appendingPathComponent("settings"), spaceChanges: 0)
            mainWindow.close(); NSApp.setActivationPolicy(.accessory)
            record("settings closed", !NSApp.windows.contains { $0.isVisible && $0.title == "Copilote" && !($0 is OverlayPanel) })
            for policy in [NSApplication.ActivationPolicy.regular, .accessory] {
                NSApp.setActivationPolicy(policy); await pause(100)
                record("activation policy \(policy.rawValue)", NSApp.activationPolicy() == policy && overlay.isVisible)
            }
            overlay.hide(); record("hidden", !overlay.isVisible)
            overlay.present(); record("restored", overlay.isVisible)
            overlay.recenter()
            for direction in [OverlayPlacement.Direction.up, .down, .left, .right] { overlay.move(direction) }
            record("moved own overlay", overlay.isVisible)
            record("overlay sharing flags", NSApp.windows.filter { $0 is OverlayPanel }.allSatisfy { $0.sharingType == .none })
            if let web = overlay.readingArea as? ResponseWebView {
                let board = NSPasteboard(name: NSPasteboard.Name("CopiloteRecette-\(UUID().uuidString)"))
                web.onCopy = { Clipboard.copy($0, to: board) }
                _ = try? await web.evaluateJavaScript("document.querySelector('#answer-tools .copy')?.click()")
                await pause(150)
                record("copy through WebKit to isolated pasteboard", board.string(forType: .string)?.contains("Controlled fixture answer") == true)
                board.releaseGlobally()
                web.onCopy = { Clipboard.copy($0) }
            }
            if let view = NSApp.windows.first(where: { $0.isVisible && $0 is OverlayPanel && !($0 is PillPanel) })?.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let image = bitmap.cgImage {
                    try? await session.add(image)
                    record("own window capture encoded and stacked", session.stackImages.count == 1)
                    session.sendCaptures(); await pause()
                    record("own window capture answered", session.stackImages.isEmpty && !session.isAnswering)
                }
            }
            session.clear()
            await fake.delayNext()
            let cancellationTopic = Topic(id: "cancel-fixture", title: "Comment fonctionne un cache ?", excerpt: [], createdAt: Date(), updatedAt: Date())
            session.answerAutomatically(AssistQuestion(action: .answer, mode: .technical, question: cancellationTopic.title, heard: [], context: AssistContext()), label: "Annulation de recette", topic: cancellationTopic)
            await pause(20)
            await listening.stop(); await pause(200)
            record("stop cancels an already streaming automatic request", !session.isAnswering && session.lastFinished == nil)
            await DiagnosticInterview.run(settings: settings, session: session, listening: listening, assist: assist, overlay: overlay, mainWindow: mainWindow, fake: fake, folder: folder, record: record)
            if args.contains("-RecetteCodex") {
                if let executable = CodexAvailability.locate(), CodexAvailability.isReady(executable: executable) {
                    do {
                        let config = try CodexAvailability.userConfig() ?? ""
                        if let problem = CodexLaunch.problem(inUserConfig: config) { throw CodexFailure(message: problem) }
                        let liveServer = CodexAppServer(executable: executable, workingDirectory: CodexAvailability.workingDirectory, privateDirectory: folder.appendingPathComponent("private-codex"), loadUserConfig: { try CodexAvailability.userConfig() })
                        server = liveServer
                        let live = CodexProvider(server: liveServer, answerModel: CodexProvider.defaultModel, topicModel: CodexProvider.defaultModel, serviceTier: nil)
                        await fake.use(live)
                        realProviderUsed = true
                        for (name, text) in [("code", "Écris une fonction Python qui inverse une liste, et sa complexité."), ("current sources", "Qui est le président actuel de la France ? Cite les sources web fournies."), ("unknown opinion", "Quel est mon président préféré ?"), ("unknown personal", "Décris mon expérience dans le projet Orion.")] {
                            assist.askText = text; assist.submitAsk(); await pause(300)
                            for _ in 0..<180 { if !session.isAnswering { break }; await pause(250) }
                            let answer = session.lastFinished?.text ?? ""
                            record("real Codex \(name)", !session.isAnswering && !answer.isEmpty && (name != "current sources" || (answer.contains("https://") && answer.contains("Macron"))) && (name != "unknown opinion" || OpinionGuard.firstPersonOpinion(in: answer) == nil))
                            try? answer.write(to: folder.appendingPathComponent("codex-\(name.replacingOccurrences(of: " ", with: "-" )).md"), atomically: true, encoding: .utf8)
                            session.clear()
                        }
                    } catch { record("real Codex unavailable: \(error.localizedDescription)", false) }
                } else { record("real Codex unavailable: CLI or login", false) }
            }
            if #available(macOS 26, *), let flag = args.firstIndex(of: "-RecetteAudio"), args.indices.contains(flag + 1) {
                do {
                    automaticVersions = []
                    try await listening.beginRecetteAudio()
                    record("real SpeechAnalyzer started", listening.isListening)
                    listening.pauseOrResume(); record("audio paused", listening.isPaused)
                    let count = listening.transcript.lines.count
                    await pause(600); record("no transcript while paused", listening.transcript.lines.count == count)
                    listening.pauseOrResume(); record("audio resumed", !listening.isPaused)
                    let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[flag + 1]))
                    while file.framePosition < file.length {
                        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600) else { break }
                        try file.read(into: buffer)
                        listening.appendRecetteAudio(buffer)
                        await pause(Int(Double(buffer.frameLength) / file.processingFormat.sampleRate * 1000))
                    }
                    await listening.drainRecetteAudio(); await pause(1000)
                    for _ in 0..<180 { if !session.isAnswering { break }; await pause(250) }
                    let transcript = listening.transcript.lines.map(\.labeled).joined(separator: "\n")
                    try? transcript.write(to: folder.appendingPathComponent("audio-transcript.txt"), atomically: true, encoding: .utf8)
                    record("ASR status: \(listening.segmenterStatus), events: \(listening.recetteEvents)", !listening.transcript.lines.isEmpty)
                    record("real audio transcribed FR", transcript.localizedCaseInsensitiveContains("binaire"))
                    record("real audio transcribed EN", transcript.localizedCaseInsensitiveContains("hash"))
                    record("audio produced topics", !listening.topics.isEmpty)
                    record("no duplicate automatic topic versions", Set(automaticVersions).count == automaticVersions.count)
                    record("audio triggered automatic reply", session.isShowingAutomatic && session.lastFinished != nil)
                    if !listening.topics.isEmpty {
                        listening.togglePin(caseIndex: 0); await pause(150)
                        record("topic pin", listening.topics.first?.isPinned == true)
                        for index in listening.topics.indices {
                            listening.answer(caseIndex: index); await pause(250)
                            for _ in 0..<180 { if !session.isAnswering { break }; await pause(250) }
                            record("topic answer \(index + 1)", assist.target?.id == listening.topics[index].id && session.answeringTopicID == listening.topics[index].id && !session.isAnswering)
                        }
                    }
                    try? (session.lastFinished?.text ?? "").write(to: folder.appendingPathComponent("audio-answer.md"), atomically: true, encoding: .utf8)
                    DiagnosticSnapshot.write(to: folder.appendingPathComponent("audio"), spaceChanges: 0)
                    await listening.stop()
                    let historyCount = session.history.count
                    await pause(1200)
                    record("audio stopped without late reply", !listening.isListening && listening.transcript.lines.isEmpty && session.history.count == historyCount)
                    try await listening.beginRecetteAudio(speaker: .me)
                    file.framePosition = 0
                    let beforeSelf = session.history.count
                    let endSelf = min(file.length, AVAudioFramePosition(file.processingFormat.sampleRate * 7))
                    while file.framePosition < endSelf {
                        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600) else { break }
                        try file.read(into: buffer)
                        listening.appendRecetteAudio(buffer)
                        await pause(100)
                    }
                    await listening.drainRecetteAudio(); await pause(500)
                    record("own voice transcribed without triggering reply", !listening.transcript.lines.isEmpty && listening.topics.isEmpty && session.history.count == beforeSelf)
                    await listening.stop()
                    // Existing permissions only; bounded hardware run, no provider use, no recording.
                    if !args.contains("-RecetteFileOnly"), ScreenCapturer.hasPermission, MicrophoneCapture.permission == .authorized {
                        settings.autoAnswer = false
                        let beforeHardware = session.history.count
                        await listening.start()
                        record("live microphone and system capture started", listening.isListening)
                        await pause(200)
                        listening.pauseOrResume(); record("live capture paused", listening.isPaused)
                        await pause(100)
                        listening.pauseOrResume(); record("live capture resumed", listening.isListening && !listening.isPaused)
                        await pause(200)
                        await listening.stop()
                        record("live capture stopped without inference", !listening.isListening && listening.transcript.lines.isEmpty && session.history.count == beforeHardware)
                        settings.autoAnswer = true
                    } else if !args.contains("-RecetteFileOnly") {
                        record("hardware capture skipped: missing existing permission", false)
                    }
                } catch {
                    record("audio failure: \(error.localizedDescription)", false)
                    await listening.stop()
                }
            }
            await DiagnosticGlass.run(folder: folder, record: record)
            await DiagnosticGroundedAnswers.run(folder: folder, record: record)
            record("recipe completed", true)
            session.clear()
            server?.terminateNow()
            overlay.hide(); defaults.removePersistentDomain(forName: suite)
            NSApp.terminate(nil)
        }
        return true
    }
}

actor RecetteProvider: LLMProvider {
    nonisolated let kind = ProviderKind.codex
    nonisolated let label = "Controlled recipe provider"
    nonisolated var topicSegmenter: any TopicSegmenter { RecetteSegmenter() }
    nonisolated let topicSegmenterName = "recette"
    private var shouldFail = false
    private(set) var conversations: [Conversation] = []
    func resetConversations() { conversations = [] }
    private var delay = false
    func delayNext() { delay = true }
    private var live: (any LLMProvider)?
    func use(_ provider: any LLMProvider) { live = provider }
    func failNext() { shouldFail = true }
    func warmUp() async {}
    func streamAnswer(to conversation: Conversation, onText: @escaping @Sendable (String) async -> Void) async throws -> CompletedMessage {
        conversations.append(conversation)
        if shouldFail { shouldFail = false; throw NSError(domain: "recette", code: 1, userInfo: [NSLocalizedDescriptionKey: "Erreur fournisseur de recette"]) }
        if let live { return try await live.streamAnswer(to: conversation, onText: onText) }
        let milliseconds = delay ? 1000 : 80
        delay = false
        try await Task.sleep(for: .milliseconds(milliseconds))
        var text = "Controlled fixture answer.\n\n**Say:** A controlled example.\n\n## Likely follow-ups\n- Why? → For this test."
        let input = conversation.messages.flatMap { $0["content"]?.arrayValue ?? [] }.compactMap { $0["text"]?.stringValue }.joined()
        if input.contains("Personal notes explicitly included") { text += "\nPrivate Orion interview pitch from the included note." }
        await onText(text)
        return CompletedMessage(content: [["type": "text", "text": .string(text)]], stopReason: "end_turn")
    }
    func complete(system: String, prompt: String, images: [CapturedImage], schema: JSONValue?) async throws -> String { "{}" }
}
private struct RecetteSegmenter: TopicSegmenter {
    func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision { .new(title: turn.text) }
}
