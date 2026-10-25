import Foundation

public struct RecordedTopic: Equatable, Sendable, Codable {
    public let title: String
    public let excerpt: [String]

    public init(title: String, excerpt: [String]) {
        self.title = title
        self.excerpt = excerpt
    }
}

public struct RecordedAnswer: Equatable, Sendable, Codable {
    /// "Répondre · Date de sortie", "Capture", "Demander".
    public let label: String
    public let markdown: String

    public init(label: String, markdown: String) {
        self.label = label
        self.markdown = markdown
    }
}

/// One listening session as kept in the history (only with "Garder l'historique" on).
public struct SessionRecord: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let started: Date
    public let duration: TimeInterval
    public let mode: MeetingMode
    public var title: String
    public let transcript: [TranscriptLine]
    public let topics: [RecordedTopic]
    public let answers: [RecordedAnswer]
    public var notes: MeetingNotes?
    public var email: FollowUpEmail?
    public var review: SelfReview?

    public init(
        id: UUID, started: Date, duration: TimeInterval, mode: MeetingMode, title: String, transcript: [TranscriptLine],
        topics: [RecordedTopic], answers: [RecordedAnswer], notes: MeetingNotes?, email: FollowUpEmail?, review: SelfReview?
    ) {
        self.id = id
        self.started = started
        self.duration = duration
        self.mode = mode
        self.title = title
        self.transcript = transcript
        self.topics = topics
        self.answers = answers
        self.notes = notes
        self.email = email
        self.review = review
    }

    /// A listening session that just ended: its own answers (asked after it started), the
    /// transcript only when the history keeps it, its first case as a title until notes give one.
    public static func ended(
        started: Date, duration: TimeInterval, mode: MeetingMode, lines: [TranscriptLine], topics: [Topic],
        answers: [(date: Date, label: String, text: String)], keepTranscript: Bool
    ) -> SessionRecord {
        SessionRecord(
            id: UUID(), started: started, duration: duration, mode: mode,
            title: topics.first?.title ?? "Session on \(SessionSummary.dateText(started))",
            transcript: keepTranscript ? lines : [],
            topics: topics.map { RecordedTopic(title: $0.title, excerpt: $0.excerpt) },
            answers: answers.filter { $0.date >= started }.sorted { $0.date < $1.date }.map { RecordedAnswer(label: $0.label, markdown: $0.text) },
            notes: nil, email: nil, review: nil
        )
    }

    /// Notes arrived: they name the session.
    public mutating func attach(_ report: MeetingReport) {
        if !report.notes.title.isEmpty { title = report.notes.title }
        notes = report.notes
        email = report.email
        review = report.review
    }

    public var summary: SessionSummary {
        SessionSummary(id: id, started: started, duration: duration, mode: mode, title: title)
    }

    /// The export: everything kept, in Markdown.
    public var markdown: String {
        var parts = ["# \(title)", "\(SessionSummary.dateText(started)) · Mode: \(mode.name) · duration: \(SessionSummary.durationText(duration))"]
        if !topics.isEmpty { parts.append("## Cases\n" + topics.map { "- \($0.title)" }.joined(separator: "\n")) }
        if !transcript.isEmpty {
            parts.append("## Transcript\n" + transcript.map { "**\($0.speaker.name)** : \($0.text)" }.joined(separator: "\n\n"))
        }
        if !answers.isEmpty {
            parts.append("## Answers\n" + answers.map { "### \($0.label)\n\($0.markdown)" }.joined(separator: "\n\n"))
        }
        if let notes { parts.append("## Notes\n" + Self.demoted(notes.markdown)) }
        if let email { parts.append("## Follow-up email\n**Subject:** \(email.subject)\n\n\(email.body)") }
        if let review { parts.append("## Answer review\n" + Self.demoted(review.markdown)) }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// Searched words: everything a person could remember of the session.
    var searchableText: String {
        var parts = transcript.map(\.text) + topics.flatMap { [$0.title] + $0.excerpt } + answers.map(\.markdown)
        if let notes { parts.append(notes.markdown) }
        if let email { parts.append(email.body) }
        return parts.joined(separator: "\n")
    }

    private static func demoted(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n").map { $0.hasPrefix("## ") ? "#" + $0 : $0 }.joined(separator: "\n")
    }
}

