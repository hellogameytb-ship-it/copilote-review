import XCTest
@testable import CopiloteKit

final class LiveAnswerSnapshotTests: XCTestCase {
    private func line(_ text:String, at:Double) -> TranscriptLine {
        TranscriptLine(speaker:.them,text:text,start:at,end:at+2)
    }
    func test_longMonologueFocusesItsFinalQuestionAndKeepsEarlierSessionContext() throws {
        let early = line("EARLY constraint: constant space",at:0)
        let monologue = (0..<30).map { line("MONOLOGUE detail \($0)",at:3600+Double($0)*8) }
        let question = line("How do we implement this in Python?",at:3845)
        let lines = [early] + monologue + [question]
        let context = AssistContext(lines:lines)
        let snapshot = try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,provisional:[]))
        XCTAssertEqual(snapshot.latestLines.last,question)
        XCTAssertTrue(snapshot.recentLines.contains(monologue[0]))
        XCTAssertFalse(snapshot.recentLines.contains(early))
        var request = AssistQuestion(action:.answer,mode:.technical,question:snapshot.focusText,heard:[],context:context)
        request.liveSnapshot = snapshot
        var conversation = Conversation(); conversation.appendUser(.assist(request))
        let prompt = conversation.messages.flatMap { $0["content"]?.arrayValue ?? [] }.compactMap { $0["text"]?.stringValue }.joined()
        XCTAssertTrue(prompt.contains("AT THE CLICK"))
        XCTAssertTrue(prompt.contains(question.text)); XCTAssertTrue(prompt.contains(early.text))
        XCTAssertFalse(prompt.contains("Current subject:"))
    }
    func test_partialOnlySnapshotIsMarkedAndDoesNotInventFinalText() throws {
        let snapshot = try XCTUnwrap(LiveAnswerSnapshot(lines:[],context:AssistContext(),provisional:[.init(speaker:.them,text:"And what about memory")]))
        XCTAssertTrue(snapshot.latestLines.isEmpty)
        XCTAssertEqual(snapshot.focusText,"Them (provisional): And what about memory")
    }
    func test_excludedSpeechCannotReenterViaOverlappingPartial() {
        let lines = [line("PRIVATE detail",at:10)]
        var context = AssistContext(lines:lines); context.toggle(context.items[0].id)
        XCTAssertNil(LiveAnswerSnapshot(lines:lines,context:context,provisional:[.init(speaker:.them,text:"PRIVATE detail continued")]))
        XCTAssertNil(LiveAnswerSnapshot(lines:lines,context:context,provisional:[.init(speaker:.them,text:"Different interim wording")]))
    }
    func test_snapshotIsImmutableWhenNewSpeechArrives() throws {
        let lines = [line("FIRST request",at:1)]
        var context = AssistContext(lines:lines)
        let snapshot = try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,provisional:[]))
        context.refresh(lines:lines + [line("SECOND request",at:3)],captures:[],extracts:[])
        XCTAssertFalse(snapshot.focusText.contains("SECOND"))
    }
    func test_emptySpeechDoesNotFallBackToAnOldTargetOrCaptures() {
        XCTAssertNil(LiveAnswerSnapshot(lines:[],context:AssistContext(captures:[.fake("screenshot")]),provisional:[]))
        XCTAssertNil(LiveAnswerSnapshot(lines:[],context:AssistContext(),provisional:[.init(speaker:.me,text:"  ")]))
    }
}
