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
