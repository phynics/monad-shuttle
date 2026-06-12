import Foundation
import Logging

struct ShuttleUpstreamRefreshResult: Equatable, Sendable {
    enum Outcome: String, Equatable, Sendable {
        case noOp = "no_op"
        case merged = "merged"
        case blocked = "blocked"
    }

    let outcome: Outcome
    let upstreamCommit: String
    let shuttleMainCommit: String?
    let conflictID: String?
}

enum ShuttleUpstreamRefreshServiceError: Error, Equatable, Sendable {
    case integrationLocked(ShuttleRepositoryState)
    case refreshFailed(String)
}

struct ShuttleUpstreamRefreshService {
    let config: ShuttleConfig
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictService: ShuttleConflictService
    let logger: Logger

    init(
        config: ShuttleConfig,
        repositoryStateStore: ShuttleRepositoryStateStore,
        conflictService: ShuttleConflictService,
        logger: Logger = ShuttleLogFactory.make(.refresh)
    ) {
        self.config = config
        self.repositoryStateStore = repositoryStateStore
        self.conflictService = conflictService
        self.logger = logger
    }

    func refresh() throws -> ShuttleUpstreamRefreshResult {
        let logger = self.logger.withMetadata([
            ShuttleLogField.operation: .string("refresh"),
        ])
        let currentState = try repositoryStateStore.fetchIntegrationState()
        guard currentState == .open else {
            logger.warning("refresh_rejected", metadata: [
                ShuttleLogField.outcome: .string("rejected"),
                ShuttleLogField.repoState: .string(currentState.rawValue),
                ShuttleLogField.errorCode: .string("repository_not_open"),
            ])
            throw ShuttleUpstreamRefreshServiceError.integrationLocked(currentState)
        }

        let bareRepositoryPath = ShuttleRepositoryBootstrapper.repositoryPath(for: config)
        let upstreamRef = "refs/remotes/origin/\(config.repository.sourceBranch)"

        let beforeMainCommit = try revParse("refs/heads/\(ShuttleRepositoryBootstrapper.shuttleMainBranch)", bareRepositoryPath: bareRepositoryPath)

        do {
            try repositoryStateStore.transitionIntegrationState(
                from: .open,
                to: .refreshing,
                config: config
            )

            _ = try ShuttleGitShell.run(
                [
                    "--git-dir",
                    bareRepositoryPath,
                    "fetch",
                    "origin",
                    "refs/heads/\(config.repository.sourceBranch):\(upstreamRef)",
                ],
                logger: logger
            )

            let upstreamCommit = try revParse(upstreamRef, bareRepositoryPath: bareRepositoryPath)
            if upstreamCommit == beforeMainCommit {
                try repositoryStateStore.transitionIntegrationState(
                    from: .refreshing,
                    to: .open,
                    config: config,
                    upstreamHeadCommit: upstreamCommit,
                    shuttleMainCommit: beforeMainCommit
                )
                return ShuttleUpstreamRefreshResult(
                    outcome: .noOp,
                    upstreamCommit: upstreamCommit,
                    shuttleMainCommit: beforeMainCommit,
                    conflictID: nil
                )
            }

            let mergeResult = try mergeUpstreamIntoShuttleMain(
                upstreamRef: upstreamRef,
                bareRepositoryPath: bareRepositoryPath
            )

            switch mergeResult {
            case .merged(let shuttleMainCommit):
                logger.info("refresh_merged", metadata: [
                    ShuttleLogField.outcome: .string("success"),
                ])
                try repositoryStateStore.transitionIntegrationState(
                    from: .refreshing,
                    to: .open,
                    config: config,
                    upstreamHeadCommit: upstreamCommit,
                    shuttleMainCommit: shuttleMainCommit
                )
                return ShuttleUpstreamRefreshResult(
                    outcome: .merged,
                    upstreamCommit: upstreamCommit,
                    shuttleMainCommit: shuttleMainCommit,
                    conflictID: nil
                )
            case .conflicted:
                let conflict = try conflictService.recordUpstreamRefreshConflict(
                    details: [
                        "reason": "merge_conflict",
                        "upstream_ref": upstreamRef,
                    ]
                )
                logger.warning("refresh_conflict_recorded", metadata: [
                    ShuttleLogField.outcome: .string("conflict"),
                    ShuttleLogField.conflictID: .string(conflict.id),
                ])
                return ShuttleUpstreamRefreshResult(
                    outcome: .blocked,
                    upstreamCommit: upstreamCommit,
                    shuttleMainCommit: nil,
                    conflictID: conflict.id
                )
            }
        } catch let error as ShuttleUpstreamRefreshServiceError {
            logger.error("refresh_failed", metadata: [
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("refresh_failed"),
            ])
            _ = try? repositoryStateStore.transitionIntegrationState(
                from: .refreshing,
                to: .open,
                config: config
            )
            throw error
        } catch {
            if try repositoryStateStore.fetchIntegrationState() == .refreshing {
                _ = try? repositoryStateStore.transitionIntegrationState(
                    from: .refreshing,
                    to: .open,
                    config: config
                )
            }
            logger.error("refresh_failed", metadata: [
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("refresh_failed"),
            ])
            throw ShuttleUpstreamRefreshServiceError.refreshFailed(error.localizedDescription)
        }
    }

    private func revParse(_ ref: String, bareRepositoryPath: String) throws -> String {
        try ShuttleGitShell.run(
            ["--git-dir", bareRepositoryPath, "rev-parse", ref],
            logger: logger
        ).stdout
    }

    private func mergeUpstreamIntoShuttleMain(
        upstreamRef: String,
        bareRepositoryPath: String
    ) throws -> MergeResult {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        _ = try ShuttleGitShell.run(
            [
                "--git-dir",
                bareRepositoryPath,
                "worktree",
                "add",
                tempURL.path,
                ShuttleRepositoryBootstrapper.shuttleMainBranch,
            ],
            logger: logger
        )

        defer {
            _ = try? ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "worktree", "remove", "--force", tempURL.path]
            )
        }

        _ = try ShuttleGitShell.run(["config", "user.name", "Shuttle Refresh"], workingDirectory: tempURL.path, logger: logger)
        _ = try ShuttleGitShell.run(["config", "user.email", "shuttle-refresh@example.com"], workingDirectory: tempURL.path, logger: logger)

        do {
            _ = try ShuttleGitShell.run(
                ["merge", "--no-ff", "--no-edit", upstreamRef],
                workingDirectory: tempURL.path,
                logger: logger
            )
            let commit = try ShuttleGitShell.run(["rev-parse", "HEAD"], workingDirectory: tempURL.path, logger: logger).stdout
            return .merged(commit)
        } catch let error as ShuttleGitShellError {
            _ = try? ShuttleGitShell.run(["merge", "--abort"], workingDirectory: tempURL.path, logger: logger)
            if case .commandFailed = error {
                return .conflicted
            }
            throw error
        }
    }

    private enum MergeResult: Equatable {
        case merged(String)
        case conflicted
    }
}
