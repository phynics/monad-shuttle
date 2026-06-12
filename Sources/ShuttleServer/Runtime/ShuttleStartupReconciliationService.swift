import Foundation
import Logging

struct ShuttleStartupReconciliationService {
    let config: ShuttleConfig
    let managedRepository: ShuttleRepositoryBootstrapResult
    let shardStore: ShuttleShardStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictStore: ShuttleConflictStore
    let auditEventStore: ShuttleAuditEventStore?
    let dockerAccessController: ShuttleDockerAccessController
    let logger: Logger = ShuttleLogFactory.make(.runtime)

    func reconcile() async throws {
        let logger = self.logger.withMetadata([
            ShuttleLogField.operation: .string("startup_reconciliation"),
        ])
        logger.info("startup_reconciliation_started")
        try reconcileRepositoryState()

        for shard in try shardStore.fetchShards() {
            switch shard.state {
            case .queued:
                try reconcileQueuedShard(shard)
            case .running:
                try await reconcileRunningShard(shard)
            case .needsInput:
                try reconcileNeedsInputShard(shard)
            case .integrating:
                try await reconcileIntegratingShard(shard)
            case .done:
                try reconcileDoneShard(shard)
            case .failed, .abandoned:
                continue
            }
        }
        logger.info("startup_reconciliation_completed", metadata: [
            ShuttleLogField.outcome: .string("success"),
        ])
    }

    private func reconcileRepositoryState() throws {
        let openBlockingConflicts = try conflictStore.fetchOpenConflicts().filter(\.blocking)
        let blockedConflictID = openBlockingConflicts.first?.id
        let nextState: ShuttleRepositoryState = (blockedConflictID != nil || repositoryHasActiveMergeState()) ? .blocked : .open

        try repositoryStateStore.upsert(
            config: config,
            integrationState: nextState,
            upstreamHeadCommit: try revParseOptional("refs/remotes/origin/\(config.repository.sourceBranch)"),
            shuttleMainCommit: try revParseOptional("refs/heads/\(managedRepository.shuttleMainBranch)"),
            blockedConflictID: blockedConflictID
        )
    }

