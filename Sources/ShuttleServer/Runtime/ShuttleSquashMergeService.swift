import Foundation
import Logging

struct ShuttleSquashMergeResult: Equatable, Sendable {
    let shardID: String
    let commitHash: String
    let retainedUntil: Date
}

enum ShuttleSquashMergeServiceError: Error, Equatable, Sendable {
    case integrationLocked(ShuttleRepositoryState)
    case shardNotReady(String)
    case conflictRecorded(String)
    case mergeFailed(String)
}

struct ShuttleSquashMergeService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let integrationGateService: ShuttleIntegrationGateService
    let shardWorkspaceService: ShuttleShardWorkspaceService
    let conflictService: ShuttleConflictService?
    let logger: Logger

    init(
        config: ShuttleConfig,
        shardStore: ShuttleShardStore,
        repositoryStateStore: ShuttleRepositoryStateStore,
        integrationGateService: ShuttleIntegrationGateService,
        shardWorkspaceService: ShuttleShardWorkspaceService,
        conflictService: ShuttleConflictService?,
        logger: Logger = ShuttleLogFactory.make(.integration)
    ) {
        self.config = config
        self.shardStore = shardStore
        self.repositoryStateStore = repositoryStateStore
        self.integrationGateService = integrationGateService
        self.shardWorkspaceService = shardWorkspaceService
        self.conflictService = conflictService
        self.logger = logger
    }

    func merge(shardID: String) throws -> ShuttleSquashMergeResult {
        let logger = self.logger.withMetadata(ShuttleLogMetadata.shard(shardID)).withMetadata([
            ShuttleLogField.operation: .string("squash_merge"),
        ])
        guard let shard = try shardStore.fetchShard(id: shardID) else {
            logger.warning("merge_rejected", metadata: [
                ShuttleLogField.outcome: .string("rejected"),
                ShuttleLogField.errorCode: .string("shard_not_ready"),
            ])
            throw ShuttleSquashMergeServiceError.shardNotReady(shardID)
        }
        guard shard.state == .integrating else {
            logger.warning("merge_rejected", metadata: [
                ShuttleLogField.outcome: .string("rejected"),
                ShuttleLogField.errorCode: .string("invalid_shard_state"),
                ShuttleLogField.shardState: .string(shard.state.rawValue),
            ])
            throw ShuttleSquashMergeServiceError.shardNotReady(shardID)
        }

        let approval: ShuttleIntegrationGateApproval
        do {
            approval = try integrationGateService.validate(shardID: shardID)
        } catch let error as ShuttleIntegrationGateError {
            switch error {
            case .repositoryNotOpen(let state):
                logger.warning("merge_rejected", metadata: [
                    ShuttleLogField.outcome: .string("rejected"),
                    ShuttleLogField.repoState: .string(state.rawValue),
                    ShuttleLogField.errorCode: .string("repository_not_open"),
                ])
                throw ShuttleSquashMergeServiceError.integrationLocked(state)
            case .branchNotMergeable:
                let conflict = try recordMergeConflict(
                    shardID: shardID,
                    reason: "branch_not_mergeable"
                )
                logger.warning("merge_conflict_recorded", metadata: [
                    ShuttleLogField.outcome: .string("conflict"),
                    ShuttleLogField.conflictID: .string(conflict.id),
                ])
                throw ShuttleSquashMergeServiceError.conflictRecorded(conflict.id)
            default:
                logger.error("merge_failed", metadata: [
                    ShuttleLogField.outcome: .string("error"),
                    ShuttleLogField.errorCode: .string("integration_gate_failed"),
                ])
                throw ShuttleSquashMergeServiceError.mergeFailed(String(describing: error))
            }
        }

        do {
            try repositoryStateStore.transitionIntegrationState(
                from: .open,
                to: .integrating,
                config: config
            )
        } catch let error as ShuttleRepositoryStateStoreError {
            switch error {
            case .stateMismatch(_, let actual):
                logger.warning("merge_rejected", metadata: [
                    ShuttleLogField.outcome: .string("rejected"),
                    ShuttleLogField.repoState: .string(actual.rawValue),
                    ShuttleLogField.errorCode: .string("integration_locked"),
                ])
                throw ShuttleSquashMergeServiceError.integrationLocked(actual)
            default:
                logger.error("merge_failed", metadata: [
                    ShuttleLogField.outcome: .string("error"),
                    ShuttleLogField.errorCode: .string("state_transition_failed"),
                ])
                throw ShuttleSquashMergeServiceError.mergeFailed(String(describing: error))
            }
        }

        do {
            let commitHash = try performSquashMerge(approval: approval)
            let retainedUntil = Date().addingTimeInterval(Double(config.retention.worktreeDays) * 24 * 60 * 60)
            try shardWorkspaceService.retainDoneShard(
                shardID: shardID,
                retainedUntil: retainedUntil
            )
            try repositoryStateStore.transitionIntegrationState(
                from: .integrating,
                to: .open,
                config: config,
                shuttleMainCommit: commitHash
            )

            return ShuttleSquashMergeResult(
                shardID: shardID,
                commitHash: commitHash,
                retainedUntil: retainedUntil
            )
        } catch let error as ShuttleSquashMergeServiceError {
            logger.log(
                level: .warning,
                "merge_completed_with_error",
                metadata: [ShuttleLogField.outcome: .string("error")]
            )
            if case .conflictRecorded = error {
                // Repository is intentionally left blocked.
            } else {
                _ = try? repositoryStateStore.transitionIntegrationState(
                    from: .integrating,
                    to: .open,
                    config: config
                )
            }
            throw error
        } catch {
            if case let .commandFailed(_, _, stderr) = error as? ShuttleGitShellError,
               stderr.localizedCaseInsensitiveContains("conflict") {
                let conflict = try recordMergeConflict(
                    shardID: shardID,
                    reason: "merge_conflict"
                )
                logger.warning("merge_conflict_recorded", metadata: [
                    ShuttleLogField.outcome: .string("conflict"),
                    ShuttleLogField.conflictID: .string(conflict.id),
                ])
                throw ShuttleSquashMergeServiceError.conflictRecorded(conflict.id)
            }

            _ = try? repositoryStateStore.transitionIntegrationState(
                from: .integrating,
                to: .open,
                config: config
            )
            logger.error("merge_failed", metadata: [
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("merge_failed"),
            ])
            throw ShuttleSquashMergeServiceError.mergeFailed(error.localizedDescription)
        }
    }

    static func buildCommitMessage(report: ShuttleCompletionReport) -> String {
        var sections: [String] = [report.summary]

        sections.append(
            """
            Files Changed:
            \(report.filesChanged.joined(separator: "\n"))
            """
        )

        sections.append(
            """
            Checks:
            \(report.checks.map { "\($0.name): \($0.status) [\($0.kind)]" }.joined(separator: "\n"))
            """
        )

        if !report.risks.isEmpty {
            sections.append(
                """
                Risks:
                \(report.risks.joined(separator: "\n"))
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private func performSquashMerge(approval: ShuttleIntegrationGateApproval) throws -> String {
        let bareRepositoryPath = ShuttleRepositoryBootstrapper.repositoryPath(for: config)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            _ = try ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "worktree", "add", tempURL.path, ShuttleRepositoryBootstrapper.shuttleMainBranch]
            )
        } catch {
            throw ShuttleSquashMergeServiceError.mergeFailed(error.localizedDescription)
        }

        defer {
            _ = try? ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "worktree", "remove", "--force", tempURL.path]
            )
        }

        do {
            _ = try ShuttleGitShell.run(["config", "user.name", "Shuttle Merge"], workingDirectory: tempURL.path)
            _ = try ShuttleGitShell.run(["config", "user.email", "shuttle-merge@example.com"], workingDirectory: tempURL.path)
            _ = try ShuttleGitShell.run(["merge", "--squash", approval.runtimeMetadata.branchName], workingDirectory: tempURL.path)
            _ = try ShuttleGitShell.run(
                ["commit", "-m", Self.buildCommitMessage(report: approval.completionReport)],
                workingDirectory: tempURL.path
            )
            return try ShuttleGitShell.run(["rev-parse", "HEAD"], workingDirectory: tempURL.path).stdout
        } catch {
            _ = try? ShuttleGitShell.run(["merge", "--abort"], workingDirectory: tempURL.path)
            throw ShuttleSquashMergeServiceError.mergeFailed(error.localizedDescription)
        }
    }

    private func recordMergeConflict(
        shardID: String,
        reason: String
    ) throws -> ShuttleStoredConflict {
        guard let conflictService else {
            throw ShuttleSquashMergeServiceError.mergeFailed("merge conflict recorded without conflict service")
        }
        return try conflictService.recordShardMergeConflict(
            sourceShardID: shardID,
            details: ["reason": reason]
        )
    }
}
