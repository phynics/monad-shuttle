import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleShardFinishRequestServiceTests: XCTestCase {
    func testRequestFinishOnRunningShardAppendsInstructionWithoutChangingState() async throws {
        let fixture = try await makeFixture(initialState: .running)

        try await fixture.service.requestFinish(shardID: fixture.shardID)

        let shard = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.shardID))
        XCTAssertEqual(shard.state, .running)

        let instructions = try fixture.auditStore.fetchPendingSystemInstructions(shardID: fixture.shardID)
        XCTAssertEqual(instructions.count, 1)
        XCTAssertTrue(instructions[0].contains("finish this shard"))

        await fixture.llm.enqueueTextResponse("Acknowledged.")
        _ = try await fixture.runner.runShard(shardID: fixture.shardID)

        let lastRequest = await fixture.llm.lastRequest()
        let request = try XCTUnwrap(lastRequest)
        let systemMessage = try XCTUnwrap(request.messages.first(where: { $0.role == .system }))
        XCTAssertTrue(systemMessage.content.contains("finish this shard"))
    }

    func testRequestFinishRejectsNonRunningShard() async throws {
        let fixture = try await makeFixture(initialState: .needsInput)

        do {
            try await fixture.service.requestFinish(shardID: fixture.shardID)
            XCTFail("Expected requestFinish to reject non-running shard")
        } catch {
            XCTAssertEqual(error as? ShuttleShardFinishRequestServiceError, .invalidShardState("needs_input"))
        }

        let instructions = try fixture.auditStore.fetchPendingSystemInstructions(shardID: fixture.shardID)
        XCTAssertTrue(instructions.isEmpty)
    }

    func testRequestFinishRejectsAlreadyFinishedShard() async throws {
        let fixture = try await makeFixture(initialState: .done)

        do {
            try await fixture.service.requestFinish(shardID: fixture.shardID)
            XCTFail("Expected requestFinish to reject finished shard")
        } catch {
            XCTAssertEqual(error as? ShuttleShardFinishRequestServiceError, .invalidShardState("done"))
        }

        let instructions = try fixture.auditStore.fetchPendingSystemInstructions(shardID: fixture.shardID)
        XCTAssertTrue(instructions.isEmpty)
    }

    private func makeFixture(initialState: ShuttleShardState) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseRoot = root.appendingPathComponent("database", isDirectory: true)
        let gitRoot = root.appendingPathComponent("git", isDirectory: true)
        let worktreesRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        let logsRoot = root.appendingPathComponent("logs", isDirectory: true)
        let configRoot = root.appendingPathComponent("config", isDirectory: true)

        try FileManager.default.createDirectory(at: databaseRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configRoot, withIntermediateDirectories: true)

        let gitFixture = try ShuttleGitTestFixture.create()
        let instructionsPath = configRoot.appendingPathComponent("shuttle-instructions.md").path
        try "Default Shuttle instructions.".write(
            to: URL(fileURLWithPath: instructionsPath),
            atomically: true,
            encoding: .utf8
        )

        let config = ShuttleConfig(
            repository: .init(url: gitFixture.originBareRepository.path, sourceBranch: gitFixture.branch, sshKeyPath: "/tmp/unused-key"),
            runtime: .init(
                containerImage: "ghcr.io/example/shuttle-runner:latest",
                containerWorkdir: "/workspace",
                commandPolicy: .init(allow: ["swift", "git"], deny: ["rm"])
            ),
            refresh: .init(schedule: "0 * * * *"),
            retention: .init(worktreeDays: 7, rawLogsDays: 7, rawLogsMaxBytes: 2_048),
            limits: .init(maxRunningShards: 4, maxIntegratingShards: 1, maxQueuedShards: 32, maxLogBytesPerShard: 2_048),
            paths: .init(
                databasePath: databaseRoot.appendingPathComponent("shuttle.sqlite").path,
                gitPath: gitRoot.path,
                worktreesPath: worktreesRoot.path,
                logsPath: logsRoot.path
            ),
            pushTargets: [],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: instructionsPath),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        let dbQueue = try ShuttleDatabase.openMigrated(atPath: config.paths.databasePath)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let workspaceService = ShuttleShardWorkspaceService(
            shardStore: shardStore,
            worktreeManager: ShuttleWorktreeManager(
                bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
                worktreesRootPath: config.paths.worktreesPath
            )
        )
        let shard = try workspaceService.createQueuedShard(
            id: "shard-request-finish-abcdef12",
            title: "Finish request shard",
            spec: "Implement the request-finish flow.",
            branchName: "shuttle/shards/request-finish-abcdef12"
        )
        if initialState != .queued {
            try shardStore.updateState(shardID: shard.id, to: initialState)
        }

        let dockerBackend = ShuttleTestDockerExecBackend()
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

        let commandService = ShuttleShardCommandExecutionService(
            shardStore: shardStore,
            dockerAccessController: accessController,
            commandLogStore: ShuttleCommandLogStore(
                dbQueue: dbQueue,
                logsRootPath: config.paths.logsPath,
                retentionDays: config.retention.rawLogsDays,
                maxBytesPerFile: config.limits.maxLogBytesPerShard
            ),
            config: config
        )
        let containerService = ShuttleShardContainerService(
            shardStore: shardStore,
            dockerAccessController: accessController,
            config: config
        )
        _ = try await containerService.createContainer(forShardID: shard.id)

        let completionReportStore = ShuttleCompletionReportStore(dbQueue: dbQueue)
        let auditStore = ShuttleAuditEventStore(dbQueue: dbQueue)
        let lifecycleService = ShuttleShardLifecycleService(
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            auditEventStore: auditStore
        )
        let transcriptStore = ShuttleAgentTranscriptStore(
            dbQueue: dbQueue,
            logsRootPath: config.paths.logsPath,
            retentionDays: config.retention.rawLogsDays,
            maxBytesPerFile: config.limits.maxLogBytesPerShard
        )
        let llm = ShuttleTestLLMService()
        let runner = ShuttleShardAgentRunner(
            config: config,
            shardStore: shardStore,
            commandService: commandService,
            lifecycleService: lifecycleService,
            transcriptStore: transcriptStore,
            llmService: llm,
            auditEventStore: auditStore
        )

        return Fixture(
            shardID: shard.id,
            shardStore: shardStore,
            auditStore: auditStore,
            llm: llm,
            runner: runner,
            service: ShuttleShardFinishRequestService(
                shardStore: shardStore,
                auditEventStore: auditStore
            )
        )
    }
}

private struct Fixture {
    let shardID: String
    let shardStore: ShuttleShardStore
    let auditStore: ShuttleAuditEventStore
    let llm: ShuttleTestLLMService
    let runner: ShuttleShardAgentRunner
    let service: ShuttleShardFinishRequestService
}
