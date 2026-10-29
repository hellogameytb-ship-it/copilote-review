import XCTest
@testable import CopiloteKit

private actor WorkProbe {
    var started:[String]=[]
    var active=0
    var maximum=0
    var gates:[String:CheckedContinuation<Void,Never>]=[:]
    func run(_ name:String,blocked:Bool=false) async -> String {
        started.append(name);active+=1;maximum=max(maximum,active)
        if blocked { await withCheckedContinuation { gates[name]=$0 } }
        active-=1;return name
    }
    func release(_ name:String) { gates.removeValue(forKey:name)?.resume() }
    func wait(_ name:String) async { for _ in 0..<500 { if started.contains(name) { return };try? await Task.sleep(for:.milliseconds(1)) } }
}
private final class FakeRequestClock: @unchecked Sendable {
    private let lock=NSLock();private var time:Double=100
    func now()->Double { lock.withLock { time } }
    func advance(_ amount:Double) { lock.withLock { time+=amount } }
}
final class CodexSchedulingTests:XCTestCase {
    func testManualPreemptsBackgroundButDoesNotOverlapItsCleanup() async throws {
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0),probe=WorkProbe()
        let background=Task { try await gate.run(work:.grouping) { await probe.run("group",blocked:true) } }
        await probe.wait("group")
        let manual=Task { try await gate.run(work:.manual) { await probe.run("manual") } }
        try await Task.sleep(for:.milliseconds(30))
        let before=await probe.started;XCTAssertEqual(before,["group"],"cancelled background must release upstream before manual begins")
        await probe.release("group")
        do { _=try await background.value;XCTFail("superseded result must not escape") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let result=try await manual.value;let max=await probe.maximum
        XCTAssertEqual(result,"manual");XCTAssertEqual(max,1)
    }
    func testPendingBackgroundCoalescesAndManualHasPriority() async throws {
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0),probe=WorkProbe()
        let first=Task { try await gate.run(work:.manual) { await probe.run("first",blocked:true) } }
        await probe.wait("first")
        let old=Task { try await gate.run(work:.automaticAnswer) { await probe.run("obsolete") } }
        try await Task.sleep(for:.milliseconds(10))
        let newest=Task { try await gate.run(work:.automaticAnswer) { await probe.run("newest") } }
        let manual=Task { try await gate.run(work:.manual) { await probe.run("manual") } }
        try await Task.sleep(for:.milliseconds(10));await probe.release("first")
        _=try await first.value;_=try await manual.value;_=try await newest.value
        do { _=try await old.value;XCTFail("obsolete must be dropped") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let starts=await probe.started;XCTAssertEqual(starts,["first","manual","newest"])
    }
    func testQueuedCancellationNeverStartsOperation() async throws {
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0),probe=WorkProbe()
        let first=Task { try await gate.run(work:.manual) { await probe.run("first",blocked:true) } }
        await probe.wait("first")
        let cancelled=Task { try await gate.run(work:.manual) { await probe.run("cancelled") } }
        try await Task.sleep(for:.milliseconds(10));cancelled.cancel()
        do { _=try await cancelled.value;XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        await probe.release("first");_=try await first.value
        let starts=await probe.started;XCTAssertEqual(starts,["first"])
    }
    func test429SharedCooldownHonorsHintThenRecoversWithoutAutoRetry() async throws {
        let clock=FakeRequestClock(),probe=WorkProbe()
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0,now:clock.now,jitter:{0})
        do { _=try await gate.run(work:.grouping) { throw CodexFailure.rateLimited(retryAfter:90) };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.retryAfter,90) }
        for work in [CodexWork.manual,.grouping,.automaticAnswer] {
            do { _=try await gate.run(work:work) { await probe.run("must not run") };XCTFail() }
            catch let e as CodexFailure { XCTAssertEqual(e.statusCode,429);XCTAssertEqual(e.retryAfter,90) }
        }
        let untouched=await probe.started;XCTAssertTrue(untouched.isEmpty)
        clock.advance(90)
        let result=try await gate.run(work:.manual) { await probe.run("recovered") };XCTAssertEqual(result,"recovered")
        do { _=try await gate.run(work:.manual) { throw CodexFailure.rateLimited(retryAfter:nil) };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.retryAfter,30,"success resets escalating cooldown") }
        clock.advance(30)
        do { _=try await gate.run(work:.manual) { throw CodexFailure.rateLimited(retryAfter:nil) };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.retryAfter,60) }
    }
    func test429RejectsAlreadyQueuedWorkInsteadOfReplayingIt() async throws {
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0,jitter:{0}),probe=WorkProbe()
        let first=Task { try await gate.run(work:.manual) { _=await probe.run("first",blocked:true);throw CodexFailure.rateLimited(retryAfter:1) } }
        await probe.wait("first")
        let queued=Task { try await gate.run(work:.grouping) { await probe.run("queued") } }
        try await Task.sleep(for:.milliseconds(10));await probe.release("first")
        do { _=try await first.value;XCTFail() } catch {}
        do { _=try await queued.value;XCTFail() } catch let e as CodexFailure { XCTAssertEqual(e.statusCode,429) }
        let starts=await probe.started;XCTAssertEqual(starts,["first"])
    }
    func testBoundedQueueRejectsExcessManualWork() async throws {
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0),probe=WorkProbe()
        let first=Task { try await gate.run(work:.manual) { await probe.run("first",blocked:true) } }
        await probe.wait("first")
        let waiting=(0..<9).map { n in Task { try await gate.run(work:.manual) { await probe.run("\(n)") } } }
        try await Task.sleep(for:.milliseconds(30));await probe.release("first");_=try await first.value
        var rejected=0
        for task in waiting { do { _=try await task.value } catch let e as CodexFailure { XCTAssertEqual(e.category,.busy);rejected+=1 } }
        XCTAssertEqual(rejected,3)
    }
    func testErrorMetadataAndJournalNeverCopySensitivePayloads() throws {
        let raw:JSONValue=["message":"PRIVATE_PROMPT token-secret", "codexErrorInfo":["httpConnectionFailed":["httpStatusCode":429]],"additionalDetails":["headers":["Retry-After":"120"]]]
        let failure=CodexFailure.from(raw)
        XCTAssertEqual(failure.statusCode,429);XCTAssertEqual(failure.retryAfter,120)
        let nested=CodexFailure.from(["message":"HTTP 429","additionalDetails":"{\"headers\":{\"Retry-After\":\"75\"}}"])
        XCTAssertEqual(nested.retryAfter,75)
        XCTAssertNil(CodexFailure(message:"request 429 used 429 tokens").statusCode)
        XCTAssertEqual(CodexFailure(message:"exceeded retry limit, last status429 Too Many Requests").category,.rateLimit)
        XCTAssertEqual(CodexFailure.from(["message":"denied","status":401]).category,.authentication)
        var log=CodexDiagnosticHistory()
        for _ in 0..<230 { log.append(CodexRequestDiagnostic(requestID:UUID(),work:.grouping,model:"model-name",phase:"failed",error:failure)) }
        XCTAssertEqual(log.entries.count,200)
        let text=String(decoding:try JSONEncoder().encode(log),as:UTF8.self)
        XCTAssertFalse(text.contains("PRIVATE_PROMPT"));XCTAssertFalse(text.contains("token-secret"));XCTAssertTrue(text.contains("429"))
    }
    func testStructuredRetrySignalSurvivesParsing() {
        let message=CodexMessage(line:#"{"method":"error","params":{"threadId":"t","willRetry":true,"error":{"message":"busy","codexErrorInfo":{"httpConnectionFailed":{"httpStatusCode":429}},"additionalDetails":{"retry_after":45}}}}"#)
        guard case let .providerFailure(thread,_,failure,retrying,terminal)=message else { return XCTFail("metadata lost") }
        XCTAssertEqual(thread,"t");XCTAssertEqual(failure.retryAfter,45);XCTAssertEqual(failure.statusCode,429);XCTAssertTrue(retrying);XCTAssertFalse(terminal)
        let end=CodexMessage(line:#"{"method":"turn/completed","params":{"threadId":"t","turn":{"status":"failed","error":{"message":"HTTP 401 unauthorized"}}}}"#)
        guard case let .providerFailure(_,_,auth,_,ended)=end else { return XCTFail("terminal failure lost") }
        XCTAssertTrue(ended);XCTAssertEqual(auth.category,.authentication)
    }
}

private actor CoalescingSegmenter:TopicSegmenter {
    nonisolated var coalescesPendingTurns:Bool { true }
    var requests:[String]=[]
    var gate:CheckedContinuation<Void,Never>?
    func decide(turn:Turn,topics:[Topic],context:String) async throws -> TopicDecision {
        requests.append(turn.text)
        if requests.count == 1 { await withCheckedContinuation { gate=$0 } }
        return .new(title:"Synthetic title")
    }
    func open() { gate?.resume();gate=nil }
    func wait() async { for _ in 0..<500 { if gate != nil { return };try? await Task.sleep(for:.milliseconds(1)) } }
}
final class CodexTopicBackpressureTests:XCTestCase {
    func testBurstKeepsImmediateTopicsButOnlyNewestPendingModelDecision() async {
        let segmenter=CoalescingSegmenter()
        let pipeline=TopicPipeline(segmenter:segmenter,segmenterName:"fixture") { _ in }
        await pipeline.handle(Turn(speaker:.them,text:"Explain memory allocation?",start:1,end:2))
        await segmenter.wait()
        for n in 2...15 { await pipeline.handle(Turn(speaker:.them,text:"Explain synthetic algorithm number \(n)?",start:Double(n*2),end:Double(n*2+1))) }
        await segmenter.open();await pipeline.waitForModel()
        let requests=await segmenter.requests
        XCTAssertEqual(requests.count,2)
        XCTAssertTrue(requests.last?.contains("15") == true)
        let board=await pipeline.board.topics;XCTAssertFalse(board.isEmpty)
    }
    func testResetDoesNotLetOldWorkerConsumeNewQueue() async {
        let segmenter=CoalescingSegmenter()
        let pipeline=TopicPipeline(segmenter:segmenter,segmenterName:"fixture") { _ in }
        await pipeline.handle(Turn(speaker:.them,text:"Explain old request?",start:1,end:2));await segmenter.wait()
        await pipeline.resetContext(after:10)
        await pipeline.handle(Turn(speaker:.them,text:"Explain fresh request?",start:11,end:12))
        await segmenter.open();await pipeline.waitForModel()
        let requests=await segmenter.requests;XCTAssertEqual(requests.count,2)
        let topics=await pipeline.board.topics
        XCTAssertFalse(topics.flatMap(\.excerpt).joined().contains("old request"))
    }
}

extension CodexSchedulingTests {
    func testKnownAccountFailureStopsBackgroundWithoutInventingHTTPCode() async throws {
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0),probe=WorkProbe()
        let failure=CodexFailure.from(["message":"fixture usage limit","codexErrorInfo":"UsageLimitExceeded"])
        XCTAssertEqual(failure.category,.usageLimit);XCTAssertNil(failure.statusCode)
        do { _=try await gate.run(work:.manual) { throw failure };XCTFail() } catch {}
        do { _=try await gate.run(work:.grouping) { await probe.run("must not run") };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.category,.usageLimit);XCTAssertNil(e.statusCode) }
        let result=try await gate.run(work:.manual) { await probe.run("explicit account recovery") }
        XCTAssertEqual(result,"explicit account recovery")
    }
    func testProviderQuotaCodeOutranksGeneric429AndPreservesRPCCode() {
        let error:JSONValue=["code":-32000,"message":"{\"status\":429,\"error\":{\"code\":\"insufficient_quota\",\"message\":\"fixture\"}}","codexErrorInfo":["httpConnectionFailed":["httpStatusCode":429]]]
        for _ in 0..<20 {
            let parsed=CodexFailure.from(error)
            XCTAssertEqual(parsed.category,.usageLimit);XCTAssertEqual(parsed.providerCode,"insufficient_quota");XCTAssertEqual(parsed.statusCode,429);XCTAssertEqual(parsed.rpcCode,-32000)
        }
        let date=Date(timeIntervalSince1970:0)
        XCTAssertEqual(CodexFailure.from(["message":"HTTP 429","headers":["Retry-After":"Thu, 01 Jan 1970 00:01:30 GMT"]],now:date).retryAfter,90)
    }
    func testStaleBackgroundIsDiscardedAfterManualWork() async throws {
        let clock=FakeRequestClock(),probe=WorkProbe()
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0,now:clock.now,jitter:{0})
        let first=Task { try await gate.run(work:.manual) { await probe.run("first",blocked:true) } }
        await probe.wait("first")
        let stale=Task { try await gate.run(work:.grouping) { await probe.run("stale") } }
        try await Task.sleep(for:.milliseconds(10));clock.advance(21);await probe.release("first");_=try await first.value
        do { _=try await stale.value;XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        let starts=await probe.started;XCTAssertEqual(starts,["first"])
    }
    func testBackgroundSpacingDoesNotDelayManualPriority() async throws {
        let gate=CodexRequestScheduler(spacing:0,backgroundSpacing:0.2),probe=WorkProbe()
        _=try await gate.run(work:.grouping) { await probe.run("first") }
        let next=Task { try await gate.run(work:.automaticAnswer) { await probe.run("background") } }
        try await Task.sleep(for:.milliseconds(10))
        let time=ProcessInfo.processInfo.systemUptime
        _=try await gate.run(work:.ask) { await probe.run("manual") }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-time,0.15)
        _=try await next.value
        let starts=await probe.started;XCTAssertEqual(starts,["first","manual","background"])
    }
}

extension CodexSchedulingTests {
    func testConcurrentDiagnosticsRemainChronologicalEvenIfDeliveredLate() {
        var log=CodexDiagnosticHistory()
        let early=CodexRequestDiagnostic(requestID:UUID(),work:.grouping,model:"fixture",phase:"failed",error:CodexFailure.rateLimited(retryAfter:30),timestamp:Date(timeIntervalSince1970:100))
        let later=CodexRequestDiagnostic(requestID:UUID(),work:.manual,model:"fixture",phase:"failed",error:CodexFailure(message:"timeout",category:.timeout),timestamp:Date(timeIntervalSince1970:200))
        log.append(later);log.append(early)
        XCTAssertEqual(log.entries.map(\.requestID),[early.requestID,later.requestID])
    }
}
