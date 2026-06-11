import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleStartupReconciliationTests: XCTestCase {
    func testStartupReconciliationKeepsDoneShardWhenRetainedWorktreeIsMissing() async throws {
        let fixture = try makeFixture(name: "done-missing-worktree")
        let workspace = try fixture.workspaceService.createQueuedShard(
            id: "shard-done-missing-worktree",
            title: "Done shard",
            spec: "Done shard",
            branchName: "shuttle/shards/done-missing-worktree"
        )
        try fixture.shardStore.markDoneRetained(
            shardID: workspace.id,
            retainedUntil: Date().addingTimeInterval(7 * 24 * 60 * 60)
        )
        try FileManager.default.removeItem(atPath: workspace.worktreePath)

        _ = try await makeEnvironment(configPath: fixture.configPath.path, dockerClient: fixture.dockerClient)

        let stored = try XCTUnwrap(fixture.shardStore.fetchShard(id: workspace.id))
        XCTAssertEqual(stored.state, .done)
        XCTAssertNotNil(stored.retainedUntil)

        let events = try fixture.auditEventStore.fetchAll()
        XCTAssertTrue(events.contains {
            $0.entityType == "shard"
                && $0.entityID == workspace.id
                && $0.eventType == "shard_reconciled"
                && $0.payload["outcome"] == "missing_retained_worktree"
        })
    }

    func testStartupReconciliationRecreatesContainerForRunningShardWithExistingWorktree() async throws {
        let fixture = try makeFixture(name: "running-container-recreate")
        let workspace = try fixture.workspaceService.createQueuedShard(
            id: "shard-running-container-recreate",
            title: "Running shard",
            spec: "Running shard",
            branchName: "shuttle/shards/running-container-recreate"
        )
        try fixture.shardStore.updateState(shardID: workspace.id, to: .running)

        _ = try await makeEnvironment(configPath: fixture.configPath.path, dockerClient: fixture.dockerClient)

        let runtimeMetadata = try XCTUnwrap(fixture.shardStore.fetchRuntimeMetadata(shardID: workspace.id))
        let createCallCount = await fixture.dockerBackend.createCallCount()
        XCTAssertEqual(runtimeMetadata.containerStatus, "running")
        XCTAssertEqual(createCallCount, 1)
    }

    func testStartupReconciliationMarksRunningShardFailedWhenWorktreeIsMissing() async throws {
        let fixture = try makeFixture(name: "running-missing-worktree")
        let workspace = try fixture.workspaceService.createQueuedShard(
            id: "shard-running-missing-worktree",
            title: "Running missing worktree",
            spec: "Running missing worktree",
            branchName: "shuttle/shards/running-missing-worktree"
        )
        try fixture.shardStore.updateState(shardID: workspace.id, to: .running)
        try FileManager.default.removeItem(atPath: workspace.worktreePath)

        _ = try await makeEnvironment(configPath: fixture.configPath.path, dockerClient: fixture.dockerClient)

        let stored = try XCTUnwrap(fixture.shardStore.fetchShard(id: workspace.id))
        XCTAssertEqual(stored.state, .failed)

        let events = try fixture.auditEventStore.fetchAll()
        XCTAssertTrue(events.contains {
            $0.entityType == "shard"
                && $0.entityID == workspace.id
                && $0.eventType == "shard_reconciled"
                && $0.payload["outcome"] == "worktree_missing_failed"
        })
    }

    func testStartupReconciliationRebuildsBlockedRepositoryStateFromOpenConflict() async throws {
        let fixture = try makeFixture(name: "blocked-from-conflict")
        try fixture.repositoryStateStore.upsert(config: fixture.config, integrationState: .open)
        let conflict = try fixture.conflictStore.create(
            id: "conflict-reopen-1",
            kind: "upstream_refresh",
            details: ["reason": "merge_conflict"]
        )

        _ = try await makeEnvironment(configPath: fixture.configPath.path, dockerClient: fixture.dockerClient)

        let repositoryState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repositoryState.integrationState, .blocked)
        XCTAssertEqual(repositoryState.blockedConflictID, conflict.id)
    }

    func testStartupReconciliationNormalizesIntegratingShardToDoneWhenAlreadyMerged() async throws {
        let fixture = try makeFixture(name: "integrating-to-done")
        let workspace = try fixture.workspaceService.createQueuedShard(
            id: "shard-integrating-to-done",
            title: "Integrating shard",
            spec: "Integrating shard",
            branchName: "shuttle/shards/integrating-to-done"
        )

        _ = try ShuttleGitShell.run(["config", "user.name", "Shuttle Tests"], workingDirectory: workspace.worktreePath)
        _ = try ShuttleGitShell.run(["config", "user.email", "shuttle-tests@example.com"], workingDirectory: workspace.worktreePath)
        let fileURL = URL(fileURLWithPath: workspace.worktreePath).appendingPathComponent("README.md")
        try "# Integrated\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try ShuttleGitShell.run(["add", "README.md"], workingDirectory: workspace.worktreePath)
        _ = try ShuttleGitShell.run(["commit", "-m", "Shard change"], workingDirectory: workspace.worktreePath)

        try fixture.completionReportStore.save(
            ShuttleCompletionReport(
                shardID: workspace.id,
                summary: "Integrated shard",
                filesChanged: ["README.md"],
                checks: [.init(name: "swift test", status: "passed", kind: "validation_command")],
                risks: [],
                createdAt: Date()
            )
        )
        try fixture.shardStore.updateState(shardID: workspace.id, to: .integrating)
        try commitOnShuttleMain(
            bareRepositoryPath: fixture.bareRepositoryPath,
            fileName: "README.md",
            contents: "# Integrated\n",
            commitMessage: "Apply shard change"
        )

        _ = try await makeEnvironment(configPath: fixture.configPath.path, dockerClient: fixture.dockerClient)

        let stored = try XCTUnwrap(fixture.shardStore.fetchShard(id: workspace.id))
        XCTAssertEqual(stored.state, .done)
        XCTAssertNotNil(stored.retainedUntil)

        let events = try fixture.auditEventStore.fetchAll()
        XCTAssertTrue(events.contains {
            $0.entityType == "shard"
                && $0.entityID == workspace.id
                && $0.eventType == "shard_reconciled"
                && $0.payload["outcome"] == "integrating_to_done"
        })
    }

    private func makeFixture(name: String) throws -> Fixture {
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
            instructions: .init(filePath: instructionsPath.path),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        let configPath = configRoot.appendingPathComponent("shuttle.yaml")
        try writeConfig(config: config, to: configPath)
        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        let dbQueue = try ShuttleDatabase.openMigrated(atPath: config.paths.databasePath)
        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        try repositoryStateStore.upsert(config: config, integrationState: .open)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let worktreeManager = ShuttleWorktreeManager(
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            worktreesRootPath: config.paths.worktreesPath
        )
        let workspaceService = ShuttleShardWorkspaceService(
            shardStore: shardStore,
            worktreeManager: worktreeManager
        )

        let dockerBackend = StartupFakeDockerBackend()
        let dockerClient = ShuttleDockerClient(
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
        )

        return Fixture(
            config: config,
            configPath: configPath,
            gitFixture: gitFixture,
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            shardStore: shardStore,
            repositoryStateStore: repositoryStateStore,
            conflictStore: ShuttleConflictStore(dbQueue: dbQueue),
            completionReportStore: ShuttleCompletionReportStore(dbQueue: dbQueue),
            auditEventStore: ShuttleAuditEventStore(dbQueue: dbQueue),
            workspaceService: workspaceService,
            dockerBackend: dockerBackend,
            dockerClient: dockerClient
        )
    }

    private func makeEnvironment(
        configPath: String,
        dockerClient: ShuttleDockerClient
    ) async throws -> ShuttleServerApp.Environment {
        try await ShuttleServerApp.makeEnvironment(
            configuration: .init(host: "127.0.0.1", port: 8080, configPath: configPath),
            dockerClient: dockerClient
        )
    }

    private func writeConfig(config: ShuttleConfig, to url: URL) throws {
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
        push_targets: []
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

    private func commitOnShuttleMain(
        bareRepositoryPath: String,
        fileName: String,
        contents: String,
        commitMessage: String
    ) throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        _ = try ShuttleGitShell.run(
            ["--git-dir", bareRepositoryPath, "worktree", "add", tempURL.path, ShuttleRepositoryBootstrapper.shuttleMainBranch]
        )
        defer {
            _ = try? ShuttleGitShell.run(["--git-dir", bareRepositoryPath, "worktree", "remove", "--force", tempURL.path])
        }

        let fileURL = tempURL.appendingPathComponent(fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try ShuttleGitShell.run(["config", "user.name", "Shuttle Tests"], workingDirectory: tempURL.path)
        _ = try ShuttleGitShell.run(["config", "user.email", "shuttle-tests@example.com"], workingDirectory: tempURL.path)
        _ = try ShuttleGitShell.run(["add", fileName], workingDirectory: tempURL.path)
        _ = try ShuttleGitShell.run(["commit", "-m", commitMessage], workingDirectory: tempURL.path)
    }
}

private struct Fixture {
    let config: ShuttleConfig
    let configPath: URL
    let gitFixture: ShuttleGitTestFixture
    let bareRepositoryPath: String
    let shardStore: ShuttleShardStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictStore: ShuttleConflictStore
    let completionReportStore: ShuttleCompletionReportStore
    let auditEventStore: ShuttleAuditEventStore
    let workspaceService: ShuttleShardWorkspaceService
    let dockerBackend: StartupFakeDockerBackend
    let dockerClient: ShuttleDockerClient
}

private actor StartupFakeDockerBackend {
    private var containers: [String: ShuttleDockerContainerInspection] = [:]
    private var createCalls: Int = 0

    func create(request: ShuttleDockerCreateContainerRequest) -> ShuttleDockerContainerInspection {
        let inspection = ShuttleDockerContainerInspection(
            name: request.name,
            image: request.image,
            status: .running,
            mounts: request.mounts,
            workingDirectory: request.workingDirectory
        )
        containers[request.name] = inspection
        createCalls += 1
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

    func createCallCount() -> Int {
        createCalls
    }
}
