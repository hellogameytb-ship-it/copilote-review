import AppKit
import CopiloteKit

/// Test-only audit, compiled into a separate copy of candidate17. No audio or live provider.
@MainActor
enum DiagnosticLatencyAudit {
    static func run(folder:URL, overlay:OverlayController, settings:SettingsStore, listening:ListeningController,
                    assist:AssistController, session:SessionController, provider:RecetteProvider,
                    record:(String,Bool)->Void) async {
        guard DiagnosticAnchorFixture.isRequested,
              ProcessInfo.processInfo.environment["COPILOTE_HEADLESS_GEOMETRY"] == "1" else { return }
        var findings:[[String:Any]] = []
        func pause(_ ms:Int = 20) async { try? await Task.sleep(for:.milliseconds(ms)) }
        func until(_ predicate:() async -> Bool) async -> Bool {
            for _ in 0..<400 { if await predicate() { return true }; await pause(5) }
            return false
        }
        func reset(auto:Bool = false) async {
            await listening.stop(); session.clear(); await provider.resetConversations()
            settings.autoAnswer = auto; listening.beginRecetteConversation(); assist.select(nil)
            await pause()
        }
        func latestPrompt() async -> String {
            let conversation = await provider.conversations.last
            let messages = conversation?.messages ?? []
            let blocks:[JSONValue] = messages.flatMap { $0["content"]?.arrayValue ?? [] }
            return blocks.compactMap { $0["text"]?.stringValue }.joined(separator:"\n")
        }
        func pipeline(_ segmenter:(any TopicSegmenter)? = nil, log:AuditLog = AuditLog()) -> TopicPipeline {
            TopicPipeline(segmenter:segmenter,segmenterName:"controlled-delay") { update in
                log.append(update)
                DispatchQueue.main.async { MainActor.assumeIsolated { listening.receiveRecetteEvent(.topics(update)) } }
            }
        }
        func turn(_ text:String, speaker:Speaker = .them, at:Double = 0) -> Turn {
            Turn(speaker:speaker,text:text,start:at,end:at+2)
        }

        // Audio-clock simulation: no PCM, microphone, speaker or transcriber is opened.
        for (name,text,finalEnd,expected) in [
            ("complete","Explain binary trees.",2.9,0.8),
            ("stale final","Explain binary trees.",1.5,1.5),
            ("unfinished conjunction","Explain binary trees and",2.9,3.0),
            ("one-word follow-up","Pourquoi ?",2.9,3.0)
        ] {
            var assembler = TurnAssembler(speaker:.them)
            assembler.handle(.speechStarted(at:0)); assembler.addFinal(text,start:0,end:finalEnd); assembler.handle(.speechEnded(at:3))
            var emittedAt:Double?
            for tick in 1...350 { let now = 3 + Double(tick)/100; if !assembler.advance(to:now).isEmpty { emittedAt = now-3; break } }
            record("endpoint \(name) matches current gate",emittedAt.map { abs($0-expected) <= 0.02 } == true)
            findings.append(["scenario":name,"simulatedEndToTurnSeconds":emittedAt ?? -1,"requestsAutomaticAnswer":TurnCompletion.requestsAnswer(text)])
        }
        var noFinal = TurnAssembler(speaker:.them)
        noFinal.handle(.speechStarted(at:0)); noFinal.handle(.speechEnded(at:3))
        record("no final text has no bounded turn fallback",noFinal.advance(to:30).isEmpty)
        record("one-word French follow-up is currently not an automatic request",!TurnCompletion.requestsAnswer("Pourquoi ?") && TurnCompletion.requestsAnswer("Et pourquoi ?"))
        findings.append(["scenario":"no final transcript","turnAfter27Seconds":false])

