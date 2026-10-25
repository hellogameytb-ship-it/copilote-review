import Foundation

/// Obsidian is an input only. The index stays outside the vault; attachments, configuration,
/// credentials and symlinks are never ingested. Suspect notes are excluded as a whole.
public enum VaultPolicy {
    public static let indexPolicy = "vault-readonly-v4"

    /// Explicit document names retain their meaning at any depth in an Obsidian vault.
    public static func documentKind(for path: String) -> BaseKind? {
        switch (path as NSString).lastPathComponent.lowercased() {
        case "cv.md": return .cv
        case "bio.md": return .bio
        case "avis.md", "opinions.md": return .opinion
        default:
            let folders = path.split(separator: "/").dropLast().map { component in
                String(component).lowercased().trimmingCharacters(in: CharacterSet.decimalDigits.union(.punctuationCharacters).union(.whitespaces))
            }
            if folders.contains("projects") || folders.contains("projets") { return .project }
            return BaseChunker.kind(forPath: path)
        }
    }
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain", isDirectory: true)
    }
    public static func isVault(_ root: URL) -> Bool {
        root.lastPathComponent == "Brain" || FileManager.default.fileExists(atPath: root.appendingPathComponent(".obsidian").path)
    }
    public static func allows(path: String) -> Bool {
        let parts = path.lowercased().split(separator: "/").map(String.init)
        let excluded = ["secret", "password", "passwd", "credential", "token", "api-key", "api_key", "apikey", "api key", "mot de passe", "mots de passe", "identifiant", "private-key", "recovery", "seed phrase", "private", "confidential", "confidentiel", "auth", "backup", "sauvegarde"]
        return !parts.contains { $0.hasPrefix(".") || excluded.contains(where: $0.contains) }
    }
    public static func containsSecrets(_ text: String) -> Bool {
        let patterns = [
            #"(?i)-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----"#,
            #"\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})\b"#,
            #"(?im)(?:password|passwd|secret|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|authorization|mot de passe)\s*[:=]\s*\S+"#,
            #"(?i)\bBearer\s+[A-Za-z0-9_.-]{16,}"#,
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            #"\b(?:AIza[A-Za-z0-9_-]{30,}|GOCSPX-[A-Za-z0-9_-]+|(?:sk|rk)_live_[A-Za-z0-9]+|xox[baprs]-[A-Za-z0-9-]+|ASIA[A-Z0-9]{16})\b"#,
            #"(?im)\b[A-Z0-9_]*(?:TOKEN|KEY|SECRET|PASSWORD)\s*[:=]\s*[\"']?[^\s\"']{8,}"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}
