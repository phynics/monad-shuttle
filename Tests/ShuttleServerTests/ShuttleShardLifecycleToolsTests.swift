import Foundation
import GRDB
import PKShared
import XCTest
@testable import ShuttleServer

final class ShuttleShardLifecycleToolsTests: XCTestCase {
    func testFinishShardRequiresStructuredCompletionReportWithValidationStatuses() async throws {
        let fixture = try makeFixture()
        let tools = makeLifecycleTools(fixture: fixture, shardID: fixture.runningShardID)
        let toolByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })

        let invalid = try await XCTUnwrap(toolByID["finish_shard"]).execute(parameters: [
            "summary": "Done",
            "files_changed": ["Sources/App.swift"],
            "checks": [["name": "swift test", "status": "passed", "kind": "check"]],
            "risks": [],
        ])
        XCTAssertFalse(invalid.success)

        let shardAfterInvalid = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.runningShardID))
        XCTAssertEqual(shardAfterInvalid.state, .running)
        XCTAssertNil(try fixture.completionReportStore.fetch(shardID: fixture.runningShardID))

        let valid = try await XCTUnwrap(toolByID["finish_shard"]).execute(parameters: [
            "summary": "Implemented lifecycle tools",
            "files_changed": ["Sources/ShuttleServer/Tools/ShuttleShardLifecycleTools.swift"],
            "checks": [
                ["name": "swift test --filter ShuttleShardLifecycleToolsTests", "status": "passed", "kind": "validation_command"],
                ["name": "swift test", "status": "passed", "kind": "check"],
            ],
            "risks": ["Merge flow still pending"],
        ])
        XCTAssertTrue(valid.success)

        let completionReport = try XCTUnwrap(fixture.completionReportStore.fetch(shardID: fixture.runningShardID))
        XCTAssertEqual(completionReport.summary, "Implemented lifecycle tools")
        XCTAssertEqual(completionReport.filesChanged, ["Sources/ShuttleServer/Tools/ShuttleShardLifecycleTools.swift"])
        XCTAssertEqual(completionReport.checks.count, 2)
        XCTAssertEqual(completionReport.validationStatuses.count, 1)

        let storedShard = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.runningShardID))
        XCTAssertEqual(storedShard.state, .integrating)

        let auditEvents = try fixture.auditStore.fetchAll().filter { $0.entityID == fixture.runningShardID }
        XCTAssertTrue(auditEvents.contains(where: { $0.eventType == "shard_finish_requested" }))
    }

    func testRequestInputMovesShardToNeedsInputAndRecordsAuditEvent() async throws {
        let fixture = try makeFixture()
        let tools = makeLifecycleTools(fixture: fixture, shardID: fixture.runningShardID)
        let toolByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })

        let result = try await XCTUnwrap(toolByID["request_input"]).execute(parameters: [
            "question": "Which push target should I use?",
            "details": "The shard is ready, but the remote target is not specified.",
        ])
        XCTAssertTrue(result.success)

        let storedShard = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.runningShardID))
        XCTAssertEqual(storedShard.state, .needsInput)

        let auditEvents = try fixture.auditStore.fetchAll().filter { $0.entityID == fixture.runningShardID }
        XCTAssertTrue(auditEvents.contains(where: {
            $0.eventType == "shard_input_requested"
                && $0.payload["question"] == "Which push target should I use?"
        }))
    }

    func testAbandonShardMovesShardToAbandonedAndRecordsAuditEvent() async throws {
        let fixture = try makeFixture()
        let tools = makeLifecycleTools(fixture: fixture, shardID: fixture.runningShardID)
        let toolByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })

        let result = try await XCTUnwrap(toolByID["abandon_shard"]).execute(parameters: [
            "reason": "Superseded by operator decision",
        ])
        XCTAssertTrue(result.success)

        let storedShard = try XCTUnwrap(fixture.shardStore.fetchShard(id: fixture.runningShardID))
        XCTAssertEqual(storedShard.state, .abandoned)

        let auditEvents = try fixture.auditStore.fetchAll().filter { $0.entityID == fixture.runningShardID }
        XCTAssertTrue(auditEvents.contains(where: {
            $0.eventType == "shard_abandoned"
                && $0.payload["reason"] == "Superseded by operator decision"
        }))
    }

    func testWorkspaceFactoryCanIncludeLifecycleTools() async throws {
        let fixture = try makeFixture()
        let commandService = try makeCommandService(fixture: fixture)
        let tools = ShuttleShardWorkspaceToolFactory.makeAllTools(
            shardID: fixture.runningShardID,
            worktreePath: fixture.root.appendingPathComponent("worktree").path,
            commandService: commandService,
            lifecycleService: fixture.lifecycleService
        )

        let toolIDs = Set(tools.map(\.id))
        XCTAssertTrue(toolIDs.contains("finish_shard"))
        XCTAssertTrue(toolIDs.contains("request_input"))
        XCTAssertTrue(toolIDs.contains("abandon_shard"))
    }

    private func makeLifecycleTools(
        fixture: Fixture,
        shardID: String
    ) -> [AnyTool] {
        ShuttleShardLifecycleToolFactory.makeLifecycleTools(
            shardID: shardID,
            lifecycleService: fixture.lifecycleService
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databasePath = root.appendingPathComponent("shuttle.sqlite").path
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let shardStore = ShuttleShardStore(dbQueue: dbQueue)
        let completionReportStore = ShuttleCompletionReportStore(dbQueue: dbQueue)
        let auditStore = ShuttleAuditEventStore(dbQueue: dbQueue)

        try shardStore.createQueuedShard(
            id: "shard-lifecycle-running",
            title: "Lifecycle shard",
            spec: "Lifecycle shard spec",
            baseCommit: "abc123",
            branchName: "shuttle/shards/lifecycle-shard",
            worktreePath: root.appendingPathComponent("worktree").path
        )
        try shardStore.updateState(
            shardID: "shard-lifecycle-running",
            to: .running
        )

        return Fixture(
            root: root,
            shardStore: shardStore,
            completionReportStore: completionReportStore,
            auditStore: auditStore,
            lifecycleService: ShuttleShardLifecycleService(
                shardStore: shardStore,
                completionReportStore: completionReportStore,
                auditEventStore: auditStore
            ),
            runningShardID: "shard-lifecycle-running"
        )
    }

    private func makeCommandService(fixture: Fixture) throws -> ShuttleShardCommandExecutionService {
        ShuttleShardCommandExecutionService(
            shardStore: fixture.shardStore,
            dockerAccessController: ShuttleDockerAccessController(
                client: ShuttleDockerClient(
                    probeAvailability: { .available(detail: "available") },
                    createContainer: { _ in fatalError("unused") },
                    inspectContainer: { _ in nil },
                    stopContainer: { _ in },
                    execInContainer: { _ in fatalError("unused") }
                ),
                statusStore: ShuttleServerStatusStore()
            ),
            commandLogStore: ShuttleCommandLogStore(
                dbQueue: fixture.shardStore.dbQueue,
                logsRootPath: fixture.root.appendingPathComponent("logs").path,
                retentionDays: 7,
                maxBytesPerFile: 1_024
            ),
            config: ShuttleConfig(
                repository: .init(url: "test", sourceBranch: "main", sshKeyPath: "/tmp/key"),
                runtime: .init(
                    containerImage: "test-image",
                    containerWorkdir: "/workspace",
                    commandPolicy: .init(allow: ["git"], deny: [])
                ),
                refresh: .init(schedule: "0 * * * *"),
                retention: .init(worktreeDays: 7, rawLogsDays: 7, rawLogsMaxBytes: 1_024),
                limits: .init(maxRunningShards: 1, maxIntegratingShards: 1, maxQueuedShards: 1, maxLogBytesPerShard: 1_024),
                paths: .init(
                    databasePath: fixture.root.appendingPathComponent("shuttle.sqlite").path,
                    gitPath: fixture.root.appendingPathComponent("git").path,
                    worktreesPath: fixture.root.appendingPathComponent("worktrees").path,
                    logsPath: fixture.root.appendingPathComponent("logs").path
                ),
                pushTargets: [],
                auth: .init(mode: .localAdmin),
                instructions: .init(filePath: "/tmp/instructions.md"),
                server: .init(host: "127.0.0.1", port: 8080)
            )
        )
    }
}

private struct Fixture {
    let root: URL
    let shardStore: ShuttleShardStore
    let completionReportStore: ShuttleCompletionReportStore
    let auditStore: ShuttleAuditEventStore
    let lifecycleService: ShuttleShardLifecycleService
    let runningShardID: String
}
