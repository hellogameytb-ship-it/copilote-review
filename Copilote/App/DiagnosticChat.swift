import AppKit
import CopiloteKit

/// Real controllers and bundled renderer, synthetic text only; no desktop input or capture.
@MainActor
enum DiagnosticChat {
    static func run(folder: URL, overlay: OverlayController, settings: SettingsStore,
                    listening: ListeningController, assist: AssistController, session: SessionController,
                    provider: RecetteProvider, record: (String, Bool) -> Void) async {
        guard DiagnosticAnchorFixture.isRequested, let web = overlay.readingArea as? ResponseWebView else { return }
        var checks: [[String: Any]] = []
        var scriptErrors: [String] = []
        func check(_ name: String, _ passed: Bool) { checks.append(["name":name,"passed":passed]);record(name,passed) }
        func pause(_ ms: Int = 120) async { try? await Task.sleep(for:.milliseconds(ms)) }
        func js(_ code: String) async -> Any? {
            do { return try await web.evaluateJavaScript(code) }
            catch { scriptErrors.append(String(describing:error)); return nil }
        }
        func boolean(_ code: String) async -> Bool { (await js(code)) as? Bool == true }
        func number(_ code: String) async -> Double { (await js(code) as? NSNumber)?.doubleValue ?? -1 }
        func finish() async { for _ in 0..<300 { if !session.isAnswering { break };await pause(5) };await pause() }
        func ask(_ question: String, reply: String) async {
            await provider.replyNext(reply);assist.askText=question;assist.submitAsk();await pause(10);await finish()
        }
        func line(_ text: String,_ start: Double) { listening.receiveRecetteEvent(.line(TranscriptLine(speaker:.them,text:text,start:start,end:start+1),language:"fixture",latency:0)) }
        func prompt() async -> String {
            let messages = await provider.conversations.last?.messages ?? []
            return messages.flatMap { $0["content"]?.arrayValue ?? [] }.compactMap { $0["text"]?.stringValue }.joined(separator:"\n")
        }
        await listening.stop();session.clear();await provider.resetConversations();settings.autoAnswer=false
        listening.beginRecetteConversation();assist.select(nil)
        WindowPrivacy.authorizeFromUserGesture();overlay.present();overlay.reveal();await pause()
        let pill = overlay.pillFrame
        let panel = NSApp.windows.first { $0.windowNumber == overlay.windowNumbers[1] }
        let frame = panel?.frame
        settings.infosysInterviewActive = true
        settings.infosysInterviewContext = String(String(repeating:"FICTIONAL_PROFILE ",count:500).prefix(7847))
        let notesBefore = session.stickyNotes.notes
        let contextBefore = settings.infosysInterviewContext
        let profileBefore = settings.infosysInterviewActive
        let preferencesBefore = settings.answerPreferences
        let stealthBefore = settings.stealth
        line("OLD_AUDIO_SECRET",1)
        await ask("FIRST_REAL_QUESTION: Explain C++ pointers",reply:"FIRST_RESPONSE\n\n" + (0..<35).map { "Paragraph \($0): a pointer stores an address; check lifetime and ownership.\n" }.joined(separator:"\n"))
        await ask("SECOND_REAL_QUESTION: Explain references",reply:"SECOND_RESPONSE: a reference names an existing object.")
        check("chat retains both actual questions and answers",await boolean("document.querySelectorAll('.chat-entry').length === 2 && document.getElementById('answer').innerText.includes('FIRST_REAL_QUESTION') && document.getElementById('answer').innerText.includes('FIRST_RESPONSE') && document.getElementById('answer').innerText.includes('SECOND_RESPONSE')"))
        _ = await js("document.getElementById('scroller').scrollTop = 0")
        await pause()
        let top = await number("document.getElementById('scroller').scrollTop")
        await provider.delayNext();await provider.replyNext("THIRD_RESPONSE")
        assist.askText="THIRD_REAL_QUESTION";assist.submitAsk();await pause(150)
        check("streaming adds one entry without replacing previous exchanges",await boolean("document.querySelectorAll('.chat-entry').length === 3 && document.getElementById('answer').innerText.includes('FIRST_RESPONSE')"))
        await finish()
        check("new answer does not steal an upward reader scroll",abs((await number("document.getElementById('scroller').scrollTop"))-top)<1)
        check("unread latest button is available while reading above",await boolean("!document.getElementById('latest').hidden"))
        _ = await js("document.getElementById('latest').click()")
        await pause()
        check("latest button returns to the newest exchange",await boolean("document.getElementById('latest').hidden && (() => { const s=document.getElementById('scroller');return s.scrollTop+s.clientHeight>=s.scrollHeight-5; })()"))
        let topic=Topic(id:"chat-card",title:"Explicit card question",excerpt:["Explicit card question"],createdAt:Date(),updatedAt:Date())
        assist.answer(topic);await pause(10);await finish()
        let beforeCache=await provider.conversations.count
        assist.answer(topic);await pause()
        let retainsFirst = await boolean("document.getElementById('answer').innerText.includes('FIRST_RESPONSE')")
        check("explicit card navigation keeps chat and reuses cache",await provider.conversations.count == beforeCache && retainsFirst)
        await provider.failNext()
        await ask("OLD_FAILED_QUESTION",reply:"unused")
        let oldFailedID = Int(await number("Number(document.querySelector('.chat-entry:last-child').dataset.answerId)"))
        await provider.failNext()
        await ask("NEW_FAILED_QUESTION",reply:"unused")
        let retryCalls = await provider.conversations.count
        _ = await js("window.webkit.messageHandlers.copilote.postMessage({type:'retry',requestID:\(oldFailedID)})")
        await pause()
        check("stale retry ID cannot resend a different newer failure",await provider.conversations.count == retryCalls)
        check("only selected failure offers a retry",await boolean("document.querySelectorAll('.chat-entry .retry').length === 1 && document.querySelector('.chat-entry:last-child .retry') !== null"))
        await provider.replyNext("CURRENT_RETRY_RESPONSE")
        _ = await js("document.querySelector('.chat-entry:last-child .retry').click()")
        await pause(10);await finish()
        let retried = await prompt()
        check("current retry resends the matching question",retried.contains("NEW_FAILED_QUESTION") && session.lastFinished?.text == "CURRENT_RETRY_RESPONSE")
        _ = await js("document.getElementById('clear-chat').click()")
        overlay.hide();await pause()
        check("hide dismisses pending clear confirmation",await boolean("document.getElementById('clear-confirmation').hidden"))
        WindowPrivacy.authorizeFromUserGesture();overlay.present();overlay.reveal();await pause()
        _ = await js("document.getElementById('clear-chat').click()")
        check("clear requires an inline confirmation",await boolean("!document.getElementById('clear-confirmation').hidden && document.querySelectorAll('.chat-entry').length >= 3"))
        _ = await js("document.getElementById('cancel-clear').click()")
        check("cancel keeps chat and audio context",await boolean("document.getElementById('clear-confirmation').hidden && document.getElementById('answer').innerText.includes('FIRST_RESPONSE')") && listening.transcript.lines.contains { $0.text == "OLD_AUDIO_SECRET" })
        // An unsent generated image, never a real capture.
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:8,pixelsHigh:8,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        if let image=bitmap.cgImage { try? await session.add(image) }
        let captures=session.stackImages
        assist.refresh()
        for item in assist.context.items where item.kind == .capture { assist.toggle(item.id) }
        // Two old requests: foreground manual and background automatic ignore cancellation.
        let beforeLate = await provider.conversations.count
        await provider.lateReplyNext("LATE_BEFORE_CLEAR")
        assist.answerNow()
        for _ in 0..<80 { if await provider.conversations.count > beforeLate { break };await pause(2) }
        await provider.lateReplyNext("BACKGROUND_BEFORE_CLEAR")
        let automatic=AssistQuestion(action:.answer,mode:.technical,question:"OLD_BACKGROUND_QUESTION",heard:[],context:AssistContext())
        session.answerAutomatically(automatic,label:"Old background",topic:Topic(id:"old-background",title:"Old background",excerpt:[],createdAt:Date(),updatedAt:Date()))
        await pause(10)
        _ = await js("(() => { document.getElementById('clear-chat').click(); document.getElementById('confirm-clear').click(); return true; })()")
        await pause(450)
        check("confirmed clear removes chat and ignores all late callbacks",await boolean("document.querySelectorAll('.chat-entry').length === 0 && !document.getElementById('reset-notice').hidden") && session.history.isEmpty && session.cardAnswers.isEmpty && session.lastFinished == nil)
        check("clear retains pending captures, notes, profile and preferences",session.stackImages == captures && session.stickyNotes.notes == notesBefore && settings.infosysInterviewContext == contextBefore && settings.infosysInterviewActive == profileBefore && settings.answerPreferences == preferencesBefore && settings.stealth == stealthBefore)
        check("clear preserves excluded pending screenshot choices",assist.context.items.filter { $0.kind == .capture }.allSatisfy { !$0.isIncluded })
        check("clear leaves listening running with fresh context",listening.isListening && !listening.isPaused && listening.transcript.lines.isEmpty && listening.topics.isEmpty && listening.sessionLines.isEmpty)
        line("LATE_OLD_AUDIO",1)
        listening.receiveRecetteEvent(.volatile(.them,"OLD_PARTIAL_FROM_BEFORE_CLEAR"))
        check("late old final and interim cannot cross the clear boundary",listening.transcript.lines.isEmpty && listening.recentProvisionalSpeech().isEmpty)
        await ask("AFTER_CLEAR_QUESTION",reply:"AFTER_CLEAR_RESPONSE")
        let after=await prompt()
        check("next prompt excludes every prior chat and audio item",!after.contains("FIRST_REAL_QUESTION") && !after.contains("FIRST_RESPONSE") && !after.contains("OLD_AUDIO_SECRET") && !after.contains("OLD_BACKGROUND_QUESTION") && !after.contains("LATE_OLD_AUDIO"))
        line("FRESH_AUDIO_AFTER_CLEAR: Explain a C++ reference",10000)
        listening.receiveRecetteEvent(.volatile(.them,"Explain reference lifetime"))
        assist.answerNow();await finish()
        let fresh=await prompt()
        check("fresh Answer and provisional speech resume after new finalized speech",fresh.contains("AT THE CLICK") && fresh.contains("FRESH_AUDIO_AFTER_CLEAR") && fresh.contains("provisional") && !fresh.contains("OLD_AUDIO_SECRET"))
        check("chat changes keep panel size and origin stable",overlay.pillFrame == pill && panel?.frame == frame)
        check("chat fixture never displays or takes desktop focus",!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
        // Own view rendering only; no desktop pixels.
        if let content=panel?.contentView,let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
            content.cacheDisplay(in:content.bounds,to:bitmap)
            try? bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("chat-panel.png"))
        }
        let callsBeforeLookup = await provider.conversations.count
        session.prepareFreshAnswer()
        session.assist(AssistQuestion(action:.answer,mode:.technical,question:"LOOKUP_BEFORE_CLEAR",heard:[],context:AssistContext()),label:"Pending lookup",topic:nil,plan:{
            _ = await Task.detached { try? await Task.sleep(for:.milliseconds(150)) }.value
            return AnswerPlan(format:AnswerFormat(kind:.personal),extracts:[BaseSnippet(source:"fixture",text:"OLD_LOOKUP_EXTRACT")])
        })
        await pause(10);session.clearChat();await pause(250)
        check("clear cancels pending base lookup before any provider request",await provider.conversations.count == callsBeforeLookup && session.history.isEmpty && !session.isAnswering)
        check("native chat scripts execute without errors",scriptErrors.isEmpty)
        try? JSONSerialization.data(withJSONObject:["checks":checks,"scriptErrors":scriptErrors,"liveAIRequests":0,"audioCaptured":false,"desktopCaptured":false,"physicalInputs":false],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("chat.json"))
        await listening.stop();session.clear();overlay.hide()
    }
}
