import Foundation

enum ShuttleShardAnswerServiceError: Error, Equatable, Sendable {
    case shardNotFound(String)
    case invalidShardState(String)
    case emptyAnswer
}

struct ShuttleShardAnswerService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let auditEventStore: ShuttleAuditEventStore

    func answer(
        shardID: String,
        answer: String,
        actor: ShuttleActorIdentity? = nil
    ) async throws {
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
    }
}
