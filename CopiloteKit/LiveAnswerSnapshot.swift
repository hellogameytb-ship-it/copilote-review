import Foundation

public struct ProvisionalSpeech: Equatable, Sendable {
    public let speaker: Speaker
    public let text: String
    public init(speaker: Speaker, text: String) { self.speaker = speaker; self.text = text }
}

/// Immutable speech focus captured by an explicit Answer gesture. Session context stays separate.
public struct LiveAnswerSnapshot: Equatable, Sendable {
    public let recentLines: [TranscriptLine]
    /// All included fragments overlapping the two-minute working window, never a fragment count.
    public let workingLines: [TranscriptLine]
    public let capturedAt: TimeInterval
    public var precedingLines: [TranscriptLine] { recentLines.filter { $0.end < capturedAt - 120 } }
    public let provisional: [ProvisionalSpeech]

    public init?(lines: [TranscriptLine], context: AssistContext, provisional: [ProvisionalSpeech], capturedAt: TimeInterval? = nil) {
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
        let cutoff = capturedAt ?? lines.map(\.end).max() ?? 0
        self.capturedAt = cutoff
        recentLines = included.filter { $0.end >= cutoff - 300 && $0.start <= cutoff }
        workingLines = recentLines.filter { $0.end >= cutoff - 120 }
        guard !workingLines.isEmpty || !self.provisional.isEmpty else { return nil }
    }

    public var focusText: String {
        (workingLines.map(\.labeled) + provisional.map { "\($0.speaker.name) (provisional): \($0.text)" }).joined(separator: "\n")
    }
}
