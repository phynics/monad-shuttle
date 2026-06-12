import Foundation
import Logging

enum ShuttleShardAnswerServiceError: Error, Equatable, Sendable {
    case shardNotFound(String)
    case invalidShardState(String)
    case emptyAnswer
}

struct ShuttleShardAnswerService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let auditEventStore: ShuttleAuditEventStore
    let logger: Logger

    init(
        config: ShuttleConfig,
        shardStore: ShuttleShardStore,
        auditEventStore: ShuttleAuditEventStore,
        logger: Logger = ShuttleLogFactory.make(.shard)
    ) {
        self.config = config
        self.shardStore = shardStore
        self.auditEventStore = auditEventStore
        self.logger = logger
    }

    func answer(
        shardID: String,
        answer: String,
        actor: ShuttleActorIdentity? = nil
    ) async throws {
        let logger = self.logger.withMetadata(ShuttleLogMetadata.shard(shardID)).withMetadata([
            ShuttleLogField.operation: .string("answer_shard"),
        ]).withMetadata(ShuttleLogMetadata.actor(actor))
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            throw ShuttleShardAnswerServiceError.emptyAnswer
        }
        guard let shard = try shardStore.fetchShard(id: shardID) else {
            throw ShuttleShardAnswerServiceError.shardNotFound(shardID)
        }
        guard shard.state == .needsInput else {
            throw ShuttleShardAnswerServiceError.invalidShardState(shard.state.rawValue)
        }

        let stateMachine = ShuttleStateMachine(shardStates: [shardID: shard.state])
        try await stateMachine.transitionShard(id: shardID, to: .running)
        try ShuttleConcurrencyLimitService(
            config: config,
            shardStore: shardStore
        ).assertCanEnterRunningState()

        try shardStore.updateState(shardID: shardID, to: .running)
        try auditEventStore.recordShardInputAnswered(
            shardID: shardID,
            answerSummary: trimmedAnswer,
            actor: actor
        )
        logger.info("shard_answered", metadata: [
            ShuttleLogField.outcome: .string("success"),
        ])
    }
}
