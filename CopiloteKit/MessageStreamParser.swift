import Foundation

/// What the overlay needs to know while a Messages API response streams in.
public enum StreamUpdate: Equatable, Sendable {
    case text(String)
    case finished(stopReason: String?)
    case failed(APIFailure)
}

/// An error reported by the API, either as an HTTP error body or as a mid-stream `error` event.
public struct APIFailure: Equatable, Sendable, Error {
    public let type: String
    public let message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }

    /// Reads `{"type":"error","error":{"type":…,"message":…}}`.
    init?(errorEvent: JSONValue) {
        guard let type = errorEvent["error"]?["type"]?.stringValue else { return nil }
        self.init(type: type, message: errorEvent["error"]?["message"]?.stringValue ?? "")
    }

    /// Body of a non-2xx response; proxies and gateways may not send an API error.
    public init(httpStatus: Int, body: Data) {
        if let json = try? JSONDecoder().decode(JSONValue.self, from: body), let failure = APIFailure(errorEvent: json) {
            self = failure
        } else {
            self.init(type: "http_\(httpStatus)", message: "HTTP \(httpStatus)")
        }
    }

    /// One line for the overlay, in French.
    public var userMessage: String {
        switch type {
        case "authentication_error", "permission_error":
            return "Anthropic rejected the API key. Check it in Settings."
        case "not_found_error":
            return "Model not found (\(message)). Check the model ID in Settings."
        case "overloaded_error":
            return "Anthropic is overloaded. Try again shortly."
        case "rate_limit_error":
            return "Rate limit reached. Try again shortly."
        case "invalid_request_error" where message.localizedCaseInsensitiveContains("effort"):
            return "This model does not support effort settings. Choose Model default in Settings."
        case "invalid_request_error":
            return "Request rejected: \(message)"
        default:
            return "API error: \(message.isEmpty ? type : message)"
        }
    }
}

/// Turns the raw bytes of a streaming Messages API response into updates.
/// Chunks can be split anywhere, including inside a UTF-8 character.
public struct MessageStreamParser: Sendable {
    private var pendingBytes = Data()
    private var eventData: [String] = []
    private var stopReason: String?
    private var blocks: [Int: JSONValue] = [:]

    public init() {}

    /// The response's content blocks, rebuilt from the deltas, to append to the
    /// conversation as the assistant turn (thinking blocks keep their signature).
    public var assistantContent: [JSONValue] {
        blocks.sorted { $0.key < $1.key }.map(\.value)
    }

    public mutating func feed(_ chunk: Data) -> [StreamUpdate] {
        pendingBytes.append(chunk)
        var updates: [StreamUpdate] = []
        while let newline = pendingBytes.firstIndex(of: UInt8(ascii: "\n")) {
            var lineBytes = pendingBytes[pendingBytes.startIndex..<newline]
            if lineBytes.last == UInt8(ascii: "\r") { lineBytes = lineBytes.dropLast() }
            updates += handleLine(String(decoding: lineBytes, as: UTF8.self))
            pendingBytes.removeSubrange(pendingBytes.startIndex...newline)
        }
        return updates
    }

    /// Call once the connection closes, to flush an event not followed by a blank line.
    public mutating func finish() -> [StreamUpdate] {
        var updates: [StreamUpdate] = []
        if !pendingBytes.isEmpty {
            updates += handleLine(String(decoding: pendingBytes, as: UTF8.self))
            pendingBytes.removeAll()
        }
        updates += dispatchEvent()
        return updates
    }

    private mutating func handleLine(_ line: String) -> [StreamUpdate] {
        if line.isEmpty { return dispatchEvent() }
        if line.hasPrefix("data:") {
            var value = line.dropFirst("data:".count)
            if value.first == " " { value = value.dropFirst() }
            eventData.append(String(value))
        }
        return []
    }

    private mutating func dispatchEvent() -> [StreamUpdate] {
        guard !eventData.isEmpty else { return [] }
        let payload = eventData.joined(separator: "\n")
        eventData.removeAll()
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)) else { return [] }
        return handle(json)
    }

    private mutating func handle(_ event: JSONValue) -> [StreamUpdate] {
        switch event["type"]?.stringValue {
        case "content_block_start":
            if let index = event["index"]?.intValue, let block = event["content_block"] {
                blocks[index] = block
            }
            return []
        case "content_block_delta":
            guard let delta = event["delta"] else { return [] }
            let index = event["index"]?.intValue ?? 0
            switch delta["type"]?.stringValue {
            case "text_delta":
                let text = delta["text"]?.stringValue ?? ""
                appendToBlock(index, field: "text", text, defaultType: "text")
                return [.text(text)]
            case "thinking_delta":
                appendToBlock(index, field: "thinking", delta["thinking"]?.stringValue ?? "", defaultType: "thinking")
            case "signature_delta":
                appendToBlock(index, field: "signature", delta["signature"]?.stringValue ?? "", defaultType: "thinking")
            default:
                break
            }
            return []
        case "message_delta":
            stopReason = event["delta"]?["stop_reason"]?.stringValue ?? stopReason
            return []
        case "message_stop":
            return [.finished(stopReason: stopReason)]
        case "error":
            return [.failed(APIFailure(errorEvent: event) ?? APIFailure(type: "api_error", message: ""))]
        default:
            return []
        }
    }

    private mutating func appendToBlock(_ index: Int, field: String, _ fragment: String, defaultType: String) {
        guard case var .object(fields) = blocks[index] ?? .object(["type": .string(defaultType)]) else { return }
        fields[field] = .string((fields[field]?.stringValue ?? "") + fragment)
        blocks[index] = .object(fields)
    }
}
