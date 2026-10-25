import Foundation

/// What the overlay shows for a personal question, built from the index in a few
/// milliseconds: no LLM, no network.
public struct Fiche: Equatable, Sendable, Identifiable {
    public enum Content: Equatable, Sendable {
        case project(ProjectCard)
        case trip(TripCard)
        case photos(PhotoGrid)
        case extract(Extract)
    }

    /// The item that was found.
    public let id: String
    public let content: Content
    /// The items to send as context if the user asks for a written answer.
    public let items: [BaseItem]

    /// Folded above an answer: its name, and what was asked about it when that is a section.
    public var foldedLine: FicheLine {
        switch content {
        case let .project(card):
            return FicheLine(title: card.name, detail: card.answersWithASection ? card.highlights.first?.title : nil)
        case let .trip(card):
            return FicheLine(title: card.place, detail: card.dates)
        case let .photos(grid):
            return FicheLine(title: grid.title, detail: grid.subtitle)
        case let .extract(extract):
            return FicheLine(title: extract.section ?? extract.title, detail: nil)
        }
    }

    /// "Project", "Trip", "CV"…
    public var kindName: String {
        switch content {
        case .project: return "Project"
        case .trip: return "Trip"
        case .photos: return "Photos"
        case let .extract(extract):
            switch extract.kind {
            case .cv: return "CV"
            case .bio: return "Bio"
            case .reference: return "Reference"
            case .opinion: return "Opinion"
            default: return "Note"
            }
        }
    }

    public var title: String {
        switch content {
        case let .project(card): return card.name
        case let .trip(card): return card.place
        case let .photos(grid): return grid.title
        case let .extract(extract): return extract.title
        }
    }
}

public struct ProjectCard: Equatable, Sendable {
    public struct Highlight: Equatable, Sendable {
        public let title: String
        public let text: String
    }

    public let name: String
    public let pitch: String?
    public let stack: [String]
    public let dates: String?
    public let links: [String]
    public let capture: URL?
    public let diagram: URL?
    /// The section asked about first, then the next one (two at most).
    public let highlights: [Highlight]
    /// A section was asked about (a story, the figures): it leads, before the diagram.
    public let answersWithASection: Bool

    public init(matched: BaseItem, fiche items: [BaseItem], root: URL, diagram: URL?) {
        let fiche = items.first { $0.section == nil } ?? matched
        let fields = fiche.fields
        name = fields["nom"]?.text ?? fiche.title
        pitch = fields["pitch"]?.text
        stack = fields["stack"]?.items ?? []
        dates = fiche.dates.map { FicheText.dates($0, ongoing: fields["fin"] == nil) }
        links = fields["liens"]?.items ?? []
        let folder = root.appendingPathComponent((fiche.source as NSString).deletingLastPathComponent)
        capture = fields["captures"]?.items.first.map { folder.appendingPathComponent($0).standardizedFileURL }
        self.diagram = diagram
        answersWithASection = matched.section != nil
        var sections = items.filter { $0.section != nil }
        // The section asked about, or else the key figures ("Chiffres").
        let first = matched.section == nil ? sections.firstIndex { $0.section?.lowercased() == "chiffres" } : sections.firstIndex { $0.id == matched.id }
        if let first { sections.insert(sections.remove(at: first), at: 0) }
        highlights = sections.prefix(2).map { Highlight(title: $0.section ?? "", text: FicheText.body(of: $0, limit: 170)) }
    }
}

public struct PhotoThumb: Equatable, Sendable, Identifiable {
    public let id: String
    public let thumbnail: URL
    public let place: String?
    public let day: String?

    public init(_ item: BaseItem) {
        id = item.id
        thumbnail = URL(fileURLWithPath: item.fields["thumb"]?.text ?? item.fields["path"]?.text ?? item.source)
        place = item.place
        day = item.dates.map { FicheText.dates($0) }
    }
}

public struct TripCard: Equatable, Sendable {
    public let place: String
    public let dates: String?
    public let summary: String?
    public let photos: [PhotoThumb]
}

/// A fiche in one line: "Revisio · Histoires › Pression / deadline".
public struct FicheLine: Equatable, Sendable {
    public let title: String
    public let detail: String?

    public init(title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }
}

public struct PhotoGrid: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let photos: [PhotoThumb]
}

public struct Extract: Equatable, Sendable {
    public let kind: BaseKind
    public let title: String
    public let section: String?
    public let text: String
    public let dates: String?
    /// "cv.md", "reference/lettre.txt".
    public let source: String

    public init(_ item: BaseItem) {
        kind = item.kind
        title = item.kind == .cv ? "CV" : item.title
        section = item.section
        text = FicheText.body(of: item, limit: 600)
        dates = item.dates.map { FicheText.dates($0) }
        source = item.source
    }
}

/// The base as the app and the replay use it: one question → the fiche to show, or the
/// extracts to send with a written answer. Same code on both sides, so the replay measures
/// what the app does.
public struct PersonalBase: Sendable {
    public struct Found: Sendable {
        public let decision: PersonalRouter.Decision
        public let fiche: Fiche
    }

    public let search: BaseSearch
    public let index: BaseIndex
    /// The base folder (captures are next to their fiche).
    public let root: URL

    public init(search: BaseSearch, index: BaseIndex, root: URL) {
        self.search = search
        self.index = index
        self.root = root
    }

