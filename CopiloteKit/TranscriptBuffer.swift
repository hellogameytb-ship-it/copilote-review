import Foundation

/// One finalized sentence or phrase, on the audio clock.
public struct TranscriptLine: Equatable, Sendable, Codable {
    /// "Eux : …", as prompts and labels show it.
    public var labeled: String { "\(speaker.name) : \(text)" }

    public let speaker: Speaker
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speaker: Speaker, text: String, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }
}

/// The full explicitly started session, both channels, retained in memory.
public struct TranscriptBuffer: Sendable {
    public static let window: TimeInterval = .infinity

    public private(set) var lines: [TranscriptLine] = []

    public init() {}

    /// Keeps lines in spoken order (by start time), whatever order they were finalized in.
    public mutating func append(_ line: TranscriptLine) {
        let index = lines.lastIndex { $0.start <= line.start }.map { $0 + 1 } ?? 0
        lines.insert(line, at: index)
        prune(now: lines.map(\.end).max() ?? line.end)
    }

    /// Compatibility hook: retention now ends only at an explicit session boundary.
    public mutating func prune(now: TimeInterval) {
        // Full-session memory is released explicitly when listening stops.
        // A long interview must not silently lose its opening constraints.
    }

    /// "Eux : …\nMoi : …" for the lines that ended in the last `seconds`, one paragraph per speaker turn.
    public func excerpt(last seconds: TimeInterval) -> String {
        guard let newest = lines.map(\.end).max() else { return "" }
        var paragraphs: [(speaker: Speaker, text: String)] = []
        for line in lines where line.end >= newest - seconds {
            if paragraphs.last?.speaker == line.speaker {
                paragraphs[paragraphs.count - 1].text += " " + line.text
            } else {
                paragraphs.append((line.speaker, line.text))
            }
        }
        return paragraphs.map { "\($0.speaker.name) : \($0.text)" }.joined(separator: "\n")
    }
}
