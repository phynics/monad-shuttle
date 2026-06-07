import Foundation
import GRDB

struct ShuttleStoredConflict: Equatable, Sendable {
    let id: String
    let kind: String
    let state: String
    let blocking: Bool
    let sourceShardID: String?
    let resolutionShardID: String?
    let details: [String: String]
    let createdAt: Date
    let updatedAt: Date
}

enum ShuttleConflictStoreError: Error, Equatable, Sendable {
    case invalidDetailsEncoding
    case invalidDetailsDecoding
}

struct ShuttleConflictStore {
    let dbQueue: DatabaseQueue

    func create(
        id: String = UUID().uuidString.lowercased(),
        kind: String,
        state: String = "open",
        blocking: Bool = true,
        sourceShardID: String? = nil,
        resolutionShardID: String? = nil,
        details: [String: String],
        createdAt: Date = Date()
    ) throws -> ShuttleStoredConflict {
        let detailsJSON = try encode(details: details)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO conflicts
                (id, kind, state, blocking, source_shard_id, resolution_shard_id, details_json, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id,
                    kind,
                    state,
                    blocking,
                    sourceShardID,
                    resolutionShardID,
                    detailsJSON,
                    createdAt,
                    createdAt,
                ]
            )
        }

        return ShuttleStoredConflict(
            id: id,
            kind: kind,
            state: state,
            blocking: blocking,
            sourceShardID: sourceShardID,
            resolutionShardID: resolutionShardID,
            details: details,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    func fetchOpenConflicts() throws -> [ShuttleStoredConflict] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, kind, state, blocking, source_shard_id, resolution_shard_id, details_json, created_at, updated_at
                FROM conflicts
                WHERE state = 'open'
                ORDER BY created_at ASC, id ASC
                """
            ).map(decodeConflict(row:))
        }
    }

    private func decodeConflict(row: Row) throws -> ShuttleStoredConflict {
        let detailsJSON: String? = row["details_json"]
        let details: [String: String]
        if let detailsJSON, !detailsJSON.isEmpty {
            details = try decode(detailsJSON: detailsJSON)
        } else {
            details = [:]
        }

        return ShuttleStoredConflict(
            id: row["id"],
            kind: row["kind"],
            state: row["state"],
            blocking: row["blocking"],
            sourceShardID: row["source_shard_id"],
            resolutionShardID: row["resolution_shard_id"],
            details: details,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func encode(details: [String: String]) throws -> String {
        let data = try JSONEncoder().encode(details)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ShuttleConflictStoreError.invalidDetailsEncoding
        }
        return json
    }

    private func decode(detailsJSON: String) throws -> [String: String] {
        guard let data = detailsJSON.data(using: .utf8) else {
            throw ShuttleConflictStoreError.invalidDetailsDecoding
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw ShuttleConflictStoreError.invalidDetailsDecoding
        }
    }
}
