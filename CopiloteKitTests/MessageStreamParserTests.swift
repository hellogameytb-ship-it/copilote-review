import XCTest
@testable import CopiloteKit

/// Transcripts follow the Messages API streaming format (event + data lines, blank-line separated).
final class MessageStreamParserTests: XCTestCase {
    func test_emitsTextDeltasThenTheStopReason() {
        var parser = MessageStreamParser()

        let updates = parser.feed(Data(Self.helloWorldStream.utf8)) + parser.finish()

        XCTAssertEqual(updates, [.text("Hello"), .text(" world"), .finished(stopReason: "end_turn")])
    }

    func test_reassemblesChunksSplitAnywhere_evenInsideMultibyteCharacters() {
        let stream = Self.textStream(deltas: ["Complexité ", "O(n log n) ", "✅"])
        var parser = MessageStreamParser()

        var updates: [StreamUpdate] = []
        for byte in Data(stream.utf8) { updates += parser.feed(Data([byte])) }
        updates += parser.finish()

        XCTAssertEqual(updates, [.text("Complexité "), .text("O(n log n) "), .text("✅"), .finished(stopReason: "end_turn")])
    }

    func test_acceptsCRLFLineEndings() {
        let stream = Self.textStream(deltas: ["a", "b"]).replacingOccurrences(of: "\n", with: "\r\n")
        var parser = MessageStreamParser()

        let updates = parser.feed(Data(stream.utf8)) + parser.finish()

        XCTAssertEqual(updates, [.text("a"), .text("b"), .finished(stopReason: "end_turn")])
    }

    func test_reportsAnErrorEventSentMidStream() {
        let stream = """
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Par"}}

        event: error
        data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}


        """
        var parser = MessageStreamParser()

        let updates = parser.feed(Data(stream.utf8)) + parser.finish()

        XCTAssertEqual(updates, [.text("Par"), .failed(APIFailure(type: "overloaded_error", message: "Overloaded"))])
    }

    /// Thinking blocks must be replayed unchanged on the next turn, signature included.
    func test_rebuildsTheAssistantContentBlocksToReplayInTheConversation() {
        let stream = """
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Two pointers"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQBCgIYAhIM"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Idée : "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"deux pointeurs."}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: message_stop
        data: {"type":"message_stop"}


        """
        var parser = MessageStreamParser()

        let updates = parser.feed(Data(stream.utf8)) + parser.finish()

        XCTAssertEqual(updates, [.text("Idée : "), .text("deux pointeurs."), .finished(stopReason: nil)])
        XCTAssertEqual(parser.assistantContent, [
            ["type": "thinking", "thinking": "Two pointers", "signature": "EqQBCgIYAhIM"],
            ["type": "text", "text": "Idée : deux pointeurs."],
        ])
    }

    static func textStream(deltas: [String], stopReason: String = "end_turn") -> String {
        var events = [
            #"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[]}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        ]
        for delta in deltas {
            let escaped = String(decoding: try! JSONEncoder().encode(delta), as: UTF8.self)
            events.append(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":\#(escaped)}}"#)
        }
        events += [
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"\#(stopReason)"},"usage":{"output_tokens":3}}"#,
            #"{"type":"message_stop"}"#,
        ]
        return events.map { "event: x\ndata: \($0)\n\n" }.joined()
    }

    static let helloWorldStream = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-sonnet-5-5","stop_reason":null,"usage":{"input_tokens":12,"output_tokens":1}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

    event: ping
    data: {"type": "ping"}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":12}}

    event: message_stop
    data: {"type":"message_stop"}


    """
}
