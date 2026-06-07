import Foundation
import GRDB

struct ShuttleActorIdentity: Equatable, Sendable {
    let actorType: String
    let actorID: String
}

struct ShuttleAuditEvent: Equatable, Sendable {
    let id: Int64
    let timestamp: Date
    let actorType: String?
    let actorID: String?
    let entityType: String
    let entityID: String
    let eventType: String
    let payload: [String: String]
}

enum ShuttleAuditEventStoreError: Error, Equatable, Sendable {
    case invalidPayloadEncoding
    case invalidPayloadDecoding
}

struct ShuttleAuditEventStore {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func recordShardCreated(
        shardID: String,
        title: String,
        actor: ShuttleActorIdentity?
    ) throws {
        try append(
            entityType: "shard",
            entityID: shardID,
            eventType: "shard_created",
            payload: ["title": title],
            actor: actor
        )
    }

    func recordShardFinishRequested(
        shardID: String,
        actor: ShuttleActorIdentity?
    ) throws {
        try append(
            entityType: "shard",
            entityID: shardID,
            eventType: "shard_finish_requested",
            payload: [:],
            actor: actor
        )
    }

    func recordShardFinishRequestedByOperator(
        shardID: String,
        instruction: String,
        actor: ShuttleActorIdentity?
    ) throws {
        try append(
            entityType: "shard",
            entityID: shardID,
            eventType: "shard_finish_requested_by_operator",
            payload: ["instruction": instruction],
            actor: actor
        )
    }

    func recordShardInputAnswered(
        shardID: String,
        answerSummary: String,
        actor: ShuttleActorIdentity?
    ) throws {
        try append(
            entityType: "shard",
            entityID: shardID,
            eventType: "shard_input_answered",
            payload: ["answer_summary": answerSummary],
            actor: actor
        )
    }

    func recordShardInputRequested(
        shardID: String,
        question: String,
        details: String?,
        actor: ShuttleActorIdentity?
    ) throws {
        var payload = ["question": question]
        if let details, !details.isEmpty {
            payload["details"] = details
        }
        try append(
            entityType: "shard",
            entityID: shardID,
            eventType: "shard_input_requested",
            payload: payload,
            actor: actor
        )
    }

    func recordShardAbandoned(
        shardID: String,
        reason: String,
        actor: ShuttleActorIdentity?
    ) throws {
        try append(
            entityType: "shard",
            entityID: shardID,
            eventType: "shard_abandoned",
            payload: ["reason": reason],
            actor: actor
        )
    }

    func recordConflictCreated(
        conflictID: String,
        kind: String,
        actor: ShuttleActorIdentity?
    ) throws {
        try append(
            entityType: "conflict",
            entityID: conflictID,
            eventType: "conflict_created",
            payload: ["kind": kind],
            actor: actor
        )
    }

    func recordConflictResolved(
        conflictID: String,
        resolutionShardID: String,
        actor: ShuttleActorIdentity?
    ) throws {
        try append(
            entityType: "conflict",
            entityID: conflictID,
            eventType: "conflict_resolved",
            payload: ["resolution_shard_id": resolutionShardID],
            actor: actor
        )
    }

    func recordPushAction(
        pushID: String,
        target: String,
        ref: String,
        result: String,
        warnings: [String] = [],
        actor: ShuttleActorIdentity?
    ) throws {
        var payload: [String: String] = [
            "target": target,
            "ref": ref,
            "result": result,
        ]
        if !warnings.isEmpty {
            payload["warnings"] = warnings.joined(separator: ",")
        }
        try append(
            entityType: "push",
            entityID: pushID,
            eventType: "push_executed",
            payload: payload,
            actor: actor
        )
    }

    func fetchAll() throws -> [ShuttleAuditEvent] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, timestamp, actor_type, actor_id, entity_type, entity_id, event_type, payload_json
                FROM audit_events
                ORDER BY id ASC
                """
            ).map { row in
                let payloadJSON: String = row["payload_json"]
                guard let payloadData = payloadJSON.data(using: .utf8),
                      let payload = try? JSONDecoder().decode([String: String].self, from: payloadData) else {
                    throw ShuttleAuditEventStoreError.invalidPayloadDecoding
                }

                return ShuttleAuditEvent(
                    id: row["id"],
                    timestamp: row["timestamp"],
                    actorType: row["actor_type"],
                    actorID: row["actor_id"],
                    entityType: row["entity_type"],
                    entityID: row["entity_id"],
                    eventType: row["event_type"],
                    payload: payload
                )
            }
        }
    }

    func fetchPendingSystemInstructions(shardID: String) throws -> [String] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT payload_json
                FROM audit_events
                WHERE entity_type = 'shard' AND entity_id = ? AND event_type = 'shard_finish_requested_by_operator'
                ORDER BY id ASC
                """,
                arguments: [shardID]
            ).compactMap { row in
                let payloadJSON: String = row["payload_json"]
                guard let payloadData = payloadJSON.data(using: .utf8),
                      let payload = try? JSONDecoder().decode([String: String].self, from: payloadData) else {
                    throw ShuttleAuditEventStoreError.invalidPayloadDecoding
                }
                return payload["instruction"]
            }
        }
    }

    private func append(
        entityType: String,
        entityID: String,
        eventType: String,
        payload: [String: String],
        actor: ShuttleActorIdentity?
    ) throws {
        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw ShuttleAuditEventStoreError.invalidPayloadEncoding
        }

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_events (timestamp, actor_type, actor_id, entity_type, entity_id, event_type, payload_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    Date(),
                    actor?.actorType,
                    actor?.actorID,
                    entityType,
                    entityID,
                    eventType,
                    payloadJSON,
                ]
            )
        }
    }
}
