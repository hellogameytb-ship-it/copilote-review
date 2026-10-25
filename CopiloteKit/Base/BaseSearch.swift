import Accelerate
import Foundation

/// Text → vector, on the device (see `ContextualEmbedder`).
public protocol TextEmbedder: Sendable {
    /// Stored with the index: another model means another vector space, so a full reindex.
    var identifier: String { get }
    func vector(for text: String) -> [Float]?
}

public struct SearchHit: Equatable, Sendable {
    public let item: BaseItem
    /// Fused rank score (orders results).
    public let score: Double
    /// `SearchEvidence`: is it worth showing without the LLM.
    public let confidence: Double

    /// Most confident first; for "raconte-moi une fois où…", a project's stories before its other
    /// sections at equal confidence; then the fused score.
    static func ranked(_ hits: [SearchHit], for intent: QueryIntent) -> [SearchHit] {
        func isStory(_ hit: SearchHit) -> Bool { intent.isBehavioral && (hit.item.section?.hasPrefix("Histoires") ?? false) }
        return hits.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            if isStory($0) != isStory($1) { return isStory($0) }
            return $0.score > $1.score
        }
    }
}

public struct SearchResult: Sendable {
    public let intent: QueryIntent
    /// Best first, after reranking by confidence.
    public let hits: [SearchHit]
    public let elapsed: Duration

    public func decision(mode: PersonalRouter.Mode) -> PersonalRouter.Decision {
        decision(router: PersonalRouter(mode: mode))
    }

    public func decision(router: PersonalRouter) -> PersonalRouter.Decision {
        router.route(intent, best: hits.first?.item)
    }
}

