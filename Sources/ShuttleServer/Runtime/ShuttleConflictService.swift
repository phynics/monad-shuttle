import Foundation

enum ShuttleConflictResolutionValidationError: Error, Equatable, Sendable {
    case repositoryNotClean(paths: [String])
    case activeMergeState
}

struct ShuttleConflictRepositoryValidator: Sendable {
    let validate: @Sendable (ShuttleConfig) throws -> Void

    static let live = ShuttleConflictRepositoryValidator { config in
        let bareRepositoryPath = ShuttleRepositoryBootstrapper.repositoryPath(for: config)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

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

        defer {
            _ = try? ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "worktree", "remove", "--force", tempURL.path]
            )
        }

        let status = try ShuttleGitShell.run(["status", "--porcelain"], workingDirectory: tempURL.path)
        let dirtyPaths = status.stdout
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard let path = parts.last else { return trimmed }
                return String(path)
            }
        if !dirtyPaths.isEmpty {
            throw ShuttleConflictResolutionValidationError.repositoryNotClean(paths: dirtyPaths)
        }

        do {
            _ = try ShuttleGitShell.run(["rev-parse", "-q", "--verify", "MERGE_HEAD"], workingDirectory: tempURL.path)
            throw ShuttleConflictResolutionValidationError.activeMergeState
        } catch let error as ShuttleGitShellError {
            if case .commandFailed = error {
                return
            }
            throw error
        }
    }
}

struct ShuttleConflictService {
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictStore: ShuttleConflictStore
    let config: ShuttleConfig
    let auditEventStore: ShuttleAuditEventStore?
    let repositoryValidator: ShuttleConflictRepositoryValidator

    init(
        repositoryStateStore: ShuttleRepositoryStateStore,
        conflictStore: ShuttleConflictStore,
        config: ShuttleConfig,
        auditEventStore: ShuttleAuditEventStore? = nil,
        repositoryValidator: ShuttleConflictRepositoryValidator = .live
    ) {
        self.repositoryStateStore = repositoryStateStore
        self.conflictStore = conflictStore
        self.config = config
        self.auditEventStore = auditEventStore
        self.repositoryValidator = repositoryValidator
    }

    func recordShardMergeConflict(
        sourceShardID: String,
        details: [String: String]
    ) throws -> ShuttleStoredConflict {
        let conflict = try conflictStore.create(
            kind: "shard_merge",
            sourceShardID: sourceShardID,
            details: details
        )
        try blockRepository(conflictID: conflict.id)
        try auditEventStore?.recordConflictCreated(
            conflictID: conflict.id,
            kind: conflict.kind,
            actor: nil
        )
        return conflict
    }

    func recordUpstreamRefreshConflict(
        details: [String: String]
    ) throws -> ShuttleStoredConflict {
        let conflict = try conflictStore.create(
            kind: "upstream_refresh",
            details: details
        )
        try blockRepository(conflictID: conflict.id)
        try auditEventStore?.recordConflictCreated(
            conflictID: conflict.id,
            kind: conflict.kind,
            actor: nil
        )
        return conflict
    }

    func resolveConflict(
        conflictID: String,
        resolutionShardID: String? = nil
    ) throws -> ShuttleStoredConflict {
        try repositoryValidator.validate(config)

        let resolved = try conflictStore.markResolved(
            conflictID: conflictID,
            resolutionShardID: resolutionShardID
        )
        try auditEventStore?.recordConflictResolved(
            conflictID: conflictID,
            resolutionShardID: resolutionShardID ?? "",
            actor: nil
        )

        let remainingOpenConflicts = try conflictStore.fetchOpenConflicts().filter(\.blocking)
        if let nextBlockingConflict = remainingOpenConflicts.first {
            try repositoryStateStore.upsert(
                config: config,
                integrationState: .blocked,
                blockedConflictID: nextBlockingConflict.id
            )
        } else {
            try repositoryStateStore.upsert(
                config: config,
                integrationState: .open,
                blockedConflictID: nil
            )
        }

        return resolved
    }

    private func blockRepository(conflictID: String) throws {
        let state = try repositoryStateStore.fetchIntegrationState()
        switch state {
        case .blocked:
            try repositoryStateStore.upsert(
                config: config,
                integrationState: .blocked,
                blockedConflictID: conflictID
            )
        case .integrating:
            try repositoryStateStore.transitionIntegrationState(
                from: .integrating,
                to: .blocked,
                config: config,
                blockedConflictID: conflictID
            )
        case .open, .refreshing:
            try repositoryStateStore.upsert(
                config: config,
                integrationState: .blocked,
                blockedConflictID: conflictID
            )
        }
    }
}
