import Foundation
import GRDB

struct ShuttleIdempotencyRecord: Equatable, Sendable {
    let key: String
    let scope: String
    let requestHash: String
    let responseJSON: String
    let createdAt: Date
    let expiresAt: Date?
}

enum ShuttleIdempotencyStoreResult: Equatable, Sendable {
    case recorded(ShuttleIdempotencyRecord)
    case replayed(ShuttleIdempotencyRecord)
}

enum ShuttleIdempotencyStoreError: Error, Equatable, Sendable {
    case requestMismatch(key: String, scope: String)
}

struct ShuttleIdempotencyStore {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func recordOrReplay(
        key: String,
        scope: String,
        requestHash: String,
        responseJSON: String,
        createdAt: Date,
        expiresAt: Date?
    ) throws -> ShuttleIdempotencyStoreResult {
        try dbQueue.write { db in
            if let existing = try fetch(key: key, db: db) {
                guard existing.scope == scope, existing.requestHash == requestHash else {
                    throw ShuttleIdempotencyStoreError.requestMismatch(key: key, scope: scope)
                }
                return .replayed(existing)
            }

            try db.execute(
                sql: """
                INSERT INTO idempotency_keys (idempotency_key, scope, request_hash, response_json, created_at, expires_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    key,
                    scope,
                    requestHash,
                    responseJSON,
                    createdAt,
                    expiresAt,
                ]
            )

            return .recorded(
                ShuttleIdempotencyRecord(
                    key: key,
                    scope: scope,
                    requestHash: requestHash,
                    responseJSON: responseJSON,
                    createdAt: createdAt,
                    expiresAt: expiresAt
                )
            )
        }
    }

    private func fetch(key: String, db: Database) throws -> ShuttleIdempotencyRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT idempotency_key, scope, request_hash, response_json, created_at, expires_at
            FROM idempotency_keys
            WHERE idempotency_key = ?
            """,
            arguments: [key]
        ) else {
            return nil
        }

        return ShuttleIdempotencyRecord(
            key: row["idempotency_key"],
            scope: row["scope"],
            requestHash: row["request_hash"],
            responseJSON: row["response_json"],
            createdAt: row["created_at"],
            expiresAt: row["expires_at"]
        )
    }
}
