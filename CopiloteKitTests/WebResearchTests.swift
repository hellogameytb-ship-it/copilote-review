import XCTest
@testable import CopiloteKit

final class WebResearchTests: XCTestCase {
    func test_currentPublicQuestionsOnly() {
        XCTAssertTrue(WebResearch.needsSearch("Qui est le président actuel de la France ?"))
        XCTAssertTrue(WebResearch.needsSearch("What is the latest Swift version?"))
        XCTAssertFalse(WebResearch.needsSearch("Quelle est ma dernière expérience professionnelle ?"))
        XCTAssertFalse(WebResearch.needsSearch("Quel est mon projet actuel ? api_key: fictitious"))
        XCTAssertFalse(WebResearch.needsSearch("Explique un arbre binaire"))
    }
    func test_searchDropsQuestionAndCitationBoilerplate() {
        XCTAssertEqual(WebResearch.publicQuery("Qui est le président actuel de la France ? Cite les sources web fournies."), "president actuel france")
    }
    func test_rssDecodingPreservesSourceAndRejectsUnsafeLink() {
        let xml = "<rss><channel><item><title>Exemple &amp; preuve</title><link>https://example.org/fact</link><description>Fait sourcé.</description></item><item><title>Bad</title><link>javascript:alert(1)</link><description>Bad</description></item></channel></rss>"
        let sources = WebResearch.parse(Data(xml.utf8))
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.title, "Exemple & preuve")
        XCTAssertEqual(sources.first?.url, "https://example.org/fact")
        XCTAssertTrue(WebResearch.instruction(sources: [], attempted: true).contains("do not invent links"))
    }
}
