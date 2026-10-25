import XCTest
@testable import CopiloteKit

/// Codex threads are started fresh for every request: the conversation travels in the turn input.
final class CodexPromptTests: XCTestCase {
    func test_screenshotsGoAsInlineImagesInCaptureOrder_withTheInstruction() throws {
        var conversation = Conversation()
        conversation.appendUser(.screenshots([.fake("page 1"), .fake("page 2")]))

        let input = CodexPrompt.turnInput(for: conversation)

        XCTAssertEqual(input.prefix(2).map { $0["url"]?.stringValue }, [
            "data:image/jpeg;base64," + Data("page 1".utf8).base64EncodedString(),
            "data:image/jpeg;base64," + Data("page 2".utf8).base64EncodedString(),
        ])
        XCTAssertEqual(input.first?["type"], "image")
        XCTAssertEqual(input.last?["type"], "text")
        XCTAssertTrue(try XCTUnwrap(input.last?["text"]?.stringValue).contains("2 ordered screenshot"))
    }

    /// A follow-up: the earlier captures (re-sent, as the Messages API history does), the earlier
    /// exchanges as text, then the new question.
    func test_aFollowUpCarriesTheEarlierCapturesAndExchanges() throws {
        var conversation = Conversation()
        conversation.appendUser(.screenshots([.fake("énoncé")]))
        conversation.appendAssistant(content: [
            ["type": "thinking", "thinking": "", "signature": "sig"],
            ["type": "text", "text": "Deque monotone, O(n)."],
        ])
        conversation.appendUser(.clipboardText("Et en O(1) mémoire ?"))

        let input = CodexPrompt.turnInput(for: conversation)

        XCTAssertEqual(input.count, 3)
        XCTAssertEqual(input.first?["url"]?.stringValue, "data:image/jpeg;base64," + Data("énoncé".utf8).base64EncodedString())
        let history = try XCTUnwrap(input[1]["text"]?.stringValue)
        XCTAssertTrue(history.contains("Me : [screenshot 1 attached]"), history)
        XCTAssertTrue(history.contains("Copilote : Deque monotone, O(n)."), history)
        XCTAssertFalse(history.contains("sig"))
        XCTAssertTrue(try XCTUnwrap(input.last?["text"]?.stringValue).contains("Et en O(1) mémoire ?"))
    }
}
