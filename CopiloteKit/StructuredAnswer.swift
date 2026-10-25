import Foundation

/// An answer read back into its sections (`## Approche`, `## Code`…), code blocks left whole.
public struct StructuredAnswer: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public let title: String
        public let body: String
    }

    public enum Shape: Equatable, Sendable {
        /// Approche → Code → Complexité → Points clés.
        case code
        /// Ce que je vois → Réponse → Points clés.
        case capture
        case free
    }

    /// What comes before the first section.
    public let lead: String
    public let sections: [Section]

    public init(markdown: String) {
        var lead: [String] = []
        var sections: [(title: String, lines: [String])] = []
        var inCode = false
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle() }
            if !inCode, line.hasPrefix("## ") {
                sections.append((String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), []))
            } else if sections.isEmpty {
                lead.append(line)
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }
        self.lead = lead.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        self.sections = sections.map { Section(title: $0.title, body: $0.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    public var shape: Shape {
        let titles = Set(sections.map { BaseText.tokens(of: $0.title).joined(separator: " ") })
        if titles.contains("approche"), titles.contains("code") { return .code }
        if titles.contains("ce que je vois") { return .capture }
        return .free
    }
}

/// "Que dire": the sentence to read out, then the likely follow-ups.
public struct WhatToSay: Equatable, Sendable {
    public struct FollowUp: Equatable, Sendable {
        public let question: String
        public let reply: String?

        public init(question: String, reply: String?) {
            self.question = question
            self.reply = reply
        }
    }

    public let sentence: String
    public let followUps: [FollowUp]

    public init?(markdown: String) {
        let answer = StructuredAnswer(markdown: markdown)
        guard let match = answer.lead.firstMatch(of: /(?:\*\*)?(?:À dire|Say)\s*:\s*(?:\*\*)?\s*([\s\S]+)/) else { return nil }
        sentence = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
        let followUpSection = answer.sections.first { $0.title.lowercased().hasPrefix("relances") || $0.title.lowercased().hasPrefix("likely follow-ups") }?.body ?? ""
        followUps = followUpSection.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { return nil }
            let parts = trimmed.dropFirst(2).components(separatedBy: "→")
            let question = parts[0].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "«»\"")))
            let reply = parts.count > 1 ? parts.dropFirst().joined(separator: "→").trimmingCharacters(in: .whitespaces) : nil
            return question.isEmpty ? nil : FollowUp(question: question, reply: reply)
        }
    }
}
