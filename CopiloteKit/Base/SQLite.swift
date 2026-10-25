import Foundation
import SQLite3

/// The system SQLite (FTS5 included), behind a minimal wrapper. Serialized mode: a connection
/// may be called from several threads (statements still share its transaction).
final class SQLiteDatabase: @unchecked Sendable {
    enum Value {
        case text(String)
        case int(Int64)
        case double(Double)
        case blob(Data)
        case null
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
            sqlite3_close(handle)
            throw Failure(description: "SQLite : \(message)")
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    /// Runs `sql` once per row of `bindings` (or once without), returning the rows read.
    @discardableResult
    func run(_ sql: String, _ values: [Value] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let .text(text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case let .int(number): sqlite3_bind_int64(statement, index, number)
            case let .double(number): sqlite3_bind_double(statement, index, number)
            case let .blob(data): _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), Self.transient) }
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        var rows: [[Value]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw failure() }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: return .int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: return .double(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return .blob(Data()) }
                    return .blob(Data(bytes: bytes, count: count))
                default: return .null
                }
            })
        }
        return rows
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func failure() -> Failure {
        Failure(description: "SQLite : \(String(cString: sqlite3_errmsg(handle)))")
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

extension SQLiteDatabase.Value {
    var text: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    var double: Double? {
        switch self {
        case let .double(value): return value
        case let .int(value): return Double(value)
        default: return nil
        }
    }

    var data: Data? {
        if case let .blob(value) = self { return value }
        return nil
    }

    init(_ text: String?) {
        self = text.map { .text($0) } ?? .null
    }
}
