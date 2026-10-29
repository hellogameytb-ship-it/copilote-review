import AppKit
import CopiloteKit

@MainActor
enum DiagnosticAnswerNow {
    static func run(folder:URL,overlay:OverlayController,settings:SettingsStore,listening:ListeningController,
                    assist:AssistController,session:SessionController,provider:RecetteProvider,record:(String,Bool)->Void) async {
        guard DiagnosticAnchorFixture.isRequested else { return }
        var checks:[[String:Any]] = []
        func check(_ name:String,_ value:Bool) { checks.append(["name":name,"passed":value]);record(name,value) }
        func waitForCount(_ count:Int) async {
            for _ in 0..<200 { if await provider.conversations.count >= count && !session.isAnswering { return };try? await Task.sleep(for:.milliseconds(5)) }
        }
        func prompt() async -> String {
            let messages = await provider.conversations.last?.messages ?? []
            let blocks:[JSONValue] = messages.flatMap { $0["content"]?.arrayValue ?? [] }
            return blocks.compactMap { $0["text"]?.stringValue }.joined(separator:"\n")
        }
        func line(_ text:String,_ at:Double) {
            listening.receiveRecetteEvent(.line(TranscriptLine(speaker:.them,text:text,start:at,end:at+1),language:"fixture",latency:0))
        }
        func reset() async {
            await listening.stop();session.clear();await provider.resetConversations();settings.autoAnswer=false
            listening.beginRecetteConversation();assist.select(nil)
        }
        func marker(_ view:NSView) -> InlineControlMarker? {
            if view.identifier?.rawValue == "AnswerNow" { return view as? InlineControlMarker }
            return view.subviews.lazy.compactMap { marker($0) }.first
        }
        await reset()
        WindowPrivacy.authorizeFromUserGesture();overlay.present();overlay.reveal()
        let frame = overlay.pillFrame
        let old = Topic(id:"old-card",title:"Explain binary trees",excerpt:["Explain binary trees."],createdAt:Date(),updatedAt:Date())
        assist.answer(old);await waitForCount(1)
        line("EARLY_SESSION_CONSTRAINT constant memory",0)
        for index in 0..<24 { line("MONOLOGUE detail \(index)",3600+Double(index)*10) }
        line("How should we implement a hash table with these constraints?",3845)
        try? await Task.sleep(for:.milliseconds(40))
        let panel = NSApp.windows.first { $0.windowNumber == overlay.windowNumbers[1] }
        panel?.contentView?.layoutSubtreeIfNeeded()
        check("Answer button invokes bound fresh action",panel?.contentView.flatMap { marker($0) }?.invokeHeadlessAction() == true)
        line("AFTER_CLICK_NEXT_SUBJECT database transactions",3850)
        await waitForCount(2)
        let first = await prompt()
        check("fresh Answer ignores cached subject and freezes click-time speech",first.contains("AT THE CLICK") && first.contains("hash table") && first.contains("EARLY_SESSION_CONSTRAINT") && !first.contains("AFTER_CLICK_NEXT_SUBJECT") && !first.contains("Current subject:"))
        check("fresh answer is not assigned to old card",session.answeringTopicID == nil && assist.target == nil)
        assist.answer(old);await waitForCount(2)
        check("explicit old-card navigation still uses its cache",await provider.conversations.count == 2 && session.answeringTopicID == old.id)
        assist.answerNow();await waitForCount(3)
        check("shortcut action uses newest speech before topic segmentation",(await prompt()).contains("AFTER_CLICK_NEXT_SUBJECT") && session.answeringTopicID == nil)
        line("Et pourquoi ?",3855);assist.answerNow();await waitForCount(4)
        let elliptical = await prompt()
        check("elliptical request retains preceding minutes",elliptical.contains("Et pourquoi ?") && elliptical.contains("MONOLOGUE detail 23"))
        check("capture and panel shortcut catalog retained",ShortcutCatalog.all.contains { $0.name == .togglePanel } && ShortcutCatalog.all.contains { $0.name == .captureScreen } && ShortcutCatalog.topicsOnly.contains(.answerLatestTopic))

        await reset()
        listening.receiveRecetteEvent(.volatile(.them,"Explain hash table memory constraints"))
        assist.answerNow();await waitForCount(1)
        let partial = await prompt()
        check("partial-only speech is explicitly provisional",partial.contains("Them (provisional): Explain hash table memory constraints"))
        check("old interim text expires",listening.recentProvisionalSpeech(at:ProcessInfo.processInfo.systemUptime+13).isEmpty)
        line("Explain hash table memory constraints.",1)
        check("final speech replaces interim text",listening.recentProvisionalSpeech().isEmpty)

        await reset()
        line("Explain hash table memory constraints.",1);line("EXCLUDED_PRIVATE_DETAIL",2)
        assist.refresh()
        if let item = assist.context.items.first(where:{$0.label.contains("EXCLUDED_PRIVATE_DETAIL")}) { assist.toggle(item.id) }
        session.stickyNotes.add()
        let note = session.stickyNotes.notes.last!.id
        session.stickyNotes.setText("PRIVATE_NOTE_AFTER_CLICK",for:note)
        let preferences = settings.answerPreferences
        assist.answerNow()
        session.stickyNotes.setIncluded(true,for:note)
        settings.answerInstructions = "INSTRUCTIONS_AFTER_CLICK"
        await waitForCount(1)
        let privacy = await prompt()
        check("snapshot preserves transcript exclusions and note consent at click",!privacy.contains("EXCLUDED_PRIVATE_DETAIL") && !privacy.contains("PRIVATE_NOTE_AFTER_CLICK"))
        check("answer preferences are frozen at click",await provider.conversations.last?.preferences == preferences)
        session.stickyNotes.setIncluded(false,for:note)
        settings.answerInstructions = preferences.instructions

        await reset()
        line("Describe NEW_PROJECT technology.",1)
        var lookupContext = AssistContext(lines: listening.transcript.lines, extracts: [
            BaseSnippet(source:"old-project",text:"STALE_BASE_EXTRACT"),
            BaseSnippet(source:"private",text:"EXCLUDED_BASE_EXTRACT")])
        lookupContext.toggle("extract-private")
        let lookupQuestion = AssistQuestion(action:.answer,mode:.technical,question:"Describe NEW_PROJECT technology.",heard:[],context:lookupContext)
        let lookupPreferences = settings.answerPreferences
        session.prepareFreshAnswer()
        session.assist(lookupQuestion,label:"Fresh lookup fixture",topic:nil,plan:{
            try? await Task.sleep(for:.milliseconds(30))
            return AnswerPlan(format:AnswerFormat(question:"Describe my project technology."),extracts:[
                BaseSnippet(source:"new-project",text:"FRESH_BASE_EXTRACT"),
                BaseSnippet(source:"private",text:"EXCLUDED_BASE_EXTRACT")])
        })
        settings.answerInstructions = "PREFERENCES_CHANGED_DURING_LOOKUP"
        await waitForCount(1)
        let lookupPrompt = await prompt()
        check("fresh lookup replaces stale extracts and respects exclusions",lookupPrompt.contains("FRESH_BASE_EXTRACT") && !lookupPrompt.contains("STALE_BASE_EXTRACT") && !lookupPrompt.contains("EXCLUDED_BASE_EXTRACT"))
        check("asynchronous lookup preserves click-time preferences",await provider.conversations.last?.preferences == lookupPreferences)
        settings.answerInstructions = lookupPreferences.instructions

        await reset()
        line("Explain binary trees.",1)
        await provider.lateReplyNext("OLD_LATE_RESPONSE")
        assist.answerNow()
        for _ in 0..<100 { if await provider.conversations.count == 1 { break };try? await Task.sleep(for:.milliseconds(5)) }
        line("Explain hash tables instead.",3)
        await provider.replyNext("NEW_INTENTION_RESPONSE")
        assist.answerNow();await waitForCount(2)
        try? await Task.sleep(for:.milliseconds(400))
        check("rapid clicks keep latest response despite noncooperative late callback",session.lastFinished?.text == "NEW_INTENTION_RESPONSE" && session.answeringTopicID == nil)
        check("newest click takes its own immutable context",(await prompt()).contains("Explain hash tables instead."))
        await reset()
        let profileContext=settings.infosysInterviewContext, profileActive=settings.infosysInterviewActive
        let longParts=(0..<10).map { "NINETY_SECOND_PART_\($0)_END: bounded queue constraint" }
        for (index,text) in longParts.enumerated() { line(text,100+Double(index)*10) }
        line("What do you think?",195)
        assist.answerNow();await waitForCount(1)
        let fullExchange=await prompt()
        let working=fullExchange.components(separatedBy:"Working conversation — last 120 seconds").last?.components(separatedBy:"Earlier continuation —").first ?? ""
        check("Answer sends every fragment of a ninety-second question in its primary context",longParts.allSatisfy { working.contains($0) } && working.contains("What do you think?"))
        check("context selection adds no separate model request",await provider.conversations.count == 1)
        line("okay",199)
        assist.answerNow();await waitForCount(2)
        let acknowledged=await prompt()
        check("acknowledgement preserves the complete question and starts a fresh answer",await provider.conversations.count == 2 && acknowledged.contains(longParts[0]) && acknowledged.contains("does not replace the question"))
        let sentPreferences=await provider.conversations.last?.preferences
        check("working-window Answer preserves active profile and its frozen preferences",settings.infosysInterviewContext == profileContext && settings.infosysInterviewActive == profileActive && provider.kind == .codex && sentPreferences == settings.answerPreferences)

        await reset()
        let threeMinuteParts=(0...18).map { "THREE_MINUTE_PART_\($0)_END: queue setup" }
        for (index,text) in threeMinuteParts.enumerated() { line(text,20+Double(index)*10) }
        assist.answerNow();await waitForCount(1)
        let extended=await prompt()
        let continuation=extended.components(separatedBy:"Earlier continuation —").last?.components(separatedBy:"Earlier session background —").first ?? ""
        check("three-minute statement beginning reaches provider as earlier continuation",threeMinuteParts.allSatisfy { extended.contains($0) } && continuation.contains(threeMinuteParts[0]))
        line("New topic: explain C++ reference lifetime",205)
        assist.answerNow();await waitForCount(2)
        let changed=await prompt()
        check("new subject is present with explicit priority over older detailed statement",changed.contains("New topic: explain C++ reference lifetime") && changed.contains("newer substantive question takes priority"))
        assist.refresh()
        if let item=assist.context.items.first(where: { $0.label.contains(threeMinuteParts[0]) }) { assist.toggle(item.id) }
        assist.answerNow();await waitForCount(3)
        check("excluded beginning cannot reenter through long-statement continuation",!(await prompt()).contains(threeMinuteParts[0]))
        session.clearChat()
        line("AFTER_RESET_NEW_QUESTION explain a pointer",10000)
        assist.answerNow();await waitForCount(4)
        let afterReset=await prompt()
        check("Clear chat removes all working continuation and older statement context",afterReset.contains("AFTER_RESET_NEW_QUESTION") && !afterReset.contains("THREE_MINUTE_PART_") && !afterReset.contains("New topic: explain C++ reference lifetime"))

        await reset()
        assist.answer(old);await waitForCount(1)
        assist.answerNow();try? await Task.sleep(for:.milliseconds(100))
        check("no speech does not replay old card or call provider",await provider.conversations.count == 1 && session.lastFinished == nil && session.answeringTopicID == nil && !session.isAnswering)
        check("Answer keeps pill anchor and never takes desktop keyboard",overlay.pillFrame == frame && !NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
        await listening.stop();overlay.hide()
        try? JSONSerialization.data(withJSONObject:["checks":checks,"liveAIRequests":0,"audio":false,"physicalKeyboardEvents":false],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("answer-now.json"))
    }
}
