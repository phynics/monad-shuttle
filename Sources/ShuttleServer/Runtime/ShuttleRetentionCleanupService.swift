import Foundation
import Logging

struct ShuttleRetentionCleanupResult: Equatable, Sendable {
    let cleanedShardCount: Int
    let deletedCommandLogIndexCount: Int
    let deletedCommandLogFileCount: Int
    let deletedAgentLogIndexCount: Int
    let deletedAgentLogFileCount: Int
}

struct ShuttleRetentionCleanupService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let auditEventStore: ShuttleAuditEventStore?
    let worktreeManager: ShuttleWorktreeManager
    let commandLogStore: ShuttleCommandLogStore
    let agentTranscriptStore: ShuttleAgentTranscriptStore
    let logger: Logger = ShuttleLogFactory.make(.retention)

    func cleanup(now: Date = Date()) throws -> ShuttleRetentionCleanupResult {
        let logger = self.logger.withMetadata([
            ShuttleLogField.operation: .string("retention_cleanup"),
        ])
        let expiredShards = try shardStore.fetchExpiredRetainedShards(now: now)
        var cleanedShardCount = 0

        for detail in expiredShards {
            guard let runtimeMetadata = detail.runtimeMetadata else {
                continue
            }

            let worktreeExists = FileManager.default.fileExists(atPath: runtimeMetadata.worktreePath)
            let branchExists = worktreeManager.branchExists(branchName: runtimeMetadata.branchName)

            try worktreeManager.removeWorktree(
                branchName: runtimeMetadata.branchName,
                worktreePath: runtimeMetadata.worktreePath
            )
            try auditEventStore?.recordShardRetentionCleaned(
                shardID: detail.shard.id,
                worktreeRemoved: worktreeExists,
                branchRemoved: branchExists
            )
            logger.info("retained_shard_cleaned", metadata: [
                ShuttleLogField.outcome: .string("success"),
                ShuttleLogField.shardID: .string(detail.shard.id),
                ShuttleLogField.branch: .string(runtimeMetadata.branchName),
            ])
            cleanedShardCount += 1
        }

        let commandCleanup = try commandLogStore.cleanupExpiredEntries(now: now)
        let agentCleanup = try agentTranscriptStore.cleanupExpiredEntries(now: now)

        let result = ShuttleRetentionCleanupResult(
            cleanedShardCount: cleanedShardCount,
            deletedCommandLogIndexCount: commandCleanup.deletedIndexCount,
            deletedCommandLogFileCount: commandCleanup.deletedFileCount,
            deletedAgentLogIndexCount: agentCleanup.deletedIndexCount,
            deletedAgentLogFileCount: agentCleanup.deletedFileCount
        )
        logger.info("retention_cleanup_completed", metadata: [
            ShuttleLogField.outcome: .string("success"),
            "cleaned_shards": .stringConvertible(result.cleanedShardCount),
            "deleted_command_log_indexes": .stringConvertible(result.deletedCommandLogIndexCount),
            "deleted_agent_log_indexes": .stringConvertible(result.deletedAgentLogIndexCount),
        ])
        return result
    }
}
