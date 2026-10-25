import Foundation

/// Catches an opinion put in the user's mouth (first person) when avis.md had none: the answer
/// then carries a warning in the app, and the replay counts it as a failure.
public enum OpinionGuard {
    /// The first phrase that states an opinion in the first person, or nil.
    public static func firstPersonOpinion(in text: String) -> String? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'")
        for pattern in patterns {
            if let range = folded.range(of: pattern, options: .regularExpression) { return String(folded[range]) }
        }
        return nil
    }

    /// Accent-free, lowercased.
    private static let patterns = [
        #"\bje (prefere|dirais|pense que|trouve que|crois que|choisirais|vote|suis pour|suis contre)\b"#,
        #"\bj'(aime|adore|admire|ai une preference)\b"#,
        #"\b(mon|ma|mes)( [a-z'-]+){0,4} (prefere|preferee|preferes|favori|favorite)s?\b"#,
        #"\b(a mon avis|selon moi|personnellement)\b"#,
        #"\bi (prefer|think|believe|love|admire|would say|'d say)\b"#,
        #"\bi'd (say|pick|choose)\b"#,
        #"\b(my favou?rite|in my opinion|personally)\b"#,
    ]
}
