import Foundation

struct ShuttleConflictService {
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictStore: ShuttleConflictStore
    let config: ShuttleConfig
    let auditEventStore: ShuttleAuditEventStore?

    init(
        repositoryStateStore: ShuttleRepositoryStateStore,
        conflictStore: ShuttleConflictStore,
        config: ShuttleConfig,
        auditEventStore: ShuttleAuditEventStore? = nil
    ) {
        self.repositoryStateStore = repositoryStateStore
        self.conflictStore = conflictStore
        self.config = config
        self.auditEventStore = auditEventStore
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
