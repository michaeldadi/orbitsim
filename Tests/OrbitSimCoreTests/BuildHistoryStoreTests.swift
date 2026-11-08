import Foundation
import SQLite3
import XCTest
@testable import OrbitSimCore

final class BuildHistoryStoreTests: XCTestCase {
    func testPersistsUpsertsAndBoundsBuildHistoryInWALMode() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbitsim-build-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("builds.sqlite3")
        let store = BuildHistoryStore(fileURL: file, maxRecords: 2)
        let old = record("old", date: 1, warnings: 0)
        let middle = record("middle", date: 2, warnings: 0)
        let latest = record("latest", date: 3, warnings: 0)

        try store.upsert([old, middle, latest])
        XCTAssertEqual(try BuildHistoryStore(fileURL: file).records().map(\.id), ["latest", "middle"])

        try store.upsert([record("latest", date: 3, warnings: 7)])
        let records = try store.records()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.warningCount, 7)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var pragma: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA journal_mode", -1, &pragma, nil), SQLITE_OK)
        defer { sqlite3_finalize(pragma) }
        XCTAssertEqual(sqlite3_step(pragma), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(pragma, 0)), "wal")
    }

    private func record(_ id: String, date: Double, warnings: Int) -> BuildRecord {
        BuildRecord(id: id, project: "Fixture", scheme: "Fixture", title: "Build",
                    startedAt: Date(timeIntervalSinceReferenceDate: date),
                    durationSeconds: 2, statusCode: "S", errorCount: 0,
                    warningCount: warnings)
    }
}