/// A row of the history list.
public struct SessionSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let started: Date
    public let duration: TimeInterval
    public let mode: MeetingMode
    public let title: String

    public init(id: UUID, started: Date, duration: TimeInterval, mode: MeetingMode, title: String) {
        self.id = id
        self.started = started
        self.duration = duration
        self.mode = mode
        self.title = title
    }

    /// "19 octobre 2026 à 14:05".
    public static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "30 min", "1 h 05".
    public static func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        return minutes < 60 ? "\(max(minutes, 1)) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }
}

/// The history, in one SQLite file in Application Support, with full-text search.
public final class HistoryStore: @unchecked Sendable {
    private let database: SQLiteDatabase

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try SQLiteDatabase(path: url.path)
        try database.execute("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS sessions(
            id TEXT PRIMARY KEY, started REAL NOT NULL, duration REAL NOT NULL, mode TEXT NOT NULL, title TEXT NOT NULL, data BLOB NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS sessions_fts USING fts5(id UNINDEXED, title, body, tokenize = 'unicode61 remove_diacritics 2');
        """)
    }

    public func save(_ record: SessionRecord) throws {
        let data = try JSONEncoder().encode(record)
        try database.transaction {
            try database.run("DELETE FROM sessions_fts WHERE id = ?", [.text(record.id.uuidString)])
            try database.run("INSERT OR REPLACE INTO sessions(id, started, duration, mode, title, data) VALUES (?, ?, ?, ?, ?, ?)", [
                .text(record.id.uuidString), .double(record.started.timeIntervalSince1970), .double(record.duration),
                .text(record.mode.rawValue), .text(record.title), .blob(data),
            ])
            try database.run("INSERT INTO sessions_fts(id, title, body) VALUES (?, ?, ?)", [
                .text(record.id.uuidString), .text(record.title), .text(record.searchableText),
            ])
        }
    }

    /// Newest first.
    public func sessions() throws -> [SessionSummary] {
        try summaries(database.run("SELECT id, started, duration, mode, title FROM sessions ORDER BY started DESC, rowid ASC"))
    }

    public func search(_ query: String) throws -> [SessionSummary] {
        let words = BaseText.tokens(of: query)
        guard !words.isEmpty else { return try sessions() }
        let match = words.map { "\"\($0)\"*" }.joined(separator: " AND ")
        return try summaries(database.run("""
        SELECT s.id, s.started, s.duration, s.mode, s.title FROM sessions s
        JOIN sessions_fts f ON f.id = s.id WHERE sessions_fts MATCH ? ORDER BY s.started DESC, s.rowid ASC
        """, [.text(match)]))
    }

    public func session(id: UUID) throws -> SessionRecord? {
        guard let data = try database.run("SELECT data FROM sessions WHERE id = ?", [.text(id.uuidString)]).first?.first?.data else { return nil }
        return try JSONDecoder().decode(SessionRecord.self, from: data)
    }

    public func delete(id: UUID) throws {
        try database.transaction {
            try database.run("DELETE FROM sessions_fts WHERE id = ?", [.text(id.uuidString)])
            try database.run("DELETE FROM sessions WHERE id = ?", [.text(id.uuidString)])
        }
    }

    /// Retention: removes sessions started more than `days` days before `now`; returns how many.
    @discardableResult
    public func purge(olderThanDays days: Int, now: Date = Date()) throws -> Int {
        let limit = now.addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        let old = try database.run("SELECT id FROM sessions WHERE started < ?", [.double(limit)]).compactMap { $0[0].text }
        for id in old {
            if let uuid = UUID(uuidString: id) { try delete(id: uuid) }
        }
        return old.count
    }

    private func summaries(_ rows: [[SQLiteDatabase.Value]]) -> [SessionSummary] {
        rows.compactMap { row in
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let started = row[1].double, let duration = row[2].double,
                  let mode = row[3].text.flatMap(MeetingMode.init(rawValue:)), let title = row[4].text else { return nil }
            return SessionSummary(id: id, started: Date(timeIntervalSince1970: started), duration: duration, mode: mode, title: title)
        }
    }
}
