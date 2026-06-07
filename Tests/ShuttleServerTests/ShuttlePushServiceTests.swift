import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttlePushServiceTests: XCTestCase {
    func testPushShuttleMainToConfiguredTarget() throws {
        let fixture = try makeFixture()
        _ = try fixture.gitFixture.addCommitAndPush(
            fileName: "CHANGELOG.md",
            contents: "upstream change\n",
            commitMessage: "Update upstream"
        )
        let refreshResult = try fixture.refreshService.refresh()

        let result = try fixture.pushService.push(
            targetName: "origin-main",
            ref: .shuttleMain,
            idempotencyKey: "push-1",
            actor: ShuttleActorIdentity(actorType: "api_client", actorID: "client-1")
        )

        XCTAssertEqual(result.targetName, "origin-main")
        XCTAssertEqual(result.localRef, "refs/heads/shuttle-main")
        XCTAssertEqual(result.remoteRef, "refs/heads/published-main")
        XCTAssertEqual(result.warnings, [])

        let remoteCommit = try ShuttleGitShell.run(
            ["rev-parse", "published-main"],
            workingDirectory: fixture.gitFixture.originBareRepository.path
        ).stdout
        XCTAssertEqual(remoteCommit, refreshResult.shuttleMainCommit)
    }

    func testPushRejectsUnconfiguredTarget() throws {
        let fixture = try makeFixture()

        XCTAssertThrowsError(
            try fixture.pushService.push(
                targetName: "missing",
                ref: .shuttleMain,
                idempotencyKey: "push-2",
                actor: nil
            )
        ) { error in
            XCTAssertEqual(error as? ShuttlePushServiceError, .targetNotConfigured("missing"))
        }
    }

    func testPushReplaysDuplicateIdempotencyKey() throws {
        let fixture = try makeFixture()

        let first = try fixture.pushService.push(
            targetName: "origin-main",
            ref: .shuttleMain,
            idempotencyKey: "push-3",
            actor: nil
        )
        let second = try fixture.pushService.push(
            targetName: "origin-main",
            ref: .shuttleMain,
            idempotencyKey: "push-3",
            actor: nil
        )

        XCTAssertEqual(second, first)
    }

    func testPushIncludesWarningMetadataWhenRepositoryBlocked() throws {
        let fixture = try makeFixture()
        try fixture.repositoryStateStore.upsert(
            config: fixture.config,
            integrationState: .blocked,
            blockedConflictID: "conflict-1"
        )

        let result = try fixture.pushService.push(
            targetName: "origin-main",
            ref: .shuttleMain,
            idempotencyKey: "push-4",
            actor: ShuttleActorIdentity(actorType: "api_client", actorID: "client-2")
        )

        XCTAssertEqual(result.warnings, ["repository_state:blocked"])

        let events = try fixture.auditEventStore.fetchAll()
        XCTAssertTrue(
            events.contains(where: {
                $0.entityType == "push" &&
                $0.entityID == "push-4" &&
                $0.payload["warnings"] == "repository_state:blocked"
            })
        )
    }

    private func makeFixture() throws -> Fixture {
        let gitFixture = try ShuttleGitTestFixture.create()
        let root = gitFixture.root.appendingPathComponent("push", isDirectory: true)
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
            pushTargets: [
                .init(name: "origin-main", remote: "origin", branch: "published-main"),
            ],
            auth: .init(mode: .localAdmin),
            instructions: .init(filePath: instructionsPath),
            server: .init(host: "127.0.0.1", port: 8080)
        )

        _ = try ShuttleRepositoryBootstrapper.bootstrap(config: config)
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: config.paths.databasePath)
        let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: dbQueue)
        try repositoryStateStore.upsert(config: config, integrationState: .open)
        let conflictStore = ShuttleConflictStore(dbQueue: dbQueue)
        let auditEventStore = ShuttleAuditEventStore(dbQueue: dbQueue)
        let conflictService = ShuttleConflictService(
            repositoryStateStore: repositoryStateStore,
            conflictStore: conflictStore,
            config: config,
            auditEventStore: auditEventStore
        )
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let idempotencyStore = ShuttleIdempotencyStore(dbQueue: dbQueue)

        return Fixture(
            config: config,
            gitFixture: gitFixture,
            repositoryStateStore: repositoryStateStore,
            auditEventStore: auditEventStore,
            refreshService: ShuttleUpstreamRefreshService(
                config: config,
                repositoryStateStore: repositoryStateStore,
                conflictService: conflictService
            ),
            pushService: ShuttlePushService(
                config: config,
                repositoryStateStore: repositoryStateStore,
                shardStore: shardStore,
                idempotencyStore: idempotencyStore,
                auditEventStore: auditEventStore
            )
        )
    }
}

private struct Fixture {
    let config: ShuttleConfig
    let gitFixture: ShuttleGitTestFixture
    let repositoryStateStore: ShuttleRepositoryStateStore
    let auditEventStore: ShuttleAuditEventStore
    let refreshService: ShuttleUpstreamRefreshService
    let pushService: ShuttlePushService
}
