import CryptoKit
import Foundation

/// Optional private, externally curated evidence. Open a fresh read-only snapshot per personal
/// request so an atomic replacement takes effect without relaunching the app.
public struct InterviewEvidenceStore: Sendable {
    public let database: URL
    public let root: URL
    public init(database: URL, root: URL) {
        self.database = database
        self.root = root
    }

    public static var defaultDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Copilote/InterviewEvidence/evidence.sqlite")
    }

    private struct Row {
        let id: String
        let topic: String
        let tags: String
        let passage: String
        let source: String
        let hash: String
        var filename: String { source.components(separatedBy: " · ").first ?? "" }
        var isCV: Bool { filename.lowercased().hasSuffix(".pdf") }
    }

    /// The last currently spoken request gates the separate CV attachment. The original
    /// two-minute exchange is still passed to the model in full.
    public static func currentQuestion(_ heard: [String]) -> String {
        let all = heard.joined(separator: "\n")
        let lines = all.components(separatedBy: .newlines)
        let interviewer = lines.compactMap { line -> String? in
            for prefix in ["Them : ", "Them (provisional): "] where line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
            return nil
        }
        guard !interviewer.isEmpty else { return all }
        let acknowledgements: Set<String> = ["okay","ok","yes","right","thanks","oui","merci","d accord"]
        return interviewer.last(where: { !acknowledgements.contains(BaseText.tokens(of: $0).joined(separator: " ")) }) ?? ""
    }

    private static let synonyms: [[String]] = [
        ["defi","difficulte","obstacle","challenge","setback","incident","resilience"],
        ["equipe","groupe","collectif","team","teamwork","collaboration"],
        ["formation","etudes","education","coursework","academic","school","grades"],
        ["parcours","experience","background","resume","cv"],
        ["projet","projets","project","projects"], ["competences","skills","stack","languages"],
        ["mesure","resultat","resultats","result","results","metric","impact"],
        ["donnees","data"], ["latence","latency"], ["confidentialite","privacy"],
        ["enseignement","teaching"], ["diriger","leadership"], ["echec","failure","failed","retook"],
        ["simulation","simulated","simule"], ["production","deployed","deploye"]
    ]
    private static let broad: Set<String> = ["cv","resume","personal","experience","project","projects","projet","projets","challenge","defi","obstacle","setback","time"]
    private static func expanded(_ terms: Set<String>) -> Set<String> {
        synonyms.reduce(into: terms) { result, family in
            if !terms.isDisjoint(with: family) { result.formUnion(family) }
        }
    }

    /// Verify the cited original inside the selected personal base. Never use an old
    /// passage with a newly edited CV or follow a link out of the vault.
    private func original(_ filename: String) -> URL? {
        guard filename == (filename as NSString).lastPathComponent,
              VaultPolicy.allows(path: filename), ["pdf","md"].contains((filename as NSString).pathExtension.lowercased()) else { return nil }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        for relative in [filename, "CV/" + filename] {
            let url = base.appendingPathComponent(relative).standardizedFileURL
            guard url.resolvingSymlinksInPath().path == url.path, url.path.hasPrefix(base.path + "/"),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size <= 32 * 1024 * 1024 else { continue }
            return url
        }
        return nil
    }

    /// A style/category guess alone is not consent to attach a private CV. Look for a
    /// request about the candidate, rather than a second-person hypothetical design problem.
    public static func isPersonalRequest(_ question: String) -> Bool {
        let intent = QueryIntent(question: question)
        guard QuestionKind(question: question) != .opinion else { return false }
        let text = BaseText.tokens(of: question).joined(separator: " ")
        if text.range(of: #"\b(how would you|if you were|comment ferais|que ferais|how do you implement|how do you design)\b"#, options: .regularExpression) != nil { return false }
        if text.hasPrefix("did you know") { return false }
        if intent.isBehavioral, text.range(of: #"\b(tell me about a time|walk me through a time|did you|you faced|you overcame|you handled|you solved|you had|raconte|racontez|tu as|vous avez|as tu|avez vous)\b"#, options: .regularExpression) != nil { return true }
        return text.range(of: #"\b(yourself|cv|resume|did you|have you|you built|you worked|tu as|vous avez|as tu|avez vous|ton parcours|mon parcours|votre parcours|(?:your|my|ton|ta|tes|vos|votre|mon|mes) (?:\w+ ){0,2}(?:project\w*|projet\w*|skills?|competences?|career|roles?|background|experiences?|studies|education|formation|internship\w*|stage\w*|responsabilit\w*))\b"#, options: .regularExpression) != nil
    }

    public func snippets(for question: String) -> [BaseSnippet] {
        let intent = QueryIntent(question: question)
        guard Self.isPersonalRequest(question) else { return [] }
        let rows = verifiedRows()
        let words = Set(intent.terms.map(\.word))
        let query = Self.expanded(Set(BaseText.tokens(of: question)))
        let meaningful = Self.expanded(words.subtracting(Self.broad))
        let overview = !query.isDisjoint(with: ["cv","resume","parcours","background","yourself","toi"])
        let ranked = rows.compactMap { row -> (Row, Int)? in
            let tags = Set(BaseText.tokens(of: row.tags))
            let topic = Set(BaseText.tokens(of: row.topic))
            let body = Set(BaseText.tokens(of: row.passage))
            let specific = meaningful.intersection(tags.union(body)).count
            let named = words.subtracting(Self.broad).intersection(topic).count
            let themed = query.intersection(tags).count
            let isStory = intent.isBehavioral && !tags.isDisjoint(with: ["challenge","setback","failure","resilience","conflict","leadership","pressure"])
            guard isStory || specific + named + themed > 0 || (overview && row.isCV) else { return nil }
            // A challenge tag alone is insufficient: the record must describe work actually
            // performed. Verbatim evidence and qualifications travel together.
            let result = row.passage.range(of: #"\b(?:from|below|sooner|reduced|lifted|restored|recovered|resumed|enabled|enabling|retook|improved|passed|permis|reduit|retabli)\b"#, options: [.regularExpression,.caseInsensitive]) != nil
            let completed = row.passage.range(of: #"\b(?:[a-z]{3,}ed|built|led|wrote|retook|got|mis|fait)\b"#, options: [.regularExpression,.caseInsensitive]) != nil
            if intent.isBehavioral && (!isStory || !completed) { return nil }
            let score = named*12 + specific*4 + themed*2 + (row.isCV ? 7 : 0)
                + (result && intent.isBehavioral ? 6 : 0)
                + (isStory && row.passage.contains("%") ? 2 : 0)
            return (row,score)
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
        guard let (best, _) = ranked.first else { return [] }
        return [snippet(for: best, in: rows)]
    }

    /// Match the exact previously shown evidence against today's database and original
    /// documents. A changed digest, passage, attribution or deleted row breaks the link.
    public func revalidated(_ references: [BaseSnippet]) -> [BaseSnippet] {
        let rows = verifiedRows()
        let current = rows.map { snippet(for: $0, in: rows) }
        return references.filter(current.contains)
    }

    private func verifiedRows() -> [Row] {
        guard let connection = try? SQLiteDatabase(path: database.path, readOnly: true),
              let values = try? connection.run("SELECT id,topic,tags,passage,source,source_sha256 FROM evidence ORDER BY id LIMIT 1001"),
              values.count <= 1000 else { return [] }
        var hashes: [String:String] = [:]
        var rows: [Row] = []
        for fields in values {
            let v = fields.compactMap(\.text)
            guard v.count == 6, !v[1].isEmpty, !v[3].isEmpty, v[3].count <= 1200,
                  v[1].count <= 512, v[4].count <= 240, v[5].count == 64,
                  !VaultPolicy.containsSecrets(v[1] + "\n" + v[3]) else { continue }
            let row = Row(id:v[0],topic:v[1],tags:v[2],passage:v[3],source:v[4],hash:v[5])
            if hashes[row.filename] == nil {
                hashes[row.filename] = original(row.filename).flatMap { try? Data(contentsOf: $0) }
                    .map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
            }
            let normalized = BaseText.tokens(of: row.passage).joined(separator: " ")
            let uncertain = ["i would ", "we could ", "hypothetical example", "a confirmer", "to confirm"]
            if hashes[row.filename] == row.hash.lowercased() && !uncertain.contains(where: normalized.contains) { rows.append(row) }
        }

        return rows
    }

    private func snippet(for best: Row, in rows: [Row]) -> BaseSnippet {
        var passages = [best.passage]
        // Keep a result-only CV bullet with a little context from the same short entry.
        // Never merge different sources or attach an entire multi-project job entry.
        let same = rows.filter { $0.topic == best.topic && $0.source == best.source && $0.hash == best.hash }
        if same.count == 2, let other = same.first(where: { $0.id != best.id }),
           best.passage.count + other.passage.count <= 1000 {
            passages = same.map(\.passage)
        }
        let provenance = best.isCV ? "Recruiter CV" : "Interview preparation note (confirm personal details)"
        let teamwork = Set(BaseText.tokens(of: best.tags)).contains("teamwork")
        let scope = teamwork ? " · team project (individual role only if documented)" : ""
        return BaseSnippet(source: "\(provenance) · \(best.source) · \(best.topic)\(scope)", text: passages.joined(separator: "\n"), interviewRevision: best.hash)
    }
}
