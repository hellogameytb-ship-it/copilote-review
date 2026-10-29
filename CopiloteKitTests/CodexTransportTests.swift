import XCTest
@testable import CopiloteKit

private final class TransportEvents: @unchecked Sendable {
    private let lock=NSLock();private var events:[CodexRequestDiagnostic]=[]
    func add(_ e:CodexRequestDiagnostic) { lock.withLock { events.append(e) } }
    var values:[CodexRequestDiagnostic] { lock.withLock { events } }
}
final class CodexTransportTests:XCTestCase {
    private func fixture() throws -> (URL,CodexAppServer,TransportEvents) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("copilote-fake-rpc-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let executable=root.appendingPathComponent("fake.py")
        try Self.script.write(to:executable,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
        let events=TransportEvents()
        let server=CodexAppServer(executable:executable,workingDirectory:root.appendingPathComponent("work"),privateDirectory:root.appendingPathComponent("private"),loadUserConfig:{nil},scheduler:CodexRequestScheduler(spacing:0,backgroundSpacing:0,jitter:{0}),onDiagnostic:events.add)
        return(root,server,events)
    }
    private func request(_ text:String,work:CodexWork = .manual,timeout:Duration = .seconds(2))->CodexAppServer.TurnRequest {
        .init(model:"fixture-model",serviceTier:nil,instructions:"synthetic",input:[["type":"text","text":.string(text)]],timeout:timeout,work:work)
    }
    private func trace(_ root:URL)->[String] { ((try? String(contentsOf:root.appendingPathComponent("fake.trace"),encoding:.utf8)) ?? "").split(separator:"\n").map(String.init) }
    private func wait(_ marker:String,_ root:URL) async throws {
        for _ in 0..<5000 { if trace(root).contains(marker) { return };try await Task.sleep(for:.milliseconds(2)) }
        throw NSError(domain:"Fixture",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing \(marker), trace: \(trace(root))"])
    }
    func test429InterruptsUpstreamRetryAndAllLaterWorkIsHeldLocally() async throws {
        let(root,server,events)=try fixture();defer { server.terminateNow();try? FileManager.default.removeItem(at:root) }
        do { _=try await server.run(request("limited",work:.grouping)) { _ in };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.statusCode,429);XCTAssertEqual(e.retryAfter,60) }
        do { _=try await server.run(request("manual")) { _ in };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.statusCode,429) }
        let lines=trace(root)
        XCTAssertEqual(lines.filter { $0.hasPrefix("start:") },["start:limited"])
        XCTAssertTrue(lines.contains("interrupt:t1"));XCTAssertTrue(lines.contains("terminal:t1"))
        XCTAssertTrue(events.values.contains { $0.upstreamRetrying && $0.statusCode == 429 && $0.retryAfterSeconds == 60 })
        XCTAssertTrue(events.values.contains { $0.phase == "failed" && $0.action == CodexWork.manual.label })
    }
    func testManualWaitsForInterruptedTerminalAndDropsLateDeltas() async throws {
        let(root,server,_)=try fixture();defer { server.terminateNow();try? FileManager.default.removeItem(at:root) }
        let deltas=TransportText()
        let group=Task { try await server.run(request("block",work:.grouping)) { text in await deltas.add(text) } }
        try await wait("start:block",root)
        let manual=Task { try await server.run(request("manual")) { _ in } }
        let answer=try await manual.value;XCTAssertEqual(answer,"fixture answer")
        do { _=try await group.value;XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        let lines=trace(root)
        XCTAssertLessThan(try XCTUnwrap(lines.firstIndex(of:"terminal:t1")),try XCTUnwrap(lines.firstIndex(of:"start:manual")))
        let text=await deltas.text;XCTAssertFalse(text.contains("STALE"))
    }
    func testCancellationBeforeThreadAcknowledgementNeverStartsTurn() async throws {
        let(root,server,_)=try fixture();defer { server.terminateNow();try? FileManager.default.removeItem(at:root) }
        let slow=CodexAppServer.TurnRequest(model:"slow-thread",serviceTier:nil,instructions:"synthetic",input:[],timeout:.seconds(2),work:.grouping)
        let task=Task { try await server.run(slow) { _ in } }
        try await wait("thread:t1",root);task.cancel()
        do { _=try await task.value;XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        try await wait("unsubscribe:t1",root)
        XCTAssertFalse(trace(root).contains { $0.hasPrefix("start:") })
    }
    func testTimeoutInterruptsAndNextExplicitRequestCanRecover() async throws {
        let(root,server,events)=try fixture();defer { server.terminateNow();try? FileManager.default.removeItem(at:root) }
        do { _=try await server.run(request("block",timeout:.milliseconds(40))) { _ in };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.category,.timeout) }
        let result=try await server.run(request("manual")) { _ in };XCTAssertEqual(result,"fixture answer")
        XCTAssertTrue(events.values.contains { $0.category == "timeout" })
    }
    func testAuthenticationAndProcessFailureHaveDistinctDiagnosticCategories() async throws {
        let(root,server,events)=try fixture();defer { server.terminateNow();try? FileManager.default.removeItem(at:root) }
        do { _=try await server.run(request("auth")) { _ in };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.category,.authentication);XCTAssertEqual(e.statusCode,401) }
        do { _=try await server.run(request("exit")) { _ in };XCTFail() }
        catch let e as CodexFailure { XCTAssertEqual(e.category,.network) }
        XCTAssertTrue(events.values.contains { $0.statusCode == 401 })
        XCTAssertTrue(events.values.contains { $0.category == "network" && $0.statusCode == nil })
    }
    func testCancellationWhileTurnStartAcknowledgementIsPendingInterruptsAfterAcknowledgement() async throws {
        let(root,server,_)=try fixture();defer { server.terminateNow();try? FileManager.default.removeItem(at:root) }
        let old=Task { try await server.run(request("slow-turn",work:.grouping)) { _ in } }
        try await wait("start:slow-turn",root);old.cancel()
        let manual=Task { try await server.run(request("manual")) { _ in } }
        do { _=try await old.value;XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        _=try await manual.value
        let lines=trace(root)
        XCTAssertTrue(lines.contains("interrupt:t1"))
        XCTAssertLessThan(try XCTUnwrap(lines.firstIndex(of:"terminal:t1")),try XCTUnwrap(lines.firstIndex(of:"start:manual")))
    }
    func testUnconfirmedInterruptionTerminatesOwnedTransportBeforeRecovery() async throws {
        let(root,server,_)=try fixture();defer { server.terminateNow();try? FileManager.default.removeItem(at:root) }
        let old=Task { try await server.run(request("ignore-interrupt",work:.grouping,timeout:.seconds(10))) { _ in } }
        try await wait("start:ignore-interrupt",root)
        let manual=Task { try await server.run(request("manual")) { _ in } }
        do { _=try await old.value;XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        _=try? await manual.value
        try await wait("transport-terminated",root)
        let lines=trace(root)
        if let start=lines.firstIndex(of:"start:manual") { XCTAssertLessThan(try XCTUnwrap(lines.firstIndex(of:"transport-terminated")),start) }
        try await Task.sleep(for:.milliseconds(50))
        let result=try await server.run(request("manual")) { _ in };XCTAssertEqual(result,"fixture answer")
    }
    private static let script = #"""
#!/usr/bin/python3
import json,sys,threading,pathlib,os,signal
lock=threading.RLock()
trace=pathlib.Path(__file__).with_suffix('.trace')
threads=0
modes={}

def mark(s):
    with lock:
        with trace.open('a') as f:f.write(s+'\n')
def send(v):
    with lock:print(json.dumps(v),flush=True)
def terminal(t):
    mark('terminal:'+t)
    send({'method':'item/agentMessage/delta','params':{'threadId':t,'delta':'STALE'}})
    send({'method':'turn/completed','params':{'threadId':t,'turn':{'status':'interrupted'}}})
signal.signal(signal.SIGTERM,lambda *_:(mark('transport-terminated'),sys.exit(0)))
for line in sys.stdin:
    m=json.loads(line);method=m.get('method');i=m.get('id');p=m.get('params',{});mark('rpc:'+str(method))
    if method=='initialize':send({'id':i,'result':{}})
    elif method=='thread/start':
        threads+=1;t='t'+str(threads);mark('thread:'+t)
        reply={'id':i,'result':{'thread':{'id':t}}}
        if p.get('model')=='slow-thread':threading.Timer(.12,lambda reply=reply:send(reply)).start()
        else:send(reply)
    elif method=='turn/start':
        t=p['threadId'];kind=p['input'][0]['text'];mark('start:'+kind)
        modes[t]=kind
        ack={'id':i,'result':{'turn':{'id':'turn-'+t}}}
        if kind=='slow-turn':threading.Timer(.12,lambda ack=ack:send(ack)).start()
        else:send(ack)
        if kind=='limited':send({'method':'error','params':{'threadId':t,'willRetry':True,'error':{'message':'fixture limit','codexErrorInfo':{'httpConnectionFailed':{'httpStatusCode':429}},'additionalDetails':{'retry_after':60}}}})
        elif kind=='auth':send({'method':'turn/completed','params':{'threadId':t,'turn':{'status':'failed','error':{'message':'fixture access refused','codexErrorInfo':{'httpConnectionFailed':{'httpStatusCode':401}}}}}})
        elif kind=='exit':os._exit(0)
        elif kind not in ['block','slow-turn','ignore-interrupt']:
            send({'method':'item/completed','params':{'threadId':t,'item':{'type':'agentMessage','text':'fixture answer'}}})
            send({'method':'turn/completed','params':{'threadId':t,'turn':{'status':'completed'}}})
    elif method=='turn/interrupt':
        t=p['threadId'];mark('interrupt:'+t);send({'id':i,'result':{}})
        if modes.get(t)!='ignore-interrupt':threading.Timer(.08,lambda t=t:terminal(t)).start()
    elif method=='thread/unsubscribe':mark('unsubscribe:'+p['threadId']);send({'id':i,'result':{}})
"""#
}
private actor TransportText { var text="";func add(_ value:String) { text+=value } }
