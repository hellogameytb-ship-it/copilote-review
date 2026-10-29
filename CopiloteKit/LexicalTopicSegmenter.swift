import Foundation

/// Decides new / continue / ignore for a turn of the others.
public protocol TopicSegmenter: Sendable {
    var coalescesPendingTurns: Bool { get }
    func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision
}

extension TopicSegmenter { public var coalescesPendingTurns: Bool { false } }

/// Offline topic segmentation from shared keywords. Less clever than the model,
/// but needs no network: used without an API key and when the API call fails.
public struct LexicalTopicSegmenter: TopicSegmenter {
    /// Share of the shorter keyword set that must overlap for a turn to continue a topic.
    static let continuationOverlap = 0.3
    /// Fewer content words than this is small talk ("d'accord, merci").
    static let minimumContentWords = 3

    public init() {}

    public func decide(turn: Turn, topics: [Topic], context: String) async throws -> TopicDecision {
        decision(for: turn, topics: topics)
    }

    public func decision(for turn: Turn, topics: [Topic]) -> TopicDecision {
        let words = Self.keywords(turn.text)
        let normalized = BaseText.tokens(of: turn.text).joined(separator: " ")
        let metricCues: Set<String> = ["measure", "metrics", "benchmark", "mesure", "mesurer"]
        if !words.isDisjoint(with: metricCues) || normalized.contains("next steps") {
            if let topic = topics.first(where: { !Self.keywords($0.title).isDisjoint(with: metricCues) }) {
                return .continueTopic(id: topic.id, title: "")
            }
            return .new(title: Self.title(for: turn.text))
        }
        if words.contains("stack") || normalized.contains("which technologies") {
            let generic: Set<String> = ["project", "projects", "projet", "projets", "present", "stack", "technologies", "back", "used", "using"]
            let explicit = words.subtracting(generic)
            if let named = topics.first(where: { !Self.keywords(([$0.title] + $0.excerpt).joined(separator: " ")).subtracting(generic).isDisjoint(with: explicit) }) {
                return .continueTopic(id: named.id, title: "")
            }
            if let topic = topics.first(where: { !Self.keywords(([$0.title] + $0.excerpt).joined(separator: " ")).isDisjoint(with: ["project", "projects", "projet", "projets", "application", "portfolio"]) }) {
                return .continueTopic(id: topic.id, title: "")
            }
        }
        if words.count < 3, TurnCompletion.requestsAnswer(turn.text), let first = topics.first,
           ["why", "how long", "how so", "pourquoi"].contains(where: normalized.hasPrefix) {
            return .continueTopic(id: first.id, title: "")
        }
        let best = topics
            .map { topic in (topic, Self.overlap(words, Self.keywords(([topic.title] + topic.excerpt).joined(separator: " ")))) }
            .max { $0.1 < $1.1 }
        if let (topic, overlap) = best, overlap >= Self.continuationOverlap {
            return .continueTopic(id: topic.id, title: "")
        }
        return words.count >= Self.minimumContentWords || TurnCompletion.requestsAnswer(turn.text) ? .new(title: Self.title(for: turn.text)) : .ignore
    }

    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        let shared = a.intersection(b).count
        guard shared >= 2, let smaller = [a.count, b.count].min(), smaller > 0 else { return 0 }
        return Double(shared) / Double(smaller)
    }

    /// Lowercased, accent-free content words of 3+ letters.
    static func keywords(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let words = folded.split { !$0.isLetter }.map(String.init)
        return Set(words.filter { $0.count >= 3 && !stopwords.contains($0) })
    }

    /// The last question of the turn, without its conversational opener, up to 9 words.
    static func title(for text: String) -> String {
        var sentences: [(text: String, isQuestion: Bool)] = []
        var current = ""
        for character in text + "." {
            guard ".?!".contains(character) else {
                current.append(character)
                continue
            }
            let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append((sentence, character == "?")) }
            current = ""
        }
        var sentence = (sentences.last { $0.isQuestion } ?? sentences.last)?.text ?? text
        while let opener = openers.first(where: { sentence.lowercased().hasPrefix($0 + " ") || sentence.lowercased().hasPrefix($0 + ",") }) {
            sentence = String(sentence.dropFirst(opener.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        }
        let words = sentence.split(separator: " ")
        var title = words.prefix(9).joined(separator: " ")
        if words.count > 9 { title += "…" }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// Longest first: the first match wins.
    private static let openers = [
        "est-ce que tu peux m'expliquer", "est-ce que tu pourrais m'expliquer", "est-ce que tu peux me dire",
        "est-ce que tu peux", "est-ce que", "tu peux m'expliquer", "peux-tu m'expliquer", "explique-moi",
        "dis-moi", "et sinon", "dernière question", "pour revenir à", "pour revenir sur",
        "d'accord", "ah", "ok", "bon", "alors", "et",
        "can you explain", "could you explain", "can you tell me", "could you tell me", "tell me",
        "okay", "so", "and",
    ]

    /// French and English function words and conversational fillers (accent-free).
    private static let stopwords: Set<String> = [
        // French
        "est", "que", "qui", "quoi", "tu", "peux", "pourrais", "expliquer", "explique", "comment", "pourquoi",
        "quelle", "quel", "quels", "quelles", "dans", "une", "des", "les", "pour", "avec", "sur", "par", "pas",
        "plus", "moins", "tres", "bien", "fait", "faire", "veux", "vous", "nous", "ils", "elle", "elles", "son",
        "sa", "ses", "mon", "mes", "ton", "tes", "leur", "leurs", "cette", "ces", "cet", "aux", "du", "de", "la",
        "le", "un", "et", "ou", "mais", "donc", "car", "ni", "alors", "sinon", "accord", "merci", "beaucoup",
        "bon", "ben", "voila", "oui", "non", "ok", "okay", "derniere", "question", "revenir", "dire", "dis",
        "moi", "toi", "lui", "qu", "il", "on", "ce", "ca", "cela", "etre", "avoir", "sont", "ont", "etait",
        "aussi", "tout", "tous", "toute", "toutes", "chose", "choses", "maintenant", "juste", "vraiment",
        // English
        "the", "and", "you", "your", "can", "could", "would", "what", "why", "how", "when", "where", "which",
        "who", "that", "this", "these", "those", "with", "for", "from", "about", "into", "are", "was", "were",
        "have", "has", "had", "does", "did", "will", "just", "great", "thanks", "thank", "good", "nice", "yes",
        "yeah", "sure", "right", "well", "tell", "explain", "please", "there", "here", "then", "also",
    ]
}
