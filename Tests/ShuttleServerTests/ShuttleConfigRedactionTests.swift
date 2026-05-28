import Foundation
import XCTest
import Hummingbird
import HummingbirdTesting
@testable import ShuttleServer

final class ShuttleConfigRedactionTests: XCTestCase {
    func testRedactedConfigMasksSSHKeyPath() {
        let config = ShuttleConfig(
            repository: .init(
                url: "git@github.com:example/repo.git",
                sourceBranch: "main",
                sshKeyPath: "/run/secrets/id_ed25519"
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
                databasePath: "/data/db",
                gitPath: "/data/git",
                worktreesPath: "/data/worktrees",
                logsPath: "/data/logs"
            ),
            pushTargets: [.init(name: "origin-main", remote: "origin", branch: "main")],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: "/config/shuttle-instructions.md"),
            server: .init(host: "0.0.0.0", port: 8080)
        )

        let redacted = ShuttleConfigResponse(redacting: config)

        XCTAssertEqual(redacted.repository.sshKeyPath, "<redacted>")
        XCTAssertEqual(redacted.repository.url, "git@github.com:example/repo.git")
        XCTAssertEqual(redacted.instructions.filePath, "/config/shuttle-instructions.md")
    }

    func testInvalidYAMLDoesNotExposeRawSecretLookingContent() throws {
        let secretMarker = "SUPER-SECRET-PRIVATE-KEY-MATERIAL"
        let fileURL = try writeConfig(
            """
            repository:
              url: git@github.com:example/repo.git
              source_branch: main
              ssh_key_path: /run/secrets/id_ed25519
            runtime: [\(secretMarker)
            """
        )

        XCTAssertThrowsError(try ShuttleConfigLoader.load(fromFilePath: fileURL.path)) { error in
            XCTAssertEqual(error as? ShuttleConfigError, .invalidYAML("invalid YAML document"))
            XCTAssertFalse(String(describing: error).contains(secretMarker))
        }
    }

    func testConfigEndpointReturnsRedactedEffectiveConfig() async throws {
        let environment = ShuttleServerApp.Environment(
            configuration: .init(host: "127.0.0.1", port: 8080, configPath: "/config/shuttle.yaml"),
            loadedConfig: ShuttleConfig(
                repository: .init(
                    url: "git@github.com:example/repo.git",
                    sourceBranch: "main",
                    sshKeyPath: "/run/secrets/id_ed25519"
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
                    databasePath: "/data/db",
                    gitPath: "/data/git",
                    worktreesPath: "/data/worktrees",
                    logsPath: "/data/logs"
                ),
                pushTargets: [.init(name: "origin-main", remote: "origin", branch: "main")],
                auth: .init(mode: .localAdmin),
                instructions: .init(filePath: "/config/shuttle-instructions.md"),
                server: .init(host: "0.0.0.0", port: 8080)
            ),
            statusStore: ShuttleServerStatusStore()
        )
        let router = ShuttleServerApp.makeRouter(environment: environment)
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/config", method: .get) { response in
                XCTAssertEqual(response.status, .ok)

                let payload = try JSONDecoder().decode(ShuttleConfigResponse.self, from: response.body)
                XCTAssertEqual(payload.repository.sshKeyPath, "<redacted>")
                XCTAssertEqual(payload.repository.sourceBranch, "main")
                XCTAssertEqual(payload.runtime.containerImage, "ghcr.io/example/shuttle-runner:latest")
            }
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
