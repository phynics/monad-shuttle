import XCTest
import Foundation
import Hummingbird
import HummingbirdTesting
@testable import ShuttleServer

final class ShuttleServerStatusRouteTests: XCTestCase {
    func testStatusEndpointReturnsReadySubsystemKeysAndRepositoryState() async throws {
        let fixture = try makeManagedEnvironment()
        let router = ShuttleServerApp.makeRouter(environment: fixture.environment)
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/status", method: .get) { response in
                XCTAssertEqual(response.status, .ok)

                let payload = try JSONDecoder().decode(ShuttleStatusResponse.self, from: response.body)
                XCTAssertEqual(payload.serverState, .ready)
                XCTAssertEqual(Set(payload.subsystems.keys), [
                    "agent_runtime",
                    "config",
                    "database",
                    "docker",
                    "git",
                    "repo_refresh",
                    "volumes",
                ])
                XCTAssertEqual(payload.repository?.integrationState, "open")
                XCTAssertEqual(payload.repository?.sourceBranch, "main")
                XCTAssertEqual(payload.repository?.shuttleMainBranch, "shuttle-main")
            }
        }
    }

    func testInvalidExplicitConfigPathSetsFatalState() async throws {
        let statusStore = ShuttleServerStatusStore()
        let configuration = ShuttleServerConfiguration(
            host: "127.0.0.1",
            port: 8080,
            configPath: "/path/that/does/not/exist.yml"
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await ShuttleServerApp.makeEnvironment(
                configuration: configuration,
                statusStore: statusStore
            )
        }

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .fatal)
    }

    func testGracefulShutdownMarksServerDraining() async throws {
        let statusStore = ShuttleServerStatusStore()
        let shutdownCoordinator = ShuttleServerShutdownCoordinator(statusStore: statusStore)

        await shutdownCoordinator.beginGracefulShutdown()

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .draining)
    }

    private func makeManagedEnvironment() throws -> ManagedEnvironmentFixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("status-route", isDirectory: true)
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
            instructions: .init(filePath: instructionsPath.path),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        let configPath = configRoot.appendingPathComponent("shuttle.yaml")
        try writeConfig(config, to: configPath)

        let environment = try awaitResult {
            try await ShuttleServerApp.makeEnvironment(
                configuration: .init(host: "127.0.0.1", port: 8080, configPath: configPath.path),
                dockerClient: .init(probeAvailability: {
                    .available(detail: "Docker socket accessible")
                })
            )
        }

        return ManagedEnvironmentFixture(environment: environment)
    }

    private func writeConfig(_ config: ShuttleConfig, to url: URL) throws {
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
        let resultBox = LockedResultBox<T>()
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

private struct ManagedEnvironmentFixture {
    let environment: ShuttleServerApp.Environment
}

private final class LockedResultBox<T>: @unchecked Sendable {
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
