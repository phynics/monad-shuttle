import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttleEndToEndFixtureScenarioTests: XCTestCase {
    func testLocalFixtureScenarioRunsShardIntegratesAndPushes() async throws {
        let fixture = try await Fixture.make(name: "e2e-happy")
        let shardID = try await fixture.createShard(
            title: "Update README",
            spec: "Update the README for Shuttle and finish with a completion report.",
            idempotencyKey: "e2e-happy-create"
        )

        await fixture.llm.enqueueToolCallTurn(calls: [
            .init(
                id: "write-1",
                name: "write_file",
                arguments: "{\"path\":\"README.md\",\"content\":\"# Fixture\\n\\nUpdated by shard.\\n\"}"
            ),
            .init(
                id: "status-1",
                name: "git_status",
                arguments: #"{}"#
            ),
        ])
        await fixture.llm.enqueueToolCallTurn(calls: [
            .init(
                id: "finish-1",
                name: "finish_shard",
                arguments: #"{"summary":"Updated README through the shard workflow","files_changed":["README.md"],"checks":[{"name":"swift test","status":"passed","kind":"validation_command"}],"risks":[]}"#
            ),
        ])
        await fixture.llm.enqueueTextResponse("Shard complete.")

        _ = try await fixture.runner.runShard(shardID: shardID)

        let commandLogs = try fixture.commandLogStore.fetchEntries(shardID: shardID)
        XCTAssertEqual(commandLogs.map(\.command), [["git", "status", "--short"]])

        let runtimeMetadata = try XCTUnwrap(fixture.shardStore.fetchRuntimeMetadata(shardID: shardID))
        try fixture.commitWorktreeChange(
            in: runtimeMetadata.worktreePath,
            fileName: "README.md",
            commitMessage: "Shard README update"
        )

        let mergeResult = try fixture.mergeService.merge(shardID: shardID)
        XCTAssertFalse(mergeResult.commitHash.isEmpty)

        let doneShards = try fixture.shardStore.fetchShards(states: [.done])
        XCTAssertEqual(doneShards.map(\.id), [shardID])

        let report = try XCTUnwrap(fixture.completionReportStore.fetch(shardID: shardID))
        XCTAssertEqual(report.summary, "Updated README through the shard workflow")

        let pushResult = try fixture.pushService.push(
            targetName: "origin-main",
            ref: .shuttleMain,
            idempotencyKey: "e2e-happy-push",
            actor: ShuttleActorIdentity(actorType: "test", actorID: "e2e")
        )
        XCTAssertEqual(pushResult.targetName, "origin-main")

        let publishedCommit = try ShuttleGitShell.run(
            ["rev-parse", "published-main"],
            workingDirectory: fixture.gitFixture.originBareRepository.path
        ).stdout
        XCTAssertEqual(publishedCommit, mergeResult.commitHash)
    }

    func testLocalFixtureScenarioBlocksIntegrationOnMergeConflict() async throws {
        let fixture = try await Fixture.make(name: "e2e-conflict")
        let firstShardID = try await fixture.createShard(
            title: "First conflict shard",
            spec: "Apply the first README change.",
            idempotencyKey: "e2e-conflict-first"
        )
        let secondShardID = try await fixture.createShard(
            title: "Second conflict shard",
            spec: "Apply the second README change.",
            idempotencyKey: "e2e-conflict-second"
        )

        try await fixture.finishCommittedShard(
            shardID: firstShardID,
            fileName: "README.md",
            contents: "# Fixture\n\nFirst shard change.\n",
            summary: "First shard completed"
        )
        _ = try fixture.mergeService.merge(shardID: firstShardID)

        try await fixture.finishCommittedShard(
            shardID: secondShardID,
            fileName: "README.md",
            contents: "# Fixture\n\nSecond shard change.\n",
            summary: "Second shard completed"
        )

        XCTAssertThrowsError(try fixture.mergeService.merge(shardID: secondShardID)) { error in
            guard case .conflictRecorded(let conflictID) = error as? ShuttleSquashMergeServiceError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertFalse(conflictID.isEmpty)
        }

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .blocked)
        XCTAssertNotNil(repoState.blockedConflictID)

        let conflicts = try fixture.conflictStore.fetchOpenConflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.kind, "shard_merge")
    }
}

