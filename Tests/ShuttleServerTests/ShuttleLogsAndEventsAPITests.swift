import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import XCTest
@testable import ShuttleServer

final class ShuttleLogsAndEventsAPITests: XCTestCase {
    func testShardEventsEndpointPaginatesInAppendOnlyOrder() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-events", state: .running)
        try fixture.auditEventStore.recordShardCreated(shardID: "shard-events", title: "A", actor: nil)
        try fixture.auditEventStore.recordShardFinishRequested(shardID: "shard-events", actor: nil)
        try fixture.auditEventStore.recordShardAbandoned(shardID: "shard-events", reason: "done", actor: nil)

        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards/shard-events/events?limit=2", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeLogsAndEventsDecoder().decode(ShuttleAuditEventPageResponse.self, from: response.body)
                XCTAssertEqual(payload.items.map(\.eventType), ["shard_created", "shard_finish_requested"])
                XCTAssertNotNil(payload.nextCursor)

                let nextCursor = try XCTUnwrap(payload.nextCursor)
                XCTAssertEqual(payload.items.last?.id, nextCursor)
            }

            try await client.execute(uri: "/api/shards/shard-events/events?limit=2&cursor=2", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeLogsAndEventsDecoder().decode(ShuttleAuditEventPageResponse.self, from: response.body)
                XCTAssertEqual(payload.items.map(\.eventType), ["shard_abandoned"])
                XCTAssertNil(payload.nextCursor)
            }
        }
    }

    func testShardLogsEndpointPaginatesIndexedChunks() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-logs", state: .running)
        try fixture.commandLogStore.append(
            ShuttleCommandLogEntry(
                shardID: "shard-logs",
                command: ["swift", "test"],
                stdout: "one",
                stderr: "",
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 1_800_000_010),
                endedAt: Date(timeIntervalSince1970: 1_800_000_011),
                toolName: "run_tests"
            )
        )
        try fixture.commandLogStore.append(
            ShuttleCommandLogEntry(
                shardID: "shard-logs",
                command: ["swift", "build"],
                stdout: "two",
                stderr: "",
                exitCode: 0,
                startedAt: Date(timeIntervalSince1970: 1_800_000_012),
                endedAt: Date(timeIntervalSince1970: 1_800_000_013),
                toolName: nil
            )
        )

        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards/shard-logs/logs?limit=1", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeLogsAndEventsDecoder().decode(ShuttleCommandLogPageResponse.self, from: response.body)
                XCTAssertEqual(payload.items.count, 1)
                XCTAssertEqual(payload.items[0].stdout, "one")
                XCTAssertEqual(payload.items[0].toolName, "run_tests")
                XCTAssertNotNil(payload.nextCursor)
            }

            try await client.execute(uri: "/api/shards/shard-logs/logs?limit=1&cursor=1", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeLogsAndEventsDecoder().decode(ShuttleCommandLogPageResponse.self, from: response.body)
                XCTAssertEqual(payload.items.count, 1)
                XCTAssertEqual(payload.items[0].stdout, "two")
                XCTAssertNil(payload.nextCursor)
            }
        }
    }

    func testRepositoryEventsEndpointPagesAcrossEntities() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-repo-events", state: .running)
        try fixture.auditEventStore.recordShardCreated(shardID: "shard-repo-events", title: "A", actor: nil)
        try fixture.auditEventStore.recordConflictCreated(conflictID: "conflict-1", kind: "merge", actor: nil)
        try fixture.auditEventStore.recordPushAction(
            pushID: "push-1",
            target: "origin-main",
            ref: "refs/heads/shuttle-main",
            result: "success",
            actor: nil
        )

        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))
        try await app.test(.router) { client in
            try await client.execute(uri: "/api/events?limit=2", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeLogsAndEventsDecoder().decode(ShuttleAuditEventPageResponse.self, from: response.body)
                XCTAssertEqual(payload.items.map(\.entityType), ["shard", "conflict"])
                XCTAssertEqual(payload.nextCursor, payload.items.last?.id)
            }
        }
    }

    func testMissingShardAndInvalidPaginationReturnClientErrors() async throws {
        let fixture = try makeFixture()
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards/missing/events", method: .get) { response in
                XCTAssertEqual(response.status, .notFound)
            }

            try await client.execute(uri: "/api/shards/missing/logs", method: .get) { response in
                XCTAssertEqual(response.status, .notFound)
            }

            try await client.execute(uri: "/api/events?cursor=nope", method: .get) { response in
                XCTAssertEqual(response.status, .badRequest)
            }

            try await client.execute(uri: "/api/events?limit=0", method: .get) { response in
                XCTAssertEqual(response.status, .badRequest)
            }
        }
    }

    private func makeFixture() throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("logs-events-api", isDirectory: true)
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
                commandPolicy: .init(allow: ["swift"], deny: ["rm"])
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
        let environment = try awaitResult {
            try await ShuttleServerApp.makeEnvironment(
                configuration: .init(host: "127.0.0.1", port: 8080, configPath: configPath.path),
                dockerClient: .init(probeAvailability: { .available(detail: "Docker socket accessible") })
            )
        }

        let dbQueue = try XCTUnwrap(environment.databaseQueue)
        return Fixture(
            environment: environment,
            shardStore: ShuttleShardStore(dbQueue: dbQueue),
            auditEventStore: ShuttleAuditEventStore(dbQueue: dbQueue),
            commandLogStore: ShuttleCommandLogStore(
                dbQueue: dbQueue,
                logsRootPath: config.paths.logsPath,
                retentionDays: config.retention.rawLogsDays,
                maxBytesPerFile: config.retention.rawLogsMaxBytes
            )
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
        let resultBox = LogsAndEventsLockedResultBox<T>()
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
    let shardStore: ShuttleShardStore
    let auditEventStore: ShuttleAuditEventStore
    let commandLogStore: ShuttleCommandLogStore

    func seedShard(id: String, state: ShuttleShardState) throws {
        try shardStore.createQueuedShard(
            id: id,
            title: "Test shard",
            spec: "Spec for \(id)",
            baseCommit: "base-\(id)",
            branchName: "shuttle/shards/\(id)",
            worktreePath: "/tmp/\(id)"
        )
        if state != .queued {
            try shardStore.updateState(shardID: id, to: state)
        }
    }
}

private func makeLogsAndEventsDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private final class LogsAndEventsLockedResultBox<T>: @unchecked Sendable {
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
