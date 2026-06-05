import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttleStartupValidationTests: XCTestCase {
    func testStartupValidationPassesWhenAllRequiredPathsExist() async throws {
        let fixture = try makeStartupFixture(includeSSHKey: true)
        let statusStore = ShuttleServerStatusStore()
        let configuration = ShuttleServerConfiguration(
            host: "127.0.0.1",
            port: 8080,
            configPath: fixture.configFile.path
        )

        _ = try await ShuttleServerApp.makeEnvironment(configuration: configuration, statusStore: statusStore)

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .ready)
    }

    func testStartupValidationFailsForMissingDatabaseVolumePath() async throws {
        let fixture = try makeStartupFixture(includeSSHKey: true)
        try FileManager.default.removeItem(at: fixture.databaseDirectory)

        let statusStore = ShuttleServerStatusStore()
        let configuration = ShuttleServerConfiguration(
            host: "127.0.0.1",
            port: 8080,
            configPath: fixture.configFile.path
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await ShuttleServerApp.makeEnvironment(configuration: configuration, statusStore: statusStore)
        }

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .fatal)
        XCTAssertEqual(payload.subsystems["database"]?.status, .failed)
        XCTAssertTrue(payload.subsystems["database"]?.detail?.contains("database volume") == true)
    }

    func testStartupValidationFailsForMissingSSHKeyPath() async throws {
        let fixture = try makeStartupFixture(includeSSHKey: false)

        let statusStore = ShuttleServerStatusStore()
        let configuration = ShuttleServerConfiguration(
            host: "127.0.0.1",
            port: 8080,
            configPath: fixture.configFile.path
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await ShuttleServerApp.makeEnvironment(configuration: configuration, statusStore: statusStore)
        }

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .fatal)
        XCTAssertEqual(payload.subsystems["config"]?.status, .failed)
        XCTAssertTrue(payload.subsystems["config"]?.detail?.contains("Unreadable SSH key path") == true)
    }

    private func makeStartupFixture(includeSSHKey: Bool) throws -> (
        root: URL,
        configFile: URL,
        databaseDirectory: URL
    ) {
        let repositoryFixture = try ShuttleGitTestFixture.create()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let db = root.appendingPathComponent("db", isDirectory: true)
        let git = root.appendingPathComponent("git", isDirectory: true)
        let worktrees = root.appendingPathComponent("worktrees", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let configDir = root.appendingPathComponent("config", isDirectory: true)
        let secretsDir = root.appendingPathComponent("secrets", isDirectory: true)
        let sshKey = secretsDir.appendingPathComponent("id_ed25519")
        let configFile = configDir.appendingPathComponent("shuttle.yaml")

        try FileManager.default.createDirectory(at: db, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktrees, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)

        if includeSSHKey {
            try "not-a-real-key".write(to: sshKey, atomically: true, encoding: .utf8)
        }

        let configYAML = """
        repository:
          url: \(repositoryFixture.originBareRepository.path)
          source_branch: \(repositoryFixture.branch)
          ssh_key_path: \(sshKey.path)

        runtime:
          container_image: ghcr.io/example/shuttle-runner:latest
          container_workdir: /workspace

        refresh:
          schedule: "0 * * * *"

        retention:
          worktree_days: 7
          raw_logs_days: 14
          raw_logs_max_bytes: 10485760

        limits:
          max_running_shards: 4
          max_integrating_shards: 1
          max_queued_shards: 32
          max_log_bytes_per_shard: 5242880

        paths:
          database: \(db.path)
          git: \(git.path)
          worktrees: \(worktrees.path)
          logs: \(logs.path)

        auth:
          mode: local_admin

        instructions:
          file_path: \(configDir.path)/shuttle-instructions.md
        """

        try configYAML.write(to: configFile, atomically: true, encoding: .utf8)
        return (root: root, configFile: configFile, databaseDirectory: db)
    }
}