private struct Fixture {
    let config: ShuttleConfig
    let gitFixture: ShuttleGitTestFixture
    let shardStore: ShuttleShardStore
    let completionReportStore: ShuttleCompletionReportStore
    let commandLogStore: ShuttleCommandLogStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictStore: ShuttleConflictStore
    let createService: ShuttleShardCreateService
    let containerService: ShuttleShardContainerService
    let lifecycleService: ShuttleShardLifecycleService
    let runner: ShuttleShardAgentRunner
    let mergeService: ShuttleSquashMergeService
    let pushService: ShuttlePushService
    let llm: ShuttleTestLLMService

    static func make(name: String) async throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent(name, isDirectory: true)
        let databaseRoot = root.appendingPathComponent("database", isDirectory: true)
        let gitRoot = root.appendingPathComponent("git", isDirectory: true)
        let worktreesRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        let logsRoot = root.appendingPathComponent("logs", isDirectory: true)
        let configRoot = root.appendingPathComponent("config", isDirectory: true)
        let secretsRoot = root.appendingPathComponent("secrets", isDirectory: true)

        try FileManager.default.createDirectory(at: databaseRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secretsRoot, withIntermediateDirectories: true)

        let instructionsPath = configRoot.appendingPathComponent("shuttle-instructions.md")
        try "Default Shuttle instructions.".write(to: instructionsPath, atomically: true, encoding: .utf8)
        let sshKeyPath = secretsRoot.appendingPathComponent("id_ed25519")
        try "test-key".write(to: sshKeyPath, atomically: true, encoding: .utf8)

        let config = ShuttleConfig(
            repository: .init(
                url: gitFixture.originBareRepository.path,
                sourceBranch: gitFixture.branch,
                sshKeyPath: sshKeyPath.path
            ),
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
            pushTargets: [.init(name: "origin-main", remote: "origin", branch: "published-main")],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: instructionsPath.path),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        let configPath = configRoot.appendingPathComponent("shuttle.yaml")
        try writeConfig(config: config, to: configPath)

        let dockerBackend = ShuttleTestDockerExecBackend()
        let llm = ShuttleTestLLMService()
        let environment = try await ShuttleServerApp.makeEnvironment(
            configuration: .init(host: "127.0.0.1", port: 8080, configPath: configPath.path),
            dockerClient: ShuttleDockerClient(
                probeAvailability: { .available(detail: "Docker socket accessible") },
                createContainer: { request in await dockerBackend.create(request: request) },
                inspectContainer: { name in await dockerBackend.inspectContainer(name: name) },
                stopContainer: { name in try await dockerBackend.stopContainer(name: name) },
                execInContainer: { request in try await dockerBackend.exec(request: request) }
            )
        )

        let dbQueue = try XCTUnwrap(environment.databaseQueue)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let completionReportStore = ShuttleCompletionReportStore(dbQueue: dbQueue)
        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        let conflictStore = ShuttleConflictStore(dbQueue: dbQueue)
        let auditEventStore = ShuttleAuditEventStore(dbQueue: dbQueue)
        let idempotencyStore = ShuttleIdempotencyStore(dbQueue: dbQueue)
        let worktreeManager = ShuttleWorktreeManager(
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            worktreesRootPath: config.paths.worktreesPath
        )
        let workspaceService = ShuttleShardWorkspaceService(
            shardStore: shardStore,
            worktreeManager: worktreeManager
        )
        let createService = ShuttleShardCreateService(
            config: config,
            shardStore: shardStore,
            workspaceService: workspaceService,
            idempotencyStore: idempotencyStore,
            auditEventStore: auditEventStore
        )
        let commandLogStore = ShuttleCommandLogStore(
            dbQueue: dbQueue,
            logsRootPath: config.paths.logsPath,
            retentionDays: config.retention.rawLogsDays,
            maxBytesPerFile: config.limits.maxLogBytesPerShard
        )
        let commandService = ShuttleShardCommandExecutionService(
            shardStore: shardStore,
            dockerAccessController: environment.dockerAccessController,
            commandLogStore: commandLogStore,
            config: config
        )
        let containerService = ShuttleShardContainerService(
            shardStore: shardStore,
            dockerAccessController: environment.dockerAccessController,
            config: config
        )
        let lifecycleService = ShuttleShardLifecycleService(
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            auditEventStore: auditEventStore
        )
        let transcriptStore = ShuttleAgentTranscriptStore(
            dbQueue: dbQueue,
            logsRootPath: config.paths.logsPath,
            retentionDays: config.retention.rawLogsDays,
            maxBytesPerFile: config.limits.maxLogBytesPerShard
        )
        let conflictService = ShuttleConflictService(
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            config: config,
            auditEventStore: auditEventStore,
            repositoryValidator: ShuttleConflictRepositoryValidator { _ in }
        )
        let integrationGateService = ShuttleIntegrationGateService(
            config: config,
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            repositoryStateStore: repositoryStateStore
        )
        let mergeService = ShuttleSquashMergeService(
            config: config,
            shardStore: shardStore,
            repositoryStateStore: repositoryStateStore,
            integrationGateService: integrationGateService,
            shardWorkspaceService: workspaceService,
            conflictService: conflictService
        )
        let pushService = ShuttlePushService(
            config: config,
            repositoryStateStore: repositoryStateStore,
            shardStore: shardStore,
            idempotencyStore: idempotencyStore,
            auditEventStore: auditEventStore
        )
        let runner = ShuttleShardAgentRunner(
            config: config,
            shardStore: shardStore,
            commandService: commandService,
            lifecycleService: lifecycleService,
            transcriptStore: transcriptStore,
            llmService: llm,
            auditEventStore: auditEventStore
        )

