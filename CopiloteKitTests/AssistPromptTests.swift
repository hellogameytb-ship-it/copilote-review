import XCTest
@testable import CopiloteKit

final class AssistPromptTests: XCTestCase {
    private let lines = [
        TranscriptLine(speaker: .them, text: "Comment tu inverserais une liste chaînée ?", start: 1, end: 3),
        TranscriptLine(speaker: .me, text: "Euh, en place je pense.", start: 4, end: 5),
        TranscriptLine(speaker: .them, text: "Et sans récursion ?", start: 6, end: 7),
    ]

    private func instruction(_ question: AssistQuestion) throws -> (text: String, blocks: [JSONValue]) {
        var conversation = Conversation()
        conversation.appendUser(.assist(question))
        let blocks = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue)
        return (try XCTUnwrap(blocks.last?["text"]?.stringValue), blocks)
    }

    /// Répondre: the case, what was said (switched-off phrases left out), and the structured format.
    func test_answerAskesForTheStructuredFormat_withTheChosenContext() throws {
        var context = AssistContext(lines: lines, captures: [], extracts: [])
        context.toggle(try XCTUnwrap(context.items.first { $0.label.contains("Euh") }).id)

        let text = try instruction(AssistQuestion(action: .answer, mode: .technical, question: "Inverser une liste chaînée",
                                                  heard: ["Comment tu inverserais une liste chaînée ?"], context: context)).text

        XCTAssertTrue(text.contains("Inverser une liste chaînée"), text)
        XCTAssertTrue(text.contains("Them : Et sans récursion ?"), text)
        XCTAssertFalse(text.contains("Euh, en place"), "switched off")
        for heading in ["## Approach", "## Code", "## Complexity", "## Key points", "## What I see", "## Answer"] {
            XCTAssertTrue(text.contains(heading), heading)
        }
        XCTAssertTrue(text.contains(MeetingMode.technical.tone), "the mode's tone")
    }

    /// Que dire: one sentence to read out, then two or three likely follow-ups.
    func test_whatToSayAsksForOneSentenceAndFollowUps() throws {
        let text = try instruction(AssistQuestion(action: .whatToSay, mode: .meeting, question: nil, heard: [], context: AssistContext(lines: lines))).text

        XCTAssertTrue(text.contains("**Say:**"), text)
        XCTAssertTrue(text.contains("## Likely follow-ups"), text)
        XCTAssertTrue(text.contains("2–3"), text)
    }

    /// Notes: the mode's own note sections, nothing that was not said.
    func test_notesFollowTheModesTemplate() throws {
        let meeting = try instruction(AssistQuestion(action: .notes, mode: .meeting, question: nil, heard: [], context: AssistContext(lines: lines))).text
        let talk = try instruction(AssistQuestion(action: .notes, mode: .presentation, question: nil, heard: [], context: AssistContext(lines: lines))).text

        XCTAssertTrue(meeting.contains("Decisions"), meeting)
        XCTAssertTrue(talk.contains("Audience questions"), talk)
        XCTAssertTrue(meeting.contains("Do not invent"), meeting)
    }

    func test_eachModeHasItsOwnTone() {
        XCTAssertEqual(Set(MeetingMode.allCases.map(\.tone)).count, 4)
        XCTAssertTrue(MeetingMode.friends.tone.contains("Relaxed"))
    }

    /// Captures go as images before the text, unless switched off.
    func test_includedCapturesAreAttached_excludedOnesAreNot() throws {
        var context = AssistContext(lines: [], captures: [.fake("énoncé"), .fake("schéma")], extracts: [])
        context.toggle(try XCTUnwrap(context.items.last).id)

        let blocks = try instruction(AssistQuestion(action: .answer, mode: .technical, question: nil, heard: [], context: context)).blocks

        XCTAssertEqual(blocks.map { $0["type"]?.stringValue }, ["image", "text"])
    }

    /// "Demander": the typed question, answered with what was just said.
    func test_aTypedQuestionIsAnsweredWithTheContext() throws {
        let text = try instruction(AssistQuestion(action: .answer, mode: .friends, question: "C'est quoi un tas binaire ?", heard: [],
                                                  context: AssistContext(lines: lines), typed: true)).text

        XCTAssertTrue(text.contains("My typed request: C'est quoi un tas binaire ?"), text)
    }
}

