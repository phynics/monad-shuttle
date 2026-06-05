import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleAuditEventStoreTests: XCTestCase {
    func testRecordsRequiredLifecycleEvents() throws {
        let store = try makeStore()
        let actor = ShuttleActorIdentity(actorType: "api_client", actorID: "client-1")

        try store.recordShardCreated(shardID: "shard-1", title: "Implement parser", actor: actor)
        try store.recordShardFinishRequested(shardID: "shard-1", actor: actor)
        try store.recordShardInputRequested(
            shardID: "shard-1",
            question: "Need deployment target",
            details: "Remote branch is ambiguous",
            actor: actor
        )
        try store.recordShardInputAnswered(
            shardID: "shard-1",
            answerSummary: "Provided missing env var details",
            actor: actor
        )
        try store.recordShardAbandoned(shardID: "shard-1", reason: "superseded", actor: actor)
        try store.recordConflictCreated(conflictID: "conflict-1", kind: "merge", actor: actor)
        try store.recordConflictResolved(
            conflictID: "conflict-1",
            resolutionShardID: "shard-2",
            actor: actor
        )
        try store.recordPushAction(
            pushID: "push-1",
            target: "origin-main",
            ref: "refs/heads/shuttle-main",
            result: "success",
            actor: actor
        )

        let events = try store.fetchAll()
        XCTAssertEqual(events.count, 8)
        XCTAssertEqual(events.map(\.eventType), [
            "shard_created",
            "shard_finish_requested",
            "shard_input_requested",
            "shard_input_answered",
            "shard_abandoned",
            "conflict_created",
            "conflict_resolved",
            "push_executed",
        ])

        for event in events {
            XCTAssertEqual(event.actorType, "api_client")
            XCTAssertEqual(event.actorID, "client-1")
            XCTAssertFalse(event.entityType.isEmpty)
            XCTAssertFalse(event.entityID.isEmpty)
        }
    }

    func testAuditEventsAreAppendOnlyAtDatabaseLevel() throws {
        let queue = try makeDatabaseQueue()
        let store = ShuttleAuditEventStore(dbQueue: queue)
        try store.recordShardCreated(shardID: "shard-1", title: "Test", actor: nil)

        let eventID = try queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM audit_events LIMIT 1")
        }
        XCTAssertNotNil(eventID)

        XCTAssertThrowsError(
            try queue.write { db in
                try db.execute(
                    sql: "UPDATE audit_events SET event_type = 'tampered' WHERE id = ?",
                    arguments: [eventID!]
                )
            }
        )

        XCTAssertThrowsError(
            try queue.write { db in
                try db.execute(
                    sql: "DELETE FROM audit_events WHERE id = ?",
                    arguments: [eventID!]
                )
            }
        )
    }

    private func makeStore() throws -> ShuttleAuditEventStore {
        let queue = try makeDatabaseQueue()
        return ShuttleAuditEventStore(dbQueue: queue)
    }

    private func makeDatabaseQueue() throws -> DatabaseQueue {
        let path = try makeTemporaryDatabasePath()
        return try ShuttleDatabase.openMigrated(atPath: path)
    }

    private func makeTemporaryDatabasePath() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("shuttle.sqlite").path
    }
}
