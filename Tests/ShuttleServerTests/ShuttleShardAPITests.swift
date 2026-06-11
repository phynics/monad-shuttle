import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import XCTest
@testable import ShuttleServer

final class ShuttleShardAPITests: XCTestCase {
    func testPostShardsCreatesShardAndReplaysByIdempotencyKey() async throws {
        let fixture = try makeFixture()
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"title":"Implement API","spec":"Build shard endpoints"}"#)
            try await client.execute(
                uri: "/api/shards",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    HTTPField.Name("Idempotency-Key")!: "create-1",
                ],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode(ShuttleCreateShardResponse.self, from: response.body)
                XCTAssertFalse(payload.shardID.isEmpty)
            }

            try await client.execute(
                uri: "/api/shards",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    HTTPField.Name("Idempotency-Key")!: "create-1",
                ],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode(ShuttleCreateShardResponse.self, from: response.body)
                let allShards = try fixture.shardStore.fetchShards()
                XCTAssertEqual(allShards.count, 1)
                XCTAssertEqual(payload.shardID, allShards[0].id)
            }
        }
    }

    func testGetShardsListsAndFiltersByState() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-running", title: "Running", spec: "Run", state: .running)
        try fixture.seedShard(id: "shard-needs-input", title: "Input", spec: "Input", state: .needsInput)
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards?states=needs_input", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode([ShuttleShardSummaryResponse].self, from: response.body)
                XCTAssertEqual(payload.map(\.id), ["shard-needs-input"])
            }

            try await client.execute(uri: "/api/shards?states=needs_input,running", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode([ShuttleShardSummaryResponse].self, from: response.body)
                XCTAssertEqual(Set(payload.map(\.id)), ["shard-needs-input", "shard-running"])
            }
        }
    }

    func testGetShardDetailReturnsJoinedShardState() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-detail", title: "Detail", spec: "Detail spec", state: .running)
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards/shard-detail", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode(ShuttleShardDetailResponse.self, from: response.body)
                XCTAssertEqual(payload.id, "shard-detail")
                XCTAssertEqual(payload.state, "running")
                XCTAssertEqual(payload.branchName, "shuttle/shards/shard-detail")
            }
        }
    }

    func testGetCompletionReportReturnsReportForShard() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-report", title: "Report", spec: "Report spec", state: .integrating)
        try ShuttleCompletionReportStore(dbQueue: try XCTUnwrap(fixture.environment.databaseQueue)).save(
            ShuttleCompletionReport(
                shardID: "shard-report",
                summary: "Implemented report",
                filesChanged: ["Sources/File.swift"],
                checks: [.init(name: "swift test", status: "passed", kind: "validation_command")],
                risks: [],
                createdAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards/shard-report/completion-report", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode(ShuttleCompletionReportResponse.self, from: response.body)
                XCTAssertEqual(payload.summary, "Implemented report")
                XCTAssertEqual(payload.filesChanged, ["Sources/File.swift"])
                XCTAssertEqual(payload.checks[0].name, "swift test")
            }
        }
    }

    func testRequestFinishAnswerAndAbandonEndpointsRespectTransitions() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-running", title: "Running", spec: "Run", state: .running)
        try fixture.seedShard(id: "shard-needs-input", title: "Needs input", spec: "Need input", state: .needsInput)
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards/shard-running/request-finish", method: .post) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode(ShuttleShardActionResponse.self, from: response.body)
                XCTAssertEqual(payload.state, "running")
            }

            try await client.execute(
                uri: "/api/shards/shard-needs-input/answer",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"answer":"Use target origin-main"}"#)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode(ShuttleShardActionResponse.self, from: response.body)
                XCTAssertEqual(payload.state, "running")
            }

            try await client.execute(
                uri: "/api/shards/shard-running/abandon",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"reason":"Superseded"}"#)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try makeShardAPIDecoder().decode(ShuttleShardActionResponse.self, from: response.body)
                XCTAssertEqual(payload.state, "abandoned")
            }
        }
    }

    func testInvalidTransitionsReturnClientErrors() async throws {
        let fixture = try makeFixture()
        try fixture.seedShard(id: "shard-queued", title: "Queued", spec: "Queued", state: .queued)
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/shards/shard-queued/request-finish", method: .post) { response in
                XCTAssertEqual(response.status, .badRequest)
            }

            try await client.execute(
                uri: "/api/shards",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"title":"x","spec":"y"}"#)
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
            }

            try await client.execute(uri: "/api/shards?states=bogus", method: .get) { response in
                XCTAssertEqual(response.status, .badRequest)
            }

            try await client.execute(
                uri: "/api/shards/shard-queued/answer",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{\"answer\":\"   \"}")
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
            }
        }
    }

    func testPostShardsRejectsWhenQueuedShardLimitReached() async throws {
        let fixture = try makeFixture(maxQueuedShards: 1)
        try fixture.seedShard(id: "shard-queued-1", title: "Queued", spec: "Queued", state: .queued)
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            let body = ByteBuffer(string: #"{"title":"Second queued shard","spec":"Should be rejected"}"#)
            try await client.execute(
                uri: "/api/shards",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    HTTPField.Name("Idempotency-Key")!: "create-limit-1",
                ],
                body: body
            ) { response in
                XCTAssertEqual(response.status, .conflict)
            }
        }
    }

    func testAnswerRejectsWhenRunningShardLimitReached() async throws {
        let fixture = try makeFixture(maxRunningShards: 1)
        try fixture.seedShard(id: "shard-running-limit", title: "Running", spec: "Running", state: .running)
        try fixture.seedShard(id: "shard-needs-input-limit", title: "Needs input", spec: "Needs input", state: .needsInput)
        let app = Application(router: ShuttleServerApp.makeRouter(environment: fixture.environment))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/shards/shard-needs-input-limit/answer",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"answer":"Proceed"}"#)
            ) { response in
                XCTAssertEqual(response.status, .conflict)
            }
        }
    }

    private func makeFixture(maxQueuedShards: Int = 32, maxRunningShards: Int = 4) throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("shard-api", isDirectory: true)
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
            limits: .init(maxRunningShards: maxRunningShards, maxIntegratingShards: 1, maxQueuedShards: maxQueuedShards, maxLogBytesPerShard: 5_242_880),
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
        let shardStore = ShuttleShardStore(dbQueue: try XCTUnwrap(environment.databaseQueue))
        return Fixture(environment: environment, shardStore: shardStore)
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
        let resultBox = ShardAPILockedResultBox<T>()
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

    func seedShard(id: String, title: String, spec: String, state: ShuttleShardState) throws {
        try shardStore.createQueuedShard(
            id: id,
            title: title,
            spec: spec,
            baseCommit: "base-\(id)",
            branchName: "shuttle/shards/\(id)",
            worktreePath: "/tmp/\(id)"
        )
        if state != .queued {
            try shardStore.updateState(shardID: id, to: state)
        }
    }
}

private func makeShardAPIDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private final class ShardAPILockedResultBox<T>: @unchecked Sendable {
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
