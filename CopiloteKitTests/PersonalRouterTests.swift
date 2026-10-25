import XCTest
@testable import CopiloteKit

final class SearchFusionTests: XCTestCase {
    /// Worked example, k = 60: x = 1/61 + 0.5/62 ≈ 0.02446, y = 1/62 + 0.5/61 ≈ 0.02433, z = 1/63.
    func test_reciprocalRankFusionWeighsEachRanking() {
        let fused = SearchFusion.fuse([(1, ["x", "y", "z"]), (0.5, ["y", "x"])])

        XCTAssertEqual(fused.map(\.id), ["x", "y", "z"])
        XCTAssertEqual(fused[0].score, 0.024458, accuracy: 1e-6)
        XCTAssertEqual(fused[2].score, 0.015873, accuracy: 1e-6)
    }
}

final class SearchEvidenceTests: XCTestCase {
    private let october = CalendarDay.day(2026, 10, 19)

    func test_aTripOfThatSummerIsFullyConfirmed_andOneOfAnotherYearIsNot() {
        let intent = QueryIntent(question: "T'étais où cet été ?", today: october)

        XCTAssertEqual(SearchEvidence.confidence(of: .trip("Lisbonne et Porto, Portugal", 2026), for: intent), 1, accuracy: 1e-9)
        XCTAssertEqual(SearchEvidence.confidence(of: .trip("Barcelone, Espagne", 2024), for: intent), 0.5, accuracy: 1e-9)
    }

    func test_coverageOfTheQuestionsWordsAndHints() {
        let motivation = QueryIntent(question: "Pourquoi tu veux faire un stage en finance quantitative ?", today: october)
        let internship = BaseItem.cv("Expériences › Stage développeuse backend — Logisto (juin 2025 – août 2025)", "API Python.")

        // Kind (0.5) + half of one word out of three (the hint "stage"; not finance, not quantitative).
        XCTAssertEqual(SearchEvidence.confidence(of: internship, for: motivation), 0.5 + 0.5 / 3, accuracy: 1e-9)
    }
}

final class PersonalRouterTests: XCTestCase {
    private let october = CalendarDay.day(2026, 10, 19)

    func test_aConfirmedPersonalQuestionShowsTheFiche_orSuggestsIt_orNothing_dependingOnTheMode() {
        let intent = QueryIntent(question: "T'étais où cet été ?", today: october)
        let portugal = BaseItem.trip("Lisbonne et Porto, Portugal", 2026)

        XCTAssertEqual(PersonalRouter(mode: .show).route(intent, best: portugal).action, .show)
        XCTAssertEqual(PersonalRouter(mode: .suggest).route(intent, best: portugal).action, .suggest)
        XCTAssertEqual(PersonalRouter(mode: .off).route(intent, best: portugal).action, .llm)
    }

    func test_aPartialMatchIsOnlySuggested_andTheLLMAnswers() {
        let intent = QueryIntent(question: "Pourquoi tu veux faire un stage en finance quantitative ?", today: october)
        let internship = BaseItem.cv("Expériences › Stage développeuse backend — Logisto (juin 2025 – août 2025)", "API Python.")

        XCTAssertEqual(PersonalRouter(mode: .show).route(intent, best: internship).action, .suggest)
    }

    func test_aTechnicalQuestionGoesToTheLLM_evenWhenANoteMentionsItsWords() {
        let intent = QueryIntent(question: "Quelle est la complexité d'une recherche dans un arbre binaire ?", today: october)
        let note = BaseItem(id: "notes/j.md#1", kind: .note, source: "notes/j.md", title: "Journal", section: "2026-03-02",
                            text: "Révisé la recherche dans un arbre binaire et sa complexité.")

        XCTAssertEqual(PersonalRouter(mode: .show).route(intent, best: note).action, .llm)
        XCTAssertEqual(PersonalRouter(mode: .show).route(intent, best: nil).action, .llm)
    }

    /// Naming a fiche ("Revisio") makes a question personal even when it is not addressed to you.
    func test_namingAFicheIsEnoughToShowIt() {
        let intent = QueryIntent(question: "Revisio, ça marche comment ?", today: october)
        let revisio = BaseItem(id: "projets/revisio.md#fiche", kind: .project, source: "projets/revisio.md", title: "Revisio",
                               text: "Revisio\nQuiz générés à partir de notes de cours")

        XCTAssertFalse(intent.isPersonal)
        XCTAssertEqual(PersonalRouter(mode: .show).route(intent, best: revisio).action, .show)
    }

    /// A place is a common word: "the capital of Japan" is not about the trip to Japan.
    func test_aPlaceNamedInAQuestionNotAddressedToYouIsNotEnough() {
        let intent = QueryIntent(question: "Quelle est la capitale du Japon ?", today: october)
        let japan = BaseItem.trip("Tokyo et Kyoto, Japon", 2025)

        XCTAssertEqual(PersonalRouter(mode: .show).route(intent, best: japan).action, .llm)
    }
}

extension BaseItem {
    static func trip(_ place: String, _ year: Int) -> BaseItem {
        BaseItem(id: "voyages/\(year).md#fiche", kind: .trip, source: "voyages/\(year).md", title: place, text: place,
                 dates: DateSpan(.day(year, 7, 6), .day(year, 7, 20)), place: place)
    }

    static func cv(_ section: String, _ text: String) -> BaseItem {
        BaseItem(id: "cv.md#\(section.slug)", kind: .cv, source: "cv.md", title: "CV", section: section,
                 text: "CV\n\(section)\n\(text)", dates: DateSpan(text: section))
    }
}
