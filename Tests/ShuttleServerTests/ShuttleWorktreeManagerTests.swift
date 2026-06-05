import Foundation
import XCTest
import GRDB
@testable import ShuttleServer

final class ShuttleWorktreeManagerTests: XCTestCase {
    func testCreateQueuedShardCreatesWorktreeAndPersistsMetadata() throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let service = try makeService(config: environment.config, databasePath: environment.databasePath)

        let branchName = ShuttleBranchNamer.makeBranchName(
            shardID: "shard-0001-abcdef12",
            title: "Add queue panel",
            spec: "Add queue panel\nwith retained shard visibility",
            existingBranchNames: []
        )
        let result = try service.createQueuedShard(
            id: "shard-0001-abcdef12",
            title: "Add queue panel",
            spec: "Add queue panel\nwith retained shard visibility",
            branchName: branchName
        )

        XCTAssertEqual(result.baseCommit, try fixture.originBranchCommit())
        XCTAssertEqual(
            result.worktreePath,
            ShuttleWorktreeManager.deterministicWorktreePath(
                rootPath: environment.config.paths.worktreesPath,
                shardID: result.id,
                branchName: branchName
            )
        )

        let headBranch = try ShuttleGitTestFixture.runGit(
            ["rev-parse", "--abbrev-ref", "HEAD"],
            in: result.worktreePath
        ).stdout
        XCTAssertEqual(headBranch, branchName)

        let shard = try XCTUnwrap(service.shardStore.fetchShard(id: result.id))
        XCTAssertEqual(shard.baseCommit, result.baseCommit)
        XCTAssertEqual(shard.state, .queued)
        XCTAssertNil(shard.retainedUntil)

        let runtimeMetadata = try XCTUnwrap(service.shardStore.fetchRuntimeMetadata(shardID: result.id))
        XCTAssertEqual(runtimeMetadata.branchName, branchName)
        XCTAssertEqual(runtimeMetadata.worktreePath, result.worktreePath)
    }

    func testCreateQueuedShardPreventsDuplicateShardCreation() throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let service = try makeService(config: environment.config, databasePath: environment.databasePath)

        let branchName = "shuttle/shards/duplicate-test-abcd1234"
        _ = try service.createQueuedShard(
            id: "shard-duplicate-abcd1234",
            title: "Duplicate test",
            spec: "Duplicate test",
            branchName: branchName
        )

        XCTAssertThrowsError(
            try service.createQueuedShard(
                id: "shard-duplicate-abcd1234",
                title: "Duplicate test",
                spec: "Duplicate test",
                branchName: branchName
            )
        ) { error in
            XCTAssertEqual(error as? ShuttleShardStoreError, .duplicateShard("shard-duplicate-abcd1234"))
        }
    }

    func testRetainDoneShardMarksWorktreeReadOnlyAndStoresRetentionDeadline() throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let service = try makeService(config: environment.config, databasePath: environment.databasePath)

        let result = try service.createQueuedShard(
            id: "shard-retain-abcdef12",
            title: "Retention test",
            spec: "Retention test",
            branchName: "shuttle/shards/retention-test-abcdef12"
        )
        let retainedUntil = Date(timeIntervalSince1970: 1_800_000_000)

        try service.retainDoneShard(shardID: result.id, retainedUntil: retainedUntil)

        let shard = try XCTUnwrap(service.shardStore.fetchShard(id: result.id))
        XCTAssertEqual(shard.state, .done)
        XCTAssertEqual(shard.retainedUntil, retainedUntil)

        let worktreeAttributes = try FileManager.default.attributesOfItem(atPath: result.worktreePath)
        let permissions = try XCTUnwrap(worktreeAttributes[FileAttributeKey.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.uint16Value & 0o222, 0)

        let readmePath = (result.worktreePath as NSString).appendingPathComponent("README.md")
        let readmeAttributes = try FileManager.default.attributesOfItem(atPath: readmePath)
        let readmePermissions = try XCTUnwrap(readmeAttributes[FileAttributeKey.posixPermissions] as? NSNumber)
        XCTAssertEqual(readmePermissions.uint16Value & 0o222, 0)
    }

    private func makeService(
        config: ShuttleConfig,
        databasePath: String
    ) throws -> ShuttleShardWorkspaceService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let bareRepositoryPath = ShuttleRepositoryBootstrapper.repositoryPath(for: config)
        let worktreeManager = ShuttleWorktreeManager(
            bareRepositoryPath: bareRepositoryPath,
            worktreesRootPath: config.paths.worktreesPath
        )

        return ShuttleShardWorkspaceService(
            shardStore: shardStore,
            worktreeManager: worktreeManager
        )
    }

    private func makeEnvironment(originURL: URL) throws -> (config: ShuttleConfig, databasePath: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseRoot = root.appendingPathComponent("database", isDirectory: true)
        let gitRoot = root.appendingPathComponent("git", isDirectory: true)
        let worktreesRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        let logsRoot = root.appendingPathComponent("logs", isDirectory: true)

        try FileManager.default.createDirectory(at: databaseRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)

        let config = ShuttleConfig(
            repository: .init(
                url: originURL.path,
                sourceBranch: "main",
                sshKeyPath: "/tmp/unused-key"
            ),
            runtime: .init(
                containerImage: "ghcr.io/example/shuttle-runner:latest",
                containerWorkdir: "/workspace",
                commandPolicy: .init(allow: [], deny: [])
            ),
            refresh: .init(schedule: "0 * * * *"),
            retention: .init(worktreeDays: 7, rawLogsDays: 14, rawLogsMaxBytes: 10_485_760),
            limits: .init(
                maxRunningShards: 4,
                maxIntegratingShards: 1,
                maxQueuedShards: 32,
                maxLogBytesPerShard: 5_242_880
            ),
            paths: .init(
                databasePath: databaseRoot.appendingPathComponent("shuttle.sqlite").path,
                gitPath: gitRoot.path,
                worktreesPath: worktreesRoot.path,
                logsPath: logsRoot.path
            ),
            pushTargets: [],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: "/tmp/instructions.md"),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        return (config, config.paths.databasePath)
    }
}
