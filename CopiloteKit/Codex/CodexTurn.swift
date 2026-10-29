import Foundation

/// One turn's state, from the app-server messages of its thread.
public struct CodexTurn: Equatable, Sendable {
    private var streamed = ""
    private var completed: String?
    private var failure: CodexFailure?
    private var isFinished = false

    public init() {}

    /// Applies one message; returns the text to show live, if any.
    public mutating func apply(_ message: CodexMessage) -> String? {
        switch message {
        case let .agentDelta(_, text):
            streamed += text
            return text
        case let .agentMessageCompleted(_, text):
            completed = text
        case let .error(_, message, willRetry):
            if !willRetry { failure = CodexFailure(message: message) }
        case let .turnCompleted(_, turnFailure):
            failure = turnFailure.map { CodexFailure(message: $0) } ?? failure
            isFinished = true
        case let .providerFailure(_, _, error, retrying, terminal):
            if !retrying { failure=error }
            if terminal { isFinished=true }
        case .response, .responseError, .serverRequest, .other:
            break
        }
        return nil
    }

    /// nil until the turn has completed. The completed message wins over the deltas (a retried
    /// attempt streams its text again).
    public var result: Result<String, CodexFailure>? {
        guard isFinished else { return nil }
        if let failure { return .failure(failure) }
        return .success(completed ?? streamed)
    }
}
