import CryptoKit
import Foundation

/// What the indexer reads of a project's local repo, read-only: README, tree (dependencies,
/// build output and hidden folders skipped) and a few key files. Its hash decides when the
/// architecture diagram is made again.
public struct RepoSnapshot: Equatable, Sendable {
    public struct KeyFile: Equatable, Sendable {
        public let path: String
        public let content: String
    }

    public let readme: String?
    /// Relative paths, folders ending in "/", sorted.
    public let tree: [String]
    public let keyFiles: [KeyFile]

    static let skippedFolders: Set<String> = [
        "node_modules", "build", "dist", "out", "target", "coverage", "DerivedData", "Pods", "vendor",
        "venv", "__pycache__", "site-packages",
    ]
    static let keyFileNames: Set<String> = [
        "package.json", "Package.swift", "project.yml", "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod",
        "docker-compose.yml", "Dockerfile", "Makefile", "Gemfile", "pom.xml", "build.gradle",
    ]
    static let maxDepth = 4
    static let maxEntries = 300
    static let maxKeyFiles = 8

    public init(at root: URL) throws {
        let files = FileManager.default
        var tree: [String] = []
        var keyFiles: [KeyFile] = []
        var readme: String?
        func visit(_ folder: URL, prefix: String, depth: Int) throws {
            let names = try files.contentsOfDirectory(atPath: folder.path).sorted()
            for name in names where !name.hasPrefix(".") && tree.count < Self.maxEntries {
                let url = folder.appendingPathComponent(name)
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                // Never leave the repo through a link.
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    guard !Self.skippedFolders.contains(name) else { continue }
                    tree.append(prefix + name + "/")
                    if depth < Self.maxDepth { try visit(url, prefix: prefix + name + "/", depth: depth + 1) }
                } else {
                    tree.append(prefix + name)
                    if depth == 1, name.lowercased().hasPrefix("readme") {
                        readme = Self.text(of: url, limit: 6000)
                    } else if Self.keyFileNames.contains(name), keyFiles.count < Self.maxKeyFiles, let text = Self.text(of: url, limit: 4000) {
                        keyFiles.append(KeyFile(path: prefix + name, content: text))
                    }
                }
            }
        }
        try visit(root, prefix: "", depth: 1)
        self.readme = readme
        self.tree = tree.sorted()
        self.keyFiles = keyFiles.sorted { $0.path < $1.path }
    }

    public var hash: String {
        var parts = [readme ?? "", "--tree--"] + tree + ["--files--"]
        for file in keyFiles { parts += [file.path, file.content] }
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Read with secrets masked: this text goes to the LLM.
    private static func text(of url: URL, limit: Int) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count < 2_000_000 else { return nil }
        let text = String(decoding: data.prefix(limit * 4), as: UTF8.self)
        return masked(String(text.prefix(limit))).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `PASSWORD: x`, `API_KEY=x`, `Token: x` keep their key and lose their value; known token
    /// shapes (sk-…, ghp_…, AKIA…) go wherever they are.
    static func masked(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            line.replacing(Self.secretAssignment) { "\($0.output.1)[masqué]" }
                .replacing(Self.tokenShape, with: "[masqué]")
        }
        .joined(separator: "\n")
    }

    private static let secretAssignment =
        /(?i)^(\s*(?:export\s+)?[\w.-]*(?:secret|password|passwd|pwd|token|api[_-]?key|private[_-]?key|access[_-]?key|credential)[\w.-]*\s*[:=]\s*).+$/
    private static let tokenShape = /\b(?:sk-[A-Za-z0-9_-]{6,}|gh[pousr]_[A-Za-z0-9]{6,}|xox[abpr]-[A-Za-z0-9-]{6,}|AKIA[0-9A-Z]{16})/
}

public struct DiagramRecord: Equatable, Sendable, Codable {
    public enum Status: String, Codable, Sendable {
        case ok
        /// The LLM answered but not with a valid diagram: not asked again for this repo state.
        case invalid
        /// The call failed (no provider, network): retried at the next indexing.
        case failed
    }

    public let repoHash: String
    public let mermaid: String?
    public let status: Status

    public init(repoHash: String, mermaid: String?, status: Status) {
        self.repoHash = repoHash
        self.mermaid = mermaid
        self.status = status
    }
}

public enum DiagramCache {
    public enum Plan: Equatable, Sendable {
        case reuse
        case generate
    }

    public static func plan(existing: DiagramRecord?, repoHash: String) -> Plan {
        guard let existing, existing.repoHash == repoHash, existing.status != .failed else { return .generate }
        return .reuse
    }

    /// The request sent once per repo state through the active `LLMProvider`.
    public static func prompt(project: String, snapshot: RepoSnapshot) -> String {
        var parts = [
            "Project: \(project)",
            "Here are the README, file tree and key source files.",
            "Return only a Mermaid `flowchart LR` architecture diagram: 4–10 nodes "
                + "(frontend, API, services, database, external services), short English labels, labelled arrows "
                + "when useful. No `click`, links, `%%{init}` directive or HTML.",
            "", "README :", snapshot.readme ?? "(none)", "", "File tree:", snapshot.tree.joined(separator: "\n"),
        ]
        for file in snapshot.keyFiles { parts += ["", "\(file.path) :", file.content] }
        return parts.joined(separator: "\n")
    }
}

/// A first check of the LLM's diagram before it is rendered (the render itself is the final
/// check): a known diagram type, nothing that acts on click or carries HTML, balanced brackets.
public enum MermaidCheck {
    static let types = ["flowchart", "graph", "sequenceDiagram", "classDiagram", "erDiagram", "stateDiagram", "mindmap"]

    public static func diagram(in answer: String) -> String? {
        var source = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenced = answer.firstMatch(of: /```mermaid[ \t]*\n([\s\S]*?)```/) {
            source = String(fenced.1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              types.contains(where: { first.trimmingCharacters(in: .whitespaces).hasPrefix($0) }),
              lines.count <= 80, source.count <= 5000 else { return nil }
        let lowered = source.lowercased()
        guard !["click ", "href", "javascript:", "%%{", "callback"].contains(where: lowered.contains),
              source.firstMatch(of: /<(?!br\s*\/?>)[a-zA-Z\/!]/) == nil,
              balanced(source) else { return nil }
        return source
    }

    private static func balanced(_ source: String) -> Bool {
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        var stack: [Character] = []
        var inQuotes = false
        for character in source {
            if character == "\"" { inQuotes.toggle() }
            if inQuotes { continue }
            if "([{".contains(character) {
                stack.append(character)
            } else if let open = pairs[character] {
                guard stack.popLast() == open else { return false }
            }
        }
        return stack.isEmpty && !inQuotes
    }
}
