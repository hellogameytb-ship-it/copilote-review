import Foundation

/// One SQLite file (in Application Support for the app): the items of the base, an FTS5
/// full-text index, their vectors, and the caches (place names, diagrams). Rebuilt from
/// `~/Copilote/` at any time: the folder stays the source of truth.
///
/// Two connections: the indexer writes through one, searches read through the other, so a
/// search sees the last committed state (WAL) and never a file half-replaced.
public final class BaseIndex: @unchecked Sendable {
    public let url: URL
    private let writer: SQLiteDatabase
    private let reader: SQLiteDatabase
    private let lock = NSLock()
    private var changes = 0

    /// A place lookup already made: a name, or none (the sea…). Failed lookups are not stored.
    enum CachedPlace: Equatable {
        case named(String)
        case nowhere
    }

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        writer = try SQLiteDatabase(path: url.path)
        try writer.execute("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, stamp TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS items(id TEXT PRIMARY KEY, file TEXT NOT NULL, data BLOB NOT NULL, vector BLOB);
        CREATE INDEX IF NOT EXISTS items_file ON items(file);
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
            id UNINDEXED, title, section, body, place, tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TABLE IF NOT EXISTS places(key TEXT PRIMARY KEY, name TEXT);
        CREATE TABLE IF NOT EXISTS diagrams(project TEXT PRIMARY KEY, record BLOB NOT NULL, image TEXT);
        CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        """)
        reader = try SQLiteDatabase(path: url.path)
    }

    /// Goes up at every write: searches reload their in-memory copy when it moves.
    public var version: Int {
        lock.withLock { changes }
    }

    private func changed() {
        lock.withLock { changes += 1 }
    }

    // MARK: Files

    func stamps() throws -> [String: String] {
        var stamps: [String: String] = [:]
        for row in try reader.run("SELECT path, stamp FROM files") {
            if let path = row[0].text, let stamp = row[1].text { stamps[path] = stamp }
        }
        return stamps
    }

    func replace(file path: String, stamp: String, items: [BaseItem], vectors: [[Float]?]) throws {
        let encoder = JSONEncoder()
        try writer.transaction {
            try deleteItems(ofFile: path)
            for (item, vector) in zip(items, vectors) {
                try writer.run("INSERT OR REPLACE INTO items(id, file, data, vector) VALUES (?, ?, ?, ?)", [
                    .text(item.id), .text(path), .blob(try encoder.encode(item)), vector.map { .blob(Self.data(of: $0)) } ?? .null,
                ])
                try writer.run("INSERT INTO items_fts(id, title, section, body, place) VALUES (?, ?, ?, ?, ?)", [
                    .text(item.id), .text(item.title), .init(item.section), .text(item.text), .init(item.place),
                ])
            }
            try writer.run("INSERT OR REPLACE INTO files(path, stamp) VALUES (?, ?)", [.text(path), .text(stamp)])
        }
        changed()
    }

    func remove(file path: String) throws {
        try writer.transaction {
            try deleteItems(ofFile: path)
            try writer.run("DELETE FROM files WHERE path = ?", [.text(path)])
        }
        changed()
    }

    /// Everything goes (another embedding model: vectors are not comparable).
    public func removeAll() throws {
        try writer.execute("DELETE FROM items; DELETE FROM items_fts; DELETE FROM files;")
        changed()
    }

    private func deleteItems(ofFile path: String) throws {
        try writer.run("DELETE FROM items_fts WHERE id IN (SELECT id FROM items WHERE file = ?)", [.text(path)])
        try writer.run("DELETE FROM items WHERE file = ?", [.text(path)])
    }

    // MARK: Reading

    public struct Stored: Sendable {
        public let item: BaseItem
        public let vector: [Float]?
    }

    /// In file order (a fiche's sections as written).
    public func items() throws -> [Stored] {
        try stored(try reader.run("SELECT data, vector FROM items ORDER BY rowid"))
    }

    /// What a file gave last time (to clean up after it).
    func items(ofFile path: String) throws -> [BaseItem] {
        try stored(try reader.run("SELECT data, vector FROM items WHERE file = ? ORDER BY rowid", [.text(path)])).map(\.item)
    }

    private func stored(_ rows: [[SQLiteDatabase.Value]]) throws -> [Stored] {
        let decoder = JSONDecoder()
        return rows.compactMap { row in
            guard let data = row[0].data, let item = try? decoder.decode(BaseItem.self, from: data) else { return nil }
            return Stored(item: item, vector: row[1].data.map(Self.vector(of:)))
        }
    }

    public var itemCount: Int {
        Int((try? reader.run("SELECT count(*) FROM items").first?.first?.double) ?? 0)
    }

    /// Item ids, best BM25 first (title and place weigh more than the body).
    func lexical(match: String, limit: Int) throws -> [String] {
        try reader.run(
            "SELECT id FROM items_fts WHERE items_fts MATCH ? ORDER BY bm25(items_fts, 0, 3.0, 2.0, 1.0, 2.0) LIMIT ?",
            [.text(match), .int(Int64(limit))]
        ).compactMap { $0[0].text }
    }

    // MARK: Caches

    /// nil: never looked up.
    func cachedPlace(forKey key: String) throws -> CachedPlace? {
        guard let row = try reader.run("SELECT name FROM places WHERE key = ?", [.text(key)]).first else { return nil }
        return row[0].text.map(CachedPlace.named) ?? .nowhere
    }

    func cachePlace(_ place: CachedPlace, forKey key: String) throws {
        let name: String? = if case let .named(name) = place { name } else { nil }
        try writer.run("INSERT OR REPLACE INTO places(key, name) VALUES (?, ?)", [.text(key), .init(name)])
    }

    public func diagram(forProject source: String) -> (record: DiagramRecord, image: URL?)? {
        guard let row = try? reader.run("SELECT record, image FROM diagrams WHERE project = ?", [.text(source)]).first,
              let data = row[0].data, let record = try? JSONDecoder().decode(DiagramRecord.self, from: data) else { return nil }
        return (record, row[1].text.map(URL.init(fileURLWithPath:)))
    }

    func setDiagram(_ record: DiagramRecord, image: URL?, forProject source: String) throws {
        try writer.run("INSERT OR REPLACE INTO diagrams(project, record, image) VALUES (?, ?, ?)", [
            .text(source), .blob(try JSONEncoder().encode(record)), .init(image?.path),
        ])
        changed()
    }

    public func meta(_ key: String) -> String? {
        (try? reader.run("SELECT value FROM meta WHERE key = ?", [.text(key)]).first)?.first?.text
    }

    func setMeta(_ key: String, _ value: String) throws {
        try writer.run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", [.text(key), .text(value)])
    }

    // MARK: Vectors

    static func data(of vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func vector(of data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
