import XCTest
@testable import CopiloteKit

final class InterviewSessionTests: XCTestCase {
    func test_sixtyFiveMinuteSessionRetainsEarlyConstraintsAndBothVoices() throws {
        var memory = TranscriptBuffer()
        memory.append(TranscriptLine(speaker: .them, text: "Use Python and constant extra space throughout this interview.", start: 0, end: 4))
        memory.append(TranscriptLine(speaker: .me, text: "I built Orion in Swift. We have no measured speedup yet.", start: 5, end: 9))
        for minute in 1...65 {
            memory.append(TranscriptLine(speaker: minute % 2 == 0 ? .me : .them, text: "Session detail at minute \(minute).", start: Double(minute * 60), end: Double(minute * 60 + 5)))
            memory.prune(now: Double(minute * 60 + 5))
        }
        let topic = topic("measure", "Then measure this", version: 1)
        var question = AssistQuestion.draft(for: topic, plan: AnswerPlan(format: AnswerFormat(kind: .technical), extracts: []), lines: memory.lines, mode: .technical)
        question.earlierAnswers = "Proposed benchmark; no measurements have been taken."
        let text = Prompts.assistInstruction(question)
        XCTAssertEqual(memory.lines.count, 67)
        XCTAssertTrue(text.contains("Them : Use Python and constant extra space"))
        XCTAssertTrue(text.contains("Me : I built Orion in Swift"))
        XCTAssertTrue(text.contains("minute 65"))
        XCTAssertTrue(text.contains("NOT verified personal facts"))
        XCTAssertTrue(text.contains("no measurements have been taken"))
        XCTAssertEqual(AnswerPreferences().language, .english)
    }

    func test_implicitRequestsKeepIndependentSubjectsAndReturnToOlderProject() async {
        let pipeline = TopicPipeline(segmenter: nil, segmenterName: "fixture", onUpdate: { _ in })
        await pipeline.handle(turn("Present your project Orion"))
        let first = await pipeline.board.topics.first!
        await pipeline.handle(turn("Which stack"))
        var board = await pipeline.board.topics
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board.first?.id, first.id)
        await pipeline.handle(turn("Then measure this"))
        board = await pipeline.board.topics
        XCTAssertEqual(board.count, 2)
        let metric = board[0].id
        await pipeline.handle(turn("Describe your project Neptune"))
        await pipeline.handle(turn("Which stack for Orion"))
        board = await pipeline.board.topics
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board.first { $0.id == first.id }?.excerpt.last, "Which stack for Orion")
        XCTAssertEqual(board.first { $0.id == metric }?.excerpt.last, "Then measure this")
        let before = board
        await pipeline.handle(turn("Please design another architecture", speaker: .me))
        board = await pipeline.board.topics
        XCTAssertEqual(board, before, "the user's voice contributes context, never a new card")
    }

    func test_oneTurnWithTwoIndependentRequestsCreatesTwoCards() async {
        let pipeline = TopicPipeline(segmenter: nil, segmenterName: "fixture", onUpdate: { _ in })
        await pipeline.handle(turn("Present your project Orion; then measure this"))
        let board = await pipeline.board.topics
        XCTAssertEqual(board.count, 2)
        XCTAssertTrue(board.contains { $0.excerpt == ["Present your project Orion;"] })
        XCTAssertTrue(board.contains { $0.excerpt == ["then measure this"] })
        XCTAssertEqual(InterviewerRequests.turns(in: turn("Design a queue. It must use constant extra memory.")).count, 1)
    }

    func test_captureOrderRemovalRetryAndIdenticalImagesStayDistinct() {
        var stack = CaptureStack()
        _ = stack.push(.fake("top")); _ = stack.push(.fake("overlap")); _ = stack.push(.fake("bottom"))
        stack.move(from: 2, to: 0)
        XCTAssertEqual(stack.images, [.fake("bottom"), .fake("top"), .fake("overlap")])
        stack.remove(at: 1)
        let sent = stack.drain()
        XCTAssertTrue(stack.isEmpty)
        _ = stack.restore(sent)
        XCTAssertEqual(stack.images, [.fake("bottom"), .fake("overlap")])
        var context = AssistContext(captures: [.fake("same"), .fake("same")])
        XCTAssertEqual(Set(context.items.map(\.id)).count, 2)
        context.toggle(context.items[0].id)
        XCTAssertEqual(context.includedCaptures.count, 1)
    }

    func test_englishShortVersionIsParsedForReadAloudCard() {
        let answer = WhatToSay(markdown: "**Say:** I used Swift for Orion.\n\n## Likely follow-ups\n- Why Swift? → Native integration.")
        XCTAssertEqual(answer?.sentence, "I used Swift for Orion.")
    }

    private func topic(_ id: String, _ title: String, version: Int) -> Topic {
        Topic(id: id, title: title, excerpt: [title], createdAt: Date(), updatedAt: Date(), version: version)
    }
    private func turn(_ text: String, speaker: Speaker = .them) -> Turn { Turn(speaker: speaker, text: text, start: 0, end: 8) }
}