        var language = LanguageArbiter(languages:["fr","en"])
        let french = TranscriptCandidate(language:"fr",text:"Explique les arbres binaires.",start:0,end:3,confidence:0.9)
        record("one language result waits for the other",language.add(french,receivedAt:10).isEmpty && language.advance(to:10.59).isEmpty)
        record("single-language arbitration releases after600ms",language.advance(to:10.61).count == 1)
        var paired = LanguageArbiter(languages:["fr","en"])
        _ = paired.add(french,receivedAt:10)
        let english = TranscriptCandidate(language:"en",text:"Binary trees.",start:0,end:3,confidence:0.2)
        record("aligned second language releases immediately",paired.add(english,receivedAt:10.1).first?.language == "fr")
        findings.append(["scenario":"FR/EN arbitration","singleLanguageWaitSeconds":0.6,"pollingPeriodSeconds":0.1,"alignedSecondLanguageImmediate":true])

        await reset()
        let burstLog = AuditLog(), delayed = AuditSegmenter(delayMS:120)
        let burst = pipeline(delayed,log:burstLog)
        let questions = ["Explain binary trees.","Describe database transactions.","Compare network protocols.","Estimate solar energy consumption."]
        for (index,text) in questions.enumerated() { await burst.handle(turn(text,at:Double(index)*3)) }
        let provisional = burstLog.snapshot().filter { !$0.isFinal }
        record("burst publishes every provisional card before model confirmations",provisional.count == 4 && burstLog.snapshot().allSatisfy { !$0.isFinal })
        await burst.waitForModel(); await pause()
        let final = burstLog.snapshot().filter(\.isFinal)
        record("model confirmation queue is serial",await delayed.maximumConcurrent == 1 && final.count == 4 && (final.last?.latency ?? 0) > 0.4)
        findings.append(["scenario":"four-turn burst","injectedSegmenterDelayMS":120,"provisionalMS":provisional.map { $0.latency*1000 },"confirmationMS":final.map { $0.latency*1000 }])
        let fallbackLog = AuditLog(), fallback = pipeline(AuditSegmenter(delayMS:120,fails:true),log:fallbackLog)
        await fallback.handle(turn("Explain hash tables.")); await fallback.waitForModel(); await pause()
        let fallbackRows = fallbackLog.snapshot()
        record("failed segmenter retains lexical topic and confirms fallback",fallbackRows.count == 2 && fallbackRows.last?.source.hasPrefix("lexical (fallback:") == true && fallbackRows.last?.topics.first?.isProvisional == false)
        findings.append(["scenario":"segmenter failure","updates":fallbackRows.map { ["source":$0.source,"latencyMS":$0.latency*1000] as [String:Any] }])

