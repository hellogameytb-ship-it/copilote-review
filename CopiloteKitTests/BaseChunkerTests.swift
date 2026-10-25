import XCTest
@testable import CopiloteKit

final class BaseChunkerTests: XCTestCase {
    func test_aProjectGivesItsFicheThenOneItemPerSection() throws {
        let markdown = """
        ---
        nom: Revisio
        pitch: Révise tes cours avec des quiz générés à partir de tes notes
        stack: [Next.js, Supabase]
        debut: 2025-09
        ---
        Une app web pour les étudiants.

        ## Le problème
        Réviser prend trop de temps.

        ## Chiffres
        120 utilisateurs la première semaine.
        """

        let items = BaseChunker.items(markdown: markdown, path: "projets/revisio.md")

        XCTAssertEqual(items.map(\.id), ["projets/revisio.md#fiche", "projets/revisio.md#le-probleme", "projets/revisio.md#chiffres"])
        XCTAssertEqual(Set(items.map(\.kind)), [.project])
        XCTAssertEqual(Set(items.map(\.title)), ["Revisio"])
        XCTAssertEqual(items.map(\.section), [nil, "Le problème", "Chiffres"])
        let fiche = try XCTUnwrap(items.first)
        XCTAssertTrue(fiche.text.contains("quiz générés"))
        XCTAssertTrue(fiche.text.contains("Next.js"))
        XCTAssertTrue(fiche.text.contains("Une app web pour les étudiants."))
        XCTAssertEqual(fiche.dates, DateSpan(.day(2025, 9, 1), .day(2025, 9, 30)))
        XCTAssertEqual(fiche.fields["stack"], .list(["Next.js", "Supabase"]))
        XCTAssertTrue(items[2].text.contains("120 utilisateurs"))
    }

    func test_theCVIsCutByExperience_andASectionWithoutEntriesStaysWhole() {
        let markdown = """
        # CV
        ## Expériences
        ### Stage backend — Logisto, Lyon (juin 2024 – août 2024)
        API de suivi de colis en Go.
        ### Assistante de cours, algèbre linéaire (2025–2026)
        Séances d'exercices.
        ## Compétences
        - Langages : Python, Swift, Go
        - Outils : Git, Docker
        """

        let items = BaseChunker.items(markdown: markdown, path: "cv.md", today: .day(2026, 10, 19))

        XCTAssertEqual(items.map(\.section), [
            "Expériences › Stage backend — Logisto, Lyon (juin 2024 – août 2024)",
            "Expériences › Assistante de cours, algèbre linéaire (2025–2026)",
            "Compétences",
        ])
        XCTAssertEqual(items.map(\.kind), [.cv, .cv, .cv])
        XCTAssertEqual(items[0].dates, DateSpan(.day(2024, 6, 1), .day(2024, 8, 31)))
        XCTAssertNil(items[2].dates)
        XCTAssertTrue(items[2].text.contains("Python, Swift, Go"))
    }

    func test_aTripCarriesItsPlaceAndDates() throws {
        let markdown = """
        ---
        lieu: Lisbonne, Portugal
        debut: 2026-07-04
        fin: 2026-07-18
        photos: photos/portugal-2026
        ---
        ## Moments forts
        Surf à Ericeira.
        """

        let fiche = try XCTUnwrap(BaseChunker.items(markdown: markdown, path: "voyages/portugal-2026.md").first)

        XCTAssertEqual(fiche.kind, .trip)
        XCTAssertEqual(fiche.title, "Lisbonne, Portugal")
        XCTAssertEqual(fiche.place, "Lisbonne, Portugal")
        XCTAssertEqual(fiche.dates, DateSpan(.day(2026, 7, 4), .day(2026, 7, 18)))
    }

    /// The templates Copilote creates hold only comments and empty fields: nothing to index.
    func test_anUnfilledTemplateGivesNothing() {
        let template = """
        ---
        nom:        # Nom du projet
        pitch:      # Une phrase
        stack: []
        ---
        <!-- Décris le projet ici.
             Plusieurs lignes de conseils. -->

        ## Le problème
        <!-- Quel problème ça résout ? -->

        ## Chiffres
        """

        XCTAssertTrue(BaseChunker.items(markdown: template, path: "projets/mon-projet.md").isEmpty)
    }

    /// A journal's entries are dated by their heading.
    func test_aSectionTitledWithADayIsDatedThatDay() {
        let items = BaseChunker.items(markdown: "# Journal\n## 2026-07-08\nJournée à la plage.\n## Idées\nRien.", path: "notes/journal.md")

        XCTAssertEqual(items.map(\.dates), [DateSpan(.day(2026, 7, 8), .day(2026, 7, 8)), nil])
    }

    func test_theKindComesFromWhereTheFileIs() {
        XCTAssertEqual(BaseChunker.kind(forPath: "notes/lectures/2026.md"), .note)
        XCTAssertEqual(BaseChunker.kind(forPath: "reference/lettre.txt"), .reference)
        XCTAssertEqual(BaseChunker.kind(forPath: "bio.md"), .bio)
        XCTAssertNil(BaseChunker.kind(forPath: "projets/_modele.md"), "templates start with _")
        XCTAssertNil(BaseChunker.kind(forPath: "LISEZMOI.md"))
    }
}
