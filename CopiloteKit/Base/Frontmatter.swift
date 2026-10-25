import Foundation

public enum FrontmatterValue: Hashable, Sendable, Codable {
    case text(String)
    case list([String])

    public var text: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    /// A list, or a single value as a one-item list.
    public var items: [String] {
        switch self {
        case let .text(value): return [value]
        case let .list(values): return values
        }
    }
}

/// The YAML header of a fiche, in the small subset the templates use: `key: value`,
/// `key: [a, b]`, `key:` followed by `- item` lines, `# comments`.
public struct Frontmatter: Sendable {
    public let fields: [String: FrontmatterValue]
    public let body: String

    public init(markdown: String) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            fields = [:]
            body = Self.trimmed(lines)
            return
        }
        var fields: [String: FrontmatterValue] = [:]
        var listKey: String?
        for raw in lines[1..<close] {
            let line = Self.uncommented(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("- "), let key = listKey {
                let item = Self.unquoted(String(trimmed.dropFirst(2)))
                guard !item.isEmpty else { continue }
                fields[key] = .list((fields[key]?.items ?? []) + [item])
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            listKey = value.isEmpty ? key : nil
            if value.hasPrefix("["), value.hasSuffix("]") {
                let items = value.dropFirst().dropLast().split(separator: ",").map { Self.unquoted(String($0)) }.filter { !$0.isEmpty }
                if !items.isEmpty { fields[key] = .list(items) }
            } else if !value.isEmpty {
                let text = Self.unquoted(value)
                if !text.isEmpty { fields[key] = .text(text) }
            }
        }
        self.fields = fields
        body = Self.trimmed(Array(lines[(close + 1)...]))
    }

    private static func trimmed(_ lines: [String]) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops a ` # comment` outside quotes (a `#` inside a URL has no space before it).
    private static func uncommented(_ line: String) -> String {
        var inQuotes = false
        var previous: Character = " "
        for index in line.indices {
            let character = line[index]
            if character == "\"" { inQuotes.toggle() }
            if character == "#", !inQuotes, previous == " " || index == line.startIndex {
                return String(line[..<index])
            }
            previous = character
        }
        return line
    }

    private static func unquoted(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, let first = trimmed.first, first == trimmed.last, first == "\"" || first == "'" {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}
