import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleDatabaseMigrationsTests: XCTestCase {
    func testMigrationsCreateExpectedTables() throws {
        let databasePath = try makeTemporaryDatabasePath()
        _ = try ShuttleDatabase.openMigrated(atPath: databasePath)

        let queue = try DatabaseQueue(path: databasePath)
        let tableNames = try queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        XCTAssertTrue(tableNames.contains("repository_state"))
        XCTAssertTrue(tableNames.contains("shards"))
        XCTAssertTrue(tableNames.contains("conflicts"))
        XCTAssertTrue(tableNames.contains("shard_runtime_metadata"))
        XCTAssertTrue(tableNames.contains("completion_reports"))
        XCTAssertTrue(tableNames.contains("audit_events"))
        XCTAssertTrue(tableNames.contains("idempotency_keys"))
        XCTAssertTrue(tableNames.contains("log_indexes"))
    }

    func testMigrationsAllowReopenWithoutError() throws {
        let databasePath = try makeTemporaryDatabasePath()
        _ = try ShuttleDatabase.openMigrated(atPath: databasePath)
        _ = try ShuttleDatabase.openMigrated(atPath: databasePath)
    }

    func testShardIdentityIsSeparateFromBranchName() throws {
        let databasePath = try makeTemporaryDatabasePath()
        let queue = try ShuttleDatabase.openMigrated(atPath: databasePath)

        let columns = try queue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(shard_runtime_metadata)").compactMap { row in
                row["name"] as String?
            }
        }

        XCTAssertTrue(columns.contains("shard_id"))
        XCTAssertTrue(columns.contains("branch_name"))
    }

    func testLogIndexSchemaStoresReferencesNotRawLogContents() throws {
        let databasePath = try makeTemporaryDatabasePath()
        let queue = try ShuttleDatabase.openMigrated(atPath: databasePath)

        let columns = try queue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(log_indexes)").compactMap { row in
                row["name"] as String?
            }
        }

        XCTAssertTrue(columns.contains("file_path"))
        XCTAssertFalse(columns.contains("content"))
        XCTAssertFalse(columns.contains("raw_log"))
    }

    private func makeTemporaryDatabasePath() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("shuttle.sqlite").path
    }
}