        return Fixture(
            config: config,
            gitFixture: gitFixture,
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            commandLogStore: commandLogStore,
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            createService: createService,
            containerService: containerService,
            lifecycleService: lifecycleService,
            runner: runner,
            mergeService: mergeService,
            pushService: pushService,
            llm: llm
        )
    }

    func createShard(
        title: String,
        spec: String,
        idempotencyKey: String
    ) async throws -> String {
        let result = try createService.createShard(
            title: title,
            spec: spec,
            idempotencyKey: idempotencyKey,
            actor: ShuttleActorIdentity(actorType: "test", actorID: "e2e")
        )
        _ = try await containerService.createContainer(forShardID: result.shardID)
        return result.shardID
    }

    func finishCommittedShard(
        shardID: String,
        fileName: String,
        contents: String,
        summary: String
    ) async throws {
        let runtimeMetadata = try XCTUnwrap(shardStore.fetchRuntimeMetadata(shardID: shardID))
        try shardStore.updateState(shardID: shardID, to: .running)
        let fileURL = URL(fileURLWithPath: runtimeMetadata.worktreePath, isDirectory: true)
            .appendingPathComponent(fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try commitWorktreeChange(
            in: runtimeMetadata.worktreePath,
            fileName: fileName,
            commitMessage: summary
        )
        try await lifecycleService.finishShard(
            shardID: shardID,
            report: ShuttleCompletionReport(
                shardID: shardID,
                summary: summary,
                filesChanged: [fileName],
                checks: [.init(name: "swift test", status: "passed", kind: "validation_command")],
                risks: [],
                createdAt: Date()
            )
        )
    }

    func commitWorktreeChange(
        in worktreePath: String,
        fileName: String,
        commitMessage: String
    ) throws {
        try ShuttleGitTestFixture.runGit(["config", "user.name", "Shuttle Tests"], in: worktreePath)
        try ShuttleGitTestFixture.runGit(["config", "user.email", "shuttle-tests@example.com"], in: worktreePath)
        try ShuttleGitTestFixture.runGit(["add", fileName], in: worktreePath)
        try ShuttleGitTestFixture.runGit(["commit", "-m", commitMessage], in: worktreePath)
    }

    private static func writeConfig(config: ShuttleConfig, to url: URL) throws {
        let contents = """
        repository:
          url: \(config.repository.url)
          source_branch: \(config.repository.sourceBranch)
          ssh_key_path: \(config.repository.sshKeyPath)
        runtime:
          container_image: \(config.runtime.containerImage)
          container_workdir: \(config.runtime.containerWorkdir)
          command_policy:
            allow:
              - swift
              - git
            deny:
              - rm
        refresh:
          schedule: "\(config.refresh.schedule)"
        retention:
          worktree_days: \(config.retention.worktreeDays)
          raw_logs_days: \(config.retention.rawLogsDays)
          raw_logs_max_bytes: \(config.retention.rawLogsMaxBytes)
        limits:
          max_running_shards: \(config.limits.maxRunningShards)
          max_integrating_shards: \(config.limits.maxIntegratingShards)
          max_queued_shards: \(config.limits.maxQueuedShards)
          max_log_bytes_per_shard: \(config.limits.maxLogBytesPerShard)
        paths:
          database: \(config.paths.databasePath)
          git: \(config.paths.gitPath)
          worktrees: \(config.paths.worktreesPath)
          logs: \(config.paths.logsPath)
        push_targets:
          - name: origin-main
            remote: origin
            branch: published-main
        auth:
          mode: \(config.auth.mode.rawValue)
        instructions:
          file_path: \(config.instructions.filePath)
        server:
          host: \(config.server.host)
          port: \(config.server.port)
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

}
