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
