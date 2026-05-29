import XCTest
@testable import ShuttleServer

final class ShuttleStateMachineTests: XCTestCase {
    func testValidServerTransitions() async throws {
        let machine = ShuttleStateMachine()

        try await machine.transitionServer(to: .draining)
        let drainingState = await machine.serverState
        XCTAssertEqual(drainingState, .draining)

        try await machine.transitionServer(to: .fatal)
        let fatalState = await machine.serverState
        XCTAssertEqual(fatalState, .fatal)
    }

    func testInvalidServerTransitionReturnsStructuredError() async {
        let machine = ShuttleStateMachine(initialServerState: .draining)

        do {
            try await machine.transitionServer(to: .ready)
            XCTFail("Expected transition to throw")
        } catch {
            XCTAssertEqual(
                error as? ShuttleStateTransitionError,
                .invalidTransition(
                    entity: .server,
                    from: "draining",
                    to: "ready",
                    reason: "transition_not_allowed"
                )
            )
        }
    }

    func testValidRepositoryTransitions() async throws {
        let machine = ShuttleStateMachine()

        try await machine.transitionRepository(to: .refreshing)
        try await machine.transitionRepository(to: .open)
        try await machine.transitionRepository(to: .integrating)
        try await machine.transitionRepository(to: .open)
        try await machine.transitionRepository(to: .blocked)
        try await machine.transitionRepository(to: .open)

        let repositoryState = await machine.repositoryState
        XCTAssertEqual(repositoryState, .open)
    }

    func testInvalidRepositoryTransitionReturnsStructuredError() async {
        let machine = ShuttleStateMachine(initialRepositoryState: .blocked)

        do {
            try await machine.transitionRepository(to: .integrating)
            XCTFail("Expected transition to throw")
        } catch {
            XCTAssertEqual(
                error as? ShuttleStateTransitionError,
                .invalidTransition(
                    entity: .repository,
                    from: "blocked",
                    to: "integrating",
                    reason: "transition_not_allowed"
                )
            )
        }
    }

    func testValidShardTransitions() async throws {
        let machine = ShuttleStateMachine()
        let shardID = "shard-1"

        try await machine.transitionShard(id: shardID, to: .running)
        try await machine.transitionShard(id: shardID, to: .needsInput)
        try await machine.transitionShard(id: shardID, to: .running)
        try await machine.transitionShard(id: shardID, to: .integrating)
        try await machine.transitionShard(id: shardID, to: .done)

        let shardState = await machine.shardState(id: shardID)
        XCTAssertEqual(shardState, .done)
    }

    func testBlockedRepositoryPreventsShardIntegration() async throws {
        let machine = ShuttleStateMachine(initialRepositoryState: .blocked)
        let shardID = "shard-2"

        try await machine.transitionShard(id: shardID, to: .running)

        do {
            try await machine.transitionShard(id: shardID, to: .integrating)
            XCTFail("Expected transition to throw")
        } catch {
            XCTAssertEqual(
                error as? ShuttleStateTransitionError,
                .invalidTransition(
                    entity: .shard(shardID),
                    from: "running",
                    to: "integrating",
                    reason: "repository_blocked"
                )
            )
        }
    }
}
