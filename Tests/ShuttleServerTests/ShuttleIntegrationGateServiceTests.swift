import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleIntegrationGateServiceTests: XCTestCase {
    func testRejectsMissingCompletionReport() throws {
        let fixture = try makeFixture()

        XCTAssertThrowsError(try fixture.gateService.validate(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(error as? ShuttleIntegrationGateError, .missingCompletionReport(fixture.shard.id))
        }
    }

    func testRejectsMissingValidationStatuses() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(
            ShuttleCompletionReport(
                shardID: fixture.shard.id,
                summary: "Done",
                filesChanged: ["README.md"],
                checks: [.init(name: "swift test", status: "passed", kind: "check")],
                risks: [],
                createdAt: Date()
            )
        )

        XCTAssertThrowsError(try fixture.gateService.validate(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(error as? ShuttleIntegrationGateError, .missingValidationStatuses(fixture.shard.id))
        }
    }

    func testRejectsUnstagedChanges() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(validReport(shardID: fixture.shard.id, filesChanged: ["README.md"]))
        try "# Dirty README\n".write(
            to: fixture.worktreeURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let status = try ShuttleGitShell.run(["status", "--porcelain"], workingDirectory: fixture.worktreeURL.path)
        XCTAssertTrue(status.stdout.contains("README.md"))

        XCTAssertThrowsError(try fixture.gateService.validate(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(
                error as? ShuttleIntegrationGateError,
                .unstagedChanges(fixture.shard.id, paths: ["README.md"])
            )
        }
    }

    func testRejectsUnreportedUntrackedFiles() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(validReport(shardID: fixture.shard.id, filesChanged: ["README.md"]))
        try "new file\n".write(
            to: fixture.worktreeURL.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try fixture.gateService.validate(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(
                error as? ShuttleIntegrationGateError,
                .unreportedUntrackedFiles(fixture.shard.id, paths: ["notes.txt"])
            )
        }
    }

    func testRejectsRepositoryWhenStateIsNotOpen() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(validReport(shardID: fixture.shard.id, filesChanged: ["README.md"]))
        try fixture.repositoryStateStore.upsert(
            config: fixture.config,
            integrationState: .blocked
        )

        XCTAssertThrowsError(try fixture.gateService.validate(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(error as? ShuttleIntegrationGateError, .repositoryNotOpen(.blocked))
        }
    }

    func testRejectsNonMergeableBranch() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(validReport(shardID: fixture.shard.id, filesChanged: ["README.md"]))

        try commitChange(
            in: fixture.worktreeURL,
            fileName: "README.md",
            contents: "# Feature branch\n",
            commitMessage: "Shard change"
        )
        try commitOnShuttleMain(
            bareRepositoryPath: fixture.bareRepositoryPath,
            fileName: "README.md",
            contents: "# Main branch\n",
            commitMessage: "Main change"
        )

        XCTAssertThrowsError(try fixture.gateService.validate(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(error as? ShuttleIntegrationGateError, .branchNotMergeable(fixture.shard.id))
        }
    }

    func testPassesWhenGateConditionsAreSatisfied() throws {
        let fixture = try makeFixture()
        try fixture.completionReportStore.save(
            validReport(
                shardID: fixture.shard.id,
                filesChanged: ["README.md", "notes.txt"]
            )
        )
        try "new file\n".write(
            to: fixture.worktreeURL.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let approval = try fixture.gateService.validate(shardID: fixture.shard.id)
        XCTAssertEqual(approval.shard.id, fixture.shard.id)
        XCTAssertEqual(approval.runtimeMetadata.branchName, fixture.shard.branchName)
        XCTAssertEqual(approval.completionReport.validationStatuses.count, 1)
    }

    private func makeFixture() throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("integration-gate", isDirectory: true)
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
            id: "shard-gate-abcdef12",
            title: "Gate shard",
            spec: "Gate shard",
            branchName: "shuttle/shards/gate-shard-abcdef12"
        )

        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        try repositoryStateStore.upsert(config: config, integrationState: .open)
        let completionReportStore = ShuttleCompletionReportStore(dbQueue: dbQueue)

        return Fixture(
            config: config,
            shard: shard,
            worktreeURL: URL(fileURLWithPath: shard.worktreePath, isDirectory: true),
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            repositoryStateStore: repositoryStateStore,
            gateService: ShuttleIntegrationGateService(
                config: config,
                shardStore: shardStore,
                completionReportStore: completionReportStore,
                repositoryStateStore: repositoryStateStore
            )
        )
    }

    private func validReport(
        shardID: String,
        filesChanged: [String]
    ) -> ShuttleCompletionReport {
        ShuttleCompletionReport(
            shardID: shardID,
            summary: "Ready for integration",
            filesChanged: filesChanged,
            checks: [.init(name: "swift test", status: "passed", kind: "validation_command")],
            risks: [],
            createdAt: Date()
        )
    }

    private func commitChange(
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
        try ShuttleGitTestFixture.runGit(["config", "user.name", "Shuttle Tests"], in: tempURL.path)
        try ShuttleGitTestFixture.runGit(["config", "user.email", "shuttle-tests@example.com"], in: tempURL.path)
        try ShuttleGitTestFixture.runGit(["add", fileName], in: tempURL.path)
        try ShuttleGitTestFixture.runGit(["commit", "-m", commitMessage], in: tempURL.path)
    }
}

private struct Fixture {
    let config: ShuttleConfig
    let shard: ShuttleShardWorkspace
    let worktreeURL: URL
    let bareRepositoryPath: String
    let shardStore: ShuttleShardStore
    let completionReportStore: ShuttleCompletionReportStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let gateService: ShuttleIntegrationGateService
}
