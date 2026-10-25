import Foundation

public struct ProvisionalSpeech: Equatable, Sendable {
    public let speaker: Speaker
    public let text: String
    public init(speaker: Speaker, text: String) { self.speaker = speaker; self.text = text }
}

/// Immutable speech focus captured by an explicit Answer gesture. Session context stays separate.
public struct LiveAnswerSnapshot: Equatable, Sendable {
    public let recentLines: [TranscriptLine]
    public let latestLines: [TranscriptLine]
    public let provisional: [ProvisionalSpeech]

    public init?(lines: [TranscriptLine], context: AssistContext, provisional: [ProvisionalSpeech]) {
        let included = context.includedLines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let excluded = context.excludedLineTexts
        self.provisional = provisional.filter { fragment in
            let text = fragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !included.contains(where: { $0.speaker == fragment.speaker && $0.text == text }),
                  !excluded.contains(where: { !($0.isEmpty) && text.localizedCaseInsensitiveContains($0) }) else { return false }
            // Do not reintroduce excluded speech through an overlapping interim result.
            if let last = lines.last(where: { $0.speaker == fragment.speaker }), excluded.contains(last.text) { return false }
            return true
        }
        let newest = lines.map(\.end).max() ?? 0
        recentLines = included.filter { $0.end >= newest - 300 }
        latestLines = Array(recentLines.suffix(3))
        guard !latestLines.isEmpty || !self.provisional.isEmpty else { return nil }
    }

    public var focusText: String {
        (latestLines.map(\.labeled) + provisional.map { "\($0.speaker.name) (provisional): \($0.text)" }).joined(separator: "\n")
    }
}
