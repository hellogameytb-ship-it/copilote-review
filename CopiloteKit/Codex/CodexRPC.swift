import Foundation

/// JSON-RPC messages sent to `codex app-server`.
public enum CodexRPC {
    public static func threadStart(
        id: Int, model: String, workingDirectory: String, baseInstructions: String, serviceTier: String?
    ) -> JSONValue {
        var params: [String: JSONValue] = [
            "model": .string(model),
            "cwd": .string(workingDirectory),
            // Replaces Codex's ~9k-token agent instructions: faster and only about answering.
            "baseInstructions": .string(baseInstructions),
            "ephemeral": true,
            "sandbox": "read-only",
            "approvalPolicy": "never",
        ]
        if let serviceTier { params["serviceTier"] = .string(serviceTier) }
        return request(id: id, method: "thread/start", params: .object(params))
    }

    public static func turnStart(id: Int, threadID: String, input: [JSONValue], effort: String, outputSchema: JSONValue?) -> JSONValue {
        var params: [String: JSONValue] = ["threadId": .string(threadID), "input": .array(input), "effort": .string(effort)]
        if let outputSchema { params["outputSchema"] = outputSchema }
        return request(id: id, method: "turn/start", params: .object(params))
    }

    public static func initialize(id: Int) -> JSONValue {
        request(id: id, method: "initialize", params: ["clientInfo": ["name": "copilote", "version": "0.2"]])
    }

    public static let initialized: JSONValue = ["jsonrpc": "2.0", "method": "initialized"]

    /// Answer to a request from the server (approval, user input): always no.
    public static func refusal(of id: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Copilote n'autorise aucune action."]]
    }

    public static func turnInterrupt(id: Int, threadID: String, turnID: String) -> JSONValue {
        request(id: id, method: "turn/interrupt", params: ["threadId": .string(threadID), "turnId": .string(turnID)])
    }

    /// Releases an ephemeral thread once its turn is over (the process stays up for the next one).
    public static func threadUnsubscribe(id: Int, threadID: String) -> JSONValue {
        request(id: id, method: "thread/unsubscribe", params: ["threadId": .string(threadID)])
    }

    static func request(id: Int, method: String, params: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": .int(id), "method": .string(method), "params": params]
    }
}
