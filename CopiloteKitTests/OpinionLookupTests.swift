import XCTest
@testable import CopiloteKit

/// An opinion question is answered only from avis.md: one section per subject, matched by its title.
final class OpinionLookupTests: XCTestCase {
    private let opinions = BaseChunker.items(markdown: """
    # Mes avis
    ## Livre préféré
    L'Étranger de Camus, pour sa phrase sèche.
    ## Télétravail
    Deux jours par semaine : le calme pour coder, le bureau pour décider.
    ## Ville où vivre
    Lausanne : le lac, et tout se fait à vélo.
    """, path: "avis.md")

    func test_anOpinionIsFoundByItsSubject() {
        XCTAssertEqual(OpinionLookup.sections(for: "C'est quoi ton livre préféré ?", in: opinions).map(\.section), ["Livre préféré"])
        XCTAssertEqual(OpinionLookup.sections(for: "Tu penses quoi du télétravail ?", in: opinions).map(\.section), ["Télétravail"])
        XCTAssertEqual(OpinionLookup.sections(for: "Et tes livres préférés, alors ?", in: opinions).map(\.section), ["Livre préféré"])
    }

    /// "préféré" alone is no subject: the président is not in the base, nothing is found.
    func test_aSubjectThatIsNotThereFindsNothing() {
        XCTAssertEqual(OpinionLookup.sections(for: "C'est qui ton président des États-Unis préféré ?", in: opinions), [])
        XCTAssertEqual(OpinionLookup.sections(for: "Tu penses quoi de la peine de mort ?", in: opinions), [])
    }

    /// A section answers only if its whole subject is asked about, word for word (not on five shared letters).
    func test_aSectionThatOnlyShares_aWordOrAPrefix_isNotTheOpinion() {
        let more = opinions + BaseChunker.items(markdown: "# Mes avis\n## Langage de programmation préféré\nSwift, pour son typage.\n", path: "avis.md")
        XCTAssertEqual(OpinionLookup.sections(for: "Tu penses quoi du programme du parti X ?", in: more), [])
        XCTAssertEqual(OpinionLookup.sections(for: "Tu penses quoi de Lyon comme ville ?", in: more), [])
        XCTAssertEqual(OpinionLookup.sections(for: "C'est quoi ton langage de programmation préféré ?", in: more).map(\.section), ["Langage de programmation préféré"])
    }
}
