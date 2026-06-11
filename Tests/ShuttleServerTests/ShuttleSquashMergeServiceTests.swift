import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleSquashMergeServiceTests: XCTestCase {
    func testBuildCommitMessageFromCompletionReport() {
        let report = ShuttleCompletionReport(
            shardID: "shard-merge-1",
            summary: "Implement integration queue",
            filesChanged: ["Sources/App.swift", "README.md"],
            checks: [
                .init(name: "swift test", status: "passed", kind: "validation_command"),
                .init(name: "swift build", status: "passed", kind: "check"),
            ],
            risks: ["Follow-up metrics panel still pending"],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let message = ShuttleSquashMergeService.buildCommitMessage(report: report)
        XCTAssertTrue(message.contains("Implement integration queue"))
        XCTAssertTrue(message.contains("Files Changed"))
        XCTAssertTrue(message.contains("Sources/App.swift"))
        XCTAssertTrue(message.contains("Checks"))
        XCTAssertTrue(message.contains("swift test: passed"))
        XCTAssertTrue(message.contains("Risks"))
    }

    func testSuccessfulSquashMergeMovesShardToDoneAndRetainsWorktree() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(validReport(shardID: fixture.shard.id))

        try commitShardChange(
            in: fixture.worktreeURL,
            fileName: "README.md",
            contents: "# Shuttle merge result\n",
            commitMessage: "Shard update"
        )

        let result = try fixture.mergeService.merge(shardID: fixture.shard.id)

        let shard = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.shard.id))
        XCTAssertEqual(shard.state, .done)
        XCTAssertNotNil(shard.retainedUntil)

        let repoState = try fixture.repositoryStateStore.fetchIntegrationState()
        XCTAssertEqual(repoState, .open)

        let mainLog = try ShuttleGitShell.run(
            ["--git-dir", fixture.bareRepositoryPath, "log", "-1", "--pretty=%B", ShuttleRepositoryBootstrapper.shuttleMainBranch]
        ).stdout
        XCTAssertTrue(mainLog.contains("Ready for integration"))
        XCTAssertTrue(mainLog.contains("Files Changed"))

        let readme = try String(contentsOf: fixture.worktreeURL.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertEqual(readme, "# Shuttle merge result\n")
        XCTAssertEqual(result.shardID, fixture.shard.id)
        XCTAssertFalse(result.commitHash.isEmpty)
    }

    func testIntegrationLockRejectsSecondIntegrationWhenRepositoryAlreadyIntegrating() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(validReport(shardID: fixture.shard.id))
        try fixture.repositoryStateStore.upsert(config: fixture.config, integrationState: .integrating)

        XCTAssertThrowsError(try fixture.mergeService.merge(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(error as? ShuttleSquashMergeServiceError, .integrationLocked(.integrating))
        }
    }

    func testIntegrationLockRejectsMergeWhileRepositoryRefreshing() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(validReport(shardID: fixture.shard.id))
        try fixture.repositoryStateStore.upsert(config: fixture.config, integrationState: .refreshing)

        XCTAssertThrowsError(try fixture.mergeService.merge(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(error as? ShuttleSquashMergeServiceError, .integrationLocked(.refreshing))
        }
    }

    private func makeFixture() throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("squash-merge", isDirectory: true)
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
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let workspaceService = ShuttleShardWorkspaceService(
            shardStore: shardStore,
            worktreeManager: ShuttleWorktreeManager(
                bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
                worktreesRootPath: config.paths.worktreesPath
            )
        )
        let shard = try workspaceService.createQueuedShard(
            id: "shard-merge-abcdef12",
            title: "Merge shard",
            spec: "Merge shard",
            branchName: "shuttle/shards/merge-shard-abcdef12"
        )
        try shardStore.updateState(shardID: shard.id, to: .integrating)

        let completionReportStore = ShuttleCompletionReportStore(dbQueue: dbQueue)
        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        try repositoryStateStore.upsert(config: config, integrationState: .open)

        let gateService = ShuttleIntegrationGateService(
            config: config,
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            repositoryStateStore: repositoryStateStore
        )
        let mergeService = ShuttleSquashMergeService(
            config: config,
            shardStore: shardStore,
            repositoryStateStore: repositoryStateStore,
            integrationGateService: gateService,
            shardWorkspaceService: workspaceService,
            conflictService: nil
        )

        return Fixture(
            config: config,
            shard: shard,
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            worktreeURL: URL(fileURLWithPath: shard.worktreePath, isDirectory: true),
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            repositoryStateStore: repositoryStateStore,
            mergeService: mergeService
        )
    }

    private func validReport(shardID: String) -> ShuttleCompletionReport {
        ShuttleCompletionReport(
            shardID: shardID,
            summary: "Ready for integration",
            filesChanged: ["README.md"],
            checks: [.init(name: "swift test", status: "passed", kind: "validation_command")],
            risks: [],
            createdAt: Date()
        )
    }

    private func commitShardChange(
        in worktreeURL: URL,
        fileName: String,
        contents: String,
        commitMessage: String
    ) throws {
        let fileURL = worktreeURL.appendingPathComponent(fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try ShuttleGitTestFixture.runGit(["config", "user.name", "Shuttle Tests"], in: worktreeURL.path)
        try ShuttleGitTestFixture.runGit(["config", "user.email", "shuttle-tests@example.com"], in: worktreeURL.path)
        try ShuttleGitTestFixture.runGit(["add", fileName], in: worktreeURL.path)
        try ShuttleGitTestFixture.runGit(["commit", "-m", commitMessage], in: worktreeURL.path)
    }
}

private struct Fixture {
    let config: ShuttleConfig
    let shard: ShuttleShardWorkspace
    let bareRepositoryPath: String
    let worktreeURL: URL
    let shardStore: ShuttleShardStore
    let completionReportStore: ShuttleCompletionReportStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let mergeService: ShuttleSquashMergeService
}
