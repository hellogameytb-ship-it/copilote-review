import Foundation

/// An extract of the base sent with a personal topic, with where it comes from.
public struct BaseSnippet: Equatable, Sendable {
    /// "Revisio › Chiffres (projets/revisio.md)".
    public let source: String
    public let text: String
    public let interviewRevision: String?

    public init(source: String, text: String, interviewRevision: String? = nil) {
        self.source = source
        self.text = text
        self.interviewRevision = interviewRevision
    }
}

public enum BaseContext {
    public static let maxSnippets = 5
    static let maxLength = 400

    /// The best items first.
    public static func snippets(from items: [BaseItem], focusingOn terms: [QueryTerm] = []) -> [BaseSnippet] {
        items.filter { !VaultPolicy.containsSecrets($0.text) && VaultPolicy.allows(path: $0.source) }.prefix(maxSnippets).map { BaseSnippet(source: "\($0.label) (\($0.source))", text: excerpt(body(of: $0), terms: terms)) }
    }

    /// In a long section, include the passage that justified retrieving the story.
    private static func excerpt(_ text: String, terms: [QueryTerm]) -> String {
        let start = cut(text, maxLength)
        guard text.count > maxLength, !terms.isEmpty,
              !terms.contains(where: { $0.matches(BaseText(start)) }) else { return start }
        var match: String.Index?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, range, _, stop in
            if let word, terms.contains(where: { $0.matches(BaseText(word)) }) {
                match = range.lowerBound
                stop = true
            }
        }
        guard let match else { return start }
        let left = text.index(match, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let boundary = text[left..<match].firstIndex(where: \.isWhitespace) ?? match
        return "…" + cut(String(text[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines), maxLength - 1)
    }

    /// An item's text without the title and section lines the chunker put first.
    static func body(of item: BaseItem) -> String {
        var lines = item.text.components(separatedBy: "\n")
        if lines.first == item.title { lines.removeFirst() }
        if let section = item.section, lines.first == section { lines.removeFirst() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// At most `limit` characters, cut on a word, without a full stop before the "…".
    static func cut(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit)
        let end = prefix.lastIndex(where: { $0 == " " || $0 == "\n" }) ?? prefix.endIndex
        return prefix[..<end].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }
}