    private func reconcileQueuedShard(_ shard: ShuttleStoredShard) throws {
        guard let runtime = try shardStore.fetchRuntimeMetadata(shardID: shard.id) else {
            return
        }

        if !FileManager.default.fileExists(atPath: runtime.worktreePath) {
            try shardStore.updateState(shardID: shard.id, to: .failed)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: .queued,
                toState: .failed,
                outcome: "worktree_missing_failed"
            )
        }
    }

    private func reconcileRunningShard(_ shard: ShuttleStoredShard) async throws {
        try await reconcileLiveShard(shard, currentState: .running)
    }

    private func reconcileNeedsInputShard(_ shard: ShuttleStoredShard) throws {
        try reconcileNeedsInputLikeShard(shard, currentState: .needsInput)
    }

    private func reconcileIntegratingShard(_ shard: ShuttleStoredShard) async throws {
        guard let runtime = try shardStore.fetchRuntimeMetadata(shardID: shard.id) else {
            try shardStore.updateState(shardID: shard.id, to: .failed)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: .integrating,
                toState: .failed,
                outcome: "missing_runtime_metadata_failed"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: runtime.worktreePath) else {
            try shardStore.updateState(shardID: shard.id, to: .failed)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: .integrating,
                toState: .failed,
                outcome: "worktree_missing_failed"
            )
            return
        }

        if try branchMatchesShuttleMain(branchName: runtime.branchName) {
            let workspaceService = ShuttleShardWorkspaceService(
                shardStore: shardStore,
                worktreeManager: ShuttleWorktreeManager(
                    bareRepositoryPath: managedRepository.bareRepositoryPath,
                    worktreesRootPath: config.paths.worktreesPath
                )
            )
            let retainedUntil = Date().addingTimeInterval(Double(config.retention.worktreeDays) * 24 * 60 * 60)
            try workspaceService.retainDoneShard(shardID: shard.id, retainedUntil: retainedUntil)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: .integrating,
                toState: .done,
                outcome: "integrating_to_done"
            )
            return
        }

        if try auditEventStore?.hasOutstandingInputRequest(shardID: shard.id) == true {
            try shardStore.updateState(shardID: shard.id, to: .needsInput)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: .integrating,
                toState: .needsInput,
                outcome: "integrating_to_needs_input"
            )
            return
        }

        try shardStore.updateState(shardID: shard.id, to: .running)
        try auditEventStore?.recordShardReconciled(
            shardID: shard.id,
            fromState: .integrating,
            toState: .running,
            outcome: "integrating_to_running"
        )
        let containerService = makeContainerService()
        _ = try await containerService.ensureContainer(forShardID: shard.id)
    }

    private func reconcileDoneShard(_ shard: ShuttleStoredShard) throws {
        guard let runtime = try shardStore.fetchRuntimeMetadata(shardID: shard.id) else {
            return
        }

        if !FileManager.default.fileExists(atPath: runtime.worktreePath) {
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: .done,
                toState: .done,
                outcome: "missing_retained_worktree"
            )
        }
    }

    private func reconcileLiveShard(
        _ shard: ShuttleStoredShard,
        currentState: ShuttleShardState
    ) async throws {
        guard let runtime = try shardStore.fetchRuntimeMetadata(shardID: shard.id) else {
            try shardStore.updateState(shardID: shard.id, to: .failed)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: currentState,
                toState: .failed,
                outcome: "missing_runtime_metadata_failed"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: runtime.worktreePath) else {
            try shardStore.updateState(shardID: shard.id, to: .failed)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: currentState,
                toState: .failed,
                outcome: "worktree_missing_failed"
            )
            return
        }

        let containerService = makeContainerService()
        _ = try await containerService.ensureContainer(forShardID: shard.id)
    }

    private func reconcileNeedsInputLikeShard(
        _ shard: ShuttleStoredShard,
        currentState: ShuttleShardState
    ) throws {
        guard let runtime = try shardStore.fetchRuntimeMetadata(shardID: shard.id) else {
            try shardStore.updateState(shardID: shard.id, to: .failed)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: currentState,
                toState: .failed,
                outcome: "missing_runtime_metadata_failed"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: runtime.worktreePath) else {
            try shardStore.updateState(shardID: shard.id, to: .failed)
            try auditEventStore?.recordShardReconciled(
                shardID: shard.id,
                fromState: currentState,
                toState: .failed,
                outcome: "worktree_missing_failed"
            )
            return
        }
    }

    private func makeContainerService() -> ShuttleShardContainerService {
        ShuttleShardContainerService(
            shardStore: shardStore,
            dockerAccessController: dockerAccessController,
            config: config
        )
    }

    private func revParseOptional(_ ref: String) throws -> String? {
        do {
            return try ShuttleGitShell.run(
                ["--git-dir", managedRepository.bareRepositoryPath, "rev-parse", ref]
            ).stdout
        } catch let error as ShuttleGitShellError {
            if case .commandFailed = error {
                return nil
            }
            throw error
        }
    }

    private func branchMatchesShuttleMain(branchName: String) throws -> Bool {
        do {
            _ = try ShuttleGitShell.run(
                [
                    "--git-dir",
                    managedRepository.bareRepositoryPath,
                    "diff",
                    "--quiet",
                    "refs/heads/\(managedRepository.shuttleMainBranch)",
                    "refs/heads/\(branchName)",
                ]
            )
            return true
        } catch let error as ShuttleGitShellError {
            if case .commandFailed(_, let status, _) = error, status == 1 {
                return false
            }
            throw error
        }
    }

    private func repositoryHasActiveMergeState() -> Bool {
        let worktreesRoot = URL(fileURLWithPath: managedRepository.bareRepositoryPath, isDirectory: true)
            .appendingPathComponent("worktrees", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: worktreesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "MERGE_HEAD" {
                return true
            }
        }
        return false
    }
}
