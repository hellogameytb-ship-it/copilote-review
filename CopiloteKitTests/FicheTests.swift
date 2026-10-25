import XCTest
@testable import CopiloteKit

final class FicheTests: XCTestCase {
    func test_datesReadTheWayPeopleSayThem() {
        XCTAssertEqual(FicheText.dates(DateSpan(.day(2026, 7, 6), .day(2026, 7, 20))), "6–20 Jul 2026")
        XCTAssertEqual(FicheText.dates(DateSpan(.day(2025, 12, 20), .day(2026, 1, 2))), "20 Dec 2025 – 2 Jan 2026")
        XCTAssertEqual(FicheText.dates(DateSpan(.day(2024, 3, 1), .day(2024, 6, 30))), "Mar – Jun 2024")
        XCTAssertEqual(FicheText.dates(DateSpan(.day(2025, 10, 1), .day(2025, 10, 31)), ongoing: true), "since Oct 2025")
        XCTAssertEqual(FicheText.dates(DateSpan(.day(2026, 7, 10), .day(2026, 7, 10))), "10 Jul 2026")
    }

    /// Asked about a project's numbers, the card is still the project's, with that section first.
    func test_aProjectCardComesFromTheWholeFiche_withTheMatchedSectionFirst() {
        let root = URL(fileURLWithPath: "/base")
        let fields: [String: FrontmatterValue] = [
            "nom": .text("Revisio"), "pitch": .text("Quiz à partir de notes"), "stack": .list(["Next.js", "Supabase"]),
            "debut": .text("2025-10"), "liens": .list(["https://revisio.example"]), "captures": .list(["captures/revisio.png"]),
        ]
        let fiche = BaseItem(id: "projets/revisio.md#fiche", kind: .project, source: "projets/revisio.md", title: "Revisio",
                             text: "Revisio\nQuiz à partir de notes\nUne app web.", dates: DateSpan(start: "2025-10", end: nil), fields: fields)
        let problem = BaseItem(id: "projets/revisio.md#le-probleme", kind: .project, source: "projets/revisio.md", title: "Revisio",
                               section: "Le problème", text: "Revisio\nLe problème\nRéviser prend du temps.", fields: fields)
        let numbers = BaseItem(id: "projets/revisio.md#chiffres", kind: .project, source: "projets/revisio.md", title: "Revisio",
                               section: "Chiffres", text: "Revisio\nChiffres\n120 utilisateurs.", fields: fields)

        let card = ProjectCard(matched: numbers, fiche: [fiche, problem, numbers], root: root, diagram: nil)

        XCTAssertEqual(card.name, "Revisio")
        XCTAssertEqual(card.pitch, "Quiz à partir de notes")
        XCTAssertEqual(card.stack, ["Next.js", "Supabase"])
        XCTAssertEqual(card.dates, "since Oct 2025")
        XCTAssertEqual(card.capture?.path, "/base/projets/captures/revisio.png")
        XCTAssertEqual(card.highlights.map(\.title), ["Chiffres", "Le problème"])
        XCTAssertEqual(card.highlights.first?.text, "120 utilisateurs.")
        let asked = ProjectCard(matched: fiche, fiche: [fiche, problem, numbers], root: root, diagram: nil)
        XCTAssertEqual(asked.highlights.map(\.title), ["Chiffres", "Le problème"], "the key figures first when the fiche itself was found")
        XCTAssertTrue(card.answersWithASection, "the section asked about comes before the diagram")
        XCTAssertFalse(asked.answersWithASection)
    }

    func test_aCutExtractEndsOnAWord_withoutDoublePunctuation() {
        XCTAssertEqual(BaseContext.cut("Une API FastAPI découpe les notes. Elle construit des questions.", 36), "Une API FastAPI découpe les notes…")
    }
}
