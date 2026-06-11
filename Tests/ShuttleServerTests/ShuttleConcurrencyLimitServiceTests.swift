import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttleConcurrencyLimitServiceTests: XCTestCase {
    func testRejectsQueuedShardCreationWhenAtLimit() throws {
        let fixture = try makeFixture(maxQueuedShards: 1, maxRunningShards: 2)
        try fixture.shardStore.createQueuedShard(
            id: "queued-1",
            title: "Queued 1",
            spec: "Queued 1",
            baseCommit: "abc123",
            branchName: "shuttle/shards/queued-1",
            worktreePath: fixture.root.appendingPathComponent("queued-1").path
        )

        XCTAssertThrowsError(try fixture.limitService.assertCanCreateQueuedShard()) { error in
            XCTAssertEqual(error as? ShuttleConcurrencyLimitError, .maxQueuedShardsReached(limit: 1))
        }
    }

    func testRejectsEnteringRunningStateWhenAtLimit() throws {
        let fixture = try makeFixture(maxQueuedShards: 2, maxRunningShards: 1)
        try fixture.shardStore.createQueuedShard(
            id: "running-1",
            title: "Running 1",
            spec: "Running 1",
            baseCommit: "abc123",
            branchName: "shuttle/shards/running-1",
            worktreePath: fixture.root.appendingPathComponent("running-1").path
        )
        try fixture.shardStore.updateState(shardID: "running-1", to: .running)

        XCTAssertThrowsError(try fixture.limitService.assertCanEnterRunningState()) { error in
            XCTAssertEqual(error as? ShuttleConcurrencyLimitError, .maxRunningShardsReached(limit: 1))
        }
    }

    private func makeFixture(
        maxQueuedShards: Int,
        maxRunningShards: Int
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databasePath = root.appendingPathComponent("shuttle.sqlite").path
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let config = ShuttleConfig(
            repository: .init(url: "test", sourceBranch: "main", sshKeyPath: "/tmp/key"),
            runtime: .init(
                containerImage: "test-image",
                containerWorkdir: "/workspace",
                commandPolicy: .init(allow: ["git"], deny: [])
            ),
            refresh: .init(schedule: "0 * * * *"),
            retention: .init(worktreeDays: 7, rawLogsDays: 7, rawLogsMaxBytes: 1_024),
            limits: .init(
                maxRunningShards: maxRunningShards,
                maxIntegratingShards: 1,
                maxQueuedShards: maxQueuedShards,
                maxLogBytesPerShard: 1_024
            ),
            paths: .init(
                databasePath: databasePath,
                gitPath: root.appendingPathComponent("git").path,
                worktreesPath: root.appendingPathComponent("worktrees").path,
                logsPath: root.appendingPathComponent("logs").path
            ),
            pushTargets: [],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: "/tmp/instructions.md"),
            server: .init(host: "127.0.0.1", port: 8080)
        )
        return Fixture(
            root: root,
            shardStore: shardStore,
            limitService: ShuttleConcurrencyLimitService(config: config, shardStore: shardStore)
        )
    }
}

private struct Fixture {
    let root: URL
    let shardStore: ShuttleShardStore
    let limitService: ShuttleConcurrencyLimitService
}
