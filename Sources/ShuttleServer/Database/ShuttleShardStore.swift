import Foundation
import GRDB

struct ShuttleStoredShard: Equatable, Sendable {
    let id: String
    let title: String
    let spec: String
    let state: ShuttleShardState
    let baseCommit: String
    let retainedUntil: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct ShuttleStoredShardRuntimeMetadata: Equatable, Sendable {
    let shardID: String
    let branchName: String
    let worktreePath: String
    let containerName: String
    let containerStatus: String
    let updatedAt: Date
}

enum ShuttleShardStoreError: Error, Equatable, Sendable {
    case duplicateShard(String)
    case shardNotFound(String)
    case invalidShardState(String)
}

struct ShuttleShardStore {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func createQueuedShard(
        id: String,
        title: String,
        spec: String,
        baseCommit: String,
        branchName: String,
        worktreePath: String,
        createdAt: Date = Date()
    ) throws {
        try dbQueue.write { db in
            if try fetchShard(id: id, db: db) != nil {
                throw ShuttleShardStoreError.duplicateShard(id)
            }

            try db.execute(
                sql: """
                INSERT INTO shards (id, title, spec, state, base_commit, retained_until, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id,
                    title,
                    spec,
                    ShuttleShardState.queued.rawValue,
                    baseCommit,
                    nil as Date?,
                    createdAt,
                    createdAt,
                ]
            )

            try db.execute(
                sql: """
                INSERT INTO shard_runtime_metadata (shard_id, branch_name, worktree_path, container_name, container_status, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id,
                    branchName,
                    worktreePath,
                    pendingContainerName(for: id),
                    "not_created",
                    createdAt,
                ]
            )
        }
    }

    func markDoneRetained(
        shardID: String,
        retainedUntil: Date,
        updatedAt: Date = Date()
    ) throws {
        try dbQueue.write { db in
            guard let existing = try fetchShard(id: shardID, db: db) else {
                throw ShuttleShardStoreError.shardNotFound(shardID)
            }

            guard existing.state == .queued || existing.state == .running || existing.state == .integrating else {
                throw ShuttleShardStoreError.invalidShardState(existing.state.rawValue)
            }

            try db.execute(
                sql: """
                UPDATE shards
                SET state = ?, retained_until = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    ShuttleShardState.done.rawValue,
                    retainedUntil,
                    updatedAt,
                    shardID,
                ]
            )

            try db.execute(
                sql: """
                UPDATE shard_runtime_metadata
                SET updated_at = ?
                WHERE shard_id = ?
                """,
                arguments: [
                    updatedAt,
                    shardID,
                ]
            )
        }
    }

    func fetchShard(id: String) throws -> ShuttleStoredShard? {
        try dbQueue.read { db in
            try fetchShard(id: id, db: db)
        }
    }

    func fetchRuntimeMetadata(shardID: String) throws -> ShuttleStoredShardRuntimeMetadata? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT shard_id, branch_name, worktree_path, container_name, container_status, updated_at
                FROM shard_runtime_metadata
                WHERE shard_id = ?
                """,
                arguments: [shardID]
            ) else {
                return nil
            }

            return ShuttleStoredShardRuntimeMetadata(
                shardID: row["shard_id"],
                branchName: row["branch_name"],
                worktreePath: row["worktree_path"],
                containerName: row["container_name"],
                containerStatus: row["container_status"],
                updatedAt: row["updated_at"]
            )
        }
    }

    private func fetchShard(id: String, db: Database) throws -> ShuttleStoredShard? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT id, title, spec, state, base_commit, retained_until, created_at, updated_at
            FROM shards
            WHERE id = ?
            """,
            arguments: [id]
        ) else {
            return nil
        }

        guard let state = ShuttleShardState(rawValue: row["state"]) else {
            throw ShuttleShardStoreError.invalidShardState(row["state"])
        }

        return ShuttleStoredShard(
            id: row["id"],
            title: row["title"],
            spec: row["spec"],
            state: state,
            baseCommit: row["base_commit"],
            retainedUntil: row["retained_until"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private func pendingContainerName(for shardID: String) -> String {
        "pending-\(shardID)"
    }
}
