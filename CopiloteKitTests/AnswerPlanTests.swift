import XCTest
@testable import CopiloteKit

/// What a case is answered with: its kind's format and the extracts of the base it may rest on.
final class AnswerPlanTests: XCTestCase {
    private var root: URL!
    private var store: URL!
    private let october = CalendarDay.day(2026, 10, 19)

    override func setUpWithError() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plan-\(UUID().uuidString)")
        root = folder.appendingPathComponent("Copilote")
        store = folder.appendingPathComponent("store")
        try write("avis.md", "# Mes avis\n## Livre préféré\nL'Étranger de Camus, pour sa phrase sèche.\n")
        try write("projets/tram-live.md", """
        ---
        nom: Tram Live
        pitch: Les horaires des trams de Lausanne en temps réel
        ---
        ## Histoires
        ### Pression / deadline
        Démo au club dans 48 h et l'API des trams tombée : un cache local a sauvé la démo.
        """)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func test_eachKindGetsItsFormat_andOnlyTheExtractsItMayUse() async throws {
        let base = try await personalBase()

        let story = await AnswerPlan.make(heard: ["Raconte-moi un projet qui t'a mis sous pression."], base: base, today: october)
        XCTAssertEqual(story.format, AnswerFormat(kind: .personal, isBehavioural: true, asksAboutTheFuture: false))
        XCTAssertEqual(story.extracts.first?.source, "Tram Live › Histoires › Pression / deadline (projets/tram-live.md)")

        let book = await AnswerPlan.make(heard: ["C'est quoi ton livre préféré ?"], base: base, today: october)
        XCTAssertEqual(book.format.kind, .opinion)
        XCTAssertEqual(book.extracts.map(\.source), ["Mes avis › Livre préféré (avis.md)"])

        let president = await AnswerPlan.make(heard: ["C'est qui ton président des États-Unis préféré ?"], base: base, today: october)
        XCTAssertEqual(president.format.kind, .opinion)
        XCTAssertEqual(president.extracts, [], "an opinion comes from avis.md or not at all")

        let plush = await AnswerPlan.make(heard: ["Parle-moi des ventes de peluches en 2027."], base: base, today: october)
        XCTAssertEqual(plush.format, AnswerFormat(kind: .estimation, isBehavioural: false, asksAboutTheFuture: true))
        XCTAssertEqual(plush.extracts, [])

        let thanks = await AnswerPlan.make(heard: ["D'accord, merci beaucoup."], base: base, today: october)
        XCTAssertFalse(thanks.isWorthDrafting)
        XCTAssertTrue(plush.isWorthDrafting)
    }

    /// The fiche shown at once: the avis section, or nothing (not a project that happens to match "préféré").
    func test_anOpinionShowsItsAvisSection_orNoFicheAtAll() async throws {
        let base = try await personalBase()

        let book = await base.fiche(for: "C'est quoi ton livre préféré ?", today: october)
        XCTAssertEqual(book?.decision.item?.section, "Livre préféré")
        XCTAssertEqual(book?.decision.action, .show)

        let president = await base.fiche(for: "C'est qui ton président des États-Unis préféré ?", today: october)
        XCTAssertNil(president)
    }

    private func personalBase() async throws -> PersonalBase {
        let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
        _ = try await BaseIndexer(index: index, embedder: WordHashEmbedder(), store: store).run(BaseSource(root: root))
        return PersonalBase(search: BaseSearch(index: index, embedder: WordHashEmbedder()), index: index, root: root)
    }

    private func write(_ path: String, _ content: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
