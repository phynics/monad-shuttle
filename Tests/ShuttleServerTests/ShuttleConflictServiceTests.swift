import Foundation
import GRDB
import XCTest
@testable import ShuttleServer

final class ShuttleConflictServiceTests: XCTestCase {
    func testResolveConflictRejectsDirtyRepository() throws {
        let fixture = try makeFixture(
            repositoryValidator: ShuttleConflictRepositoryValidator { _ in
                throw ShuttleConflictResolutionValidationError.repositoryNotClean(paths: ["README.md"])
            }
        )
        let conflict = try fixture.conflictService.recordUpstreamRefreshConflict(
            details: ["reason": "merge_conflict", "upstream_ref": "origin/main"]
        )

        XCTAssertThrowsError(try fixture.conflictService.resolveConflict(conflictID: conflict.id)) { error in
            XCTAssertEqual(
                error as? ShuttleConflictResolutionValidationError,
                .repositoryNotClean(paths: ["README.md"])
            )
        }

        let stored = try XCTUnwrap(fixture.conflictStore.fetchConflict(id: conflict.id))
        XCTAssertEqual(stored.state, "open")
    }

    func testResolveConflictRejectsActiveMergeState() throws {
        let fixture = try makeFixture(
            repositoryValidator: ShuttleConflictRepositoryValidator { _ in
                throw ShuttleConflictResolutionValidationError.activeMergeState
            }
        )
        let conflict = try fixture.conflictService.recordUpstreamRefreshConflict(
            details: ["reason": "merge_conflict", "upstream_ref": "origin/main"]
        )

        XCTAssertThrowsError(try fixture.conflictService.resolveConflict(conflictID: conflict.id)) { error in
            XCTAssertEqual(
                error as? ShuttleConflictResolutionValidationError,
                .activeMergeState
            )
        }

        let stored = try XCTUnwrap(fixture.conflictStore.fetchConflict(id: conflict.id))
        XCTAssertEqual(stored.state, "open")
    }

