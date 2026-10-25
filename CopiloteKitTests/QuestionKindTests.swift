import XCTest
@testable import CopiloteKit

final class QuestionKindTests: XCTestCase {
    private let october = CalendarDay.day(2026, 10, 19)

    /// Each kind gets its own answer format; the type comes from rules and the local classifier.
    func test_theKindOfEachQuestionInFrenchAndEnglish() {
        let examples: [(String, QuestionKind)] = [
            ("Parle-moi des ventes de peluches en 2027.", .estimation),
            ("Combien de pianistes il y a à Paris, à ton avis ?", .estimation),
            ("How many golf balls fit in a school bus?", .estimation),
            ("Quel chiffre d'affaires pour un food truck à Lyon ?", .estimation),
            ("C'est quoi la capitale de l'Australie ?", .fact),
            ("Quand a été signé le traité de Rome ?", .fact),
            ("Who invented the telephone?", .fact),
            ("C'est qui ton président des États-Unis préféré ?", .opinion),
            ("C'est quoi ton livre préféré ?", .opinion),
            ("Tu penses quoi du télétravail ?", .opinion),
            ("What's your favourite programming language?", .opinion),
            ("Raconte-moi un projet qui t'a mis sous pression.", .personal),
            ("Parle-moi d'un échec et de ce que tu en as appris.", .personal),
            ("Tell me about a time you disagreed with a teammate.", .personal),
            ("T'étais où cet été ?", .personal),
            ("Comment tu inverserais une liste chaînée sans récursion ?", .technical),
            ("Quelle est la complexité d'une recherche dans un arbre binaire ?", .technical),
            ("D'accord, merci beaucoup.", .none),
            ("On fait une pause de cinq minutes.", .none),
            // « ou » and « qui » are not questions on their own.
            ("Je pense qu'on pourrait livrer lundi ou mardi.", .none),
            ("C'est Marc qui s'occupe du support.", .none),
            // A story word in a technical question is not a story to tell, unless a story is asked for.
            ("Comment tu gères une erreur dans ton code ?", .technical),
            ("Raconte-moi une erreur de code qui t'a coûté cher.", .personal),
        ]
        for (question, kind) in examples {
            XCTAssertEqual(QuestionKind(question: question, today: october), kind, question)
        }
    }

    /// The year asked about tells a forecast from a past figure.
    func test_aFutureYearMakesItAProjection() {
        XCTAssertTrue(QuestionKind.asksAboutTheFuture("Parle-moi des ventes de peluches en 2027.", today: october))
        XCTAssertFalse(QuestionKind.asksAboutTheFuture("Les ventes de peluches en 2024 ?", today: october))
    }
}
