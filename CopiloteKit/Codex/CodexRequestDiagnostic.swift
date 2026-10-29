import Foundation

/// Allowlisted metadata only: no input, output, provider raw error, thread ID, paths or credentials.
public struct CodexRequestDiagnostic: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let requestID: UUID
    public let timestamp: Date
    public let action: String
    public let phase: String
    public let provider: String
    public let model: String
    public let category: String?
    public let rpcCode: Int?
    public let providerCode: String?
    public let statusCode: Int?
    public let retryAfterSeconds: Double?
    public let upstreamRetrying: Bool

    public init(requestID:UUID, work:CodexWork, model:String, phase:String, error:Error? = nil, upstreamRetrying:Bool = false, timestamp:Date = Date()) {
        id=UUID();self.requestID=requestID;self.timestamp=timestamp;action=work.label;self.phase=phase;provider="Codex"
        self.model=model.range(of:#"^[A-Za-z0-9._-]{1,80}$"#,options:.regularExpression) != nil ? model : "custom model"
        let failure=error as? CodexFailure
        category=error is CancellationError ? "cancelled" : failure?.category.rawValue ?? (error == nil ? nil : "provider")
        rpcCode=failure?.rpcCode
        providerCode=failure?.providerCode
        statusCode=failure?.statusCode;retryAfterSeconds=failure?.retryAfter;self.upstreamRetrying=upstreamRetrying
    }
    public var summary:String {
        let f=DateFormatter();f.dateFormat="yyyy-MM-dd HH:mm:ss Z"
        return "\(f.string(from:timestamp)) · \(action) · \(phase) · \(provider)/\(model) · \(category ?? "ok")" +
            (statusCode.map { " · HTTP \($0)" } ?? "") + (providerCode.map { " · \($0)" } ?? "") + (rpcCode.map { " · RPC \($0)" } ?? "") + (retryAfterSeconds.map { " · wait ≥\(String(format:"%.0f",ceil($0)))s" } ?? "") +
            (upstreamRetrying ? " · upstream retry reported" : "") + " · id \(requestID.uuidString)"
    }
}

public struct CodexDiagnosticHistory: Codable, Sendable {
    public private(set) var entries: [CodexRequestDiagnostic] = []
    public init() {}
    public mutating func append(_ event:CodexRequestDiagnostic) {
        entries.append(event)
        entries.sort { $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp }
        entries=Array(entries.suffix(200))
    }
    public var text:String { entries.map(\.summary).joined(separator:"\n") }
}
