import Foundation
import Logging

struct ShuttleShardCreateResult: Codable, Equatable, Sendable {
    let shardID: String
}

enum ShuttleShardCreateServiceError: Error, Equatable, Sendable {
    case emptyTitle
    case emptySpec
    case idempotencyConflict(String)
    case invalidStoredResponse
}

struct ShuttleShardCreateService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let workspaceService: ShuttleShardWorkspaceService
    let idempotencyStore: ShuttleIdempotencyStore
    let auditEventStore: ShuttleAuditEventStore
    let logger: Logger

    init(
        config: ShuttleConfig,
        shardStore: ShuttleShardStore,
        workspaceService: ShuttleShardWorkspaceService,
        idempotencyStore: ShuttleIdempotencyStore,
        auditEventStore: ShuttleAuditEventStore,
        logger: Logger = ShuttleLogFactory.make(.shard)
    ) {
        self.config = config
        self.shardStore = shardStore
        self.workspaceService = workspaceService
        self.idempotencyStore = idempotencyStore
        self.auditEventStore = auditEventStore
        self.logger = logger
    }

    func createShard(
        title: String,
        spec: String,
        idempotencyKey: String,
        actor: ShuttleActorIdentity? = nil
    ) throws -> ShuttleShardCreateResult {
        let logger = self.logger.withMetadata([
            ShuttleLogField.operation: .string("create_shard"),
        ]).withMetadata(ShuttleLogMetadata.actor(actor))
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ShuttleShardCreateServiceError.emptyTitle
        }
        guard !trimmedSpec.isEmpty else {
            throw ShuttleShardCreateServiceError.emptySpec
        }
        let requestHash = "\(trimmedTitle)|\(trimmedSpec)"

        let provisionalShardID = UUID().uuidString.lowercased()
        var existingBranchNames: [String] = []
        for shard in try shardStore.fetchShards() {
            if let branchName = try shardStore.fetchRuntimeMetadata(shardID: shard.id)?.branchName {
                existingBranchNames.append(branchName)
            }
        }
        let branchName = ShuttleBranchNamer.makeBranchName(
            shardID: provisionalShardID,
            title: trimmedTitle,
            spec: trimmedSpec,
            existingBranchNames: existingBranchNames
        )
        let responseJSON = try encode(result: .init(shardID: provisionalShardID))

        let idemResult: ShuttleIdempotencyStoreResult
        do {
            idemResult = try idempotencyStore.recordOrReplay(
                key: idempotencyKey,
                scope: "shard_create",
                requestHash: requestHash,
                responseJSON: responseJSON,
                createdAt: Date(),
                expiresAt: nil
            )
        } catch let error as ShuttleIdempotencyStoreError {
            switch error {
            case .requestMismatch(let key, _):
                throw ShuttleShardCreateServiceError.idempotencyConflict(key)
            }
        }

        switch idemResult {
        case .replayed(let record):
            logger.info("shard_create_replayed", metadata: [
                ShuttleLogField.outcome: .string("replayed"),
            ])
            return try decode(resultJSON: record.responseJSON)
        case .recorded:
            break
        }

        try ShuttleConcurrencyLimitService(
            config: config,
            shardStore: shardStore
        ).assertCanCreateQueuedShard()

        _ = try workspaceService.createQueuedShard(
            id: provisionalShardID,
            title: trimmedTitle,
            spec: trimmedSpec,
            branchName: branchName
        )
        try auditEventStore.recordShardCreated(
            shardID: provisionalShardID,
            title: trimmedTitle,
            actor: actor
        )
        logger.info("shard_created", metadata: [
            ShuttleLogField.outcome: .string("success"),
            ShuttleLogField.shardID: .string(provisionalShardID),
            ShuttleLogField.branch: .string(branchName),
        ])
        return .init(shardID: provisionalShardID)
    }

    private func encode(result: ShuttleShardCreateResult) throws -> String {
        let data = try JSONEncoder().encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ShuttleShardCreateServiceError.invalidStoredResponse
        }
        return json
    }

    private func decode(resultJSON: String) throws -> ShuttleShardCreateResult {
        guard let data = resultJSON.data(using: .utf8) else {
            throw ShuttleShardCreateServiceError.invalidStoredResponse
        }
        return try JSONDecoder().decode(ShuttleShardCreateResult.self, from: data)
    }
}
