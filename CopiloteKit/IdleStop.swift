import Foundation

/// Listening forgotten after the call stops by itself: 10 min without a phrase, paused time aside
/// (Cluely ends a session after 10 min without audio). Times are uptime seconds.
public struct IdleStop: Equatable, Sendable {
    public static let delay: TimeInterval = 10 * 60

    /// The last phrase, moved forward by the pauses since.
    private var quietSince: TimeInterval
    private var pausedAt: TimeInterval?

    public init(now: TimeInterval) {
        quietSince = now
    }

    public mutating func heard(at now: TimeInterval) {
        quietSince = now
        if pausedAt != nil { pausedAt = now }
    }

    public mutating func pause(at now: TimeInterval) {
        if pausedAt == nil { pausedAt = now }
    }

    public mutating func resume(at now: TimeInterval) {
        guard let pausedAt else { return }
        quietSince += now - pausedAt
        self.pausedAt = nil
    }

    /// Seconds left before listening stops; nil while paused.
    public func remaining(at now: TimeInterval) -> TimeInterval? {
        pausedAt == nil ? max(quietSince + Self.delay - now, 0) : nil
    }
}
