import Foundation

enum ShuttleConcurrencyLimitError: Error, Equatable, Sendable {
    case maxQueuedShardsReached(limit: Int)
    case maxRunningShardsReached(limit: Int)
}

struct ShuttleConcurrencyLimitService {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore

    func assertCanCreateQueuedShard() throws {
        let queuedCount = try shardStore.fetchShards(states: [.queued]).count
        if queuedCount >= config.limits.maxQueuedShards {
            throw ShuttleConcurrencyLimitError.maxQueuedShardsReached(limit: config.limits.maxQueuedShards)
        }
    }

    func assertCanEnterRunningState() throws {
        let runningCount = try shardStore.fetchShards(states: [.running]).count
        if runningCount >= config.limits.maxRunningShards {
            throw ShuttleConcurrencyLimitError.maxRunningShardsReached(limit: config.limits.maxRunningShards)
        }
    }
}
