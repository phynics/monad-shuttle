import Foundation
import Hummingbird

struct ShuttleCreateShardRequest: Decodable, Sendable {
    let title: String
    let spec: String
}

struct ShuttleAnswerShardRequest: Decodable, Sendable {
    let answer: String
}

struct ShuttleAbandonShardRequest: Decodable, Sendable {
    let reason: String
}

struct ShuttleShardSummaryResponse: ResponseCodable, Equatable, Sendable {
    let id: String
    let title: String
    let state: String
    let branchName: String?
    let containerStatus: String?
    let retainedUntil: Date?
    let createdAt: Date
    let updatedAt: Date

    init(detail: ShuttleStoredShardDetail) {
        self.id = detail.shard.id
        self.title = detail.shard.title
        self.state = detail.shard.state.rawValue
        self.branchName = detail.runtimeMetadata?.branchName
        self.containerStatus = detail.runtimeMetadata?.containerStatus
        self.retainedUntil = detail.shard.retainedUntil
        self.createdAt = detail.shard.createdAt
        self.updatedAt = detail.shard.updatedAt
    }
}

struct ShuttleShardDetailResponse: ResponseCodable, Equatable, Sendable {
    let id: String
    let title: String
    let spec: String
    let state: String
    let baseCommit: String
    let branchName: String?
    let worktreePath: String?
    let containerName: String?
    let containerStatus: String?
    let retainedUntil: Date?
    let createdAt: Date
    let updatedAt: Date

    init(detail: ShuttleStoredShardDetail) {
        self.id = detail.shard.id
        self.title = detail.shard.title
        self.spec = detail.shard.spec
        self.state = detail.shard.state.rawValue
        self.baseCommit = detail.shard.baseCommit
        self.branchName = detail.runtimeMetadata?.branchName
        self.worktreePath = detail.runtimeMetadata?.worktreePath
        self.containerName = detail.runtimeMetadata?.containerName
        self.containerStatus = detail.runtimeMetadata?.containerStatus
        self.retainedUntil = detail.shard.retainedUntil
        self.createdAt = detail.shard.createdAt
        self.updatedAt = detail.shard.updatedAt
    }
}

struct ShuttleCreateShardResponse: ResponseCodable, Equatable, Sendable {
    let shardID: String
}

struct ShuttleShardActionResponse: ResponseCodable, Equatable, Sendable {
    let shardID: String
    let state: String
}

struct ShuttleAuditEventResponse: ResponseCodable, Equatable, Sendable {
    let id: Int64
    let timestamp: Date
    let actorType: String?
    let actorID: String?
    let entityType: String
    let entityID: String
    let eventType: String
    let payload: [String: String]

    init(event: ShuttleAuditEvent) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.actorType = event.actorType
        self.actorID = event.actorID
        self.entityType = event.entityType
        self.entityID = event.entityID
        self.eventType = event.eventType
        self.payload = event.payload
    }
}

struct ShuttleCommandLogChunkResponse: ResponseCodable, Equatable, Sendable {
    let id: Int64
    let shardID: String
    let stream: String
    let filePath: String
    let offsetStart: Int64
    let offsetEnd: Int64
    let createdAt: Date
    let command: [String]
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let startedAt: Date
    let endedAt: Date
    let toolName: String?

    init(entry: ShuttleCommandLogIndexEntry) {
        self.id = entry.id
        self.shardID = entry.shardID
        self.stream = entry.stream
        self.filePath = entry.filePath
        self.offsetStart = entry.offsetStart
        self.offsetEnd = entry.offsetEnd
        self.createdAt = entry.createdAt
        self.command = entry.entry.command
        self.stdout = entry.entry.stdout
        self.stderr = entry.entry.stderr
        self.exitCode = entry.entry.exitCode
        self.startedAt = entry.entry.startedAt
        self.endedAt = entry.entry.endedAt
        self.toolName = entry.entry.toolName
    }
}

struct ShuttleAuditEventPageResponse: ResponseCodable, Equatable, Sendable {
    let items: [ShuttleAuditEventResponse]
    let nextCursor: Int64?
}

struct ShuttleCommandLogPageResponse: ResponseCodable, Equatable, Sendable {
    let items: [ShuttleCommandLogChunkResponse]
    let nextCursor: Int64?
}

struct ShuttleResolveConflictRequest: Decodable, Sendable {
    let resolutionShardID: String?
}

struct ShuttlePushRequest: Decodable, Sendable {
    let targetName: String
    let ref: ShuttlePushRefRequest
}

struct ShuttlePushRefRequest: Decodable, Sendable {
    let kind: String
    let shardID: String?
}

struct ShuttleConflictResponse: ResponseCodable, Equatable, Sendable {
    let id: String
    let kind: String
    let state: String
    let blocking: Bool
    let sourceShardID: String?
    let resolutionShardID: String?
    let details: [String: String]
    let createdAt: Date
    let updatedAt: Date

    init(conflict: ShuttleStoredConflict) {
        self.id = conflict.id
        self.kind = conflict.kind
        self.state = conflict.state
        self.blocking = conflict.blocking
        self.sourceShardID = conflict.sourceShardID
        self.resolutionShardID = conflict.resolutionShardID
        self.details = conflict.details
        self.createdAt = conflict.createdAt
        self.updatedAt = conflict.updatedAt
    }
}

struct ShuttleUpstreamRefreshResponse: ResponseCodable, Equatable, Sendable {
    let outcome: String
    let upstreamCommit: String
    let shuttleMainCommit: String?
    let conflictID: String?

    init(result: ShuttleUpstreamRefreshResult) {
        self.outcome = result.outcome.rawValue
        self.upstreamCommit = result.upstreamCommit
        self.shuttleMainCommit = result.shuttleMainCommit
        self.conflictID = result.conflictID
    }
}

struct ShuttlePushResponse: ResponseCodable, Equatable, Sendable {
    let pushID: String
    let targetName: String
    let localRef: String
    let remoteRef: String
    let warnings: [String]
    let result: String

    init(result: ShuttlePushResult) {
        self.pushID = result.pushID
        self.targetName = result.targetName
        self.localRef = result.localRef
        self.remoteRef = result.remoteRef
        self.warnings = result.warnings
        self.result = result.result
    }
}
