import AppKit
import CopiloteKit

/// Native UI and controller checks with a fake provider and sanitized synthetic diagnostics.
@MainActor
enum DiagnosticRequestReliability {
    static func run(folder:URL,overlay:OverlayController,settings:SettingsStore,listening:ListeningController,
                    assist:AssistController,session:SessionController,providers:ProviderController,
                    provider:RecetteProvider,record:(String,Bool)->Void) async {
        guard DiagnosticAnchorFixture.isRequested,let web=overlay.readingArea as? ResponseWebView else { return }
        var checks:[[String:Any]]=[]
        func check(_ name:String,_ passed:Bool) { checks.append(["name":name,"passed":passed]);record(name,passed) }
        func pause(_ ms:Int=120) async { try? await Task.sleep(for:.milliseconds(ms)) }
        func finish() async { await pause(20);for _ in 0..<400 { if !session.isAnswering { break };await pause(5) };await pause() }
        func contains(_ text:String) async -> Bool {
            let literal=String(data:try! JSONEncoder().encode(text),encoding:.utf8)!
            return (try? await web.evaluateJavaScript("document.getElementById('answer').innerText.includes(\(literal))")) as? Bool == true
        }
        await listening.stop();session.clear();await provider.resetConversations();settings.autoAnswer=false
        WindowPrivacy.authorizeFromUserGesture();overlay.present();overlay.reveal()
        let panel=NSApp.windows.first { $0.windowNumber == overlay.windowNumbers[1] }
        let frame=panel?.frame,pill=overlay.pillFrame
        let notes=session.stickyNotes.notes,profile=settings.infosysInterviewContext,prefs=settings.answerPreferences
        await provider.replyNext("PREVIOUS_SUCCESSFUL_ANSWER")
        assist.askText="Synthetic first question";assist.submitAsk();await finish()
        let previous=session.lastFinished
        await provider.failNext(CodexFailure.rateLimited(retryAfter:45))
        assist.askText="RECOVERABLE_SYNTHETIC_DRAFT";assist.submitAsk();await finish()
        check("429 retains the last successful answer value",session.lastFinished == previous && previous != nil)
        check("failed Ask restores its draft without starting another request",await provider.conversations.count == 2 && assist.askText == "RECOVERABLE_SYNTHETIC_DRAFT")
        let priorVisible=await contains("PREVIOUS_SUCCESSFUL_ANSWER"),errorVisible=await contains("request limited (429)")
        check("chat retains prior answer and shows a readable 429",priorVisible && errorVisible)
        check("Ask uses manual scheduling context",await provider.lastWork == .ask)
        let count=session.history.count
        let event=CodexRequestDiagnostic(requestID:UUID(),work:.grouping,model:"fixture-model",phase:"upstream retry",error:CodexFailure.rateLimited(retryAfter:45),upstreamRetrying:true)
        providers.recordDiagnostic(event);await pause()
        check("background error appears inline without replacing chat or draft",session.latestProviderDiagnostic == event && session.history.count == count && assist.askText == "RECOVERABLE_SYNTHETIC_DRAFT" && session.lastFinished == previous)
        check("error banner keeps panel origin and pill anchor",panel?.frame.origin == frame?.origin && overlay.pillFrame == pill)
        check("background error includes timestamp action model status delay and correlation ID",providers.diagnosticHistory.text.contains(event.requestID.uuidString) && providers.diagnosticHistory.text.contains("Topic grouping") && providers.diagnosticHistory.text.contains("fixture-model") && providers.diagnosticHistory.text.contains("HTTP 429") && providers.diagnosticHistory.text.contains("45s"))
        let board=NSPasteboard.withUniqueName();defer { board.releaseGlobally() }
        Clipboard.copy(providers.diagnosticHistory.text,to:board)
        check("diagnostic details can be copied through an isolated pasteboard",board.string(forType:.string) == providers.diagnosticHistory.text)
        await provider.failNext(CodexFailure(message:"Denied",category:.authentication,statusCode:401),after:.milliseconds(60))
        assist.askText="OLD_TYPED_DRAFT";assist.submitAsk();await pause(20);assist.askText="NEW_USER_DRAFT";await finish()
        check("a failure never overwrites a newer user draft",assist.askText == "NEW_USER_DRAFT")
        check("authentication error does not erase the previous answer",session.lastFinished == previous)
        let failures:[CodexFailure]=[.init(message:"synthetic timeout",category:.timeout),.init(message:"synthetic disconnect",category:.network),.init(message:"synthetic access",category:.authentication,statusCode:403)]
        let before=providers.diagnosticHistory.entries.count
        let tasks=failures.map { failure in Task { @MainActor in providers.recordDiagnostic(CodexRequestDiagnostic(requestID:UUID(),work:.automaticAnswer,model:"fixture-model",phase:"failed",error:failure)) } }
        for task in tasks { await task.value }
        check("concurrent errors retain separate correlated diagnostics",providers.diagnosticHistory.entries.count == before+3 && Set(providers.diagnosticHistory.entries.suffix(3).map(\.requestID)).count == 3)
        let newest=session.latestProviderDiagnostic
        providers.recordDiagnostic(CodexRequestDiagnostic(requestID:UUID(),work:.grouping,model:"fixture-model",phase:"failed",error:CodexFailure.rateLimited(retryAfter:30),timestamp:Date(timeIntervalSince1970:1)))
        check("late error delivery cannot replace a newer error banner",session.latestProviderDiagnostic == newest)
        let banner=session.latestProviderDiagnostic
        providers.recordDiagnostic(CodexRequestDiagnostic(requestID:UUID(),work:.grouping,model:"fixture-model",phase:"cancelled",error:CancellationError()))
        check("expected cancellation is recorded without showing a new failure banner",session.latestProviderDiagnostic == banner && providers.diagnosticHistory.entries.last?.category == "cancelled")
        for _ in 0..<210 { providers.recordDiagnostic(CodexRequestDiagnostic(requestID:UUID(),work:.grouping,model:"fixture-model",phase:"failed",error:CodexFailure(message:"SECRET_PROMPT_TOKEN_CV",category:.network))) }
        let data=try? JSONEncoder().encode(providers.diagnosticHistory)
        let text=data.map { String(decoding:$0,as:UTF8.self) } ?? ""
        check("diagnostic history stays bounded and excludes prompts errors and profile content",providers.diagnosticHistory.entries.count == 200 && !text.contains("SECRET_PROMPT_TOKEN_CV") && !text.contains("RECOVERABLE_SYNTHETIC_DRAFT") && !text.contains("PREVIOUS_SUCCESSFUL_ANSWER"))
        session.latestProviderDiagnostic=nil
        check("error banner can be dismissed without changing chat",session.latestProviderDiagnostic == nil && session.history.count == count+1)
        await provider.replyNext("EXPLICIT_RECOVERY_ANSWER")
        assist.askText="Retry explicitly";assist.submitAsk();await finish()
        check("explicit request recovers without switching provider",session.lastFinished?.text == "EXPLICIT_RECOVERY_ANSWER" && provider.kind == .codex)
        check("error handling preserves profile notes and answer preferences",settings.infosysInterviewContext == profile && session.stickyNotes.notes == notes && settings.answerPreferences == prefs)
        check("reliability fixture never takes focus displays windows or starts listening",!NSApp.isActive && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow } && !listening.isListening)
        try? JSONSerialization.data(withJSONObject:["checks":checks,"liveAIRequests":0,"desktopCaptured":false,"audioCaptured":false,"privateInterviewDataUsed":false,"generalPasteboardUsed":false],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("request-reliability.json"))
        session.clear();session.latestProviderDiagnostic=nil;overlay.hide()
    }
}
