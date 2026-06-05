import Foundation
import XCTest
import GRDB
@testable import ShuttleServer

final class ShuttleCommandLogStoreTests: XCTestCase {
    func testAppendWritesRawLogsOutsideSQLiteAndIndexesEntries() throws {
        let environment = try makeEnvironment()
        let store = try makeStore(environment: environment, maxBytesPerFile: 256, retentionDays: 14)
        try insertShard(id: "shard-log-1", dbQueue: environment.dbQueue)

        try store.append(
            ShuttleCommandLogEntry(
                shardID: "shard-log-1",
                command: ["swift", "test"],
                stdout: "ok",
                stderr: "",
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                endedAt: Date(timeIntervalSince1970: 1_800_000_001),
                toolName: nil
            )
        )

        let entries = try store.fetchEntries(shardID: "shard-log-1")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].stdout, "ok")

        let indexRows = try fetchIndexRows(dbQueue: environment.dbQueue, shardID: "shard-log-1")
        XCTAssertEqual(indexRows.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexRows[0].filePath))
    }

    func testRotationCreatesMultipleRawLogFilesWhenSizeThresholdExceeded() throws {
        let environment = try makeEnvironment()
        let store = try makeStore(environment: environment, maxBytesPerFile: 180, retentionDays: 14)
        try insertShard(id: "shard-log-rotate", dbQueue: environment.dbQueue)

        for index in 0..<3 {
            try store.append(
                ShuttleCommandLogEntry(
                    shardID: "shard-log-rotate",
                    command: ["swift", "test"],
                    stdout: String(repeating: "x", count: 35),
                    stderr: "",
                    exitCode: 0,
                    startedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index * 2)),
                    endedAt: Date(timeIntervalSince1970: 1_800_000_001 + Double(index * 2)),
                    toolName: nil
                )
            )
        }

        let entries = try store.fetchEntries(shardID: "shard-log-rotate")
        XCTAssertEqual(entries.count, 3)

        let indexRows = try fetchIndexRows(dbQueue: environment.dbQueue, shardID: "shard-log-rotate")
        let uniqueFiles = Set(indexRows.map(\.filePath))
        XCTAssertGreaterThan(uniqueFiles.count, 1)
        for filePath in uniqueFiles {
            let size = try fileSize(atPath: filePath)
            XCTAssertLessThanOrEqual(size, 180)
        }
    }

    func testCleanupDeletesExpiredLogsAndRemovesIndexes() throws {
        let environment = try makeEnvironment()
        let store = try makeStore(environment: environment, maxBytesPerFile: 256, retentionDays: 7)
        try insertShard(id: "shard-log-cleanup", dbQueue: environment.dbQueue)

        let oldEndedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try store.append(
            ShuttleCommandLogEntry(
                shardID: "shard-log-cleanup",
                command: ["swift", "test"],
                stdout: "old",
                stderr: "",
                exitCode: 0,
                startedAt: oldEndedAt.addingTimeInterval(-1),
                endedAt: oldEndedAt,
                toolName: nil
            )
        )

        let rowsBefore = try fetchIndexRows(dbQueue: environment.dbQueue, shardID: "shard-log-cleanup")
        XCTAssertEqual(rowsBefore.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rowsBefore[0].filePath))

        let deleted = try store.cleanupExpiredEntries(
            now: oldEndedAt.addingTimeInterval(Double(8 * 24 * 60 * 60))
        )

        XCTAssertEqual(deleted.deletedIndexCount, 1)
        XCTAssertEqual(deleted.deletedFileCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rowsBefore[0].filePath))
        XCTAssertEqual(try fetchIndexRows(dbQueue: environment.dbQueue, shardID: "shard-log-cleanup").count, 0)
    }

    private func makeEnvironment() throws -> (root: URL, dbQueue: DatabaseQueue, logsRoot: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbRoot = root.appendingPathComponent("db", isDirectory: true)
        let logsRoot = root.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: dbRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: dbRoot.appendingPathComponent("shuttle.sqlite").path)
        return (root, dbQueue, logsRoot.path)
    }

    private func makeStore(
        environment: (root: URL, dbQueue: DatabaseQueue, logsRoot: String),
        maxBytesPerFile: Int,
        retentionDays: Int
    ) throws -> ShuttleCommandLogStore {
        ShuttleCommandLogStore(
            dbQueue: environment.dbQueue,
            logsRootPath: environment.logsRoot,
            retentionDays: retentionDays,
            maxBytesPerFile: maxBytesPerFile
        )
    }

    private func fetchIndexRows(dbQueue: DatabaseQueue, shardID: String) throws -> [(filePath: String, offsetStart: Int64, offsetEnd: Int64)] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT file_path, offset_start, offset_end
                FROM log_indexes
                WHERE shard_id = ?
                ORDER BY id ASC
                """,
                arguments: [shardID]
            ).map { row in
                (
                    filePath: row["file_path"],
                    offsetStart: row["offset_start"],
                    offsetEnd: row["offset_end"]
                )
            }
        }
    }

    private func fileSize(atPath path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private func insertShard(id: String, dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            try db.execute(
                sql: """
                INSERT INTO shards (id, title, spec, state, base_commit, retained_until, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id,
                    "Test shard",
                    "Test shard spec",
                    ShuttleShardState.running.rawValue,
                    "deadbeef",
                    nil as Date?,
                    now,
                    now,
                ]
            )
        }
    }
}