/// Hybrid search over the index: BM25 (FTS5) on the question's words, cosine on on-device
/// vectors, the period asked for, and the kinds asked for as a filter; fused by weighted RRF,
/// then the best few reranked by `SearchEvidence`. No network, no LLM.
public actor BaseSearch {
    private let index: BaseIndex
    private let embedder: TextEmbedder
    private var loadedVersion = -1
    private var items: [BaseItem] = []
    private var byID: [String: Int] = [:]
    /// Centred, unit-length vectors (centring removes the direction all sentences share).
    private var vectors: [[Float]?] = []
    private var mean: [Float] = []

    static let weights = (lexical: 1.0, period: 1.0, vector: 0.5, recency: 0.3)

    public init(index: BaseIndex, embedder: TextEmbedder) {
        self.index = index
        self.embedder = embedder
    }

    public func search(_ question: String, today: CalendarDay = .today(), limit: Int = 8) throws -> SearchResult {
        let clock = ContinuousClock()
        let started = clock.now
        try reloadIfNeeded()
        let intent = QueryIntent(question: question, today: today)

        var lexical: [String] = []
        if !intent.terms.isEmpty {
            lexical = try index.lexical(match: intent.terms.map(\.ftsQuery).joined(separator: " OR "), limit: 50)
        }
        let semantic = vectorRanking(question)
        let period = intent.period.map(periodRanking) ?? []

        func kept(_ ids: [String]) -> [String] {
            intent.kinds.isEmpty ? ids : ids.filter { byID[$0].map { intent.kinds.contains(items[$0].kind) } ?? false }
        }
        var rankings: [(weight: Double, ids: [String])] = [
            (Self.weights.lexical, kept(lexical)), (Self.weights.period, kept(period)), (Self.weights.vector, kept(semantic)),
        ]
        if !intent.kinds.isEmpty {
            // "c'est quoi ton projet ?": with nothing more to go on, the latest fiches of that kind.
            rankings.append((Self.weights.recency, recencyRanking(of: intent.kinds)))
        }
        if rankings.allSatisfy({ $0.ids.isEmpty }) {
            rankings = [(Self.weights.lexical, lexical), (Self.weights.vector, semantic)]
        }

        func hits(_ rankings: [(weight: Double, ids: [String])]) -> [SearchHit] {
            SearchHit.ranked(SearchFusion.fuse(rankings).prefix(max(limit, 12)).compactMap { entry -> SearchHit? in
                guard let position = byID[entry.id] else { return nil }
                let item = items[position]
                return SearchHit(item: item, score: entry.score, confidence: SearchEvidence.confidence(of: item, for: intent))
            }, for: intent)
        }
        var found = hits(rankings)
        if !intent.kinds.isEmpty, found.count < limit {
            // Context for a written answer: other kinds after the asked one (the fiche stays first).
            let seen = Set(found.map(\.item.id))
            found += hits([(Self.weights.lexical, lexical), (Self.weights.vector, semantic)]).filter { !seen.contains($0.item.id) }
        }
        return SearchResult(intent: intent, hits: Array(found.prefix(limit)), elapsed: clock.now - started)
    }

    /// Photos of a trip: its linked folder, or taken during its dates. Oldest first.
    public func photos(for trip: BaseItem, limit: Int = 24) throws -> [BaseItem] {
        try reloadIfNeeded()
        let folder = trip.fields["photos"]?.text.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        return Array(items.filter { item in
            guard item.kind == .photo else { return false }
            if let folder, item.source.hasPrefix(folder) { return true }
            if let dates = trip.dates, let taken = item.dates { return dates.contains(taken.start) }
            return false
        }
        .sorted { ($0.dates?.start ?? .day(0, 1, 1), $0.source) < ($1.dates?.start ?? .day(0, 1, 1), $1.source) }
        .prefix(limit))
    }

    /// Photos taken in a period (a question about photos with no trip fiche).
    public func photos(in period: DateSpan, limit: Int = 24) throws -> [BaseItem] {
        try reloadIfNeeded()
        return Array(items.filter { $0.kind == .photo && ($0.dates.map { period.overlaps($0) } ?? false) }
            .sorted { ($0.dates?.start ?? .day(0, 1, 1)) < ($1.dates?.start ?? .day(0, 1, 1)) }
            .prefix(limit))
    }

    /// The other sections of a fiche (a project card lists its numbers, its stack…).
    public func items(ofSource source: String) throws -> [BaseItem] {
        try reloadIfNeeded()
        return items.filter { $0.source == source }
    }

    public func opinionItems() throws -> [BaseItem] {
        try reloadIfNeeded()
        return items.filter { $0.kind == .opinion }
    }

    /// Loads the index and the model ahead of the first question.
    public func warmUp() {
        try? reloadIfNeeded()
        _ = embedder.vector(for: "préchauffage")
    }

    // MARK: Rankings

    private func vectorRanking(_ question: String) -> [String] {
        guard !mean.isEmpty, let raw = embedder.vector(for: question), raw.count == mean.count else { return [] }
        let query = Self.centred(raw, mean)
        var scored: [(Int, Float)] = []
        for (position, vector) in vectors.enumerated() {
            guard let vector else { continue }
            var dot: Float = 0
            vDSP_dotpr(query, 1, vector, 1, &dot, vDSP_Length(query.count))
            if dot > 0.05 { scored.append((position, dot)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(50).map { items[$0.0].id }
    }

    /// Items in the period, longest overlap first (a two-week trip before one photo), fiches first.
    private func periodRanking(_ period: DateSpan) -> [String] {
        items.enumerated()
            .compactMap { position, item -> (Int, Int)? in
                guard let dates = item.dates else { return nil }
                let days = dates.overlap(with: period)
                return days > 0 ? (position, days) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return (items[lhs.0].section == nil ? 0 : 1) < (items[rhs.0].section == nil ? 0 : 1)
            }
            .prefix(50)
            .map { items[$0.0].id }
    }

    private func recencyRanking(of kinds: Set<BaseKind>) -> [String] {
        items.filter { kinds.contains($0.kind) && $0.section == nil && $0.kind != .photo }
            .sorted { ($0.dates?.end ?? .day(0, 1, 1)) > ($1.dates?.end ?? .day(0, 1, 1)) }
            .prefix(20)
            .map(\.id)
    }

    // MARK: Snapshot

    private func reloadIfNeeded() throws {
        let version = index.version
        guard version != loadedVersion else { return }
        let stored = try index.items()
        items = stored.map(\.item)
        byID = Dictionary(items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let raw = stored.map(\.vector)
        let dimension = raw.compactMap { $0?.count }.first ?? 0
        let usable = raw.compactMap { $0 }.filter { $0.count == dimension }
        if dimension > 0, !usable.isEmpty {
            var sum = [Float](repeating: 0, count: dimension)
            for vector in usable { vDSP_vadd(sum, 1, vector, 1, &sum, 1, vDSP_Length(dimension)) }
            var scale = 1 / Float(usable.count)
            vDSP_vsmul(sum, 1, &scale, &sum, 1, vDSP_Length(dimension))
            mean = sum
            vectors = raw.map { $0.flatMap { $0.count == dimension ? Self.centred($0, sum) : nil } }
        } else {
            mean = []
            vectors = raw.map { _ in nil }
        }
        loadedVersion = version
    }

    private static func centred(_ vector: [Float], _ mean: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: vector.count)
        vDSP_vsub(mean, 1, vector, 1, &result, 1, vDSP_Length(vector.count))
        var norm: Float = 0
        vDSP_svesq(result, 1, &norm, vDSP_Length(result.count))
        guard norm > 0 else { return result }
        var scale = 1 / norm.squareRoot()
        vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(result.count))
        return result
    }
}
