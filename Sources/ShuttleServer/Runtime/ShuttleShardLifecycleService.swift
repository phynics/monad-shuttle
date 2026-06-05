import Foundation

enum ShuttleShardLifecycleServiceError: Error, Equatable, Sendable {
    case invalidCompletionReport(String)
}

struct ShuttleShardLifecycleService {
    let shardStore: ShuttleShardStore
    let completionReportStore: ShuttleCompletionReportStore
    let auditEventStore: ShuttleAuditEventStore

    func finishShard(
        shardID: String,
        report: ShuttleCompletionReport,
        actor: ShuttleActorIdentity? = nil
    ) async throws {
        try validate(report: report, expectedShardID: shardID)
        let existing = try requireShard(shardID: shardID)
        try await validateTransition(shardID: shardID, from: existing.state, to: .integrating)

        try completionReportStore.save(report)
        try shardStore.updateState(shardID: shardID, to: .integrating)
        try auditEventStore.recordShardFinishRequested(shardID: shardID, actor: actor)
    }

    func requestInput(
        shardID: String,
        question: String,
        details: String?,
        actor: ShuttleActorIdentity? = nil
    ) async throws {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Input question must not be empty")
        }

        let existing = try requireShard(shardID: shardID)
        try await validateTransition(shardID: shardID, from: existing.state, to: .needsInput)

        try shardStore.updateState(shardID: shardID, to: .needsInput)
        try auditEventStore.recordShardInputRequested(
            shardID: shardID,
            question: trimmedQuestion,
            details: details?.trimmingCharacters(in: .whitespacesAndNewlines),
            actor: actor
        )
    }

    func abandonShard(
        shardID: String,
        reason: String,
        actor: ShuttleActorIdentity? = nil
    ) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Abandon reason must not be empty")
        }

        let existing = try requireShard(shardID: shardID)
        try await validateTransition(shardID: shardID, from: existing.state, to: .abandoned)

        try shardStore.updateState(shardID: shardID, to: .abandoned)
        try auditEventStore.recordShardAbandoned(shardID: shardID, reason: trimmedReason, actor: actor)
    }

    private func requireShard(shardID: String) throws -> ShuttleStoredShard {
        guard let shard = try shardStore.fetchShard(id: shardID) else {
            throw ShuttleShardStoreError.shardNotFound(shardID)
        }
        return shard
    }

    private func validateTransition(
        shardID: String,
        from currentState: ShuttleShardState,
        to nextState: ShuttleShardState
    ) async throws {
        let stateMachine = ShuttleStateMachine(shardStates: [shardID: currentState])
        try await stateMachine.transitionShard(id: shardID, to: nextState)
    }

    private func validate(report: ShuttleCompletionReport, expectedShardID: String) throws {
        guard report.shardID == expectedShardID else {
            throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Completion report shard ID mismatch")
        }

        guard !report.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Completion report summary must not be empty")
        }

        guard !report.filesChanged.isEmpty else {
            throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Completion report must list changed files")
        }

        guard !report.validationStatuses.isEmpty else {
            throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Completion report must include validation command statuses")
        }

        for check in report.checks {
            if check.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Completion report checks must have names")
            }
            if check.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Completion report checks must have statuses")
            }
            if check.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ShuttleShardLifecycleServiceError.invalidCompletionReport("Completion report checks must have kinds")
            }
        }
    }
}
