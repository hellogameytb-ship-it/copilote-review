import XCTest
@testable import CopiloteKit

final class ChatContextTests: XCTestCase {
    func test_budgetIncludesActualQuestionsAndKeepsRecentPairsBounded() {
        let rows = (0..<30).map { (question: "QUESTION_\($0)", answer: "ANSWER_\($0)") }
        let text = ChatContextBudget.previousExchanges(rows)
        XCTAssertFalse(text.contains("QUESTION_23"))
        XCTAssertTrue(text.contains("QUESTION_24")); XCTAssertTrue(text.contains("ANSWER_29"))
        let large = ChatContextBudget.previousExchanges((0..<30).map { _ in (String(repeating:"q",count:9000),String(repeating:"a",count:9000)) })
        XCTAssertLessThanOrEqual(large.count, ChatContextBudget.maximumCharacters)
    }

    func test_resetRejectsOldLinesTurnsAndLateNoncooperativeTopicDecisions() async throws {
        let segmenter = ResetSegmenter()
        let pipeline = TopicPipeline(segmenter:segmenter,segmenterName:"fixture") { _ in }
        await pipeline.add(TranscriptLine(speaker:.them,text:"OLD_CONTEXT",start:1,end:2))
        await pipeline.handle(Turn(speaker:.them,text:"Explain binary trees?",start:1,end:2))
        for _ in 0..<100 { if await segmenter.started { break };try await Task.sleep(for:.milliseconds(2)) }
        await pipeline.resetContext(after:10)
        await pipeline.add(TranscriptLine(speaker:.them,text:"OLD_LATE_CONTEXT",start:2,end:12))
        await pipeline.handle(Turn(speaker:.them,text:"Explain old algorithms?",start:2,end:12))
        await pipeline.add(TranscriptLine(speaker:.them,text:"FRESH_CONTEXT",start:11,end:12))
        await pipeline.handle(Turn(speaker:.them,text:"Explain new hash tables?",start:11,end:12))
        await pipeline.waitForModel()
        try await Task.sleep(for:.milliseconds(100))
        let topics = await pipeline.board.topics
        let lines = await pipeline.transcript.lines
        XCTAssertEqual(lines.map(\.text),["FRESH_CONTEXT"])
        XCTAssertEqual(topics.count,1)
        XCTAssertEqual(topics.first?.title,"NEW_DECISION")
        let contexts = await segmenter.contexts
        XCTAssertFalse(contexts.last?.contains("OLD_CONTEXT") ?? true)
    }
}

private actor ResetSegmenter: TopicSegmenter {
    var started = false
    var contexts: [String] = []
    func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision {
        contexts.append(context)
        if !started {
            started = true
            _ = await Task.detached { try? await Task.sleep(for:.milliseconds(80)) }.value
            return .new(title:"OLD_DECISION")
        }
        return .new(title:"NEW_DECISION")
    }
}
