import Foundation

/// Weighted reciprocal rank fusion: each ranking adds weight / (k + rank) to its items.
public enum SearchFusion {
    public static func fuse(_ rankings: [(weight: Double, ids: [String])], k: Double = 60) -> [(id: String, score: Double)] {
        var scores: [String: Double] = [:]
        var firstSeen: [String: Int] = [:]
        for (weight, ids) in rankings {
            for (rank, id) in ids.enumerated() {
                scores[id, default: 0] += weight / (k + Double(rank + 1))
                if firstSeen[id] == nil { firstSeen[id] = firstSeen.count }
            }
        }
        return scores.map { (id: $0.key, score: $0.value) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : firstSeen[$0.id]! < firstSeen[$1.id]! }
    }
}

/// How sure we are that an item answers the question, from 0 to 1. Fused scores only order
/// results; this says whether the best one is worth showing without the LLM.
public enum SearchEvidence {
    /// Kind expected by the question: half. Then the share of the question's words (or hints)
    /// the item contains, or all of it when the item falls in the asked period or is named.
    public static func confidence(of item: BaseItem, for intent: QueryIntent) -> Double {
        let text = BaseText(item.label + "\n" + item.text)
        let matched = intent.terms.filter { $0.matches(text) }.count
        var evidence = intent.terms.isEmpty ? 0 : Double(matched) / Double(intent.terms.count)
        if let period = intent.period, let dates = item.dates, dates.overlaps(period) { evidence = 1 }
        if namesTheFiche(item, intent) { evidence = 1 }
        guard !intent.kinds.isEmpty, item.kind != .note else { return 0.8 * evidence }
        return (intent.kinds.contains(item.kind) ? 0.5 : 0) + 0.5 * evidence
    }

    /// "Revisio, ça marche comment ?", "c'était bien Porto ?": a word of the question is the
    /// name of a project, a trip's place or a photo's place.
    public static func namesTheFiche(_ item: BaseItem, _ intent: QueryIntent) -> Bool {
        guard [.project, .trip, .photo].contains(item.kind) else { return false }
        let names = BaseText([item.title, item.place ?? ""].joined(separator: " "))
        return intent.terms.contains { $0.word.count >= 4 && names.tokens.contains($0.word) }
    }

    /// A question not addressed to the user is still about them when it names one of their
    /// projects. Not a place: "la capitale du Japon" is not about the trip to Japan.
    public static func namesAProject(_ item: BaseItem, _ intent: QueryIntent) -> Bool {
        item.kind == .project && namesTheFiche(item, intent)
    }

    public static func isAboutTheUser(_ intent: QueryIntent, best: BaseItem) -> Bool {
        intent.isPersonal || namesAProject(best, intent)
    }
}

/// Personal question + a fiche we are sure of → the fiche, at once; otherwise the LLM.
public struct PersonalRouter: Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case off
        case suggest
        case show
    }

    public enum Action: Equatable, Sendable {
        case llm
        /// A one-line suggestion the user can open.
        case suggest
        /// The fiche itself, in place of an answer.
        case show
    }

    public struct Decision: Equatable, Sendable {
        public let action: Action
        public let item: BaseItem?
        public let confidence: Double

        public init(action: Action, item: BaseItem?, confidence: Double) {
            self.action = action
            self.item = item
            self.confidence = confidence
        }
    }

    public var mode: Mode
    public var showThreshold: Double
    public var suggestThreshold: Double

    public init(mode: Mode, showThreshold: Double = 0.75, suggestThreshold: Double = 0.5) {
        self.mode = mode
        self.showThreshold = showThreshold
        self.suggestThreshold = suggestThreshold
    }

    public func route(_ intent: QueryIntent, best: BaseItem?) -> Decision {
        guard mode != .off, let best else { return Decision(action: .llm, item: best, confidence: 0) }
        let confidence = SearchEvidence.confidence(of: best, for: intent)
        guard SearchEvidence.isAboutTheUser(intent, best: best) else {
            return Decision(action: .llm, item: best, confidence: confidence)
        }
        let action: Action
        if confidence >= showThreshold {
            action = mode == .show ? .show : .suggest
        } else if confidence >= suggestThreshold {
            action = .suggest
        } else {
            action = .llm
        }
        return Decision(action: action, item: best, confidence: confidence)
    }
}
