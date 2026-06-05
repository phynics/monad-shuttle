import Foundation
import XCTest
import GRDB
@testable import ShuttleServer

final class ShuttleShardCommandExecutionServiceTests: XCTestCase {
    func testRunGeneralCommandUsesDockerExecWithConfiguredWorkdirAndLogsResult() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(
            originURL: fixture.originBareRepository,
            commandPolicy: .init(allow: ["swift"], deny: ["rm"])
        )
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-exec-general-abcdef12",
            title: "General command",
            spec: "General command",
            branchName: "shuttle/shards/general-command-abcdef12"
        )

        let dockerBackend = FakeDockerExecBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        _ = try await containerService.createContainer(forShardID: shard.id)

        let commandService = try makeCommandService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )

        let result = try await commandService.runGeneralCommand(
            shardID: shard.id,
            command: ["swift", "test"]
        )

        let execRequest = await dockerBackend.singleExecCall()
        XCTAssertEqual(execRequest.command, ["swift", "test"])
        XCTAssertEqual(execRequest.workingDirectory, environment.config.runtime.containerWorkdir)
        XCTAssertEqual(result.stdout, "ok")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertLessThanOrEqual(result.startedAt, result.endedAt)

        let logEntries = try commandService.commandLogStore.fetchEntries(shardID: shard.id)
        XCTAssertEqual(logEntries.count, 1)
        XCTAssertEqual(logEntries[0].exitCode, 0)
        XCTAssertEqual(logEntries[0].stdout, "ok")
    }

    func testRunGeneralCommandRejectsDeniedOrUnapprovedCommand() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(
            originURL: fixture.originBareRepository,
            commandPolicy: .init(allow: ["swift"], deny: ["rm"])
        )
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-exec-policy-abcdef12",
            title: "Policy command",
            spec: "Policy command",
            branchName: "shuttle/shards/policy-command-abcdef12"
        )

        let dockerBackend = FakeDockerExecBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        _ = try await containerService.createContainer(forShardID: shard.id)

        let commandService = try makeCommandService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )

        do {
            _ = try await commandService.runGeneralCommand(
                shardID: shard.id,
                command: ["git", "status"]
            )
            XCTFail("Expected denied command error")
        } catch let error as ShuttleCommandPolicyError {
            XCTAssertEqual(error, .commandNotAllowed("git"))
        }

        let execCallCount = await dockerBackend.execCallCount()
        XCTAssertEqual(execCallCount, 0)
    }

    func testRunNamedCommandBypassesAllowListButStillUsesDockerExec() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(
            originURL: fixture.originBareRepository,
            commandPolicy: .init(allow: ["swift"], deny: ["rm"])
        )
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-exec-named-abcdef12",
            title: "Named command",
            spec: "Named command",
            branchName: "shuttle/shards/named-command-abcdef12"
        )

        let dockerBackend = FakeDockerExecBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        _ = try await containerService.createContainer(forShardID: shard.id)

        let commandService = try makeCommandService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )

        let result = try await commandService.runNamedCommand(
            shardID: shard.id,
            toolName: "git_status",
            command: ["git", "status", "--short"]
        )

        let execCallCount = await dockerBackend.execCallCount()
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(execCallCount, 1)
    }

    private func makeWorkspaceService(
        config: ShuttleConfig,
        databasePath: String
    ) throws -> ShuttleShardWorkspaceService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        return ShuttleShardWorkspaceService(
            shardStore: ShuttleShardStore(dbQueue: dbQueue),
            worktreeManager: ShuttleWorktreeManager(
                bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
                worktreesRootPath: config.paths.worktreesPath
            )
        )
    }

    private func makeContainerService(
        config: ShuttleConfig,
        databasePath: String,
        dockerBackend: FakeDockerExecBackend
    ) async throws -> ShuttleShardContainerService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let statusStore = ShuttleServerStatusStore()
        let accessController = ShuttleDockerAccessController(
            client: ShuttleDockerClient(
                probeAvailability: { .available(detail: "Docker socket accessible") },
                createContainer: { request in await dockerBackend.create(request: request) },
                inspectContainer: { name in await dockerBackend.inspectContainer(name: name) },
                stopContainer: { name in try await dockerBackend.stopContainer(name: name) },
                execInContainer: { request in try await dockerBackend.exec(request: request) }
            ),
            statusStore: statusStore
        )
        _ = await accessController.probeHealth()
        return ShuttleShardContainerService(
            shardStore: ShuttleShardStore(dbQueue: dbQueue),
            dockerAccessController: accessController,
            config: config
        )
    }

    private func makeCommandService(
        config: ShuttleConfig,
        databasePath: String,
        dockerBackend: FakeDockerExecBackend
    ) throws -> ShuttleShardCommandExecutionService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let statusStore = ShuttleServerStatusStore()
        let accessController = ShuttleDockerAccessController(
            client: ShuttleDockerClient(
                probeAvailability: { .available(detail: "Docker socket accessible") },
                createContainer: { request in await dockerBackend.create(request: request) },
                inspectContainer: { name in await dockerBackend.inspectContainer(name: name) },
                stopContainer: { name in try await dockerBackend.stopContainer(name: name) },
                execInContainer: { request in try await dockerBackend.exec(request: request) }
            ),
            statusStore: statusStore
        )
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let commandLogStore = ShuttleCommandLogStore(dbQueue: dbQueue, logsRootPath: config.paths.logsPath)
        return ShuttleShardCommandExecutionService(
            shardStore: shardStore,
            dockerAccessController: accessController,
            commandLogStore: commandLogStore,
            config: config
        )
    }

    private func makeEnvironment(
        originURL: URL,
        commandPolicy: ShuttleConfig.Runtime.CommandPolicy
    ) throws -> (config: ShuttleConfig, databasePath: String) {
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
            repository: .init(url: originURL.path, sourceBranch: "main", sshKeyPath: "/tmp/unused-key"),
            runtime: .init(
                containerImage: "ghcr.io/example/shuttle-runner:latest",
                containerWorkdir: "/workspace",
                commandPolicy: commandPolicy
            ),
            refresh: .init(schedule: "0 * * * *"),
            retention: .init(worktreeDays: 7, rawLogsDays: 14, rawLogsMaxBytes: 10_485_760),
            limits: .init(maxRunningShards: 4, maxIntegratingShards: 1, maxQueuedShards: 32, maxLogBytesPerShard: 5_242_880),
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

private actor FakeDockerExecBackend {
    private var containers: [String: ShuttleDockerContainerInspection] = [:]
    private var execCalls: [ShuttleDockerExecRequest] = []

    func create(request: ShuttleDockerCreateContainerRequest) -> ShuttleDockerContainerInspection {
        let inspection = ShuttleDockerContainerInspection(
            name: request.name,
            image: request.image,
            status: .running,
            mounts: request.mounts,
            workingDirectory: request.workingDirectory
        )
        containers[request.name] = inspection
        return inspection
    }

    func inspectContainer(name: String) -> ShuttleDockerContainerInspection? {
        containers[name]
    }

    func stopContainer(name: String) throws {
        guard let existing = containers[name] else {
            throw ShuttleDockerClientError.containerNotFound(name)
        }
        containers[name] = ShuttleDockerContainerInspection(
            name: existing.name,
            image: existing.image,
            status: .stopped,
            mounts: existing.mounts,
            workingDirectory: existing.workingDirectory
        )
    }

    func exec(request: ShuttleDockerExecRequest) throws -> ShuttleDockerExecResult {
        guard containers[request.containerName] != nil else {
            throw ShuttleDockerClientError.containerNotFound(request.containerName)
        }
        execCalls.append(request)
        return ShuttleDockerExecResult(
            stdout: "ok",
            stderr: "",
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
    }

    func singleExecCall() -> ShuttleDockerExecRequest {
        execCalls[0]
    }

    func execCallCount() -> Int {
        execCalls.count
    }
}
