import Foundation
import SQLite3

/// A local cache of observed Xcode build manifests. Each operation opens its
/// own connection; SQLite serializes writes and WAL permits concurrent reads.
public struct BuildHistoryStore: Sendable {
    public let fileURL: URL
    public let maxRecords: Int

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OrbitSim/builds.sqlite3")
    }

    public init(fileURL: URL = Self.defaultFileURL, maxRecords: Int = 10_000) {
        self.fileURL = fileURL
        self.maxRecords = maxRecords
    }

    public func upsert(_ records: [BuildRecord]) throws {
        guard (1...100_000).contains(maxRecords) else {
            throw OrbitSimError.invalidArgument("Build retention must be 1–100000 records")
        }
        guard !records.isEmpty else { return }
        let db = try open()
        defer { sqlite3_close(db) }
        try execute("BEGIN IMMEDIATE", on: db)
        do {
            let sql = """
                INSERT INTO builds (project, id, scheme, title, started_at, duration_seconds,
                                    status_code, error_count, warning_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(project, id) DO UPDATE SET
                  scheme=excluded.scheme, title=excluded.title,
                  started_at=excluded.started_at, duration_seconds=excluded.duration_seconds,
                  status_code=excluded.status_code, error_count=excluded.error_count,
                  warning_count=excluded.warning_count
                """
            var statement: OpaquePointer?
            try prepare(sql, on: db, into: &statement)
            defer { sqlite3_finalize(statement) }
            for record in records {
                guard record.startedAt.timeIntervalSinceReferenceDate.isFinite,
                      record.durationSeconds.isFinite, record.durationSeconds >= 0,
                      (0...Int(Int32.max)).contains(record.errorCount),
                      (0...Int(Int32.max)).contains(record.warningCount) else {
                    throw OrbitSimError.invalidArgument("Build record has invalid numeric values")
                }
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(record.project, index: 1, to: statement, on: db)
                try bind(record.id, index: 2, to: statement, on: db)
                try bind(record.scheme, index: 3, to: statement, on: db)
                try bind(record.title, index: 4, to: statement, on: db)
                guard sqlite3_bind_double(statement, 5, record.startedAt.timeIntervalSinceReferenceDate) == SQLITE_OK,
                      sqlite3_bind_double(statement, 6, record.durationSeconds) == SQLITE_OK else {
                    throw databaseError(db)
                }
                try bind(record.statusCode, index: 7, to: statement, on: db)
                guard sqlite3_bind_int(statement, 8, Int32(record.errorCount)) == SQLITE_OK,
                      sqlite3_bind_int(statement, 9, Int32(record.warningCount)) == SQLITE_OK,
                      sqlite3_step(statement) == SQLITE_DONE else {
                    throw databaseError(db)
                }
            }
            try execute("DELETE FROM builds WHERE rowid NOT IN (SELECT rowid FROM builds ORDER BY started_at DESC LIMIT \(maxRecords))", on: db)
            try execute("COMMIT", on: db)
        } catch {
            try? execute("ROLLBACK", on: db)
            throw error
        }
    }

    public func records(limit: Int = 500) throws -> [BuildRecord] {
        guard (1...10_000).contains(limit) else {
            throw OrbitSimError.invalidArgument("Build history limit must be 1–10000")
        }
        let db = try open()
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        try prepare("""
            SELECT project, id, scheme, title, started_at, duration_seconds,
                   status_code, error_count, warning_count
            FROM builds ORDER BY started_at DESC LIMIT ?
            """, on: db, into: &statement)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int(statement, 1, Int32(limit)) == SQLITE_OK else {
            throw databaseError(db)
        }
        var result: [BuildRecord] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw databaseError(db) }
            result.append(BuildRecord(
                id: columnText(statement, 1),
                project: columnText(statement, 0),
                scheme: columnText(statement, 2),
                title: columnText(statement, 3),
                startedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 4)),
                durationSeconds: sqlite3_column_double(statement, 5),
                statusCode: columnText(statement, 6),
                errorCount: Int(sqlite3_column_int(statement, 7)),
                warningCount: Int(sqlite3_column_int(statement, 8))
            ))
        }
    }

    private func open() throws -> OpaquePointer {
        guard fileURL.isFileURL else {
            throw OrbitSimError.invalidArgument("Build history must use a local file")
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &connection, flags, nil) == SQLITE_OK,
              let db = connection else {
            let detail = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let connection { sqlite3_close(connection) }
            throw OrbitSimError.commandFailed(tool: "sqlite", code: 1, detail: detail)
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            sqlite3_busy_timeout(db, 5_000)
            try execute("PRAGMA secure_delete=ON", on: db)
            var pragma: OpaquePointer?
            try prepare("PRAGMA journal_mode=WAL", on: db, into: &pragma)
            let pragmaStatus = sqlite3_step(pragma)
            let journalMode = pragmaStatus == SQLITE_ROW ? columnText(pragma, 0).lowercased() : ""
            sqlite3_finalize(pragma)
            guard journalMode == "wal" else {
                throw OrbitSimError.unsupportedAction("SQLite could not enable WAL mode")
            }
            try migrate(db)
            return db
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    private func migrate(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        try prepare("PRAGMA user_version", on: db, into: &statement)
        let status = sqlite3_step(statement)
        let version = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        guard status == SQLITE_ROW else { throw databaseError(db) }
        guard version <= 1 else {
            throw OrbitSimError.unsupportedAction("Build history was written by a newer OrbitSim version")
        }
        if version == 0 {
            try execute("BEGIN IMMEDIATE", on: db)
            do {
                try execute("""
                    CREATE TABLE builds (
                      project TEXT NOT NULL,
                      id TEXT NOT NULL,
                      scheme TEXT NOT NULL,
                      title TEXT NOT NULL,
                      started_at REAL NOT NULL,
                      duration_seconds REAL NOT NULL,
                      status_code TEXT NOT NULL,
                      error_count INTEGER NOT NULL,
                      warning_count INTEGER NOT NULL,
                      PRIMARY KEY (project, id)
                    )
                    """, on: db)
                try execute("CREATE INDEX builds_started_at ON builds(started_at DESC)", on: db)
                try execute("PRAGMA user_version=1", on: db)
                try execute("COMMIT", on: db)
            } catch {
                try? execute("ROLLBACK", on: db)
                throw error
            }
        }
    }

    private func prepare(_ sql: String, on db: OpaquePointer,
                         into statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(db)
        }
    }

    private func execute(_ sql: String, on db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw databaseError(db)
        }
    }

    private func bind(_ value: String, index: Int32, to statement: OpaquePointer?,
                      on db: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw databaseError(db)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func databaseError(_ db: OpaquePointer) -> OrbitSimError {
        OrbitSimError.commandFailed(tool: "sqlite", code: sqlite3_errcode(db),
                                    detail: String(cString: sqlite3_errmsg(db)))
    }
}
