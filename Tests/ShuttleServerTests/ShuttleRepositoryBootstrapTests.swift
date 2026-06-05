import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttleRepositoryBootstrapTests: XCTestCase {
    func testBootstrapClonesBareRepositoryAndCreatesShuttleMain() throws {
        let fixture = try ShuttleGitTestFixture.create()
        let config = try makeConfig(originURL: fixture.originBareRepository)

        let result = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        XCTAssertEqual(result.sourceBranch, "main")
        XCTAssertEqual(result.shuttleMainBranch, "shuttle-main")

        let isBare = try ShuttleGitTestFixture.runGit(
            ["rev-parse", "--is-bare-repository"],
            in: result.bareRepositoryPath
        ).stdout
        XCTAssertEqual(isBare, "true")

        let shuttleMainCommit = try ShuttleGitTestFixture.runGit(
            ["rev-parse", "refs/heads/shuttle-main"],
            in: result.bareRepositoryPath
        ).stdout
        XCTAssertEqual(shuttleMainCommit, try fixture.originBranchCommit())
    }

    func testBootstrapFetchesUpdatedUpstreamBranchOnRerun() throws {
        let fixture = try ShuttleGitTestFixture.create()
        let config = try makeConfig(originURL: fixture.originBareRepository)

        let initial = try ShuttleRepositoryBootstrapper.bootstrap(config: config)
        let newCommit = try fixture.addCommitAndPush(
            fileName: "CHANGELOG.md",
            contents: "update\n",
            commitMessage: "Update fixture"
        )

        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        let fetchedCommit = try ShuttleGitTestFixture.runGit(
            ["rev-parse", "refs/remotes/origin/main"],
            in: initial.bareRepositoryPath
        ).stdout
        XCTAssertEqual(fetchedCommit, newCommit)
    }

    func testBootstrapFailsWhenExistingRepositoryOriginDoesNotMatchConfig() throws {
        let firstFixture = try ShuttleGitTestFixture.create()
        let secondFixture = try ShuttleGitTestFixture.create()
        let config = try makeConfig(originURL: firstFixture.originBareRepository)
        let mismatchedConfig = try makeConfig(
            originURL: secondFixture.originBareRepository,
            gitRootOverride: URL(fileURLWithPath: config.paths.gitPath, isDirectory: true)
        )

        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        XCTAssertThrowsError(try ShuttleRepositoryBootstrapper.bootstrap(config: mismatchedConfig)) { error in
            XCTAssertTrue(
                (error as? ShuttleStartupError).map {
                    if case .gitOperationFailed(let detail) = $0 {
                        return detail.contains("origin mismatch")
                    }
                    return false
                } ?? false
            )
        }
    }

    private func makeConfig(
        originURL: URL,
        gitRootOverride: URL? = nil
    ) throws -> ShuttleConfig {
        let gitRoot: URL
        if let gitRootOverride {
            gitRoot = gitRootOverride
        } else {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            gitRoot = root.appendingPathComponent("git", isDirectory: true)
            try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        }

        return ShuttleConfig(
            repository: .init(
                url: originURL.path,
                sourceBranch: "main",
                sshKeyPath: "/tmp/unused-key"
            ),
            runtime: .init(
                containerImage: "ghcr.io/example/shuttle-runner:latest",
                containerWorkdir: "/workspace",
                commandPolicy: .init(allow: [], deny: [])
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
                databasePath: "/tmp/db",
                gitPath: gitRoot.path,
                worktreesPath: "/tmp/worktrees",
                logsPath: "/tmp/logs"
            ),
            pushTargets: [],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: "/tmp/instructions.md"),
            server: .init(host: "127.0.0.1", port: 8080)
        )
    }
}
