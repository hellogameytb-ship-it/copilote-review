import Foundation

/// One line from `codex app-server` (JSON-RPC over stdio, one JSON object per line).
public enum CodexMessage: Equatable, Sendable {
    /// Answer to one of our requests.
    case response(id: Int, result: JSONValue)
    case responseError(id: Int, message: String)
    /// A request from the server (approval, user input): must be answered. JSON-RPC ids may be numbers or strings.
    case serverRequest(id: JSONValue, method: String)
    case agentDelta(threadID: String, text: String)
    case agentMessageCompleted(threadID: String, text: String)
    /// `failure` is nil when the turn completed normally.
    case turnCompleted(threadID: String, failure: String?)
    case error(threadID: String, message: String, willRetry: Bool)
    case providerFailure(threadID: String?, rpcID: Int?, failure: CodexFailure, retrying: Bool, terminal: Bool = false)
    case other(method: String?)

    public init(line: String) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            self = .other(method: nil)
            return
        }
        let params = json["params"]
        if let id = json["id"], id != .null {
            if let method = json["method"]?.stringValue {
                self = .serverRequest(id: id, method: method)
            } else if let id = id.intValue, let error = json["error"] {
                let failure=CodexFailure.from(error)
                if failure.statusCode != nil || failure.retryAfter != nil || failure.providerCode != nil || failure.rpcCode != nil { self = .providerFailure(threadID:nil,rpcID:id,failure:failure,retrying:false) }
                else { self = .responseError(id:id,message:failure.message) }
            } else if let id = id.intValue {
                self = .response(id: id, result: json["result"] ?? .null)
            } else {
                self = .other(method: nil)
            }
            return
        }
        switch json["method"]?.stringValue {
        case "item/agentMessage/delta":
            self = .agentDelta(threadID: params?["threadId"]?.stringValue ?? "", text: params?["delta"]?.stringValue ?? "")
        case "item/completed" where params?["item"]?["type"] == "agentMessage":
            self = .agentMessageCompleted(threadID: params?["threadId"]?.stringValue ?? "", text: params?["item"]?["text"]?.stringValue ?? "")
        case "turn/completed":
            let turn = params?["turn"]
            let failed = turn?["status"]?.stringValue == "failed"
            if failed {
                let failure=CodexFailure.from(turn?["error"])
                if failure.statusCode != nil || failure.retryAfter != nil || failure.providerCode != nil || failure.rpcCode != nil {
                    self = .providerFailure(threadID:params?["threadId"]?.stringValue,rpcID:nil,failure:failure,retrying:false,terminal:true); return
                }
            }
            self = .turnCompleted(
                threadID: params?["threadId"]?.stringValue ?? "",
                failure: failed ? Self.readableMessage(turn?["error"]?["message"]?.stringValue) : nil
            )
        case "error":
            let failure=CodexFailure.from(params?["error"])
            if failure.statusCode != nil || failure.retryAfter != nil || failure.providerCode != nil || failure.rpcCode != nil {
                self = .providerFailure(threadID:params?["threadId"]?.stringValue,rpcID:nil,failure:failure,retrying:params?["willRetry"] == .bool(true)); return
            }
            self = .error(
                threadID: params?["threadId"]?.stringValue ?? "",
                message: Self.readableMessage(params?["error"]?["message"]?.stringValue),
                willRetry: params?["willRetry"] == .bool(true)
            )
        case let method:
            self = .other(method: method)
        }
    }

    /// Codex forwards the API's error body as a JSON string: keep its human message.
    static func readableMessage(_ raw: String?) -> String {
        guard let raw else { return "erreur inconnue" }
        if let body = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)),
           let message = body["error"]?["message"]?.stringValue ?? body["message"]?.stringValue {
            return message
        }
        return raw
    }
}
