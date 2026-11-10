import AppKit
import CopiloteKit

@MainActor
enum DiagnosticOpenQuestions {
    static func run(folder: URL, settings: SettingsStore, listening: ListeningController, assist: AssistController,
                    session: SessionController, fake: RecetteProvider, record: (String, Bool) -> Void) async {
        guard DiagnosticAnchorFixture.isRequested else { return }
        var checks: [[String: Any]] = []
        var inputs: [String] = []
        func check(_ name: String, _ passed: Bool) {
            checks.append(["name": name, "passed": passed])
            record(name, passed)
        }
        func sent(after count: Int) async -> String {
            for _ in 0..<400 {
                if await fake.conversations.count > count && !session.isAnswering { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard await fake.conversations.count == count + 1, let conversation = await fake.conversations.last else { return "" }
            let input = CodexPrompt.turnInput(for: conversation).compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
            inputs.append(input)
            return input
        }
        func ask(_ question: String) async -> String {
            let count = await fake.conversations.count
            assist.askText = question
            assist.submitAsk()
            return await sent(after: count)
        }

        await listening.stop()
        session.clear()
        await fake.resetConversations()
        settings.technicalInterviewActive = false
        let general = "How can two rhythms sound different at the same tempo?"
        let normal = await ask(general)
        check("open general Ask reaches the provider in Normal with no personal excerpts",
              normal.contains(general) && !normal.contains("Technical interview. Answer in English") && assist.context.includedExtracts.isEmpty)

        settings.technicalInterviewActive = true
        let cpp = "Explain why binding a const reference can extend the lifetime of a temporary in C++."
        let technical = await ask(cpp)
        check("general C++ Ask needs no personal source in technical interview",
              technical.contains(cpp) && technical.contains("hypothetical question directly") && assist.context.includedExtracts.isEmpty)

        session.clear()
        listening.beginRecetteConversation()
        let bridge = "Two couriers. One bridge. Fair alternating crossings, please."
        listening.receiveRecetteEvent(.line(TranscriptLine(speaker: .them, text: bridge, start: 1, end: 2), language: "fixture", latency: 0))
        let count = await fake.conversations.count
        await fake.replyNext("BRIDGE_ROTATION_FIXTURE")
        assist.answerNow()
        let live = await sent(after: count)
        check("uncategorized spoken Answer reaches provider once using the working conversation",
              QuestionKind(question: bridge) == .none && live.contains(bridge) && live.contains("last 120 seconds"))
        let followUp = "And if a third courier arrives?"
        let follow = await ask(followUp)
        check("elliptical typed follow-up carries the earlier exchange across Answer and Ask",
              follow.contains(followUp) && follow.contains(bridge) && follow.contains("BRIDGE_ROTATION_FIXTURE"))
        await listening.stop()
        session.clear()

        let opinion = "What is your favorite programming language?"
        let preferences = await ask(opinion)
        check("personal preference without sources reaches provider with neutral opinion guidance",
              preferences.contains(opinion) && preferences.contains("invent a first-person preference"))
        let current = "Who is the current president of fictional Exampleland?"
        let uncertain = await ask(current)
        check("time-sensitive Ask marks the controlled search as unavailable without claiming verification",
              uncertain.contains(current) && uncertain.contains("Web research was unavailable") && uncertain.contains("Do not present current facts as verified"))
        session.clear()
        let ambiguous = "Would that work here?"
        let clarification = await ask(ambiguous)
        check("ambiguous Ask reaches provider with focused clarification only where necessary",
              clarification.contains(ambiguous) && clarification.contains("only when ambiguity prevents a useful answer"))
        settings.technicalInterviewActive = false
        session.clear()
        try? JSONSerialization.data(withJSONObject: ["checks": checks, "syntheticCodexInputs": inputs, "liveAIRequests": 0, "webSearch": "controlled empty response"],
                                    options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("open-questions.json"))
    }
}
