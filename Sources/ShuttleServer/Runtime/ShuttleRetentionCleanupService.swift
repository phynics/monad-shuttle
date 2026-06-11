import Foundation

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

    func cleanup(now: Date = Date()) throws -> ShuttleRetentionCleanupResult {
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
            cleanedShardCount += 1
        }

        let commandCleanup = try commandLogStore.cleanupExpiredEntries(now: now)
        let agentCleanup = try agentTranscriptStore.cleanupExpiredEntries(now: now)

        return ShuttleRetentionCleanupResult(
            cleanedShardCount: cleanedShardCount,
            deletedCommandLogIndexCount: commandCleanup.deletedIndexCount,
            deletedCommandLogFileCount: commandCleanup.deletedFileCount,
            deletedAgentLogIndexCount: agentCleanup.deletedIndexCount,
            deletedAgentLogFileCount: agentCleanup.deletedFileCount
        )
    }
}