final class ConversationModeTests: XCTestCase {
    /// ⌥1-4, ⌘⇧↩ and ⌘⇧V follow the mode too: its tone and the structured answer format.
    func test_theExistingShortcutsAnswerInTheModesToneAndFormat() throws {
        var conversation = Conversation()
        conversation.mode = .friends

        conversation.appendUser(.topic(TopicQuestion(title: "Week-end", excerpt: ["Tu fais quoi samedi ?"], context: "", screenshots: [])))
        conversation.appendUser(.screenshots([.fake("énoncé")]))

        let topic = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue?.last?["text"]?.stringValue)
        let screens = try XCTUnwrap(conversation.messages.last?["content"]?.arrayValue?.last?["text"]?.stringValue)
        XCTAssertTrue(topic.contains(MeetingMode.friends.tone), topic)
        XCTAssertTrue(screens.contains("## What I see"), screens)
        XCTAssertTrue(screens.contains(MeetingMode.friends.tone), screens)
    }

    func test_withoutAModeNothingChanges() throws {
        var conversation = Conversation()
        conversation.appendUser(.clipboardText("Inverse une liste chaînée."))

        let text = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue?.last?["text"]?.stringValue)
        XCTAssertFalse(text.contains("Mode :"))
    }
}

final class ModeShapesTheAnswerTests: XCTestCase {
    /// A mode changes what is asked for, not only the tone: among friends no heavy structure,
    /// in a presentation a way back to the talk.
    func test_eachModeAsksForItsOwnKindOfAnswer() {
        let friends = Prompts.actionInstruction(.answer, mode: .friends)
        let talk = Prompts.actionInstruction(.answer, mode: .presentation)
        let say = Prompts.actionInstruction(.whatToSay, mode: .technical)

        XCTAssertTrue(friends.contains(MeetingMode.friends.answerGuidance), friends)
        XCTAssertTrue(talk.contains(MeetingMode.presentation.answerGuidance), talk)
        XCTAssertTrue(say.contains(MeetingMode.technical.answerGuidance), say)
        XCTAssertEqual(Set(MeetingMode.allCases.map(\.answerGuidance)).count, 4)
    }

    /// The end-of-meeting notes follow the mode too.
    func test_theEndNotesFollowTheMode() {
        let lines = [TranscriptLine(speaker: .them, text: "On part sur Postgres.", start: 1, end: 2)]

        let technical = MeetingNotesRequest.prompt(transcript: lines, mode: .technical)
        let friends = MeetingNotesRequest.prompt(transcript: lines, mode: .friends)

        XCTAssertTrue(technical.contains(MeetingMode.technical.notesFocus), technical)
        XCTAssertTrue(friends.contains(MeetingMode.friends.notesFocus), friends)
        XCTAssertNotEqual(technical, friends.replacingOccurrences(of: "Entre potes", with: "Technique"))
    }
}

final class SwitchedOffHeardTests: XCTestCase {
    /// A phrase switched off in the context is not sent either as "what they said" about the case.
    func test_aSwitchedOffPhraseLeavesTheCasesExcerptToo() throws {
        let line = TranscriptLine(speaker: .them, text: "Et sans récursion ?", start: 6, end: 7)
        var context = AssistContext(lines: [line], captures: [], extracts: [])
        context.toggle(try XCTUnwrap(context.items.first).id)
        var conversation = Conversation()

        conversation.appendUser(.assist(AssistQuestion(action: .answer, mode: .technical, question: "Liste chaînée",
                                                       heard: ["Comment tu l'inverserais ?", "Et sans récursion ?"], context: context)))

        let text = try XCTUnwrap(conversation.messages.first?["content"]?.arrayValue?.last?["text"]?.stringValue)
        XCTAssertTrue(text.contains("Comment tu l'inverserais ?"), text)
        XCTAssertFalse(text.contains("Et sans récursion"), text)
    }
}
