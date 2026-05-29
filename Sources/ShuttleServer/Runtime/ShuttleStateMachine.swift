import Foundation

public enum ShuttleRepositoryState: String, Codable, Equatable, Sendable {
    case open
    case refreshing
    case integrating
    case blocked
}

public enum ShuttleShardState: String, Codable, Equatable, Sendable {
    case queued
    case running
    case needsInput = "needs_input"
    case integrating
    case done
    case failed
    case abandoned
}

public enum ShuttleStateMachineEntity: Equatable, Sendable {
    case server
    case repository
    case shard(String)
}

public enum ShuttleStateTransitionError: Error, Equatable, Sendable {
    case invalidTransition(entity: ShuttleStateMachineEntity, from: String, to: String, reason: String)
}

public actor ShuttleStateMachine {
    public private(set) var serverState: ShuttleServerState
    public private(set) var repositoryState: ShuttleRepositoryState
    private var shardStates: [String: ShuttleShardState]

    public init(
        initialServerState: ShuttleServerState = .ready,
        initialRepositoryState: ShuttleRepositoryState = .open,
        shardStates: [String: ShuttleShardState] = [:]
    ) {
        self.serverState = initialServerState
        self.repositoryState = initialRepositoryState
        self.shardStates = shardStates
    }

    public func shardState(id: String) -> ShuttleShardState {
        shardStates[id] ?? .queued
    }

    public func transitionServer(to next: ShuttleServerState) throws {
        let allowed: [ShuttleServerState: Set<ShuttleServerState>] = [
            .ready: [.draining, .fatal],
            .draining: [.fatal],
            .fatal: [],
        ]

        guard allowed[serverState, default: []].contains(next) else {
            throw ShuttleStateTransitionError.invalidTransition(
                entity: .server,
                from: serverState.rawValue,
                to: next.rawValue,
                reason: "transition_not_allowed"
            )
        }

        serverState = next
    }

    public func transitionRepository(to next: ShuttleRepositoryState) throws {
        let allowed: [ShuttleRepositoryState: Set<ShuttleRepositoryState>] = [
            .open: [.refreshing, .integrating, .blocked],
            .refreshing: [.open, .blocked],
            .integrating: [.open, .blocked],
            .blocked: [.open],
        ]

        guard allowed[repositoryState, default: []].contains(next) else {
            throw ShuttleStateTransitionError.invalidTransition(
                entity: .repository,
                from: repositoryState.rawValue,
                to: next.rawValue,
                reason: "transition_not_allowed"
            )
        }

        repositoryState = next
    }

    public func transitionShard(id: String, to next: ShuttleShardState) throws {
        let current = shardStates[id] ?? .queued

        if next == .integrating, repositoryState == .blocked {
            throw ShuttleStateTransitionError.invalidTransition(
                entity: .shard(id),
                from: current.rawValue,
                to: next.rawValue,
                reason: "repository_blocked"
            )
        }

        let allowed: [ShuttleShardState: Set<ShuttleShardState>] = [
            .queued: [.running, .failed, .abandoned],
            .running: [.needsInput, .integrating, .failed, .abandoned],
            .needsInput: [.running, .failed, .abandoned],
            .integrating: [.done, .failed],
            .done: [],
            .failed: [],
            .abandoned: [],
        ]

        guard allowed[current, default: []].contains(next) else {
            throw ShuttleStateTransitionError.invalidTransition(
                entity: .shard(id),
                from: current.rawValue,
                to: next.rawValue,
                reason: "transition_not_allowed"
            )
        }

        shardStates[id] = next
    }
}
