import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleIdempotencyStoreTests: XCTestCase {
    func testStoresNewIdempotencyRecord() throws {
        let store = try makeStore()
        let createdAt = Date()
        let result = try store.recordOrReplay(
            key: "idem-1",
            scope: "shard_create",
            requestHash: "hash-a",
            responseJSON: #"{"status":"created","id":"shard-1"}"#,
            createdAt: createdAt,
            expiresAt: nil
        )

        XCTAssertEqual(
            result,
            .recorded(
                ShuttleIdempotencyRecord(
                    key: "idem-1",
                    scope: "shard_create",
                    requestHash: "hash-a",
                    responseJSON: #"{"status":"created","id":"shard-1"}"#,
                    createdAt: createdAt,
                    expiresAt: nil
                )
            )
        )
    }

    func testReplaysExistingRecordForSameRequest() throws {
        let store = try makeStore()
        let createdAt = Date()
        _ = try store.recordOrReplay(
            key: "idem-2",
            scope: "push",
            requestHash: "hash-push",
            responseJSON: #"{"status":"ok"}"#,
            createdAt: createdAt,
            expiresAt: nil
        )

        let replay = try store.recordOrReplay(
            key: "idem-2",
            scope: "push",
            requestHash: "hash-push",
            responseJSON: #"{"status":"ignored"}"#,
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: nil
        )

        guard case let .replayed(record) = replay else {
            return XCTFail("Expected replayed result")
        }
        XCTAssertEqual(record.key, "idem-2")
        XCTAssertEqual(record.scope, "push")
        XCTAssertEqual(record.requestHash, "hash-push")
        XCTAssertEqual(record.responseJSON, #"{"status":"ok"}"#)
        XCTAssertLessThan(abs(record.createdAt.timeIntervalSince(createdAt)), 1.0)
        XCTAssertNil(record.expiresAt)
    }

    func testConflictsForMismatchedRequestHash() throws {
        let store = try makeStore()
        _ = try store.recordOrReplay(
            key: "idem-3",
            scope: "shard_create",
            requestHash: "hash-original",
            responseJSON: #"{"status":"created"}"#,
            createdAt: Date(),
            expiresAt: nil
        )

        XCTAssertThrowsError(
            try store.recordOrReplay(
                key: "idem-3",
                scope: "shard_create",
                requestHash: "hash-different",
                responseJSON: #"{"status":"created"}"#,
                createdAt: Date(),
                expiresAt: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? ShuttleIdempotencyStoreError,
                .requestMismatch(key: "idem-3", scope: "shard_create")
            )
        }
    }

    private func makeStore() throws -> ShuttleIdempotencyStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbPath = root.appendingPathComponent("shuttle.sqlite").path
        let queue = try ShuttleDatabase.openMigrated(atPath: dbPath)
        return ShuttleIdempotencyStore(dbQueue: queue)
    }
}
