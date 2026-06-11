import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest
@testable import ShuttleServer

final class ShuttleRepositoryOperationsAPITests: XCTestCase {
    func testGetConflictsListsOpenAndResolvedRecords() async throws {
        let fixture = try makeFixture()
        let first = try fixture.conflictService.recordUpstreamRefreshConflict(
            details: ["reason": "merge_conflict", "upstream_ref": "origin/main"]
        )
        _ = try fixture.conflictService.recordShardMergeConflict(
            sourceShardID: fixture.shard.id,
            details: ["reason": "branch_not_mergeable"]
        )
        _ = try fixture.conflictService.resolveConflict(conflictID: first.id, resolutionShardID: fixture.shard.id)

        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/conflicts", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeRepositoryOperationsDecoder().decode([ShuttleConflictResponse].self, from: response.body)
                XCTAssertEqual(payload.count, 2)
                XCTAssertEqual(Set(payload.map(\.state)), ["open", "resolved"])
            }
        }
    }

    func testResolveConflictEndpointResolvesAndReopensRepository() async throws {
        let fixture = try makeFixture()
        let conflict = try fixture.conflictService.recordUpstreamRefreshConflict(
            details: ["reason": "merge_conflict", "upstream_ref": "origin/main"]
        )
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/conflicts/\(conflict.id)/resolve",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"resolutionShardID":"shard-api-ops"}"#)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeRepositoryOperationsDecoder().decode(ShuttleConflictResponse.self, from: response.body)
                XCTAssertEqual(payload.state, "resolved")
                XCTAssertEqual(payload.resolutionShardID, "shard-api-ops")
            }
        }

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .open)
        XCTAssertNil(repoState.blockedConflictID)
    }

    func testRefreshEndpointReturnsConflictWhenRepositoryBlocked() async throws {
        let fixture = try makeFixture()
        try fixture.repositoryStateStore.upsert(
            config: fixture.config,
            integrationState: .blocked,
            blockedConflictID: "conflict-locked"
        )
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/repository/refresh", method: .post) { response in
                XCTAssertEqual(response.status, .conflict)
            }
        }
    }

    func testPushEndpointIsIdempotentAndRecordsAuditEvent() async throws {
        let fixture = try makeFixture()
        _ = try fixture.gitFixture.addCommitAndPush(
            fileName: "CHANGELOG.md",
            contents: "upstream change\n",
            commitMessage: "Update upstream"
        )
        _ = try fixture.refreshService.refresh()

        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))
        let body = ByteBuffer(string: #"{"targetName":"origin-main","ref":{"kind":"shuttle_main","shardID":null}}"#)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/pushes",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    HTTPField.Name("Idempotency-Key")!: "push-api-1",
                ],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeRepositoryOperationsDecoder().decode(ShuttlePushResponse.self, from: response.body)
                XCTAssertEqual(payload.pushID, "push-api-1")
                XCTAssertEqual(payload.targetName, "origin-main")
            }

            try await client.execute(
                uri: "/api/pushes",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    HTTPField.Name("Idempotency-Key")!: "push-api-1",
                ],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeRepositoryOperationsDecoder().decode(ShuttlePushResponse.self, from: response.body)
                XCTAssertEqual(payload.pushID, "push-api-1")
            }
        }

        let events = try fixture.auditEventStore.fetchAll()
        XCTAssertTrue(events.contains { $0.entityType == "push" && $0.entityID == "push-api-1" && $0.eventType == "push_executed" })
    }

    private func makeFixture() throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("repo-ops-api", isDirectory: true)
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
            pushTargets: [.init(name: "origin-main", remote: "origin", branch: "published-main")],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: instructionsPath.path),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        let configPath = configRoot.appendingPathComponent("shuttle.yaml")
        try writeConfig(config: config, to: configPath)
        let environment = try awaitResult {
            try await ShuttleServerApp.makeEnvironment(
                configuration: .init(host: "127.0.0.1", port: 8080, configPath: configPath.path),
                dockerClient: .init(probeAvailability: { .available(detail: "Docker socket accessible") })
            )
        }

        let dbQueue = try XCTUnwrap(environment.databaseQueue)
        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        let conflictStore = ShuttleConflictStore(dbQueue: dbQueue)
        let auditEventStore = ShuttleAuditEventStore(dbQueue: dbQueue)
        let conflictService = ShuttleConflictService(
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            config: config,
            auditEventStore: auditEventStore,
            repositoryValidator: ShuttleConflictRepositoryValidator { _ in }
        )
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        try shardStore.createQueuedShard(
            id: "shard-api-ops",
            title: "API ops shard",
            spec: "API ops shard",
            baseCommit: "deadbeef",
            branchName: "shuttle/shards/api-ops",
            worktreePath: "/tmp/shard-api-ops"
        )
        let refreshService = ShuttleUpstreamRefreshService(
            config: config,
            repositoryStateStore: repositoryStateStore,
            conflictService: conflictService
        )
        let pushService = ShuttlePushService(
            config: config,
            repositoryStateStore: repositoryStateStore,
            shardStore: shardStore,
            idempotencyStore: ShuttleIdempotencyStore(dbQueue: dbQueue),
            auditEventStore: auditEventStore
        )

        return Fixture(
            environment: environment,
            config: config,
            gitFixture: gitFixture,
            shard: try XCTUnwrap(shardStore.fetchShard(id: "shard-api-ops")),
            repositoryStateStore: repositoryStateStore,
            auditEventStore: auditEventStore,
            conflictService: conflictService,
            refreshService: refreshService,
            pushService: pushService
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

    private func awaitResult<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = RepositoryOperationsLockedResultBox<T>()
        Task {
            do {
                resultBox.set(result: .success(try await operation()))
            } catch {
                resultBox.set(result: .failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try resultBox.get()
    }
}

private struct Fixture {
    let environment: ShuttleServerApp.Environment
    let config: ShuttleConfig
    let gitFixture: ShuttleGitTestFixture
    let shard: ShuttleStoredShard
    let repositoryStateStore: ShuttleRepositoryStateStore
    let auditEventStore: ShuttleAuditEventStore
    let conflictService: ShuttleConflictService
    let refreshService: ShuttleUpstreamRefreshService
    let pushService: ShuttlePushService
}

private func makeRepositoryOperationsDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private final class RepositoryOperationsLockedResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func set(result: Result<T, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try result!.get()
    }
}
