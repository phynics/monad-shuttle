import Foundation
import XCTest
import GRDB
@testable import ShuttleServer

final class ShuttleShardContainerServiceTests: XCTestCase {
    func testCreateContainerUsesConfiguredImageAndWorktreeMountAndPersistsMetadata() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-container-create-abcdef12",
            title: "Container create",
            spec: "Container create",
            branchName: "shuttle/shards/container-create-abcdef12"
        )

        let dockerBackend = FakeDockerBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )

        let runtime = try await containerService.createContainer(forShardID: shard.id)
        let createCall = await dockerBackend.singleCreateCall()

        XCTAssertEqual(createCall.image, environment.config.runtime.containerImage)
        XCTAssertEqual(createCall.mounts, [
            .init(sourcePath: shard.worktreePath, targetPath: environment.config.runtime.containerWorkdir)
        ])
        XCTAssertEqual(runtime.containerStatus, .running)
        XCTAssertEqual(runtime.worktreePath, shard.worktreePath)

        let storedMetadata = try XCTUnwrap(containerService.shardStore.fetchRuntimeMetadata(shardID: shard.id))
        XCTAssertEqual(storedMetadata.containerName, runtime.containerName)
        XCTAssertEqual(storedMetadata.containerStatus, "running")
    }

    func testInspectContainerReturnsDockerState() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-container-inspect-abcdef12",
            title: "Container inspect",
            spec: "Container inspect",
            branchName: "shuttle/shards/container-inspect-abcdef12"
        )

        let dockerBackend = FakeDockerBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        let created = try await containerService.createContainer(forShardID: shard.id)

        let inspected = try await containerService.inspectContainer(forShardID: shard.id)

        XCTAssertEqual(inspected.name, created.containerName)
        XCTAssertEqual(inspected.status, .running)
    }

    func testStopContainerUpdatesStoredMetadata() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-container-stop-abcdef12",
            title: "Container stop",
            spec: "Container stop",
            branchName: "shuttle/shards/container-stop-abcdef12"
        )

        let dockerBackend = FakeDockerBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        let created = try await containerService.createContainer(forShardID: shard.id)

        try await containerService.stopContainer(forShardID: shard.id)

        let storedMetadata = try XCTUnwrap(containerService.shardStore.fetchRuntimeMetadata(shardID: shard.id))
        let dockerInspection = await dockerBackend.inspect(name: created.containerName)
        XCTAssertEqual(storedMetadata.containerName, created.containerName)
        XCTAssertEqual(storedMetadata.containerStatus, "stopped")
        XCTAssertEqual(dockerInspection?.status, .stopped)
    }

    func testEnsureContainerRecreatesMissingContainerUsingStoredMetadata() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-container-recreate-abcdef12",
            title: "Container recreate",
            spec: "Container recreate",
            branchName: "shuttle/shards/container-recreate-abcdef12"
        )

        let dockerBackend = FakeDockerBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        let created = try await containerService.createContainer(forShardID: shard.id)
        await dockerBackend.removeContainer(named: created.containerName)

        let recreated = try await containerService.ensureContainer(forShardID: shard.id)
        let createCallCount = await dockerBackend.createCallCount()

        XCTAssertEqual(recreated.containerName, created.containerName)
        XCTAssertEqual(createCallCount, 2)

        let storedMetadata = try XCTUnwrap(containerService.shardStore.fetchRuntimeMetadata(shardID: shard.id))
        XCTAssertEqual(storedMetadata.containerStatus, "running")
    }

    private func makeWorkspaceService(
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
        return ShuttleShardWorkspaceService(shardStore: shardStore, worktreeManager: worktreeManager)
    }

    private func makeContainerService(
        config: ShuttleConfig,
        databasePath: String,
        dockerBackend: FakeDockerBackend
    ) async throws -> ShuttleShardContainerService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let statusStore = ShuttleServerStatusStore()
        let accessController = ShuttleDockerAccessController(
            client: ShuttleDockerClient(
                probeAvailability: { .available(detail: "Docker socket accessible") },
                createContainer: { request in
                    await dockerBackend.create(request: request)
                },
                inspectContainer: { name in
                    await dockerBackend.inspect(name: name)
                },
                stopContainer: { name in
                    try await dockerBackend.stop(name: name)
                }
            ),
            statusStore: statusStore
        )
        _ = await accessController.probeHealth()

        return ShuttleShardContainerService(
            shardStore: shardStore,
            dockerAccessController: accessController,
            config: config
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

private actor FakeDockerBackend {
    struct CreateCall: Equatable {
        let request: ShuttleDockerCreateContainerRequest

        var image: String { request.image }
        var mounts: [ShuttleDockerBindMount] { request.mounts }
    }

    private var containers: [String: ShuttleDockerContainerInspection] = [:]
    private var createCalls: [CreateCall] = []

    func create(request: ShuttleDockerCreateContainerRequest) -> ShuttleDockerContainerInspection {
        let inspection = ShuttleDockerContainerInspection(
            name: request.name,
            image: request.image,
            status: .running,
            mounts: request.mounts,
            workingDirectory: request.workingDirectory
        )
        containers[request.name] = inspection
        createCalls.append(.init(request: request))
        return inspection
    }

    func inspect(name: String) -> ShuttleDockerContainerInspection? {
        containers[name]
    }

    func stop(name: String) throws {
        guard let container = containers[name] else {
            throw ShuttleDockerClientError.containerNotFound(name)
        }
        containers[name] = ShuttleDockerContainerInspection(
            name: container.name,
            image: container.image,
            status: .stopped,
            mounts: container.mounts,
            workingDirectory: container.workingDirectory
        )
    }

    func removeContainer(named name: String) {
        containers.removeValue(forKey: name)
    }

    func singleCreateCall() -> CreateCall {
        createCalls[0]
    }

    func createCallCount() -> Int {
        createCalls.count
    }
}
