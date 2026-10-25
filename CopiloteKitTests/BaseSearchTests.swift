import ImageIO
import XCTest
@testable import CopiloteKit

/// The whole chain on a small base in a temporary folder: files → index (SQLite, FTS5,
/// vectors) → search. Fake embedder and place names: no network, no model download.
final class BaseSearchTests: XCTestCase {
    private var root: URL!
    private var store: URL!
    private let october = CalendarDay.day(2026, 10, 19)

    override func setUpWithError() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("base-\(UUID().uuidString)")
        root = folder.appendingPathComponent("Copilote")
        store = folder.appendingPathComponent("store")
        try write("projets/revisio.md", """
        ---
        nom: Revisio
        pitch: Application web qui génère des quiz à partir de notes de cours
        stack: [Next.js, Supabase]
        debut: 2025-10
        ---
        ## Chiffres
        120 utilisateurs la première semaine.
        """)
        try write("projets/meteo-velo.md", "---\nnom: Météo Vélo\npitch: App iOS qui dit s'il faut prendre le vélo\n---\n")
        try write("voyages/portugal-2026.md", "---\nlieu: Lisbonne et Porto, Portugal\ndebut: 2026-07-06\nfin: 2026-07-20\n---\n## Résumé\nSurf à Ericeira.\n")
        try write("voyages/barcelone-2024.md", "---\nlieu: Barcelone, Espagne\ndebut: 2024-08-10\nfin: 2024-08-17\n---\n## Résumé\nPlage et Sagrada Família.\n")
        try write("cv.md", "# CV\n## Compétences\n- Langages : Python, TypeScript, Swift\n")
        try write("notes/journal.md", "# Journal\n## 2026-03-02\nRévisé les arbres binaires pour l'examen.\n## 2026-07-08\nJournée à la plage.\n")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func test_thePersonalQuestionsOfTheBriefFindTheirFicheFirst() async throws {
        let base = try await indexedBase()

        let summer = try await base.search("T'étais où cet été ?", today: october)
        XCTAssertEqual(summer.hits.first?.item.id, "voyages/portugal-2026.md#fiche")
        XCTAssertEqual(summer.decision(mode: .show).action, .show)

        let project = try await base.search("C'est quoi ton projet d'app de révision ?", today: october)
        XCTAssertEqual(project.hits.first?.item.title, "Revisio")
        XCTAssertEqual(project.decision(mode: .show).action, .show)

        let skills = try await base.search("Tu codes en quoi ?", today: october)
        XCTAssertEqual(skills.hits.first?.item.section, "Compétences")
    }

    func test_aTechnicalQuestionIsLeftToTheLLM() async throws {
        let base = try await indexedBase()

        let result = try await base.search("Comment on équilibre un arbre binaire de recherche ?", today: october)

        XCTAssertEqual(result.decision(mode: .show).action, .llm)
    }

    func test_reindexingReadsOnlyWhatChanged_andForgetsWhatWasRemoved() async throws {
        let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
        let indexer = BaseIndexer(index: index, embedder: WordHashEmbedder(), store: store)
        let first = try await indexer.run(BaseSource(root: root))
        XCTAssertEqual(first.changedFiles, 6)

        try write("projets/meteo-velo.md", "---\nnom: Météo Vélo\npitch: App iOS SwiftUI pour cyclistes\n---\n")
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/journal.md"))
        let second = try await indexer.run(BaseSource(root: root))

        XCTAssertEqual(second.changedFiles, 1)
        XCTAssertEqual(second.removedFiles, 1)
        let base = BaseSearch(index: index, embedder: WordHashEmbedder())
        let result = try await base.search("ton app pour cyclistes", today: october)
        XCTAssertEqual(result.hits.first?.item.title, "Météo Vélo")
        let beach = try await base.search("journée à la plage", today: october)
        XCTAssertFalse(beach.hits.contains { $0.item.kind == .note })
    }

    /// "Un projet qui t'a mis sous pression": the story told in a project's Histoires section.
    func test_aBehaviouralQuestionFindsTheProjectsStory() async throws {
        try write("projets/tram-live.md", """
        ---
        nom: Tram Live
        pitch: Carte en temps réel des trams
        ---
        ## Le problème
        Les horaires affichés n'étaient pas fiables.

        ## Histoires
        ### Pression / deadline
        Démo au club dans 48 h et l'API des trams tombée : un cache local a sauvé la démo.
        ### Conflit ou désaccord
        Désaccord sur la carte : on a testé les deux versions.
        """)
        let base = try await indexedBase()

        let result = try await base.search("Raconte-moi un projet qui t'a mis sous pression.", today: october)

        XCTAssertEqual(result.hits.first?.item.section, "Histoires › Pression / deadline")
        XCTAssertEqual(result.decision(mode: .show).action, .show)
    }

    /// Personal retrieval must not pad a response with unrelated notes to reach a fixed count.
    func test_aPersonalTopicGetsOnlyRelevantExtracts_aTechnicalOneNone() async throws {
        let base = try await personalBase()

        let skills = await base.snippets(for: "Tu codes en quoi ?", today: october)
        XCTAssertTrue((1...5).contains(skills.count), "\(skills.count)")
        XCTAssertFalse(skills.contains { $0.source.contains("voyages/") })
        XCTAssertEqual(skills.first?.source, "CV › Compétences (cv.md)")

        let technical = await base.snippets(for: "Comment on équilibre un arbre binaire de recherche ?", today: october)
        XCTAssertEqual(technical, [])
    }