    func testShardMergeConflictCreatesConflictRecordAndBlocksRepository() throws {
        let fixture = try makeFixture()

        let conflict = try fixture.conflictService.recordShardMergeConflict(
            sourceShardID: fixture.shard.id,
            details: ["reason": "merge_conflict", "branch": "shuttle/shards/example"]
        )

        XCTAssertEqual(conflict.kind, "shard_merge")
        XCTAssertEqual(conflict.state, "open")
        XCTAssertTrue(conflict.blocking)
        XCTAssertEqual(conflict.sourceShardID, fixture.shard.id)

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .blocked)
        XCTAssertEqual(repoState.blockedConflictID, conflict.id)
    }

    func testUpstreamRefreshConflictCreatesConflictRecordAndBlocksRepository() throws {
        let fixture = try makeFixture()

        let conflict = try fixture.conflictService.recordUpstreamRefreshConflict(
            details: ["reason": "merge_conflict", "upstream_ref": "origin/main"]
        )

        XCTAssertEqual(conflict.kind, "upstream_refresh")
        XCTAssertEqual(conflict.state, "open")
        XCTAssertNil(conflict.sourceShardID)

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .blocked)
        XCTAssertEqual(repoState.blockedConflictID, conflict.id)
    }

    func testBlockedRepositoryRefusesNewIntegrations() throws {
        let fixture = try makeFixture()
        try fixture.repositoryStateStore.upsert(
            config: fixture.config,
            integrationState: .blocked,
            blockedConflictID: "conflict-1"
        )

        let gate = ShuttleIntegrationGateService(
            config: fixture.config,
            shardStore: fixture.shardStore,
            completionReportStore: fixture.completionReportStore,
            repositoryStateStore: fixture.repositoryStateStore
        )
        try fixture.completionReportStore.save(
            ShuttleCompletionReport(
                shardID: fixture.shard.id,
                summary: "Ready",
                filesChanged: ["README.md"],
                checks: [.init(name: "swift test", status: "passed", kind: "validation_command")],
                risks: [],
                createdAt: Date()
            )
        )

        XCTAssertThrowsError(try gate.validate(shardID: fixture.shard.id)) { error in
            XCTAssertEqual(error as? ShuttleIntegrationGateError, .repositoryNotOpen(.blocked))
        }
    }

    func testSquashMergeFailureCreatesConflictAndLeavesRepositoryBlocked() throws {
        let fixture = try makeFixture()
        try fixture.shardStore.updateState(shardID: fixture.shard.id, to: .integrating)
        try fixture.completionReportStore.save(
            ShuttleCompletionReport(
                shardID: fixture.shard.id,
                summary: "Ready",
                filesChanged: ["README.md"],
                checks: [.init(name: "swift test", status: "passed", kind: "validation_command")],
                risks: [],
                createdAt: Date()
            )
        )

        try commitShardChange(
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

        XCTAssertThrowsError(try fixture.mergeService.merge(shardID: fixture.shard.id)) { error in
            guard case let .conflictRecorded(conflictID) = error as? ShuttleSquashMergeServiceError else {
                return XCTFail("Expected conflictRecorded error, got \(error)")
            }
            XCTAssertFalse(conflictID.isEmpty)
        }

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .blocked)
        XCTAssertNotNil(repoState.blockedConflictID)

        let conflicts = try fixture.conflictStore.fetchOpenConflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].kind, "shard_merge")
    }

    func testResolveOneOfMultipleConflictsKeepsRepositoryBlocked() throws {
        let fixture = try makeFixture()
        let first = try fixture.conflictService.recordUpstreamRefreshConflict(
            details: ["reason": "merge_conflict", "upstream_ref": "origin/main"]
        )
        let second = try fixture.conflictService.recordShardMergeConflict(
            sourceShardID: fixture.shard.id,
            details: ["reason": "branch_not_mergeable"]
        )

        let resolved = try fixture.conflictService.resolveConflict(conflictID: first.id)
        XCTAssertEqual(resolved.state, "resolved")

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .blocked)
        XCTAssertEqual(repoState.blockedConflictID, second.id)
    }

    func testResolveLastOpenConflictReopensRepositoryAndAuditsResolution() throws {
        let fixture = try makeFixture()
        let conflict = try fixture.conflictService.recordUpstreamRefreshConflict(
            details: ["reason": "merge_conflict", "upstream_ref": "origin/main"]
        )

        let resolved = try fixture.conflictService.resolveConflict(
            conflictID: conflict.id,
            resolutionShardID: fixture.shard.id
        )

        XCTAssertEqual(resolved.state, "resolved")
        XCTAssertEqual(resolved.resolutionShardID, fixture.shard.id)

        let repoState = try XCTUnwrap(fixture.repositoryStateStore.fetch())
        XCTAssertEqual(repoState.integrationState, .open)
        XCTAssertNil(repoState.blockedConflictID)

        let events = try fixture.auditEventStore.fetchAll()
        XCTAssertTrue(
            events.contains(where: {
                $0.entityType == "conflict" &&
                $0.entityID == conflict.id &&
                $0.eventType == "conflict_resolved" &&
                $0.payload["resolution_shard_id"] == fixture.shard.id
            })
        )
    }

    private func makeFixture(
        repositoryValidator: ShuttleConflictRepositoryValidator = .live
    ) throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("conflicts", isDirectory: true)
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
            id: "shard-conflict-abcdef12",
            title: "Conflict shard",
            spec: "Conflict shard",
            branchName: "shuttle/shards/conflict-shard-abcdef12"
        )

        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        try repositoryStateStore.upsert(config: config, integrationState: .open)
        let completionReportStore = ShuttleCompletionReportStore(dbQueue: dbQueue)
        let conflictStore = ShuttleConflictStore(dbQueue: dbQueue)
        let auditEventStore = ShuttleAuditEventStore(dbQueue: dbQueue)
        let conflictService = ShuttleConflictService(
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            config: config,
            auditEventStore: auditEventStore,
            repositoryValidator: repositoryValidator
        )
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
            conflictService: conflictService
        )

        return Fixture(
            config: config,
            shard: shard,
            worktreeURL: URL(fileURLWithPath: shard.worktreePath, isDirectory: true),
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            conflictService: conflictService,
            auditEventStore: auditEventStore,
            mergeService: mergeService
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
    let shard: ShuttleShardWorkspace
    let worktreeURL: URL
    let bareRepositoryPath: String
    let shardStore: ShuttleShardStore
    let completionReportStore: ShuttleCompletionReportStore
    let repositoryStateStore: ShuttleRepositoryStateStore
    let conflictStore: ShuttleConflictStore
    let conflictService: ShuttleConflictService
    let auditEventStore: ShuttleAuditEventStore
    let mergeService: ShuttleSquashMergeService
}
