import AppKit
import WebKit
import CopiloteKit

/// Silent, opt-in tests against production controllers and only this process's windows.
@MainActor
enum DiagnosticInterview {
    static func run(settings: SettingsStore, session: SessionController, listening: ListeningController,
                    assist: AssistController, overlay: OverlayController, mainWindow: MainWindowController,
                    fake: RecetteProvider, folder: URL, record: (String, Bool) -> Void) async {
        func pause(_ ms: Int = 300) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func prompt(_ conversation: Conversation?) -> String {
            conversation?.messages.flatMap { $0["content"]?.arrayValue ?? [] }.compactMap { $0["text"]?.stringValue }.joined(separator: "\n") ?? ""
        }
        func images(_ conversation: Conversation?) -> [String] {
            conversation?.messages.flatMap { $0["content"]?.arrayValue ?? [] }.filter { $0["type"] == "image" }.compactMap { $0["source"]?["data"]?.stringValue } ?? []
        }
        func ownImage(_ color: NSColor) -> CGImage {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            color.setFill(); NSRect(x: 0, y: 0, width: 120, height: 80).fill()
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.cgImage!
        }
        session.clear(); await fake.resetConversations()
        settings.autoAnswer = true
        settings.answerInstructions = "Use evidence only. Never invent measured results."
        listening.beginRecetteConversation()
        let pipeline = TopicPipeline(segmenter: nil, segmenterName: "silent fixture") { update in
            DispatchQueue.main.async { listening.receiveRecetteEvent(.topics(update)) }
        }
        func feed(_ text: String, _ speaker: Speaker, _ time: Double, request: Bool = true) async {
            let line = TranscriptLine(speaker: speaker, text: text, start: time, end: time + 3)
            listening.receiveRecetteEvent(.line(line, language: "en", latency: 0))
            await pipeline.add(line)
            if request { await pipeline.handle(Turn(speaker: speaker, text: text, start: time, end: time + 3)) }
        }
        await feed("Use Python and constant extra space for coding questions.", .them, 0, request: false)
        await feed("I built Orion in Swift. We have no measured speedup yet.", .me, 5)
        await fake.delayNext()
        await feed("Present your project Orion", .them, 10)
        await pause(100)
        await feed("Then measure this", .them, 20)
        await pause(150)
        listening.receiveRecetteEvent(.speaking(.me, true))
        await pause(1000)
        record("two automatic cards complete independently while the user speaks", session.cardAnswers.count == 2 && session.cardAnswers.values.allSatisfy { $0.contains("Controlled fixture answer") })
        let historyBeforeVoice = session.history.count
        await feed("Describe another algorithm that I used myself.", .me, 30)
        await pause()
        record("the user speech adds context without answering or cancelling", session.history.count == historyBeforeVoice && listening.transcript.lines.last?.speaker == .me)
        listening.receiveRecetteEvent(.speaking(.me, false))
        let topics = listening.topics
        let countBeforeCache = await fake.conversations.count
        for topic in topics { assist.answer(topic); await pause(60) }
        record("switching cards restores cached response without a provider call", await fake.conversations.count == countBeforeCache && session.answeringTopicID == topics.last?.id)
        await feed("Which stack for Orion", .them, 40)
        await pause()
        record("follow-up updates older project only", listening.topics.count == 2 && session.history.count == historyBeforeVoice + 1 && listening.topics.last?.excerpt.last == "Which stack for Orion")
        for minute in 1...65 { await feed("Retained session detail at minute \(minute).", minute % 2 == 0 ? .me : .them, Double(minute * 60), request: false) }
        assist.askText = "For the rest of this session, use British spelling and make tradeoffs explicit."; assist.submitAsk(); await pause()
        assist.askText = "Explain the earlier project and all its constraints."; assist.submitAsk(); await pause()
        let cumulative = prompt(await fake.conversations.last)
        record("manual request includes 65 minute context, early constraints and the user facts", cumulative.contains("constant extra space") && cumulative.contains("I built Orion in Swift") && cumulative.contains("minute 65"))
        record("typed standing instructions persist in later request", cumulative.contains("Earlier typed user requests") && cumulative.contains("British spelling"))
        record("assistant drafts distinguished from personal evidence", cumulative.contains("NOT verified personal facts"))
        record("English default and custom standing instructions reach provider", settings.answerPreferences.language == .english && cumulative.contains("Never invent measured results"))
        DiagnosticSnapshot.write(to: folder.appendingPathComponent("interview-cards"), spaceChanges: 0)
        await listening.stop()
        listening.beginRecetteConversation()
        assist.askText = "Explain a binary tree"; assist.submitAsk(); await pause()
        let resetPrompt = prompt(await fake.conversations.last)
        record("new session drops previous transcript and typed context", !resetPrompt.contains("British spelling") && !resetPrompt.contains("minute 65"))
        await listening.stop(); session.clear()

        // Distinct locally drawn images: only our generated pixels enter the request.
        for color in [NSColor.red, .green, .blue] { try? await session.add(ownImage(color)) }
        let original = session.stackImages
        session.moveCapture(from: 2, to: 0); session.removeCapture(at: 1)
        let expected = [original[2], original[1]]
        record("screenshot reorder and delete reflected in visible stack", session.stackImages == expected)
        DiagnosticSnapshot.write(to: folder.appendingPathComponent("screenshots"), spaceChanges: 0)
        await fake.failNext(); session.sendCaptures(); await pause()
        record("failed screenshots restored in displayed order", session.stackImages == expected && !session.isAnswering)
        session.sendCaptures(); await pause()
        let imageRequest = await fake.conversations.last
        record("retry sends exactly the ordered screenshot stack", images(imageRequest) == expected.map { $0.data.base64EncodedString() } && session.stackImages.isEmpty)
        record("all screenshot constraints and overlap requested", prompt(imageRequest).contains("Read ALL") && prompt(imageRequest).contains("overlapping"))
        assist.askText = "Explain a hash table"; assist.submitAsk(); await pause()
        record("next typed request has no stale screenshots", images(await fake.conversations.last).isEmpty)
        for color in [NSColor.yellow, .purple] { try? await session.add(ownImage(color)) }
        let toCancel = session.stackImages
        await fake.delayNext(); session.sendCaptures(); await pause(50); session.cancelCurrent(); await pause(1100)
        record("cancel keeps screenshot order and rejects late provider result", session.stackImages == toCancel && !session.isAnswering && session.history.first?.note == "Cancelled")
        session.sendCaptures(); await pause()
        record("cancelled screenshots can be retried", session.stackImages.isEmpty && session.lastFinished?.text.contains("Controlled fixture answer") == true)
        session.clear()

        let sticky = session.stickyNotes
        sticky.add(); sticky.add()
        let firstNote = sticky.notes[0].id
        sticky.setText("Private Orion interview pitch — never upload by default", for: firstNote)
        record("multiple editable notes persist locally", sticky.notes.count == 2 && settings.defaults.data(forKey: "stickyNotesV1") != nil)
        assist.askText = "Explain a binary tree"; assist.submitAsk(); await pause()
        record("personal notes excluded from AI by default", !prompt(await fake.conversations.last).contains("Private Orion interview pitch"))
        sticky.setIncluded(true, for: firstNote)
        assist.askText = "Summarize my prepared note"; assist.submitAsk(); await pause()
        record("explicit note consent includes content", prompt(await fake.conversations.last).contains("Private Orion interview pitch"))
        sticky.setIncluded(false, for: firstNote)
        assist.askText = "Explain a binary tree"; assist.submitAsk(); await pause()
        record("unchecked note and drafts derived from it leave future AI context", !prompt(await fake.conversations.last).contains("Private Orion interview pitch"))
        sticky.togglePin(firstNote)
        record("note pin persists", sticky.notes[0].isPinned)
        sticky.delete(firstNote)
        record("delete hides note and remains recoverable", !sticky.isWindowVisible(firstNote) && sticky.hasDeleted)
        sticky.restoreLastDeleted()
        record("restore preserves text and pin", sticky.isWindowVisible(firstNote) && sticky.notes[0].text.contains("Private Orion") && sticky.notes[0].isPinned)
        let restored = StickyNotesController(settings: settings)
        record("notes survive controller recreation", restored.notes == sticky.notes)
        listening.beginRecetteConversation()
        if let window = sticky.windowForDiagnostic(firstNote), let content = window.contentView {
            func editor(in view: NSView) -> StickyTextView? {
                if let result = view as? StickyTextView { return result }
                return view.subviews.lazy.compactMap { editor(in: $0) }.first
            }
            if let textView = editor(in: content) {
                window.makeKeyAndOrderFront(nil); window.makeFirstResponder(textView)
                textView.insertText(" — edited éèà []", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
                record("native note typing keeps listening active", listening.isListening && sticky.notes[0].text.contains("edited éèà []"))
                textView.cancelOperation(nil)
            } else { record("native note editor exists", false) }
        }
        await listening.stop()
        overlay.hide()
        record("hide all includes personal notes", sticky.notes.filter { $0.deletedAt == nil }.allSatisfy { !sticky.isWindowVisible($0.id) })
        overlay.present()
        record("reopen restores visible personal notes", sticky.notes.filter { $0.deletedAt == nil }.allSatisfy { sticky.isWindowVisible($0.id) })
        DiagnosticSnapshot.write(to: folder.appendingPathComponent("personal-notes"), spaceChanges: 0)
        sticky.toggleVisible()
        record("notes can hide independently", !sticky.isWindowVisible(firstNote) && overlay.isVisible)
        sticky.toggleVisible()

        // The actual delegate route uses the same reopen helper as normal launches.
        var spaceChanges = 0
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in spaceChanges += 1 }
        for iteration in 1...3 {
            settings.stealth = false; NSApp.setActivationPolicy(.regular)
            mainWindow.show(); mainWindow.close()
            _ = (NSApp.delegate as? AppDelegate)?.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            let main = NSApp.windows.first { $0.title == "Copilote" && !($0 is OverlayPanel) }
            record("close then delegate reopen \(iteration)", overlay.model.isUnfolded && overlay.isVisible)
            mainWindow.show(); main?.miniaturize(nil); await pause(80)
            _ = (NSApp.delegate as? AppDelegate)?.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
            record("minimized settings leave usable workspace on reopen \(iteration)", overlay.model.isUnfolded && overlay.isVisible)
            NSApp.hide(nil); await pause(80)
            _ = (NSApp.delegate as? AppDelegate)?.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            await pause(120)
            record("hidden app reopens \(iteration)", !NSApp.isHidden && overlay.model.isUnfolded && overlay.isVisible)
            mainWindow.close(); settings.stealth = true; NSApp.setActivationPolicy(.accessory)
            overlay.hide()
            _ = (NSApp.delegate as? AppDelegate)?.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            record("stealth reopen restores expanded panel \(iteration)", overlay.isVisible && overlay.model.isUnfolded)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        record("reopen causes no Space switch", spaceChanges == 0)
        settings.overlayOpacity = 0.7
        record("background density leaves foreground opacity intact", NSApp.windows.filter { $0 is OverlayPanel }.allSatisfy { $0.contentView?.alphaValue == 1 })
        if let web = overlay.readingArea as? ResponseWebView {
            let bg = try? await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
            record("WebKit reading surface has transparent CSS and native underlay", bg == "rgba(0, 0, 0, 0)" && web.underPageBackgroundColor.alphaComponent == 0)
        }
        let accessibleSurface = FrostedSurface()
        accessibleSurface.backgroundMode = .system
        accessibleSurface.density = 0.7
        accessibleSurface.updateVeil(reduceTransparency: true)
        record("Reduce Transparency uses opaque background without fading text", accessibleSurface.veilAlpha == 1 && accessibleSurface.alphaValue == 1)
        accessibleSurface.updateVeil(reduceTransparency: false)
        record("glass density restores translucent background", accessibleSurface.veilAlpha < 0.5 && accessibleSurface.alphaValue == 1)
        accessibleSurface.backgroundMode = .translucent
        accessibleSurface.updateVeil(reduceTransparency: true)
        record("explicit Translucent mode remains translucent with Reduce Transparency on", accessibleSurface.veilAlpha < 0.9 && accessibleSurface.alphaValue == 1)
        accessibleSurface.backgroundMode = .opaque
        accessibleSurface.updateVeil(reduceTransparency: false)
        record("explicit Opaque mode remains opaque", accessibleSurface.veilAlpha == 1)
        record("requested app appearance migration selects Translucent", settings.overlayBackground == .translucent)
        record("native blur respects system accessibility and sharing remains disabled", NSApp.windows.filter { $0 is OverlayPanel }.allSatisfy { $0.contentView is FrostedSurface && $0.sharingType == .none })
        DiagnosticSnapshot.write(to: folder.appendingPathComponent("reopened"), spaceChanges: spaceChanges)
        sticky.closeAll()
    }
}
