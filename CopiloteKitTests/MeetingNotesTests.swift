import XCTest
@testable import CopiloteKit

final class MeetingNotesTests: XCTestCase {
    private let transcript = [
        TranscriptLine(speaker: .them, text: "On part sur une sortie le 12 novembre.", start: 1, end: 3),
        TranscriptLine(speaker: .me, text: "D'accord, je prépare la démo pour jeudi.", start: 4, end: 6),
        TranscriptLine(speaker: .them, text: "Reste à savoir qui gère le support.", start: 7, end: 9),
        TranscriptLine(speaker: .them, text: "On refait un point vendredi.", start: 10, end: 11),
    ]

    private let answer = """
    {"titre": "Sortie du 12 novembre",
     "points_cles": [{"texte": "Sortie prévue le 12 novembre", "preuve": "une sortie le 12 novembre"}],
     "decisions": [{"texte": "Date de sortie fixée", "preuve": "On part sur une sortie le 12 novembre"},
                   {"texte": "Budget validé à 20 k€", "preuve": "le budget est validé"}],
     "actions": [{"texte": "Préparer la démo", "qui": "Moi", "preuve": "je prépare la démo pour jeudi"}],
     "questions_ouvertes": [{"texte": "Qui gère le support ?", "preuve": "qui gère le support"}],
     "suite": [{"texte": "Point vendredi", "preuve": "On refait un point vendredi"}]}
    """

    /// Nothing invented: an item whose quote is not in the transcript goes.
    func test_itemsWithoutAQuoteFromTheTranscriptAreDropped() throws {
        let notes = try MeetingNotesRequest.notes(fromJSON: answer, transcript: transcript)

        XCTAssertEqual(notes.title, "Sortie du 12 novembre")
        XCTAssertEqual(notes.decisions.map(\.text), ["Date de sortie fixée"], "the budget was never mentioned")
        XCTAssertEqual(notes.actions.map(\.text), ["Préparer la démo"])
        XCTAssertEqual(notes.actions.first?.owner, "Moi")
        XCTAssertEqual(notes.openQuestions.map(\.text), ["Qui gère le support ?"])
    }

    func test_theFiveSectionsInOrder_actionsAsBoxesToTick() throws {
        let notes = try MeetingNotesRequest.notes(fromJSON: answer, transcript: transcript)

        let markdown = notes.markdown

        let headings = markdown.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }
        XCTAssertEqual(headings, ["## Key points", "## Decisions", "## Actions", "## Open questions", "## Next steps"])
        XCTAssertTrue(markdown.contains("- [ ] Préparer la démo (Moi)"), markdown)
    }

    /// The follow-up email is written from the kept notes only, in the mode's tone.
    func test_theFollowUpEmailUsesOnlyWhatWasKept() throws {
        let notes = try MeetingNotesRequest.notes(fromJSON: answer, transcript: transcript)

        let email = notes.email(mode: .meeting)
        XCTAssertEqual(email.subject, "Follow-up: Sortie du 12 novembre")
        XCTAssertTrue(email.body.hasPrefix("Hello,"))
        XCTAssertTrue(email.body.contains("- Date de sortie fixée"))
        XCTAssertTrue(email.body.contains("- Préparer la démo (Moi)"))
        XCTAssertFalse(email.body.contains("20 k€"))

        XCTAssertTrue(notes.email(mode: .friends).body.hasPrefix("Hi,"))
    }

    func test_anEmptySectionStaysEmpty_andIsLeftOutOfTheEmail() throws {
        let notes = try MeetingNotesRequest.notes(fromJSON: #"{"titre": "", "points_cles": [], "decisions": [], "actions": [], "questions_ouvertes": [], "suite": []}"#, transcript: transcript)

        XCTAssertTrue(notes.markdown.contains("## Decisions\n_None._"), notes.markdown)
        XCTAssertFalse(notes.email(mode: .meeting).body.contains("Next steps"))
    }

    func test_theRequestCarriesTheTranscriptAndTheRule() {
        let prompt = MeetingNotesRequest.prompt(transcript: transcript, mode: .technical)

        XCTAssertTrue(prompt.contains("Them : On part sur une sortie le 12 novembre."))
        XCTAssertTrue(prompt.contains("Me : D'accord, je prépare la démo pour jeudi."))
        XCTAssertTrue(prompt.contains("preuve"))
        XCTAssertEqual(MeetingNotesRequest.schema["required"], ["titre", "points_cles", "decisions", "actions", "questions_ouvertes", "suite"])
    }
}

final class SelfReviewTests: XCTestCase {
    private let transcript = [
        TranscriptLine(speaker: .them, text: "Pourquoi ce choix de base de données ?", start: 1, end: 3),
        TranscriptLine(speaker: .me, text: "Euh, en fait, c'était un peu au feeling, Postgres quoi.", start: 4, end: 7),
    ]

    /// Only my own phrases are reviewed; a rephrasing of something I never said goes.
    func test_onlyMyPhrases_andRephrasingsOfWhatIActuallySaid() throws {
        let prompt = SelfReviewRequest.prompt(transcript: transcript)
        XCTAssertTrue(prompt.contains("c'était un peu au feeling"))
        XCTAssertFalse(prompt.contains("Pourquoi ce choix"))

        let review = try SelfReviewRequest.review(fromJSON: """
        {"points_forts": ["Réponse directe"], "a_ameliorer": ["Justifier le choix"],
         "reformulations": [{"original": "c'était un peu au feeling, Postgres quoi", "mieux": "J'ai choisi Postgres pour ses transactions."},
                            {"original": "je ne sais pas", "mieux": "Bonne question."}]}
        """, transcript: transcript)

        XCTAssertEqual(review.strengths, ["Réponse directe"])
        XCTAssertEqual(review.rephrasings.map(\.better), ["J'ai choisi Postgres pour ses transactions."])
    }
}
