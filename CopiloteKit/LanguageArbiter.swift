import Foundation

/// A final result from one language's transcriber.
public struct TranscriptCandidate: Equatable, Sendable {
    public let language: String
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    /// Mean word confidence, 0...1.
    public let confidence: Double

    public init(language: String, text: String, start: TimeInterval, end: TimeInterval, confidence: Double) {
        self.language = language
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct ArbitratedText: Equatable, Sendable {
    public let language: String
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(language: String, text: String, start: TimeInterval, end: TimeInterval) {
        self.language = language
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Picks, for each stretch of speech, the language whose transcription is the most confident.
/// A passage is decided once every language has transcribed up to about the same point,
/// or `timeout` after its first result if a language stays silent.
public struct LanguageArbiter: Sendable {
    public let languages: [String]
    public let alignmentTolerance: TimeInterval
    public let timeout: TimeInterval
    /// The last winner: live (volatile) text is shown in this language.
    public private(set) var preferredLanguage: String

    private var pending: [String: [TranscriptCandidate]] = [:]
    private var firstPendingAt: TimeInterval?
    /// End of the last passage decided: later results inside it are late duplicates.
    private var decidedThrough: TimeInterval = -.infinity

    public init(languages: [String], alignmentTolerance: TimeInterval = 0.35, timeout: TimeInterval = 0.6) {
        self.languages = languages
        self.alignmentTolerance = alignmentTolerance
        self.timeout = timeout
        preferredLanguage = languages.first ?? ""
    }

    /// `now` is when the result arrived (any monotonic clock, same as `advance`).
    public mutating func add(_ candidate: TranscriptCandidate, receivedAt now: TimeInterval) -> [ArbitratedText] {
        guard candidate.end > decidedThrough + 0.05 else { return [] }
        pending[candidate.language, default: []].append(candidate)
        if firstPendingAt == nil { firstPendingAt = now }
        let ends = languages.compactMap { pending[$0]?.last?.end }
        guard ends.count == languages.count, let latest = ends.max(), let earliest = ends.min(),
              latest - earliest <= alignmentTolerance else { return [] }
        return closeGroup()
    }

    public mutating func advance(to now: TimeInterval) -> [ArbitratedText] {
        guard let first = firstPendingAt, now - first >= timeout else { return [] }
        return closeGroup()
    }

    private mutating func closeGroup() -> [ArbitratedText] {
        let scored = pending.compactMap { language, candidates -> (String, [TranscriptCandidate], Double)? in
            guard !candidates.isEmpty else { return nil }
            return (language, candidates, candidates.map(\.confidence).reduce(0, +) / Double(candidates.count))
        }
        pending.removeAll()
        firstPendingAt = nil
        guard let (language, candidates, _) = scored.max(by: { $0.2 < $1.2 }) else { return [] }
        preferredLanguage = language
        decidedThrough = max(decidedThrough, scored.flatMap(\.1).map(\.end).max() ?? decidedThrough)
        return [ArbitratedText(
            language: language,
            text: candidates.map(\.text).joined(separator: " "),
            start: candidates.map(\.start).min() ?? 0,
            end: candidates.map(\.end).max() ?? 0
        )]
    }
}