        await reset()
        let routeLog = AuditLog(), routing = pipeline(log:routeLog)
        let question = "Explain binary trees."
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker:.me,text:question,start:0,end:2),language:"fixture",latency:0))
        await routing.handle(turn(question,speaker:.me)); await pause()
        record("microphone-labelled question is context only, no card",listening.transcript.lines.count == 1 && routeLog.snapshot().isEmpty && listening.topics.isEmpty)
        await routing.handle(turn(question)); await pause()
        record("same system-audio-labelled question creates a card",listening.topics.count == 1)
        findings.append(["scenario":"source routing","microphoneSpeaker":"me","systemAudioSpeaker":"them","speakerDiarization":false])

        // Local 80 ms provider delay is imposed by RecetteProvider, not an AI benchmark.
        for speaking in [false,true] {
            await reset(auto:true)
            listening.receiveRecetteEvent(.speaking(.them,speaking))
            let log = AuditLog(), live = pipeline(AuditSegmenter(delayMS:400),log:log)
            let start = ProcessInfo.processInfo.systemUptime
            let historyBefore = session.history.count
            await live.handle(turn("Explain binary trees."))
            let cardArrived = await until { !listening.topics.isEmpty }
            let cardMS = (ProcessInfo.processInfo.systemUptime-start)*1000
            record("auto \(speaking) provisional card arrives",cardArrived)
            if speaking {
                await pause(180)
                record("speaking gate prevents provider work",await provider.conversations.isEmpty)
                listening.receiveRecetteEvent(.speaking(.them,false))
            }
            let textArrived = await until { session.history.count > historyBefore && session.history.first?.text.isEmpty == false }
            let firstTextMS = (ProcessInfo.processInfo.systemUptime-start)*1000
            record("auto \(speaking) first text arrives before model confirmation",textArrived && !log.snapshot().contains(where: \.isFinal))
            await live.waitForModel(); await pause()
            findings.append(["scenario":speaking ? "auto held while speaking" : "auto from provisional card","injectedSegmenterDelayMS":400,"injectedProviderDelayMS":80,"cardAfterHandleMS":cardMS,"firstTextAfterHandleMS":firstTextMS,"confirmationAfterHandleMS":(log.snapshot().last?.latency ?? 0)*1000])
        }

        await reset()
        let early = "FICTIONAL_EARLY_CONSTRAINT use constant memory."
        let late = "FICTIONAL_LATEST_DETAIL discuss implementation."
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker:.me,text:early,start:0,end:2),language:"fixture",latency:0))
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker:.them,text:late,start:4000,end:4002),language:"fixture",latency:0))
        assist.run(.answer)
        record("Answer without target completes",await until { await provider.conversations.count == 1 && !session.isAnswering })
        let fullPrompt = await latestPrompt()
        record("Answer includes both start-of-session and latest context",fullPrompt.contains(early) && fullPrompt.contains(late) && !fullPrompt.contains("Current subject:"))
        if let item = assist.context.items.first(where: { $0.label.contains(early) }) { assist.toggle(item.id) }
        assist.run(.answer)
        record("second Answer completes",await until { await provider.conversations.count == 2 && !session.isAnswering })
        record("Answer respects transcript exclusion",!(await latestPrompt()).contains(early))
        findings.append(["scenario":"Answer context","contextSpanSeconds":4002,"includesBeginningOfSession":true,"respectsExclusion":true,"ninetySecondWindowApplied":false])

        await reset()
        let old = Topic(id:"audit-old",title:"Explain binary trees",excerpt:["Explain binary trees."],createdAt:Date(),updatedAt:Date())
        assist.answer(old)
        record("first card answer completes",await until { await provider.conversations.count == 1 && !session.isAnswering })
        let cachedStart = ProcessInfo.processInfo.systemUptime
        assist.answer(old); await pause()
        record("repeat card click reuses request without provider work",await provider.conversations.count == 1)
        let cacheMS = (ProcessInfo.processInfo.systemUptime-cachedStart)*1000
        var renamed = old; renamed.title = "Binary tree algorithms"
        record("title-only correction retains version cache",session.hasCachedRequest(for:renamed))
        var changed = old; changed.version += 1; changed.excerpt.append("Explain binary trees memory complexity.")
        record("follow-up version invalidates old cache",!session.hasCachedRequest(for:changed) && !session.showCachedAnswer(for:changed))
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker:.me,text:"NEW_CONTEXT_AFTER_CACHE",start:10,end:12),language:"fixture",latency:0))
        assist.answer(old); await pause()
        let cachedPrompt = await latestPrompt()
        record("same-version cache ignores new microphone context",await provider.conversations.count == 1 && !cachedPrompt.contains("NEW_CONTEXT_AFTER_CACHE"))
        assist.run(.answer)
        record("Answer button regenerates even when card cache exists",await until { await provider.conversations.count == 2 && !session.isAnswering })
        record("regenerated Answer incorporates new context",(await latestPrompt()).contains("NEW_CONTEXT_AFTER_CACHE"))
        settings.infosysInterviewActive = true
        record("profile scope invalidates cache",!session.hasCachedRequest(for:old))
        settings.infosysInterviewActive = false
        findings.append(["scenario":"cache","observedClickPlus20msWaitMS":cacheMS,"sameVersionReuses":true,"titleOnlyReuses":true,"followUpVersionInvalidates":true,"newMicrophoneContextInvalidates":false,"profileScopeInvalidates":true,"AnswerButtonRegenerates":true])

        await reset()
        let mergeA = Topic(id:"merge-a",title:"Explain binary trees",excerpt:["Explain binary trees."],createdAt:Date(),updatedAt:Date())
        let mergeB = Topic(id:"merge-b",title:"Explain tree memory",excerpt:["Explain tree memory constraints."],createdAt:Date(),updatedAt:Date())
        assist.answer(mergeA)
        record("merge first answer completes",await until { await provider.conversations.count == 1 && !session.isAnswering })
        assist.answer(mergeB)
        record("merge second answer completes",await until { await provider.conversations.count == 2 && !session.isAnswering })
        var merged = mergeA; merged.version = 2; merged.excerpt += mergeB.excerpt
        session.follow(merged:mergeB.id,into:merged)
        record("merge relabels existing request with new topic version",session.hasCachedRequest(for:merged) && session.showCachedAnswer(for:merged))
        record("merge does not regenerate combined question",await provider.conversations.count == 2)
        findings.append(["scenario":"merge cache","newVersionMarkedCachedWithoutRegeneration":true,"providerCallsBeforeAndAfter":2])

        await reset()
        let selection = pipeline()
        await selection.handle(turn("Explain binary trees.")); await pause()
        guard let first = listening.topics.first else { record("selection fixture topic exists",false); return }
        assist.answer(first)
        record("selection initial answer completes",await until { await provider.conversations.count == 1 && !session.isAnswering })
        await selection.handle(turn("Explain binary trees memory complexity.",at:4)); await pause()
        record("selected target remains an older value after automatic updates disabled",listening.topics.first?.version == 2 && assist.target?.version == 1)
        await selection.handle(turn("Describe database transactions.",at:8)); await pause()
        assist.run(.answer)
        record("Answer with selected older topic completes",await until { await provider.conversations.count == 2 && !session.isAnswering })
        record("Answer keeps selected topic rather than first card",(await latestPrompt()).contains("Current subject: \(first.title)"))
        let newest = listening.topics.first?.id
        listening.answer(caseIndex:0)
        record("latest subject action routes to first card",await until { await provider.conversations.count == 3 && !session.isAnswering })
        record("latest subject target matches card zero",assist.target?.id == newest && newest != first.id)
        findings.append(["scenario":"selection","AnswerUsesSelectedTarget":true,"latestSubjectShortcutUsesIndexZero":true,"selectedTargetVersionCanRemainStale":true])
        await listening.stop(); overlay.hide()
        record("audit never shows or takes desktop windows",!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow })
        let report:[String:Any] = ["findings":findings,"audioUsed":false,"liveAIRequests":0,"desktopCaptured":false,"candidateProductionLogicUnchanged":true,
            "limitations":"Controlled timestamps and imposed model/provider delays; no measurement or diagnosis of the user's conversation, real ASR, network latency, physical clicks, or OS hotkeys."]
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("latency-audit.json"))
    }
}

private final class AuditLog: @unchecked Sendable {
    private let lock = NSLock()
    private var rows:[TopicUpdate] = []
    func append(_ update:TopicUpdate) { lock.withLock { rows.append(update) } }
    func snapshot() -> [TopicUpdate] { lock.withLock { rows } }
}

private actor AuditSegmenter: TopicSegmenter {
    let delayMS:Int
    let fails:Bool
    private var concurrent = 0
    private(set) var maximumConcurrent = 0
    init(delayMS:Int,fails:Bool = false) { self.delayMS = delayMS; self.fails = fails }
    func decide(turn:Turn,topics:[Topic],context:String) async throws -> TopicDecision {
        concurrent += 1; maximumConcurrent = max(maximumConcurrent,concurrent)
        defer { concurrent -= 1 }
        try await Task.sleep(for:.milliseconds(delayMS))
        if fails { throw APIFailure(type:"audit_failure",message:"Controlled failure") }
        return .new(title:turn.text)
    }
}
