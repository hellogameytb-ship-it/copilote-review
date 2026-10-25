import AppKit
import CopiloteKit

@MainActor
enum DiagnosticGroundedAnswers {
    static func run(folder: URL, record: (String, Bool) -> Void) async {
        guard ProcessInfo.processInfo.arguments.contains("-RecetteInterviewCodex") else { return }
        guard let executable = CodexAvailability.locate(), CodexAvailability.isReady(executable: executable) else { record("real interview provider available", false); return }
        var server: CodexAppServer?
        defer { server?.terminateNow() }
        do {
            let config = try CodexAvailability.userConfig() ?? ""
            if let issue = CodexLaunch.problem(inUserConfig: config) { throw CodexFailure(message: issue) }
            let connection = CodexAppServer(executable: executable, workingDirectory: CodexAvailability.workingDirectory, privateDirectory: folder.appendingPathComponent("private-interview-codex"), loadUserConfig: { try CodexAvailability.userConfig() })
            server = connection
            let provider = CodexProvider(server: connection, answerModel: CodexProvider.defaultModel, topicModel: CodexProvider.defaultModel, serviceTier: nil)
            let source = BaseSnippet(source: "Fictional CV › Orion", text: "Orion is a fictional personal study app. I implemented it in Swift with SQLite. It has no measured performance results. No other stack or user-count facts are available.")
            var lines = [TranscriptLine(speaker: .them, text: "Do not claim results that have not been measured. Explain tradeoffs.", start: 0, end: 4), TranscriptLine(speaker: .me, text: "I designed Orion's offline-first study workflow.", start: 5, end: 8)]
            for minute in 1...65 { lines.append(TranscriptLine(speaker: minute % 2 == 0 ? .me : .them, text: "We discussed interview detail \(minute).", start: Double(minute * 60), end: Double(minute * 60 + 5))) }
            for (name, request, kind) in [("project", "Present your project Orion and its stack.", QuestionKind.personal), ("measure", "Then measure this: propose a benchmark for Orion, respecting what we said at the start.", .technical)] {
                let question = AssistQuestion(action: .answer, mode: .technical, question: request, heard: [request], context: AssistContext(lines: lines, extracts: [source]), format: AnswerFormat(kind: kind))
                var conversation = Conversation(); conversation.appendUser(.assist(question))
                let message = try await provider.streamAnswer(to: conversation) { _ in }
                let text = message.content.compactMap { $0["text"]?.stringValue }.joined()
                try text.write(to: folder.appendingPathComponent("real-\(name).md"), atomically: true, encoding: .utf8)
                if name == "project" { record("real provider grounds project in fictional CV and user's voice", text.contains("Swift") && text.contains("SQLite") && text.lowercased().contains("offline") && !text.contains("React")) }
                else { record("real provider distinguishes proposed measurement from actual results", text.lowercased().contains("benchmark") && (text.lowercased().contains("not") || text.lowercased().contains("no measured"))) }
            }
            func screenshot(_ text: String) -> CapturedImage? {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 300).fill()
                text.draw(in: NSRect(x: 25, y: 25, width: 850, height: 250), withAttributes: [.foregroundColor: NSColor.black, .font: NSFont.monospacedSystemFont(ofSize: 23, weight: .medium)])
                NSGraphicsContext.restoreGraphicsState()
                return bitmap.cgImage.flatMap { ImageEncoder.encodeForModel($0) }
            }
            let shots = [screenshot("PROBLEM — page 1\nWrite Python first_unique(nums).\nReturn the INDEX of the first unique integer.\nUse O(n) time; do not sort the input."), screenshot("PROBLEM — page 2 (overlap)\nReturn the INDEX of the first unique integer.\nIf none exists, return -1. Empty input: -1.\nExample: [2, 2, 3, 4, 3] returns 3.")].compactMap { $0 }
            var visual = Conversation()
            visual.appendUser(.assist(AssistQuestion(action: .answer, mode: .technical, question: "Solve this scrolling problem across the ordered screenshots. Give runnable Python and verify the examples.", heard: [], context: AssistContext(captures: shots))))
            let visualMessage = try await provider.streamAnswer(to: visual) { _ in }
            let visualText = visualMessage.content.compactMap { $0["text"]?.stringValue }.joined()
            try visualText.write(to: folder.appendingPathComponent("real-screenshots.md"), atomically: true, encoding: .utf8)
            record("real provider reads both overlapping coding screenshots", shots.count == 2 && visualText.contains("first_unique") && visualText.contains("-1") && visualText.contains("3") && visualText.lowercased().contains("o(n)"))
            let project = Topic(id: "project", title: "Present your project Orion", excerpt: ["Present your project Orion"], createdAt: Date(), updatedAt: Date())
            let measurement = Topic(id: "measurement", title: "Measure Orion performance", excerpt: ["Then measure this"], createdAt: Date(), updatedAt: Date())
            let decision = try await provider.topicSegmenter.decide(turn: Turn(speaker: .them, text: "Which stack for Orion", start: 4000, end: 4003), topics: [measurement, project], context: "Me: I built Orion with Swift and SQLite.")
            if case let .continueTopic(id, _) = decision { record("real segmenter routes named stack follow-up to older project card", id == "project") }
            else { record("real segmenter routes named stack follow-up to older project card", false) }
        } catch { record("real interview provider error: \(error.localizedDescription)", false) }
    }
}
