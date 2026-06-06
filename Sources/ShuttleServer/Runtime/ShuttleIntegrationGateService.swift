import Foundation

struct ShuttleIntegrationGateApproval: Equatable, Sendable {
    let shard: ShuttleStoredShard
    let runtimeMetadata: ShuttleStoredShardRuntimeMetadata
    let completionReport: ShuttleCompletionReport
}

enum ShuttleIntegrationGateError: Error, Equatable, Sendable {
    case shardNotFound(String)
    case runtimeMetadataMissing(String)
    case missingCompletionReport(String)
    case missingValidationStatuses(String)
    case repositoryNotOpen(ShuttleRepositoryState)
    case unstagedChanges(String, paths: [String])
    case unreportedUntrackedFiles(String, paths: [String])
    case branchNotMergeable(String)
}

struct ShuttleIntegrationGateService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let completionReportStore: ShuttleCompletionReportStore
    let repositoryStateStore: ShuttleRepositoryStateStore

    func validate(shardID: String) throws -> ShuttleIntegrationGateApproval {
        guard let shard = try shardStore.fetchShard(id: shardID) else {
            throw ShuttleIntegrationGateError.shardNotFound(shardID)
        }
        guard let runtimeMetadata = try shardStore.fetchRuntimeMetadata(shardID: shardID) else {
            throw ShuttleIntegrationGateError.runtimeMetadataMissing(shardID)
        }
        guard let report = try completionReportStore.fetch(shardID: shardID) else {
            throw ShuttleIntegrationGateError.missingCompletionReport(shardID)
        }
        guard !report.validationStatuses.isEmpty else {
            throw ShuttleIntegrationGateError.missingValidationStatuses(shardID)
        }

        let repoState = try repositoryStateStore.fetchIntegrationState()
        guard repoState == .open else {
            throw ShuttleIntegrationGateError.repositoryNotOpen(repoState)
        }

        let status = try inspectStatus(worktreePath: runtimeMetadata.worktreePath)
        if !status.unstagedPaths.isEmpty {
            throw ShuttleIntegrationGateError.unstagedChanges(shardID, paths: status.unstagedPaths)
        }

        let reportPaths = Set(report.filesChanged)
        let unreportedUntracked = status.untrackedPaths.filter { !reportPaths.contains($0) }
        if !unreportedUntracked.isEmpty {
            throw ShuttleIntegrationGateError.unreportedUntrackedFiles(
                shardID,
                paths: unreportedUntracked
            )
        }

        guard branchIsMergeable(branchName: runtimeMetadata.branchName) else {
            throw ShuttleIntegrationGateError.branchNotMergeable(shardID)
        }

        return ShuttleIntegrationGateApproval(
            shard: shard,
            runtimeMetadata: runtimeMetadata,
            completionReport: report
        )
    }

    private func inspectStatus(worktreePath: String) throws -> ShuttleShardWorktreeStatus {
        let unstagedResult = try ShuttleGitShell.run(["diff", "--name-only"], workingDirectory: worktreePath)
        let untrackedResult = try ShuttleGitShell.run(
            ["ls-files", "--others", "--exclude-standard"],
            workingDirectory: worktreePath
        )

        let unstagedPaths = unstagedResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        let untrackedPaths = untrackedResult.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        return ShuttleShardWorktreeStatus(
            unstagedPaths: unstagedPaths.sorted(),
            untrackedPaths: untrackedPaths.sorted()
        )
    }

    private func branchIsMergeable(branchName: String) -> Bool {
        let bareRepositoryPath = ShuttleRepositoryBootstrapper.repositoryPath(for: config)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            _ = try ShuttleGitShell.run(
                [
                    "--git-dir",
                    bareRepositoryPath,
                    "worktree",
                    "add",
                    "--detach",
                    tempURL.path,
                    ShuttleRepositoryBootstrapper.shuttleMainBranch,
                ]
            )
        } catch {
            return false
        }

        defer {
            _ = try? ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "worktree", "remove", "--force", tempURL.path]
            )
        }

        do {
            _ = try ShuttleGitShell.run(
                ["merge", "--no-commit", "--no-ff", branchName],
                workingDirectory: tempURL.path
            )
            _ = try? ShuttleGitShell.run(["merge", "--abort"], workingDirectory: tempURL.path)
            return true
        } catch {
            _ = try? ShuttleGitShell.run(["merge", "--abort"], workingDirectory: tempURL.path)
            return false
        }
    }
}

private struct ShuttleShardWorktreeStatus: Equatable, Sendable {
    let unstagedPaths: [String]
    let untrackedPaths: [String]
}
