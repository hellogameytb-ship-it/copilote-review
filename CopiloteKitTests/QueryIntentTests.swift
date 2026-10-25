import XCTest
@testable import CopiloteKit

final class QueryIntentTests: XCTestCase {
    private let october = CalendarDay.day(2026, 10, 19)

    func test_whereWereYouThisSummer_looksForTripsAndPhotosOfTheSummerJustPast() {
        let intent = QueryIntent(question: "T'étais où cet été ?", today: october)

        XCTAssertTrue(intent.isPersonal)
        XCTAssertEqual(intent.kinds, [.trip, .photo])
        XCTAssertEqual(intent.period, DateSpan(.day(2026, 6, 1), .day(2026, 8, 31)))
    }

    func test_inJuly_lastSummerIsLastYearsSummer() {
        let intent = QueryIntent(question: "Where did you go last summer?", today: .day(2026, 7, 10))

        XCTAssertTrue(intent.isPersonal)
        XCTAssertEqual(intent.kinds, [.trip, .photo])
        XCTAssertEqual(intent.period, DateSpan(.day(2025, 6, 1), .day(2025, 8, 31)))
    }

    func test_aProjectQuestionKeepsItsContentWords_notTheCueWords() {
        let intent = QueryIntent(question: "C'est quoi ton projet d'app de révision ?", today: october)

        XCTAssertTrue(intent.isPersonal)
        XCTAssertEqual(intent.kinds, [.project])
        XCTAssertEqual(intent.terms.map(\.word), ["revision"])
        XCTAssertNil(intent.period)
    }

    /// Spoken questions start with "Génial", "Salut", "OK"…: not words a fiche should contain.
    func test_interjectionsAreNotContentWords() {
        let intent = QueryIntent(question: "Génial. Et sinon, c'est quoi ton projet d'app de révision ?", today: october)

        XCTAssertEqual(intent.terms.map(\.word), ["revision"])
    }

    func test_whatDoYouCodeIn_pointsAtTheCVSkills() throws {
        let intent = QueryIntent(question: "Tu codes en quoi ?", today: october)

        XCTAssertTrue(intent.isPersonal)
        XCTAssertEqual(intent.kinds, [.cv])
        let hint = try XCTUnwrap(intent.terms.first)
        XCTAssertTrue(hint.matches(BaseText("Compétences\n- Langages : Python, Swift")))
    }

    func test_technicalQuestionsAreNotPersonal_evenAddressedToYou() {
        for question in [
            "Tu peux m'expliquer comment fonctionne le ramasse-miettes en Java ?",
            "Quelle est la complexité d'une recherche dans un arbre binaire équilibré ?",
            "D'accord, merci.",
        ] {
            XCTAssertFalse(QueryIntent(question: question, today: october).isPersonal, question)
        }
    }

    func test_aMonthAndYear_andPhotosOfAPlace() {
        let april = QueryIntent(question: "Et toi, tu as fait quoi en avril 2025 ?", today: october)
        XCTAssertEqual(april.period, DateSpan(.day(2025, 4, 1), .day(2025, 4, 30)))
        XCTAssertTrue(april.isPersonal)

        let photos = QueryIntent(question: "Montre-moi tes photos du Japon", today: october)
        XCTAssertEqual(photos.kinds, [.photo, .trip])
        XCTAssertEqual(photos.terms.map(\.word), ["japon"])
    }

    /// No cue word: the small local classifier recognises the kind from its examples' vocabulary.
    func test_theLocalClassifierCatchesPhrasingsWithoutCueWords() {
        let stay = QueryIntent(question: "Alors, ton séjour là-bas, c'était bien la plage ?", today: october)
        XCTAssertTrue(stay.isPersonal)
        XCTAssertTrue(stay.kinds.contains(.trip))

        let weekend = QueryIntent(question: "Tu fais quoi le week-end en général ?", today: october)
        XCTAssertTrue(weekend.isPersonal)
        XCTAssertEqual(weekend.kinds, [.bio])
    }
}
