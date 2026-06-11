import Foundation
import XCTest
import GRDB
import PKShared
@testable import ShuttleServer

final class ShuttleRetentionCleanupServiceTests: XCTestCase {
    func testCleanupRemovesExpiredRetainedWorktreeAndBranchButKeepsMetadata() throws {
        let fixture = try makeFixture()
        let shard = try fixture.workspaceService.createQueuedShard(
            id: "shard-cleanup-expired",
            title: "Expired retained shard",
            spec: "Expired retained shard",
            branchName: "shuttle/shards/cleanup-expired"
        )
        let expiredAt = Date(timeIntervalSince1970: 1_800_000_000)
        try fixture.workspaceService.retainDoneShard(shardID: shard.id, retainedUntil: expiredAt)

        XCTAssertTrue(FileManager.default.fileExists(atPath: shard.worktreePath))
        XCTAssertTrue(fixture.worktreeManager.branchExists(branchName: shard.branchName))

        let result = try fixture.cleanupService.cleanup(now: expiredAt.addingTimeInterval(1))

        XCTAssertEqual(result.cleanedShardCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shard.worktreePath))
        XCTAssertFalse(fixture.worktreeManager.branchExists(branchName: shard.branchName))

        let storedShard = try XCTUnwrap(fixture.shardStore.fetchShard(id: shard.id))
        let runtime = try XCTUnwrap(fixture.shardStore.fetchRuntimeMetadata(shardID: shard.id))
        XCTAssertEqual(storedShard.state, .done)
        XCTAssertEqual(runtime.branchName, shard.branchName)
        XCTAssertEqual(runtime.worktreePath, shard.worktreePath)

        let events = try fixture.auditStore.fetchAll()
        XCTAssertTrue(events.contains {
            $0.entityType == "shard"
                && $0.entityID == shard.id
                && $0.eventType == "shard_retention_cleaned"
                && $0.payload["worktree_removed"] == "true"
                && $0.payload["branch_removed"] == "true"
        })
    }

    func testCleanupLeavesUnexpiredRetainedShardUntouched() throws {
        let fixture = try makeFixture()
        let shard = try fixture.workspaceService.createQueuedShard(
            id: "shard-cleanup-unexpired",
            title: "Unexpired retained shard",
            spec: "Unexpired retained shard",
            branchName: "shuttle/shards/cleanup-unexpired"
        )
        let retainedUntil = Date(timeIntervalSince1970: 1_800_000_100)
        try fixture.workspaceService.retainDoneShard(shardID: shard.id, retainedUntil: retainedUntil)

        let result = try fixture.cleanupService.cleanup(now: retainedUntil.addingTimeInterval(-1))

        XCTAssertEqual(result.cleanedShardCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shard.worktreePath))
        XCTAssertTrue(fixture.worktreeManager.branchExists(branchName: shard.branchName))
    }

    func testCleanupDeletesExpiredCommandAndAgentLogs() throws {
        let fixture = try makeFixture()
        let oldDate = Date(timeIntervalSince1970: 1_800_000_000)

        try insertShard(id: "shard-log-cleanup", dbQueue: fixture.dbQueue)
        try fixture.commandLogStore.append(
            ShuttleCommandLogEntry(
                shardID: "shard-log-cleanup",
                command: ["swift", "test"],
                stdout: "old",
                stderr: "",
                exitCode: 0,
                startedAt: oldDate.addingTimeInterval(-1),
                endedAt: oldDate,
                toolName: nil
            )
        )
        try fixture.agentTranscriptStore.append(
            shardID: "shard-log-cleanup",
            event: .delta(event: .generation(text: "old transcript")),
            recordedAt: oldDate
        )

        let result = try fixture.cleanupService.cleanup(now: oldDate.addingTimeInterval(Double(8 * 24 * 60 * 60)))

        XCTAssertEqual(result.deletedCommandLogIndexCount, 1)
        XCTAssertEqual(result.deletedCommandLogFileCount, 1)
        XCTAssertEqual(result.deletedAgentLogIndexCount, 1)
        XCTAssertEqual(result.deletedAgentLogFileCount, 1)

        let remainingIndexes: Int = try fixture.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM log_indexes WHERE shard_id = ?", arguments: ["shard-log-cleanup"]) ?? 0
        }
        XCTAssertEqual(remainingIndexes, 0)
    }

    private func makeFixture() throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("retention-cleanup", isDirectory: true)
        let databaseRoot = root.appendingPathComponent("database", isDirectory: true)
        let gitRoot = root.appendingPathComponent("git", isDirectory: true)
        let worktreesRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        let logsRoot = root.appendingPathComponent("logs", isDirectory: true)

        try FileManager.default.createDirectory(at: databaseRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)

        let config = ShuttleConfig(
            repository: .init(
                url: gitFixture.originBareRepository.path,
                sourceBranch: gitFixture.branch,
                sshKeyPath: "/tmp/unused-key"
            ),
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
            instructions: .init(filePath: "/tmp/instructions.md"),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)

        let dbQueue = try ShuttleDatabase.openMigrated(atPath: config.paths.databasePath)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let worktreeManager = ShuttleWorktreeManager(
            bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
            worktreesRootPath: config.paths.worktreesPath
        )
        let workspaceService = ShuttleShardWorkspaceService(
            shardStore: shardStore,
            worktreeManager: worktreeManager
        )
        let auditStore = ShuttleAuditEventStore(dbQueue: dbQueue)
        let commandLogStore = ShuttleCommandLogStore(
            dbQueue: dbQueue,
            logsRootPath: config.paths.logsPath,
            retentionDays: config.retention.rawLogsDays,
            maxBytesPerFile: config.retention.rawLogsMaxBytes
        )
        let agentTranscriptStore = ShuttleAgentTranscriptStore(
            dbQueue: dbQueue,
            logsRootPath: config.paths.logsPath,
            retentionDays: config.retention.rawLogsDays,
            maxBytesPerFile: config.retention.rawLogsMaxBytes
        )

        return Fixture(
            dbQueue: dbQueue,
            shardStore: shardStore,
            worktreeManager: worktreeManager,
            workspaceService: workspaceService,
            auditStore: auditStore,
            commandLogStore: commandLogStore,
            agentTranscriptStore: agentTranscriptStore,
            cleanupService: ShuttleRetentionCleanupService(
                config: config,
                shardStore: shardStore,
                auditEventStore: auditStore,
                worktreeManager: worktreeManager,
                commandLogStore: commandLogStore,
                agentTranscriptStore: agentTranscriptStore
            )
        )
    }

    private func insertShard(id: String, dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            try db.execute(
                sql: """
                INSERT INTO shards (id, title, spec, state, base_commit, retained_until, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id,
                    "Test shard",
                    "Test shard spec",
                    ShuttleShardState.done.rawValue,
                    "deadbeef",
                    now,
                    now,
                    now,
                ]
            )
        }
    }
}

private struct Fixture {
    let dbQueue: DatabaseQueue
    let shardStore: ShuttleShardStore
    let worktreeManager: ShuttleWorktreeManager
    let workspaceService: ShuttleShardWorkspaceService
    let auditStore: ShuttleAuditEventStore
    let commandLogStore: ShuttleCommandLogStore
    let agentTranscriptStore: ShuttleAgentTranscriptStore
    let cleanupService: ShuttleRetentionCleanupService
}
