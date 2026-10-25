import Foundation

/// An extract of the base sent with a personal topic, with where it comes from.
public struct BaseSnippet: Equatable, Sendable {
    /// "Revisio › Chiffres (projets/revisio.md)".
    public let source: String
    public let text: String

    public init(source: String, text: String) {
        self.source = source
        self.text = text
    }
}

public enum BaseContext {
    public static let maxSnippets = 5
    static let maxLength = 400

    /// The best items first.
    public static func snippets(from items: [BaseItem]) -> [BaseSnippet] {
        items.filter { !VaultPolicy.containsSecrets($0.text) && VaultPolicy.allows(path: $0.source) }.prefix(maxSnippets).map { BaseSnippet(source: "\($0.label) (\($0.source))", text: cut(body(of: $0), maxLength)) }
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
