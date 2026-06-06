import Foundation
import GRDB

struct ShuttleStoredRepositoryState: Equatable, Sendable {
    let repoURL: String
    let sourceBranch: String
    let shuttleMainBranch: String
    let upstreamHeadCommit: String?
    let shuttleMainCommit: String?
    let integrationState: ShuttleRepositoryState
    let blockedConflictID: String?
    let createdAt: Date
    let updatedAt: Date
}

enum ShuttleRepositoryStateStoreError: Error, Equatable, Sendable {
    case invalidIntegrationState(String)
}

struct ShuttleRepositoryStateStore {
    let dbQueue: DatabaseQueue

    func fetch() throws -> ShuttleStoredRepositoryState? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT repo_url, source_branch, shuttle_main_branch, upstream_head_commit, shuttle_main_commit,
                       integration_state, blocked_conflict_id, created_at, updated_at
                FROM repository_state
                ORDER BY id ASC
                LIMIT 1
                """
            ) else {
                return nil
            }

            guard let integrationState = ShuttleRepositoryState(rawValue: row["integration_state"]) else {
                throw ShuttleRepositoryStateStoreError.invalidIntegrationState(row["integration_state"])
            }

            return ShuttleStoredRepositoryState(
                repoURL: row["repo_url"],
                sourceBranch: row["source_branch"],
                shuttleMainBranch: row["shuttle_main_branch"],
                upstreamHeadCommit: row["upstream_head_commit"],
                shuttleMainCommit: row["shuttle_main_commit"],
                integrationState: integrationState,
                blockedConflictID: row["blocked_conflict_id"],
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    func fetchIntegrationState() throws -> ShuttleRepositoryState {
        try fetch()?.integrationState ?? .open
    }

    func upsert(
        config: ShuttleConfig,
        integrationState: ShuttleRepositoryState,
        upstreamHeadCommit: String? = nil,
        shuttleMainCommit: String? = nil,
        blockedConflictID: String? = nil,
        updatedAt: Date = Date()
    ) throws {
        try dbQueue.write { db in
            let existingID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM repository_state ORDER BY id ASC LIMIT 1"
            )

            if let existingID {
                try db.execute(
                    sql: """
                    UPDATE repository_state
                    SET repo_url = ?, source_branch = ?, shuttle_main_branch = ?, upstream_head_commit = ?,
                        shuttle_main_commit = ?, integration_state = ?, blocked_conflict_id = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        config.repository.url,
                        config.repository.sourceBranch,
                        ShuttleRepositoryBootstrapper.shuttleMainBranch,
                        upstreamHeadCommit,
                        shuttleMainCommit,
                        integrationState.rawValue,
                        blockedConflictID,
                        updatedAt,
                        existingID,
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO repository_state
                    (repo_url, source_branch, shuttle_main_branch, upstream_head_commit, shuttle_main_commit,
                     integration_state, blocked_conflict_id, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        config.repository.url,
                        config.repository.sourceBranch,
                        ShuttleRepositoryBootstrapper.shuttleMainBranch,
                        upstreamHeadCommit,
                        shuttleMainCommit,
                        integrationState.rawValue,
                        blockedConflictID,
                        updatedAt,
                        updatedAt,
                    ]
                )
            }
        }
    }
}
