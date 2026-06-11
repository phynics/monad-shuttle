import Foundation
import GRDB
import PositronicKit
import PKShared
import XCTest
@testable import ShuttleServer

final class ShuttleShardAgentRunnerTests: XCTestCase {
    func testRunShardBuildsPromptFromDeploymentInstructionsRepoGuidanceAndShardSpec() async throws {
        let fixture = try await makeFixture()
        try """
        Follow Shuttle deployment policy.
        """.write(to: URL(fileURLWithPath: fixture.config.instructions.filePath), atomically: true, encoding: .utf8)
        try """
        Repo guidance from AGENTS.md.
        """.write(to: fixture.worktreeURL.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

        await fixture.llm.enqueueTextResponse("Work complete.")

        _ = try await fixture.runner.runShard(shardID: fixture.shardID)

        let lastRequest = await fixture.llm.lastRequest()
        let recorded = try XCTUnwrap(lastRequest)
        let systemMessage = try XCTUnwrap(recorded.messages.first(where: { $0.role == .system }))
        let userMessage = try XCTUnwrap(recorded.messages.last(where: { $0.role == .user }))

        XCTAssertTrue(systemMessage.content.contains("Follow Shuttle deployment policy."))
        XCTAssertTrue(systemMessage.content.contains("Repo guidance from AGENTS.md."))
        XCTAssertTrue(userMessage.content.contains("Implement the shard agent runner"))

        let expectedToolIDs = Set(
            ShuttleShardWorkspaceToolFactory.makeAllTools(
                shardID: fixture.shardID,
                worktreePath: fixture.worktreeURL.path,
                commandService: fixture.commandService,
                lifecycleService: fixture.lifecycleService
            ).map(\.id)
        )
        XCTAssertEqual(Set(recorded.toolIDs), expectedToolIDs)
    }

    func testRunShardWritesTranscriptEventsToRawLogsAndIndexes() async throws {
        let fixture = try await makeFixture()
        await fixture.llm.enqueueTextResponse("Transcript me.")

        let result = try await fixture.runner.runShard(shardID: fixture.shardID)
        XCTAssertFalse(result.events.isEmpty)

        let transcriptEntries = try fixture.transcriptStore.fetchEntries(shardID: fixture.shardID)
        XCTAssertFalse(transcriptEntries.isEmpty)
        XCTAssertTrue(transcriptEntries.contains(where: {
            if case .delta(event: .generation(text: "Transcript me.")) = $0.event {
                return true
            }
            return false
        }))

        let logIndexCount = try await fixture.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM log_indexes WHERE shard_id = ? AND stream = 'agent'",
                arguments: [fixture.shardID]
            ) ?? 0
        }
        XCTAssertGreaterThan(logIndexCount, 0)
    }

    func testRunShardCanFinishShardThroughLifecycleTool() async throws {
        let fixture = try await makeFixture()
        await fixture.llm.enqueueToolCallTurn(calls: [
            .init(
                id: "finish-1",
                name: "finish_shard",
                arguments: #"{"summary":"Implemented shard agent runner","files_changed":["Sources/ShuttleServer/Agents/ShuttleShardAgentRunner.swift"],"checks":[{"name":"swift test","status":"passed","kind":"validation_command"}],"risks":[]}"#
            ),
        ])
        await fixture.llm.enqueueTextResponse("Shard finished.")

        _ = try await fixture.runner.runShard(shardID: fixture.shardID)

        let shard = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.shardID))
        XCTAssertEqual(shard.state, .integrating)

        let report = try XCTUnwrap(fixture.completionReportStore.fetch(shardID: fixture.shardID))
        XCTAssertEqual(report.summary, "Implemented shard agent runner")
    }

    func testRunShardCanRequestInputThroughLifecycleTool() async throws {
        let fixture = try await makeFixture()
        await fixture.llm.enqueueToolCallTurn(calls: [
            .init(
                id: "input-1",
                name: "request_input",
                arguments: #"{"question":"Which remote branch should Shuttle push?","details":"The shard is complete but the target branch is unspecified."}"#
            ),
        ])
        await fixture.llm.enqueueTextResponse("Awaiting input.")

        _ = try await fixture.runner.runShard(shardID: fixture.shardID)

        let shard = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.shardID))
        XCTAssertEqual(shard.state, .needsInput)
    }

    func testRunShardRejectsQueuedShardWhenRunningLimitReached() async throws {
        let fixture = try await makeFixture(maxRunningShards: 1)
        try fixture.shardStore.createQueuedShard(
            id: "shard-already-running",
            title: "Running shard",
            spec: "Running shard",
            baseCommit: "abc123",
            branchName: "shuttle/shards/already-running",
            worktreePath: fixture.worktreeURL.deletingLastPathComponent().appendingPathComponent("already-running").path
        )
        try fixture.shardStore.updateState(shardID: "shard-already-running", to: .running)

        do {
            _ = try await fixture.runner.runShard(shardID: fixture.shardID)
            XCTFail("Expected running shard limit error")
        } catch {
            XCTAssertEqual(error as? ShuttleConcurrencyLimitError, .maxRunningShardsReached(limit: 1))
        }
    }

    private func makeFixture(maxRunningShards: Int = 4) async throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("agent-runner", isDirectory: true)
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

        let instructionsPath = configRoot.appendingPathComponent("shuttle-instructions.md").path
        let config = ShuttleConfig(
            repository: .init(url: gitFixture.originBareRepository.path, sourceBranch: gitFixture.branch, sshKeyPath: "/tmp/unused-key"),
            runtime: .init(
                containerImage: "ghcr.io/example/shuttle-runner:latest",
                containerWorkdir: "/workspace",
                commandPolicy: .init(allow: ["swift", "git"], deny: ["rm"])
            ),
            refresh: .init(schedule: "0 * * * *"),
            retention: .init(worktreeDays: 7, rawLogsDays: 7, rawLogsMaxBytes: 2_048),
            limits: .init(maxRunningShards: maxRunningShards, maxIntegratingShards: 1, maxQueuedShards: 32, maxLogBytesPerShard: 2_048),
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
        try "Default Shuttle instructions.".write(
            to: URL(fileURLWithPath: instructionsPath),
            atomically: true,
            encoding: .utf8
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
            id: "shard-agent-runner-abcdef12",
            title: "Agent runner",
            spec: "Implement the shard agent runner and report completion.",
            branchName: "shuttle/shards/agent-runner-abcdef12"
        )

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
            llmService: llm
        )

        return Fixture(
            dbQueue: dbQueue,
            config: config,
            shardID: shard.id,
            worktreeURL: URL(fileURLWithPath: shard.worktreePath, isDirectory: true),
            shardStore: shardStore,
            commandService: commandService,
            lifecycleService: lifecycleService,
            completionReportStore: completionReportStore,
            transcriptStore: transcriptStore,
            llm: llm,
            runner: runner
        )
    }
}

private struct Fixture {
    let dbQueue: DatabaseQueue
    let config: ShuttleConfig
    let shardID: String
    let worktreeURL: URL
    let shardStore: ShuttleShardStore
    let commandService: ShuttleShardCommandExecutionService
    let lifecycleService: ShuttleShardLifecycleService
    let completionReportStore: ShuttleCompletionReportStore
    let transcriptStore: ShuttleAgentTranscriptStore
    let llm: ShuttleTestLLMService
    let runner: ShuttleShardAgentRunner
}
