import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttleUpstreamRefreshServiceTests: XCTestCase {
    func testRefreshNoOpLeavesRepositoryOpen() throws {
        let fixture = try makeFixture()

        let result = try fixture.refreshService.refresh()

        XCTAssertEqual(result.outcome, .noOp)
        XCTAssertNil(result.conflictID)

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .open)
        XCTAssertEqual(repoState.upstreamHeadCommit, try fixture.gitFixture.originBranchCommit())
    }

    func testRefreshMergesNewUpstreamCommitIntoShuttleMain() throws {
        let fixture = try makeFixture()
        let upstreamCommit = try fixture.gitFixture.addCommitAndPush(
            fileName: "CHANGELOG.md",
            contents: "upstream change\n",
            commitMessage: "Update upstream"
        )

        let result = try fixture.refreshService.refresh()

        XCTAssertEqual(result.outcome, .merged)
        XCTAssertEqual(result.upstreamCommit, upstreamCommit)
        XCTAssertNil(result.conflictID)

        let mainLog = try ShuttleGitShell.run(
            ["--git-dir", fixture.bareRepositoryPath, "log", "-1", "--pretty=%B", ShuttleRepositoryBootstrapper.shuttleMainBranch]
        ).stdout
        XCTAssertTrue(mainLog.contains("Merge"))

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .open)
        XCTAssertEqual(repoState.upstreamHeadCommit, upstreamCommit)
        XCTAssertEqual(repoState.shuttleMainCommit, result.shuttleMainCommit)
    }

    func testRefreshConflictCreatesConflictAndBlocksRepository() throws {
        let fixture = try makeFixture()

        try commitOnShuttleMain(
            bareRepositoryPath: fixture.bareRepositoryPath,
            fileName: "README.md",
            contents: "# shuttle main change\n",
            commitMessage: "Shuttle main change"
        )
        _ = try fixture.gitFixture.addCommitAndPush(
            fileName: "README.md",
            contents: "# upstream change\n",
            commitMessage: "Upstream change"
        )

        let result = try fixture.refreshService.refresh()

        XCTAssertEqual(result.outcome, .blocked)
        XCTAssertNotNil(result.conflictID)

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .blocked)
        XCTAssertEqual(repoState.blockedConflictID, result.conflictID)

        let conflicts = try fixture.conflictStore.fetchOpenConflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].kind, "upstream_refresh")
    }

    private func makeFixture() throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("refresh", isDirectory: true)
        let databaseRoot = root.appendingPathComponent("database", isDirectory: true)
        let gitRoot = root.appendingPathComponent("git", isDirectory: true)
        let worktreesRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        let logsRoot = root.appendingPathComponent("logs", isDirectory: true)
        let configRoot = root.appendingPathComponent("config", isDirectory: true)

        try FileManager.default.createDirectory(at: databaseRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configRoot, withIntermediateDirectories: true)

        let instructionsPath = configRoot.appendingPathComponent("shuttle-instructions.md").path
        try "Default Shuttle instructions.".write(
            to: URL(fileURLWithPath: instructionsPath),
            atomically: true,
            encoding: .utf8
        )

        let config = ShuttleConfig(
            repository: .init(url: gitFixture.originBareRepository.path, sourceBranch: gitFixture.branch, sshKeyPath: "/tmp/unused-key"),
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
            pushTargets: [],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: instructionsPath),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        let dbQueue = try ShuttleDatabase.openMigrated(atPath: config.paths.databasePath)
        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        try repositoryStateStore.upsert(config: config, integrationState: .open)
        let conflictStore = ShuttleConflictStore(dbQueue: dbQueue)
        let conflictService = ShuttleConflictService(
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            config: config
        )

        return Fixture(
            config: config,
            gitFixture: gitFixture,
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            refreshService: ShuttleUpstreamRefreshService(
                config: config,
                repositoryStateStore: repositoryStateStore,
                conflictService: conflictService
            )
        )
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
    let gitFixture: ShuttleGitTestFixture
    let bareRepositoryPath: String
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictStore: ShuttleConflictStore
    let refreshService: ShuttleUpstreamRefreshService
}
