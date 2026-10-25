import XCTest
@testable import CopiloteKit

/// An opinion question not in avis.md must not come back with an opinion in the user's mouth.
final class OpinionGuardTests: XCTestCase {
    func test_aFirstPersonOpinionIsCaught() {
        for text in [
            "Personnellement, je préfère Obama.",
            "Mon président préféré, c'est Lincoln.",
            "À mon avis, Roosevelt reste le plus marquant.",
            "**À dire :** « Je dirais Kennedy, pour son charisme. »",
            "J'admire beaucoup Lincoln.",
            "I'd say my favourite is Lincoln.",
            "In my opinion, FDR.",
        ] {
            XCTAssertNotNil(OpinionGuard.firstPersonOpinion(in: text), text)
        }
    }

    func test_neutralAnglesPass() {
        let angles = """
        ## Angles possibles
        - **Le bilan économique** : certains retiennent la croissance des années Clinton.
        - **La politique étrangère** : d'autres citent Roosevelt pendant la guerre.
        - **Le symbole** : Lincoln reste associé à l'abolition de l'esclavage.
        """
        XCTAssertNil(OpinionGuard.firstPersonOpinion(in: angles))
    }

    func test_onlyAnOpinionQuestionWithNothingInAvisIsWatched() {
        let missing = AssistQuestion(action: .answer, mode: .meeting, question: "Président préféré", heard: [], context: AssistContext(), format: AnswerFormat(kind: .opinion))
        let found = AssistQuestion(action: .answer, mode: .meeting, question: "Livre préféré", heard: [], context: AssistContext(extracts: [BaseSnippet(source: "avis.md", text: "L'Étranger")]), format: AnswerFormat(kind: .opinion))
        XCTAssertTrue(missing.isOpinionMissing)
        XCTAssertFalse(found.isOpinionMissing)
    }
}
