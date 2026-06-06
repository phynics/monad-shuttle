import Foundation

enum ShuttleShardFinishRequestServiceError: Error, Equatable, Sendable {
    case shardNotFound(String)
    case invalidShardState(String)
}

struct ShuttleShardFinishRequestService {
    let shardStore: ShuttleShardStore
    let auditEventStore: ShuttleAuditEventStore

    func requestFinish(
        shardID: String,
        actor: ShuttleActorIdentity? = nil
    ) async throws {
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
    }

    static let finishInstruction =
        "System instruction for shard {shard_id}: finish this shard if the work is complete. Run your validations, call finish_shard with a full completion report, or explain what remains."
}
