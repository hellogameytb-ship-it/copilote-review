import Foundation

/// The user's diction over a session (Final Round's debrief signals), computed on the Mac from the
/// transcript: share of talk time, words, pace, verbal tics. No model, nothing sent.
public struct SpeechStats: Equatable, Sendable {
    public struct Filler: Equatable, Sendable {
        public let word: String
        public let count: Int

        public init(word: String, count: Int) {
            self.word = word
            self.count = count
        }
    }

    /// The user's share of the speaking time, 0 to 1.
    public let talkShare: Double
    public let words: Int
    /// Over the user's own speaking time; nil under 30 s of speech (too short to mean anything).
    public let wordsPerMinute: Int?
    /// Most frequent first.
    public let fillers: [Filler]

    /// French and English tics that are rarely meant: "genre", "like" or "voilà" are left out, they
    /// are too often real words.
    static let fillerWords = ["euh", "heu", "hum", "bah", "du coup", "en fait", "tu vois", "um", "uh", "you know", "basically"]

    /// Nil when the user never spoke.
    public init?(transcript: [TranscriptLine]) {
        let mine = transcript.filter { $0.speaker == .me }
        guard !mine.isEmpty else { return nil }
        let duration: ([TranscriptLine]) -> TimeInterval = { $0.reduce(0) { $0 + max($1.end - $1.start, 0) } }
        let speaking = duration(mine)
        let total = duration(transcript)
        talkShare = total > 0 ? speaking / total : 0
        let text = mine.map(\.text).joined(separator: " ")
        words = text.split(whereSeparator: \.isWhitespace).filter { $0.contains { $0.isLetter || $0.isNumber } }.count
        wordsPerMinute = speaking >= 30 ? Int((Double(words) / (speaking / 60)).rounded()) : nil
        let found: [Filler] = Self.fillerWords.map { Filler(word: $0, count: Self.occurrences(of: $0, in: text)) }.filter { $0.count > 0 }
        // A stable sort: ties keep the list's order.
        fillers = found.enumerated().sorted { lhs, rhs in
            lhs.element.count != rhs.element.count ? lhs.element.count > rhs.element.count : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// "Tu as parlé 42 % du temps · 1250 mots · 140 mots/min · « euh » ×12, « du coup » ×5".
    public var summary: String {
        var parts = ["You spoke \(Int((talkShare * 100).rounded()))% of the time", "\(words) words"]
        if let wordsPerMinute { parts.append("\(wordsPerMinute) words/min") }
        if !fillers.isEmpty { parts.append(fillers.prefix(3).map { "« \($0.word) » ×\($0.count)" }.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// Whole words or phrases, any case: "genre" is not in "généreux".
    private static func occurrences(of filler: String, in text: String) -> Int {
        let phrase = filler.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])\(phrase)(?![\\p{L}\\p{N}])", options: [.caseInsensitive]) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
