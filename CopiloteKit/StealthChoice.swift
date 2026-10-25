import Foundation

/// Durable ON/OFF choice with an ephemeral, owner-specific confirmation for ON → OFF.
public struct StealthChoice: Equatable, Sendable {
    public enum Source: String, Sendable { case pill, settings }
    public struct Request: Equatable, Sendable {
        public let id: UUID
        public let source: Source
    }
    public private(set) var isEnabled: Bool
    public private(set) var pendingOff: Request?

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public mutating func request(_ enabled: Bool, from source: Source) {
        if enabled { pendingOff = nil; isEnabled = true; return }
        guard isEnabled else { pendingOff = nil; return }
        guard pendingOff?.source != source else { return }
        pendingOff = Request(id: UUID(), source: source)
    }

    public mutating func confirmOff(_ id: UUID) {
        guard isEnabled, pendingOff?.id == id else { return }
        pendingOff = nil
        isEnabled = false
    }

    public mutating func cancel() { pendingOff = nil }
}