    /// The fiche the app shows is the one the search found, built in the Kit.
    func test_aPersonalQuestionComesBackWithItsFiche() async throws {
        let base = try await personalBase()

        let summer = await base.fiche(for: "T'étais où cet été ?", today: october)
        let found = try XCTUnwrap(summer)

        XCTAssertEqual(found.decision.action, .show)
        XCTAssertEqual(found.fiche.title, "Lisbonne et Porto, Portugal")
        let none = await base.fiche(for: "Comment on équilibre un arbre binaire de recherche ?", today: october)
        XCTAssertNil(none)
    }

    /// Offline or throttled: the photo is indexed without a place, and asked again next time.
    func test_aFailedPlaceLookupIsRetriedAtTheNextIndexing() async throws {
        try writePhoto("photos/portugal/ericeira.jpg", latitude: 38.9637, longitude: -9.4176)
        let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
        let places = FlakyPlaces()

        _ = try await BaseIndexer(index: index, embedder: WordHashEmbedder(), store: store, places: places).run(BaseSource(root: root))
        XCTAssertNil(try index.items().first { $0.item.kind == .photo }?.item.place)

        let second = try await BaseIndexer(index: index, embedder: WordHashEmbedder(), store: store, places: places).run(BaseSource(root: root))
        XCTAssertEqual(second.changedFiles, 1, "only the photo is read again")
        XCTAssertEqual(try index.items().first { $0.item.kind == .photo }?.item.place, "Ericeira, Portugal")
    }

    // MARK: Helpers

    private func personalBase() async throws -> PersonalBase {
        let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
        _ = try await BaseIndexer(index: index, embedder: WordHashEmbedder(), store: store).run(BaseSource(root: root))
        return PersonalBase(search: BaseSearch(index: index, embedder: WordHashEmbedder()), index: index, root: root)
    }

    private func writePhoto(_ path: String, latitude: Double, longitude: Double) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:07:10 10:30:00"],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: latitude, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: abs(longitude), kCGImagePropertyGPSLongitudeRef: "W",
            ],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func indexedBase() async throws -> BaseSearch {
        let index = try BaseIndex(url: store.appendingPathComponent("index.sqlite"))
        _ = try await BaseIndexer(index: index, embedder: WordHashEmbedder(), store: store).run(BaseSource(root: root))
        return BaseSearch(index: index, embedder: WordHashEmbedder())
    }

    private func write(_ path: String, _ content: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        // A new modification date even within the same second as the first write.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double.random(in: 1...1000))], ofItemAtPath: url.path)
    }
}

/// "Un échec et ce que tu en as appris": at equal confidence, the story before the section that
/// only shares the word "appris" (the on-device model ranks that one closer on the demo base).
final class StoryFirstTests: XCTestCase {
    func test_aBehaviouralQuestionPutsTheStoriesFirst_atEqualConfidence() {
        let lesson = SearchHit(item: item("projets/revisio.md#appris", "Ce que j'ai appris"), score: 0.03, confidence: 1)
        let story = SearchHit(item: item("projets/synthe.md#echec", "Histoires › Échec et ce que j'ai appris"), score: 0.02, confidence: 1)
        let doubt = SearchHit(item: item("projets/tram.md#conflit", "Histoires › Conflit ou désaccord"), score: 0.04, confidence: 0.5)

        let behavioural = QueryIntent(question: "Parle-moi d'un échec et de ce que tu en as appris.")
        XCTAssertEqual(SearchHit.ranked([lesson, story, doubt], for: behavioural).map(\.item.id),
                       [story.item.id, lesson.item.id, doubt.item.id])

        let plain = QueryIntent(question: "Qu'est-ce que tu as appris sur Revisio ?")
        XCTAssertEqual(SearchHit.ranked([lesson, story, doubt], for: plain).map(\.item.id),
                       [lesson.item.id, story.item.id, doubt.item.id])
    }

    private func item(_ id: String, _ section: String) -> BaseItem {
        BaseItem(id: id, kind: .project, source: String(id.prefix { $0 != "#" }), title: "Projet", section: section, text: section)
    }
}

/// Deterministic stand-in for the on-device model: words hashed into 64 buckets (FNV-1a, the
/// same from one run to the next, unlike `hashValue`).
struct WordHashEmbedder: TextEmbedder {
    let identifier = "test-word-hash"

    func vector(for text: String) -> [Float]? {
        var vector = [Float](repeating: 0, count: 64)
        for token in BaseText.tokens(of: text) {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in token.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
            vector[Int(hash % 64)] += 1
        }
        return vector
    }
}

/// Fails the first lookup (offline), answers the next ones.
final class FlakyPlaces: PlaceNamer, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func name(for coordinate: Coordinate) async throws -> String? {
        let call = lock.withLock { calls += 1; return calls }
        if call == 1 { throw URLError(.notConnectedToInternet) }
        return "Ericeira, Portugal"
    }
}
