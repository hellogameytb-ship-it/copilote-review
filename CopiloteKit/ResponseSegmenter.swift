import Foundation

/// A piece of the model's answer, as the overlay renders it.
public enum ResponseSegment: Equatable, Sendable {
    case markdown(String)
    /// `isComplete` turns true once the closing fence has arrived (or the answer is final):
    /// only then is the diagram worth handing to Mermaid.
    case diagram(source: String, isComplete: Bool)
}

/// Splits a (possibly still streaming) Markdown answer into Markdown and ```mermaid blocks.
/// Fences follow CommonMark: ``` or ~~~, at most 3 spaces of indentation, and a closing
/// fence of the same character at least as long as the opening one.
public enum ResponseSegmenter {
    public static func segments(of text: String, isFinal: Bool) -> [ResponseSegment] {
        var builder = Builder()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            if isLast && line.isEmpty { break }
            builder.consume(line, terminated: !isLast, isFinal: isFinal)
        }
        return builder.finish(isFinal: isFinal)
    }

    private struct Fence {
        let character: Character
        let length: Int
        let isMermaid: Bool
    }

    private struct Builder {
        var segments: [ResponseSegment] = []
        var markdown = ""
        var openFence: Fence?
        var diagramLines: [Substring] = []

        mutating func consume(_ line: Substring, terminated: Bool, isFinal: Bool) {
            let newline = terminated ? "\n" : ""
            guard let fence = openFence else {
                if let opening = Self.openingFence(line), opening.isMermaid {
                    flushMarkdown()
                    openFence = opening
                    diagramLines = []
                } else {
                    openFence = Self.openingFence(line)
                    markdown += line + newline
                }
                return
            }
            if Self.closes(fence, line), terminated || isFinal {
                openFence = nil
                if fence.isMermaid {
                    segments.append(.diagram(source: diagramLines.joined(separator: "\n"), isComplete: true))
                } else {
                    markdown += line + newline
                }
            } else if fence.isMermaid {
                diagramLines.append(line)
            } else {
                markdown += line + newline
            }
        }

        mutating func finish(isFinal: Bool) -> [ResponseSegment] {
            if let fence = openFence, fence.isMermaid {
                segments.append(.diagram(source: diagramLines.joined(separator: "\n"), isComplete: isFinal))
            } else {
                flushMarkdown()
            }
            return segments
        }

        private mutating func flushMarkdown() {
            if !markdown.isEmpty { segments.append(.markdown(markdown)) }
            markdown = ""
        }

        private static func openingFence(_ line: Substring) -> Fence? {
            guard let (character, length, rest) = fenceRun(line) else { return nil }
            let info = rest.trimmingCharacters(in: .whitespaces)
            if character == "`" && info.contains("`") { return nil }
            let language = info.split(separator: " ").first.map { $0.lowercased() }
            return Fence(character: character, length: length, isMermaid: language == "mermaid")
        }

        private static func closes(_ fence: Fence, _ line: Substring) -> Bool {
            guard let (character, length, rest) = fenceRun(line) else { return false }
            return character == fence.character && length >= fence.length
                && rest.allSatisfy { $0 == " " || $0 == "\t" }
        }

        /// Up to 3 spaces, then a run of at least 3 backticks or tildes.
        private static func fenceRun(_ line: Substring) -> (Character, Int, Substring)? {
            let indent = line.prefix { $0 == " " }.count
            guard indent <= 3 else { return nil }
            let body = line.dropFirst(indent)
            guard let character = body.first, character == "`" || character == "~" else { return nil }
            let length = body.prefix { $0 == character }.count
            guard length >= 3 else { return nil }
            return (character, length, body.dropFirst(length))
        }
    }
}
