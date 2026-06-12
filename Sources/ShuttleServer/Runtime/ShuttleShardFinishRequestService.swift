import Foundation
import Logging

enum ShuttleShardFinishRequestServiceError: Error, Equatable, Sendable {
    case shardNotFound(String)
    case invalidShardState(String)
}

struct ShuttleShardFinishRequestService {
    let shardStore: ShuttleShardStore
    let auditEventStore: ShuttleAuditEventStore
    let logger: Logger

    init(
        shardStore: ShuttleShardStore,
        auditEventStore: ShuttleAuditEventStore,
        logger: Logger = ShuttleLogFactory.make(.shard)
    ) {
        self.shardStore = shardStore
        self.auditEventStore = auditEventStore
        self.logger = logger
    }

    func requestFinish(
        shardID: String,
        actor: ShuttleActorIdentity? = nil
    ) async throws {
        let logger = self.logger.withMetadata(ShuttleLogMetadata.shard(shardID)).withMetadata([
            ShuttleLogField.operation: .string("request_finish"),
        ]).withMetadata(ShuttleLogMetadata.actor(actor))
        guard let shard = try shardStore.fetchShard(id: shardID) else {
            throw ShuttleShardFinishRequestServiceError.shardNotFound(shardID)
        }

        guard shard.state == .running else {
            throw ShuttleShardFinishRequestServiceError.invalidShardState(shard.state.rawValue)
        }

        try auditEventStore.recordShardFinishRequestedByOperator(
            shardID: shardID,
            instruction: Self.finishInstruction
                .replacingOccurrences(of: "{shard_id}", with: shardID),
            actor: actor
        )
        logger.info("shard_finish_requested", metadata: [
            ShuttleLogField.outcome: .string("success"),
        ])
    }

    static let finishInstruction =
        "System instruction for shard {shard_id}: finish this shard if the work is complete. Run your validations, call finish_shard with a full completion report, or explain what remains."
}
