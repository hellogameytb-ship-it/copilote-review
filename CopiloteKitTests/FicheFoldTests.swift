import XCTest
@testable import CopiloteKit

/// In a meeting, what to say comes first: once the answer has words, the fiche above it folds to
/// one line; until then it stays open (it is what shows in under a second).
final class FicheFoldTests: XCTestCase {
    func test_theFicheStaysOpenUntilTheAnswerHasWords_thenFolds() {
        var fold = FicheFold()
        fold.ficheShown()
        XCTAssertFalse(fold.isFolded)

        fold.answer(.waiting)
        XCTAssertFalse(fold.isFolded, "the answer is on its way: nothing moves yet")

        fold.answer(.reading)
        XCTAssertTrue(fold.isFolded)
    }

    /// A click opens it again, and the answer's next words don't fold it back; the next fiche
    /// starts open and folds with its own answer.
    func test_theUsersClickWinsUntilTheNextFiche() {
        var fold = FicheFold()
        fold.ficheShown()
        fold.answer(.reading)

        fold.toggle()
        XCTAssertFalse(fold.isFolded)
        fold.answer(.waiting)
        fold.answer(.reading)
        XCTAssertFalse(fold.isFolded, "the user opened it")

        fold.ficheShown()
        XCTAssertFalse(fold.isFolded)
        fold.answer(.reading)
        XCTAssertTrue(fold.isFolded)
    }

    /// A new answer asked, no words yet: never folded over nothing.
    func test_aNewAnswerWithNoWordsYetOpensTheFicheUntilItsWords() {
        var fold = FicheFold()
        fold.ficheShown()
        fold.answer(.reading)

        fold.answer(.waiting)
        XCTAssertFalse(fold.isFolded)
        fold.answer(.reading)
        XCTAssertTrue(fold.isFolded)
    }

    /// « Afficher » on a suggestion while an answer is read: the fiche opens, and stays open.
    func test_showingASuggestedFicheOpensIt() {
        var fold = FicheFold()
        fold.ficheShown()
        fold.answer(.reading)

        fold.open()

        XCTAssertFalse(fold.isFolded)
        fold.answer(.reading)
        XCTAssertFalse(fold.isFolded)
    }

    /// The answer went (withdrawn, cleared): nothing to read under the cases, the fiche opens.
    func test_whenTheAnswerGoesTheFicheOpens() {
        var fold = FicheFold()
        fold.ficheShown()
        fold.answer(.reading)

        fold.answer(.none)

        XCTAssertFalse(fold.isFolded)
    }
}

/// What the session shows under the fiche, from its answer: the phase that drives the fold.
final class AnswerPhaseTests: XCTestCase {
    func test_wordsAreReading_noWordsAreWaiting_aFailureWithoutWordsLeavesTheFicheOpen() {
        XCTAssertEqual(AnswerPhase(text: "", failed: false), .waiting)
        XCTAssertEqual(AnswerPhase(text: "Situation :", failed: false), .reading)
        XCTAssertEqual(AnswerPhase(text: "", failed: true), .none, "an error notice alone is no reason to hide the fiche")
        XCTAssertEqual(AnswerPhase(text: "Situation :", failed: true), .reading)
    }
}

/// Folded, a fiche still says what it is and what was asked about it.
final class FicheLineTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/base")

    func test_aFoldedFicheKeepsItsNameAndTheSectionAskedAbout() {
        let fields: [String: FrontmatterValue] = ["nom": .text("Revisio"), "pitch": .text("Quiz à partir de notes")]
        let summary = BaseItem(id: "projets/revisio.md#fiche", kind: .project, source: "projets/revisio.md", title: "Revisio",
                               text: "Revisio\nQuiz à partir de notes", fields: fields)
        let story = BaseItem(id: "projets/revisio.md#pression", kind: .project, source: "projets/revisio.md", title: "Revisio",
                             section: "Histoires › Pression / deadline", text: "Revisio\nTrois jours avant la démo…", fields: fields)

        let asked = Fiche(id: story.id, content: .project(ProjectCard(matched: story, fiche: [summary, story], root: root, diagram: nil)), items: [story])
        XCTAssertEqual(asked.foldedLine, FicheLine(title: "Revisio", detail: "Histoires › Pression / deadline"))

        let whole = Fiche(id: summary.id, content: .project(ProjectCard(matched: summary, fiche: [summary, story], root: root, diagram: nil)), items: [summary])
        XCTAssertEqual(whole.foldedLine, FicheLine(title: "Revisio", detail: nil))

        let trip = Fiche(id: "voyages/portugal.md#fiche", content: .trip(TripCard(place: "Lisbonne et Porto, Portugal", dates: "6–20 juil. 2026", summary: nil, photos: [])), items: [])
        XCTAssertEqual(trip.foldedLine, FicheLine(title: "Lisbonne et Porto, Portugal", detail: "6–20 juil. 2026"))

        let skills = BaseItem(id: "cv.md#competences", kind: .cv, source: "cv.md", title: "CV", section: "Compétences", text: "CV\nCompétences\n- Swift")
        XCTAssertEqual(Fiche(id: skills.id, content: .extract(Extract(skills)), items: [skills]).foldedLine, FicheLine(title: "Compétences", detail: nil))
    }
}
