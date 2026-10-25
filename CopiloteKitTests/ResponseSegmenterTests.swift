import XCTest
@testable import CopiloteKit

final class ResponseSegmenterTests: XCTestCase {
    func test_splitsACompleteMermaidBlockOutOfTheMarkdown() {
        let answer = """
        **Idée** : un graphe.

        ```mermaid
        graph TD
          A --> B
        ```

        Complexité O(n).
        """

        XCTAssertEqual(ResponseSegmenter.segments(of: answer, isFinal: true), [
            .markdown("**Idée** : un graphe.\n\n"),
            .diagram(source: "graph TD\n  A --> B", isComplete: true),
            .markdown("\nComplexité O(n)."),
        ])
    }

    func test_aMermaidBlockStillStreamingIsIncomplete() {
        let partial = "Voici l'archi :\n```mermaid\ngraph LR\n  Client --> Ser"

        XCTAssertEqual(ResponseSegmenter.segments(of: partial, isFinal: false), [
            .markdown("Voici l'archi :\n"),
            .diagram(source: "graph LR\n  Client --> Ser", isComplete: false),
        ])
    }

    func test_aClosingFenceWithoutNewlineOnlyCountsOnceTheAnswerIsFinal() {
        // "```" at the very end could still grow into "````" or more text.
        let text = "```mermaid\ngraph TD\n  A --> B\n```"

        XCTAssertEqual(ResponseSegmenter.segments(of: text, isFinal: false), [
            .diagram(source: "graph TD\n  A --> B\n```", isComplete: false),
        ])
        XCTAssertEqual(ResponseSegmenter.segments(of: text, isFinal: true), [
            .diagram(source: "graph TD\n  A --> B", isComplete: true),
        ])
    }

    func test_aMermaidExampleInsideALongerFenceStaysMarkdown() {
        // The inner ``` lines are shorter than the opening ```` fence, so they don't close it.
        let text = "````markdown\n```mermaid\ngraph TD\n```\n```mermaid\nx\n```\n````\n"

        XCTAssertEqual(ResponseSegmenter.segments(of: text, isFinal: true), [.markdown(text)])
    }

    func test_otherCodeBlocksStayMarkdown_andAMermaidBlockAfterThemIsStillFound() {
        let text = "```python\nprint('```mermaid')\n```\n~~~ Mermaid\nflowchart TD\n~~~~\n"

        XCTAssertEqual(ResponseSegmenter.segments(of: text, isFinal: true), [
            .markdown("```python\nprint('```mermaid')\n```\n"),
            .diagram(source: "flowchart TD", isComplete: true),
        ])
    }

    func test_plainMarkdownIsASingleSegment() {
        let text = "Idée : deux pointeurs.\n\n```swift\nlet x = 1\n"

        XCTAssertEqual(ResponseSegmenter.segments(of: text, isFinal: false), [.markdown(text)])
    }
}
