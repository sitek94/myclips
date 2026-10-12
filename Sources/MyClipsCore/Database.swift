import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

// SQLite copies bound values before the call returns.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal SQLite wrapper. Not thread-safe; owned by the `Store` actor.
final class Database {
    private let handle: OpaquePointer

    init(path: String) throws {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            sqlite3_close(db)
            throw SQLiteError(code: rc, message: message)
        }
        handle = db
        try execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        guard rc == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? ""
            sqlite3_free(error)
            throw SQLiteError(code: rc, message: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw lastError(rc) }
        return Statement(stmt: stmt, db: self)
    }

    func run(_ sql: String, _ values: [SQLValue] = []) throws {
        try prepare(sql).run(values)
    }

    func query<T>(_ sql: String, _ values: [SQLValue] = [], _ row: (Statement) -> T) throws -> [T] {
        try prepare(sql).rows(values, row)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    func lastError(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }
}

final class Statement {
    private let stmt: OpaquePointer
    private let db: Database

    fileprivate init(stmt: OpaquePointer, db: Database) {
        self.stmt = stmt
        self.db = db
    }

    deinit { sqlite3_finalize(stmt) }

    func run(_ values: [SQLValue] = []) throws {
        try bind(values)
        while try step() {}
    }

    func rows<T>(_ values: [SQLValue], _ row: (Statement) -> T) throws -> [T] {
        try bind(values)
        var result: [T] = []
        while try step() { result.append(row(self)) }
        return result
    }

    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(stmt, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(stmt, column) }

    func text(_ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    func blob(_ column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(stmt, column))
        guard count > 0, let bytes = sqlite3_column_blob(stmt, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func bind(_ values: [SQLValue]) throws {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32 =
                switch value {
                case .int(let value): sqlite3_bind_int64(stmt, index, value)
                case .double(let value): sqlite3_bind_double(stmt, index, value)
                case .text(let value): sqlite3_bind_text(stmt, index, value, -1, transient)
                case .blob(let value) where value.isEmpty: sqlite3_bind_zeroblob(stmt, index, 0)
                case .blob(let value): value.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32($0.count), transient) }
                case .null: sqlite3_bind_null(stmt, index)
                }
            guard rc == SQLITE_OK else { throw db.lastError(rc) }
        }
    }

    private func step() throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        case let rc: throw db.lastError(rc)
        }
    }
}
