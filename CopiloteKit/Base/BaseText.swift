import Foundation

/// Text folded for matching: lower case, no accents, words only ("T'étais" → "t", "etais").
public struct BaseText: Sendable {
    public let tokens: [String]

    public init(_ text: String) {
        tokens = Self.tokens(of: text)
    }

    public static func tokens(of text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
        var tokens: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// A word of four letters or more matches every word starting with its stem
    /// ("revision" → "revis…": révision, réviser, Revisio).
    func contains(word: String) -> Bool {
        let stem = Self.stem(word)
        return stem.count >= 4 ? tokens.contains { $0.hasPrefix(stem) } : tokens.contains(word)
    }

    /// Light French/English suffix stripping, keeping at least four letters.
    static func stem(_ word: String) -> String {
        guard word.count > 4 else { return word }
        for suffix in ["ements", "ement", "ations", "ation", "ions", "ion", "euses", "euse", "eurs", "eur", "ees", "ee", "es", "er", "ez", "e", "s"]
        where word.hasSuffix(suffix) && word.count - suffix.count >= 4 {
            return String(word.dropLast(suffix.count))
        }
        return word
    }
}

/// A word of the question that a fiche should contain, or one of its alternatives
/// ("tu codes en quoi" → compétences, langages, skills…).
public struct QueryTerm: Hashable, Sendable {
    public let word: String
    public let alternatives: [String]

    public init(word: String, alternatives: [String] = []) {
        self.word = word
        self.alternatives = [word] + alternatives.filter { $0 != word }
    }

    public func matches(_ text: BaseText) -> Bool {
        alternatives.contains { text.contains(word: $0) }
    }

    /// The FTS5 query for this term: any alternative, prefix-matched when long enough.
    var ftsQuery: String {
        let parts = alternatives.map { word in
            let stem = BaseText.stem(word)
            return stem.count >= 4 ? "\"\(stem)\"*" : "\"\(word)\""
        }
        return parts.count == 1 ? parts[0] : "(" + parts.joined(separator: " OR ") + ")"
    }
}
