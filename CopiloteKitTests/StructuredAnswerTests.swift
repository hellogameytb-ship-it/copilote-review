import XCTest
@testable import CopiloteKit

final class StructuredAnswerTests: XCTestCase {
    func test_aCodeAnswerIsReadAsItsFourSections_evenWithHashesInTheCode() {
        let markdown = """
        On inverse les pointeurs en un passage.

        ## Approche
        Trois pointeurs : précédent, courant, suivant.

        ## Code
        ```python
        ## pas un titre : un commentaire
        def inverse(tete):
            prec = None
        ```

        ## Complexité
        O(n) en temps, O(1) en mémoire.

        ## Points clés
        - En place
        """

        let answer = StructuredAnswer(markdown: markdown)

        XCTAssertEqual(answer.lead, "On inverse les pointeurs en un passage.")
        XCTAssertEqual(answer.sections.map(\.title), ["Approche", "Code", "Complexité", "Points clés"])
        XCTAssertTrue(answer.sections[1].body.contains("## pas un titre"))
        XCTAssertEqual(answer.shape, .code)
    }

    func test_aCaptureAnswerAndAPlainOneAreToldApart() {
        XCTAssertEqual(StructuredAnswer(markdown: "## Ce que je vois\nUn graphe.\n## Réponse\nOui.\n## Points clés\n- a").shape, .capture)
        XCTAssertEqual(StructuredAnswer(markdown: "Je dirais oui.\n## Points clés\n- a").shape, .free)
    }

    /// Que dire: the sentence to read out, then the likely follow-ups with a short reply each.
    func test_whatToSayGivesTheSentenceAndTheFollowUps() throws {
        let markdown = """
        **À dire :** On peut livrer jeudi si on garde le périmètre actuel.

        ## Relances probables
        - « Et si on ajoute l'export ? » → Il faudrait une semaine de plus.
        - « Qui teste ? » → Moi, mercredi.
        - Et le budget ?
        """

        let say = try XCTUnwrap(WhatToSay(markdown: markdown))

        XCTAssertEqual(say.sentence, "On peut livrer jeudi si on garde le périmètre actuel.")
        XCTAssertEqual(say.followUps, [
            WhatToSay.FollowUp(question: "Et si on ajoute l'export ?", reply: "Il faudrait une semaine de plus."),
            WhatToSay.FollowUp(question: "Qui teste ?", reply: "Moi, mercredi."),
            WhatToSay.FollowUp(question: "Et le budget ?", reply: nil),
        ])
    }

    func test_anAnswerWithoutTheSentenceIsNotAWhatToSay() {
        XCTAssertNil(WhatToSay(markdown: "## Relances probables\n- a"))
    }
}