    /// Before listening: the index in memory and the model loaded, so the first question is fast.
    public func warmUp() async {
        await search.warmUp()
    }

    /// The fiche for a question about the user, or nil (the LLM's job, or nothing found).
    /// An opinion shows its avis.md section, or nothing: never a fiche that only shares "préféré".
    public func fiche(for question: String, router: PersonalRouter = PersonalRouter(mode: .show), today: CalendarDay = .today()) async -> Found? {
        if QuestionKind(question: question, today: today) == .opinion {
            guard router.mode != .off, let items = try? await search.opinionItems(),
                  let item = OpinionLookup.sections(for: question, in: items).first,
                  let fiche = try? await fiche(for: item) else { return nil }
            let action: PersonalRouter.Action = router.mode == .show ? .show : .suggest
            return Found(decision: PersonalRouter.Decision(action: action, item: item, confidence: 1), fiche: fiche)
        }
        guard let result = try? await search.search(question, today: today) else { return nil }
        let decision = result.decision(router: router)
        guard decision.action != .llm, let item = decision.item, let fiche = try? await fiche(for: item) else { return nil }
        return Found(decision: decision, fiche: fiche)
    }

    /// ⌥1-4 on a topic about the user: the three best extracts, and the next two if they are
    /// confident enough. Nothing for any other topic.
    public func snippets(for text: String, router: PersonalRouter = PersonalRouter(mode: .show), today: CalendarDay = .today()) async -> [BaseSnippet] {
        guard router.mode != .off, let result = try? await search.search(text, today: today), let best = result.hits.first,
              SearchEvidence.isAboutTheUser(result.intent, best: best.item) else { return [] }
        let chosen = result.hits.filter { $0.confidence >= router.suggestThreshold }.prefix(BaseContext.maxSnippets).map(\.item)
        return BaseContext.snippets(from: chosen)
    }

    /// An opinion question: the sections of avis.md about its subject, or none (never a guess).
    public func opinions(for question: String) async -> [BaseSnippet] {
        guard let items = try? await search.opinionItems() else { return [] }
        return BaseContext.snippets(from: OpinionLookup.sections(for: question, in: items))
    }

    public func fiche(for item: BaseItem) async throws -> Fiche {
        switch item.kind {
        case .project:
            let items = try await search.items(ofSource: item.source)
            let card = ProjectCard(matched: item, fiche: items, root: root, diagram: index.diagram(forProject: item.source)?.image)
            return Fiche(id: item.id, content: .project(card), items: [item] + items.filter { $0.id != item.id })
        case .trip:
            let items = try await search.items(ofSource: item.source)
            let fiche = items.first { $0.section == nil } ?? item
            let photos = try await search.photos(for: fiche)
            let summary = items.first { $0.section != nil }.map { FicheText.body(of: $0, limit: 260) }
            let card = TripCard(place: fiche.place ?? fiche.title, dates: fiche.dates.map { FicheText.dates($0) }, summary: summary,
                                photos: photos.map(PhotoThumb.init))
            return Fiche(id: item.id, content: .trip(card), items: [item] + items.filter { $0.id != item.id })
        case .photo:
            let folder = (item.source as NSString).deletingLastPathComponent
            var photos = [item]
            if let day = item.dates?.start {
                // The photos of that month, from the same folder or the same place.
                photos = try await search.photos(in: .month(day.month, of: day.year))
                    .filter { ($0.source as NSString).deletingLastPathComponent == folder || $0.place == item.place }
            }
            let grid = PhotoGrid(title: item.place ?? item.title, subtitle: item.dates.map { FicheText.dates($0) }, photos: photos.map(PhotoThumb.init))
            return Fiche(id: item.id, content: .photos(grid), items: [item])
        default:
            return Fiche(id: item.id, content: .extract(Extract(item)), items: [item])
        }
    }
}

/// French text of the fiches.
public enum FicheText {
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "6–20 juil. 2026", "mars – juin 2024", "since oct. 2025".
    public static func dates(_ span: DateSpan, ongoing: Bool = false) -> String {
        let start = span.start, end = span.end
        func month(_ day: CalendarDay) -> String { months[day.month - 1] }
        if ongoing { return "since \(month(start)) \(start.year)" }
        if start == end { return "\(start.day) \(month(start)) \(start.year)" }
        let wholeMonths = start.day == 1 && end.day == CalendarDay.lastDay(ofMonth: end.month, year: end.year)
        if wholeMonths {
            if start.year == end.year {
                return start.month == end.month ? "\(month(start)) \(start.year)" : "\(month(start)) – \(month(end)) \(end.year)"
            }
            return "\(month(start)) \(start.year) – \(month(end)) \(end.year)"
        }
        if start.year == end.year, start.month == end.month { return "\(start.day)–\(end.day) \(month(end)) \(end.year)" }
        if start.year == end.year { return "\(start.day) \(month(start)) – \(end.day) \(month(end)) \(end.year)" }
        return "\(start.day) \(month(start)) \(start.year) – \(end.day) \(month(end)) \(end.year)"
    }

    /// An item's text without its title and section lines, cut on a word.
    public static func body(of item: BaseItem, limit: Int) -> String {
        BaseContext.cut(BaseContext.body(of: item), limit)
    }
}
