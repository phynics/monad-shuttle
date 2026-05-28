import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttleConfigLoaderTests: XCTestCase {
    func testLoadValidConfigParsesExpectedFields() throws {
        let fileURL = try self.writeConfig(
            """
            repository:
              url: git@github.com:example/repo.git
              source_branch: main
              ssh_key_path: /run/secrets/id_ed25519

            runtime:
              container_image: ghcr.io/example/shuttle-runner:latest
              container_workdir: /workspace
              command_policy:
                allow:
                  - swift
                  - git
                deny:
                  - rm

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

            push_targets:
              - name: origin-main
                remote: origin
                branch: main

            auth:
              mode: local_admin

            instructions:
              file_path: /config/shuttle-instructions.md

            server:
              host: 0.0.0.0
              port: 8080
            """
        )

        let config = try ShuttleConfigLoader.load(fromFilePath: fileURL.path)

        XCTAssertEqual(config.repository.url, "git@github.com:example/repo.git")
        XCTAssertEqual(config.repository.sourceBranch, "main")
        XCTAssertEqual(config.repository.sshKeyPath, "/run/secrets/id_ed25519")
        XCTAssertEqual(config.runtime.containerImage, "ghcr.io/example/shuttle-runner:latest")
        XCTAssertEqual(config.runtime.containerWorkdir, "/workspace")
        XCTAssertEqual(config.runtime.commandPolicy.allow, ["swift", "git"])
        XCTAssertEqual(config.runtime.commandPolicy.deny, ["rm"])
        XCTAssertEqual(config.refresh.schedule, "0 * * * *")
        XCTAssertEqual(config.retention.worktreeDays, 7)
        XCTAssertEqual(config.retention.rawLogsDays, 14)
        XCTAssertEqual(config.retention.rawLogsMaxBytes, 10_485_760)
        XCTAssertEqual(config.limits.maxRunningShards, 4)
        XCTAssertEqual(config.limits.maxIntegratingShards, 1)
        XCTAssertEqual(config.limits.maxQueuedShards, 32)
        XCTAssertEqual(config.limits.maxLogBytesPerShard, 5_242_880)
        XCTAssertEqual(config.paths.databasePath, "/data/db")
        XCTAssertEqual(config.paths.gitPath, "/data/git")
        XCTAssertEqual(config.paths.worktreesPath, "/data/worktrees")
        XCTAssertEqual(config.paths.logsPath, "/data/logs")
        XCTAssertEqual(config.pushTargets, [
            ShuttleConfig.PushTarget(name: "origin-main", remote: "origin", branch: "main")
        ])
        XCTAssertEqual(config.auth.mode, .localAdmin)
        XCTAssertEqual(config.instructions.filePath, "/config/shuttle-instructions.md")
        XCTAssertEqual(config.server.host, "0.0.0.0")
        XCTAssertEqual(config.server.port, 8080)
    }

    func testLoadConfigRejectsMissingRequiredField() throws {
        let fileURL = try self.writeConfig(
            """
            repository:
              source_branch: main
              ssh_key_path: /run/secrets/id_ed25519

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

            auth:
              mode: local_admin

            instructions:
              file_path: /config/shuttle-instructions.md
            """
        )

        XCTAssertThrowsError(try ShuttleConfigLoader.load(fromFilePath: fileURL.path)) { error in
            XCTAssertEqual(error as? ShuttleConfigError, .missingRequiredField("repository.url"))
        }
    }

    func testLoadConfigRejectsUnknownField() throws {
        let fileURL = try self.writeConfig(
            """
            repository:
              url: git@github.com:example/repo.git
              source_branch: main
              ssh_key_path: /run/secrets/id_ed25519
              mystery: nope

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

            auth:
              mode: local_admin

            instructions:
              file_path: /config/shuttle-instructions.md
            """
        )

        XCTAssertThrowsError(try ShuttleConfigLoader.load(fromFilePath: fileURL.path)) { error in
            XCTAssertEqual(error as? ShuttleConfigError, .unknownField("repository.mystery"))
        }
    }

    func testLoadConfigRejectsInvalidAbsolutePathField() throws {
        let fileURL = try self.writeConfig(
            """
            repository:
              url: git@github.com:example/repo.git
              source_branch: main
              ssh_key_path: secrets/id_ed25519

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

            auth:
              mode: local_admin

            instructions:
              file_path: /config/shuttle-instructions.md
            """
        )

        XCTAssertThrowsError(try ShuttleConfigLoader.load(fromFilePath: fileURL.path)) { error in
            XCTAssertEqual(
                error as? ShuttleConfigError,
                .invalidPath(field: "repository.ssh_key_path", reason: "must be an absolute path")
            )
        }
    }

    func testLoadConfigRejectsInvalidConcurrencyLimits() throws {
        let fileURL = try self.writeConfig(
            """
            repository:
              url: git@github.com:example/repo.git
              source_branch: main
              ssh_key_path: /run/secrets/id_ed25519

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
              max_running_shards: 0
              max_integrating_shards: 2
              max_queued_shards: 32
              max_log_bytes_per_shard: 5242880

            auth:
              mode: local_admin

            instructions:
              file_path: /config/shuttle-instructions.md
            """
        )

        XCTAssertThrowsError(try ShuttleConfigLoader.load(fromFilePath: fileURL.path)) { error in
            XCTAssertEqual(
                error as? ShuttleConfigError,
                .invalidValue(field: "limits.max_running_shards", reason: "must be greater than zero")
            )
        }
    }

    func testLoadConfigRejectsInvalidPushTargetDefinition() throws {
        let fileURL = try self.writeConfig(
            """
            repository:
              url: git@github.com:example/repo.git
              source_branch: main
              ssh_key_path: /run/secrets/id_ed25519

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

            push_targets:
              - name: origin-main
                remote: ""
                branch: main

            auth:
              mode: local_admin

            instructions:
              file_path: /config/shuttle-instructions.md
            """
        )

        XCTAssertThrowsError(try ShuttleConfigLoader.load(fromFilePath: fileURL.path)) { error in
            XCTAssertEqual(
                error as? ShuttleConfigError,
                .invalidValue(field: "push_targets[0].remote", reason: "must not be empty")
            )
        }
    }

    private func writeConfig(_ contents: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("shuttle.yaml")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
