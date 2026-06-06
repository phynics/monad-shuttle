import Foundation

struct ShuttleSquashMergeResult: Equatable, Sendable {
    let shardID: String
    let commitHash: String
    let retainedUntil: Date
}

enum ShuttleSquashMergeServiceError: Error, Equatable, Sendable {
    case integrationLocked(ShuttleRepositoryState)
    case shardNotReady(String)
    case mergeFailed(String)
}

struct ShuttleSquashMergeService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let integrationGateService: ShuttleIntegrationGateService
    let shardWorkspaceService: ShuttleShardWorkspaceService

    func merge(shardID: String) throws -> ShuttleSquashMergeResult {
        guard let shard = try shardStore.fetchShard(id: shardID) else {
            throw ShuttleSquashMergeServiceError.shardNotReady(shardID)
        }
        guard shard.state == .integrating else {
            throw ShuttleSquashMergeServiceError.shardNotReady(shardID)
        }

        let approval: ShuttleIntegrationGateApproval
        do {
            approval = try integrationGateService.validate(shardID: shardID)
        } catch let error as ShuttleIntegrationGateError {
            switch error {
            case .repositoryNotOpen(let state):
                throw ShuttleSquashMergeServiceError.integrationLocked(state)
            default:
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
                throw ShuttleSquashMergeServiceError.integrationLocked(actual)
            default:
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
            _ = try? repositoryStateStore.transitionIntegrationState(
                from: .integrating,
                to: .open,
                config: config
            )
            throw error
        } catch {
            _ = try? repositoryStateStore.transitionIntegrationState(
                from: .integrating,
                to: .open,
                config: config
            )
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
}
