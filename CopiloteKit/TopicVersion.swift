import Foundation

/// One version of a topic: a continuation makes earlier answers to it stale.
public struct TopicVersion: Equatable, Sendable {
    public let id: String
    public let version: Int

    public init(_ topic: Topic) {
        id = topic.id
        version = topic.version
    }
}
