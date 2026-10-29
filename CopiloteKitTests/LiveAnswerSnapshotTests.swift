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
        XCTAssertEqual(snapshot.workingLines.last,question)
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
        XCTAssertTrue(snapshot.workingLines.isEmpty)
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
    private func sentPrompt(_ snapshot: LiveAnswerSnapshot, context: AssistContext,
                            format: AnswerFormat? = nil) -> String {
        var request = AssistQuestion(action:.answer,mode:.technical,question:snapshot.focusText,
                                     heard:[],context:context,format:format)
        request.liveSnapshot = snapshot
        var conversation = Conversation();conversation.appendUser(.assist(request))
        let messageText = conversation.messages.flatMap { $0["content"]?.arrayValue ?? [] }
            .compactMap { $0["text"]?.stringValue }.joined(separator:"\n")
        let codexText = CodexPrompt.turnInput(for:conversation).compactMap { $0["text"]?.stringValue }.joined(separator:"\n")
        XCTAssertEqual(codexText,messageText,"Codex transport must receive the full working exchange unchanged")
        return codexText
    }

    func test_ninetySecondFragmentedQuestionKeepsEveryFragmentBeforeShortFollowUp() throws {
        let details = (0..<10).map { line("SETUP_FRAGMENT_\($0): preserve this constraint",at:100+Double($0)*10) }
        let lines = details + [line("What do you think?",at:195)]
        let context = AssistContext(lines:lines)
        let snapshot = try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,provisional:[],capturedAt:197))
        XCTAssertEqual(snapshot.workingLines,lines)
        let prompt = sentPrompt(snapshot,context:context)
        for detail in details { XCTAssertTrue(snapshot.focusText.contains(detail.text));XCTAssertTrue(prompt.contains(detail.text)) }
        XCTAssertTrue(prompt.contains("Resolve a short follow-up"))
        XCTAssertFalse(prompt.contains("Latest finalized speech"))
    }

    func test_acknowledgementAndUserSpeechDoNotReplaceQuestionInWorkingExchange() throws {
        let lines = [line("How would you implement a bounded queue?",at:100),
                     line("Preserve FIFO ordering and reject overflow",at:120),
                     TranscriptLine(speaker:.me,text:"I would check the capacity first",start:140,end:142),
                     line("okay",at:145)]
        let context = AssistContext(lines:lines)
        let snapshot = try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,provisional:[],capturedAt:147))
        XCTAssertEqual(snapshot.workingLines,lines)
        let prompt = sentPrompt(snapshot,context:context)
        XCTAssertTrue(prompt.contains("does not replace the question"))
        XCTAssertTrue(prompt.contains("The user's own answer is context"))
        XCTAssertTrue(prompt.contains(lines[2].labeled))
    }

    func test_workingWindowUsesTimeAndKeepsCrossingFragmentWithoutDuplicatingContext() throws {
        let old=line("OLDER_SESSION_FACT",at:0)
        let before=line("PRECEDING_STATEMENT",at:277)
        let crossing=TranscriptLine(speaker:.them,text:"CROSSING_CONSTRAINT",start:270,end:281)
        let lines=[old,crossing,before,line("CURRENT_REQUEST",at:398)]
        let context=AssistContext(lines:lines)
        let snapshot=try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,provisional:[],capturedAt:400))
        XCTAssertEqual(snapshot.workingLines,[crossing,lines[3]])
        XCTAssertEqual(snapshot.precedingLines,[before])
        let prompt=sentPrompt(snapshot,context:context)
        for item in lines { XCTAssertEqual(prompt.components(separatedBy:item.text).count-1,1) }
    }

    func test_threeMinuteStatementKeepsItsBeginningAsContinuation() throws {
        let lines=(0...18).map { line("LONG_PROBLEM_PART_\($0)_END",at:20+Double($0)*10) }
        let context=AssistContext(lines:lines)
        let snapshot=try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,provisional:[],capturedAt:202))
        XCTAssertFalse(snapshot.workingLines.contains(lines[0]))
        XCTAssertTrue(snapshot.precedingLines.contains(lines[0]))
        XCTAssertEqual(snapshot.recentLines,lines)
        let prompt=sentPrompt(snapshot,context:context)
        for item in lines { XCTAssertEqual(prompt.components(separatedBy:item.text).count-1,1) }
        XCTAssertTrue(prompt.contains("extend it with the earlier continuation"))
    }

    func test_newQuestionTakesPriorityOverOldTopicAndLexicalFormat() throws {
        let lines=[line("What is your favorite book?",at:10),
                   line("New topic: implement a C++ queue",at:150),
                   line("What happens when its capacity is reached?",at:180)]
        let context=AssistContext(lines:lines)
        let snapshot=try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,provisional:[],capturedAt:182))
        XCTAssertFalse(snapshot.focusText.contains(lines[0].text))
        XCTAssertTrue(snapshot.focusText.contains(lines[1].text))
        let prompt=sentPrompt(snapshot,context:context,format:AnswerFormat(kind:.opinion))
        XCTAssertTrue(prompt.contains("newer substantive question takes priority"))
        XCTAssertFalse(prompt.contains(Prompts.noOpinionInstruction))
        XCTAssertTrue(prompt.contains("if none is supported, offer neutral possible angles"))
        XCTAssertTrue(prompt.contains("## Complexity"))
    }

    func test_exclusionsApplyToEveryTimeBandAndProvisionalSpeech() throws {
        let lines=[line("PRIVATE_OLD",at:0),line("PRIVATE_CONTINUATION",at:200),
                   line("PRIVATE_WORKING",at:390),line("ALLOWED_QUESTION",at:398)]
        var context=AssistContext(lines:lines)
        for item in context.items where item.label.contains("PRIVATE_") { context.toggle(item.id) }
        let snapshot=try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:context,
            provisional:[.init(speaker:.them,text:"PRIVATE_WORKING continued")],capturedAt:400))
        let prompt=sentPrompt(snapshot,context:context)
        XCTAssertFalse(prompt.contains("PRIVATE_"))
        XCTAssertTrue(prompt.contains("ALLOWED_QUESTION"))
    }

    func test_silenceDoesNotMoveWindowBackToAnOldQuestion() {
        let lines=[line("OLD_QUESTION",at:100)]
        XCTAssertNil(LiveAnswerSnapshot(lines:lines,context:AssistContext(lines:lines),provisional:[],capturedAt:300))
    }

    func test_provisionalFollowUpKeepsFinalizedWorkingStatement() throws {
        let lines=[line("Explain this queue with a maximum capacity of ten",at:100),
                   line("The producer must not block",at:150)]
        let snapshot=try XCTUnwrap(LiveAnswerSnapshot(lines:lines,context:AssistContext(lines:lines),
            provisional:[.init(speaker:.them,text:"and when it is full")],capturedAt:180))
        XCTAssertTrue(snapshot.focusText.contains(lines[0].text))
        XCTAssertTrue(snapshot.focusText.hasSuffix("Them (provisional): and when it is full"))
    }

}
