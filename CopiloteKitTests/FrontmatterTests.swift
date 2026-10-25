import XCTest
@testable import CopiloteKit

final class FrontmatterTests: XCTestCase {
    func test_readsScalarsAndBothListForms_andKeepsTheBody() {
        let file = """
        ---
        nom: Revisio
        pitch: "Révise tes cours : quiz générés à partir de tes notes"   # une phrase
        stack: [Next.js, Supabase, "Python"]
        liens:
          - https://revisio.example/#demo
          - https://github.com/example/revisio
        fin:
        ---
        ## Le problème
        Réviser prend trop de temps.
        """

        let parsed = Frontmatter(markdown: file)

        XCTAssertEqual(parsed.fields["nom"], .text("Revisio"))
        XCTAssertEqual(parsed.fields["pitch"], .text("Révise tes cours : quiz générés à partir de tes notes"))
        XCTAssertEqual(parsed.fields["stack"], .list(["Next.js", "Supabase", "Python"]))
        XCTAssertEqual(parsed.fields["liens"], .list(["https://revisio.example/#demo", "https://github.com/example/revisio"]))
        XCTAssertNil(parsed.fields["fin"], "an empty value is no value")
        XCTAssertEqual(parsed.body, "## Le problème\nRéviser prend trop de temps.")
    }

    func test_aFileWithoutFrontmatterIsAllBody() {
        let parsed = Frontmatter(markdown: "# Idées\r\n- une note\r\n")

        XCTAssertTrue(parsed.fields.isEmpty)
        XCTAssertEqual(parsed.body, "# Idées\n- une note")
    }
}

final class CalendarDayTests: XCTestCase {
    func test_partialDatesCoverTheWholeMonthOrYear() {
        XCTAssertEqual(DateSpan(start: "2025-07-04", end: "2025-07-18"), DateSpan(.day(2025, 7, 4), .day(2025, 7, 18)))
        XCTAssertEqual(DateSpan(start: "2025-07", end: nil), DateSpan(.day(2025, 7, 1), .day(2025, 7, 31)))
        XCTAssertEqual(DateSpan(start: "2024", end: "2025-02"), DateSpan(.day(2024, 1, 1), .day(2025, 2, 28)))
        XCTAssertNil(DateSpan(start: "bientôt", end: nil))
    }

    func test_readsTheDatesOfACVHeading() {
        XCTAssertEqual(DateSpan(text: "Stage backend — Logisto, Lyon (juin 2024 – août 2024)"), DateSpan(.day(2024, 6, 1), .day(2024, 8, 31)))
        XCTAssertEqual(DateSpan(text: "Licence d'informatique, 2021–2024"), DateSpan(.day(2021, 1, 1), .day(2024, 12, 31)))
        XCTAssertEqual(DateSpan(text: "Assistante de cours (sept. 2025 - aujourd'hui)", today: .day(2026, 10, 19)), DateSpan(.day(2025, 9, 1), .day(2026, 10, 19)))
        XCTAssertNil(DateSpan(text: "Langages et outils"))
    }

    func test_overlap() {
        let trip = DateSpan(.day(2026, 7, 4), .day(2026, 7, 18))

        XCTAssertTrue(trip.overlaps(DateSpan(.day(2026, 6, 1), .day(2026, 8, 31))))
        XCTAssertFalse(trip.overlaps(DateSpan(.day(2025, 6, 1), .day(2025, 8, 31))))
    }
}
