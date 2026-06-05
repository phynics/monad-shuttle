import Foundation
import XCTest
import GRDB
import PKShared
@testable import ShuttleServer

final class ShuttleShardWorkspaceToolsTests: XCTestCase {
    func testFactoryProvidesScopedFilesystemAndGitTools() throws {
        let root = try makeWorktreeFixture()
        let tools = ShuttleShardWorkspaceToolFactory.makeFilesystemTools(worktreePath: root.worktree.path)
        let toolIDs = Set(tools.map(\.id))

        XCTAssertTrue(toolIDs.contains("cat"))
        XCTAssertTrue(toolIDs.contains("ls"))
        XCTAssertTrue(toolIDs.contains("find"))
        XCTAssertTrue(toolIDs.contains("grep"))
        XCTAssertTrue(toolIDs.contains("search_files"))
        XCTAssertTrue(toolIDs.contains("write_file"))
        XCTAssertTrue(toolIDs.contains("delete_file"))
    }

    func testReusedReadToolRejectsTraversalAbsoluteAndSymlinkEscapes() async throws {
        let root = try makeWorktreeFixture()
        let readTool = ReadFileTool(currentDirectory: root.worktree.path, jailRoot: root.worktree.path)

        let traversal = try await readTool.execute(parameters: ["path": "../outside.txt"])
        XCTAssertFalse(traversal.success)

        let absoluteOutside = try await readTool.execute(parameters: ["path": root.outsideFile.path])
        XCTAssertFalse(absoluteOutside.success)

        let symlinkEscape = try await readTool.execute(parameters: ["path": "outside-link.txt"])
        XCTAssertFalse(symlinkEscape.success)

        let inside = try await readTool.execute(parameters: ["path": "README.md"])
        XCTAssertTrue(inside.success)
        XCTAssertEqual(inside.output, "hello")
    }

    func testWriteAndDeleteToolsRejectEscapesAndOperateInsideWorktree() async throws {
        let root = try makeWorktreeFixture()
        let writeTool = ShuttleWriteFileTool(worktreePath: root.worktree.path)
        let deleteTool = ShuttleDeleteFileTool(worktreePath: root.worktree.path)

        let writeInside = try await writeTool.execute(parameters: [
            "path": "Sources/New.swift",
            "content": "struct New {}\n",
        ])
        XCTAssertTrue(writeInside.success)
        XCTAssertEqual(
            try String(contentsOf: root.worktree.appendingPathComponent("Sources/New.swift"), encoding: .utf8),
            "struct New {}\n"
        )

        let writeOutside = try await writeTool.execute(parameters: [
            "path": root.outsideFile.path,
            "content": "leak",
        ])
        XCTAssertFalse(writeOutside.success)
        XCTAssertEqual(try String(contentsOf: root.outsideFile, encoding: .utf8), "secret")

        let deleteOutside = try await deleteTool.execute(parameters: ["path": "outside-link.txt"])
        XCTAssertFalse(deleteOutside.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.outsideFile.path))

        let deleteInside = try await deleteTool.execute(parameters: ["path": "Sources/New.swift"])
        XCTAssertTrue(deleteInside.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.worktree.appendingPathComponent("Sources/New.swift").path))
    }

    func testGitToolsExecuteInsideShardContainerWorkdir() async throws {
        let fixture = try ShuttleGitTestFixture.create()
        let environment = try makeEnvironment(originURL: fixture.originBareRepository)
        let workspaceService = try makeWorkspaceService(config: environment.config, databasePath: environment.databasePath)
        let shard = try workspaceService.createQueuedShard(
            id: "shard-workspace-tools-abcdef12",
            title: "Workspace tools",
            spec: "Workspace tools",
            branchName: "shuttle/shards/workspace-tools-abcdef12"
        )

        let dockerBackend = FakeWorkspaceToolDockerBackend()
        let containerService = try await makeContainerService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        _ = try await containerService.createContainer(forShardID: shard.id)

        let commandService = try makeCommandService(
            config: environment.config,
            databasePath: environment.databasePath,
            dockerBackend: dockerBackend
        )
        let tools = ShuttleShardWorkspaceToolFactory.makeGitTools(
            shardID: shard.id,
            commandService: commandService
        )
        let toolByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })

        let status = try await XCTUnwrap(toolByID["git_status"]).execute(parameters: [:])
        let diff = try await XCTUnwrap(toolByID["git_diff"]).execute(parameters: [:])
        let log = try await XCTUnwrap(toolByID["git_log"]).execute(parameters: ["limit": 3])

        XCTAssertTrue(status.success)
        XCTAssertTrue(diff.success)
        XCTAssertTrue(log.success)

        let execCalls = await dockerBackend.execCallsSnapshot()
        XCTAssertEqual(execCalls.map(\.command), [
            ["git", "status", "--short"],
            ["git", "diff", "--"],
            ["git", "log", "--oneline", "-3"],
        ])
        XCTAssertEqual(Set(execCalls.map(\.workingDirectory)), [environment.config.runtime.containerWorkdir])
    }

    private func makeWorktreeFixture() throws -> (root: URL, worktree: URL, outsideFile: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worktree = root.appendingPathComponent("worktree", isDirectory: true)
        let sources = worktree.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "hello".write(to: worktree.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "secret".write(to: root.appendingPathComponent("outside.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: worktree.appendingPathComponent("outside-link.txt"),
            withDestinationURL: root.appendingPathComponent("outside.txt")
        )
        return (root, worktree, root.appendingPathComponent("outside.txt"))
    }

    private func makeWorkspaceService(
        config: ShuttleConfig,
        databasePath: String
    ) throws -> ShuttleShardWorkspaceService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        return ShuttleShardWorkspaceService(
            shardStore: ShuttleShardStore(dbQueue: dbQueue),
            worktreeManager: ShuttleWorktreeManager(
                bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: config),
                worktreesRootPath: config.paths.worktreesPath
            )
        )
    }

    private func makeContainerService(
        config: ShuttleConfig,
        databasePath: String,
        dockerBackend: FakeWorkspaceToolDockerBackend
    ) async throws -> ShuttleShardContainerService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let accessController = await makeDockerAccessController(dockerBackend: dockerBackend)
        return ShuttleShardContainerService(
            shardStore: ShuttleShardStore(dbQueue: dbQueue),
            dockerAccessController: accessController,
            config: config
        )
    }

    private func makeCommandService(
        config: ShuttleConfig,
        databasePath: String,
        dockerBackend: FakeWorkspaceToolDockerBackend
    ) throws -> ShuttleShardCommandExecutionService {
        let dbQueue = try ShuttleDatabase.openMigrated(atPath: databasePath)
        let accessController = ShuttleDockerAccessController(
            client: makeDockerClient(dockerBackend: dockerBackend),
            statusStore: ShuttleServerStatusStore()
        )
        let commandLogStore = ShuttleCommandLogStore(
            dbQueue: dbQueue,
            logsRootPath: config.paths.logsPath,
            retentionDays: config.retention.rawLogsDays,
            maxBytesPerFile: config.limits.maxLogBytesPerShard
        )
        return ShuttleShardCommandExecutionService(
            shardStore: ShuttleShardStore(dbQueue: dbQueue),
            dockerAccessController: accessController,
            commandLogStore: commandLogStore,
            config: config
        )
    }

    private func makeDockerAccessController(
        dockerBackend: FakeWorkspaceToolDockerBackend
    ) async -> ShuttleDockerAccessController {
        let accessController = ShuttleDockerAccessController(
            client: makeDockerClient(dockerBackend: dockerBackend),
            statusStore: ShuttleServerStatusStore()
        )
        _ = await accessController.probeHealth()
        return accessController
    }

    private func makeDockerClient(dockerBackend: FakeWorkspaceToolDockerBackend) -> ShuttleDockerClient {
        ShuttleDockerClient(
            probeAvailability: { .available(detail: "Docker socket accessible") },
            createContainer: { request in await dockerBackend.create(request: request) },
            inspectContainer: { name in await dockerBackend.inspectContainer(name: name) },
            stopContainer: { name in try await dockerBackend.stopContainer(name: name) },
            execInContainer: { request in try await dockerBackend.exec(request: request) }
        )
    }

    private func makeEnvironment(originURL: URL) throws -> (config: ShuttleConfig, databasePath: String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseRoot = root.appendingPathComponent("database", isDirectory: true)
        let gitRoot = root.appendingPathComponent("git", isDirectory: true)
        let worktreesRoot = root.appendingPathComponent("worktrees", isDirectory: true)
        let logsRoot = root.appendingPathComponent("logs", isDirectory: true)

        try FileManager.default.createDirectory(at: databaseRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreesRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)

        let config = ShuttleConfig(
            repository: .init(url: originURL.path, sourceBranch: "main", sshKeyPath: "/tmp/unused-key"),
            runtime: .init(
                containerImage: "ghcr.io/example/shuttle-runner:latest",
                containerWorkdir: "/workspace",
                commandPolicy: .init(allow: [], deny: ["rm"])
            ),
            refresh: .init(schedule: "0 * * * *"),
            retention: .init(worktreeDays: 7, rawLogsDays: 14, rawLogsMaxBytes: 10_485_760),
            limits: .init(maxRunningShards: 4, maxIntegratingShards: 1, maxQueuedShards: 32, maxLogBytesPerShard: 5_242_880),
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
        return (config, config.paths.databasePath)
    }
}

private actor FakeWorkspaceToolDockerBackend {
    private var containers: [String: ShuttleDockerContainerInspection] = [:]
    private var execCalls: [ShuttleDockerExecRequest] = []

    func create(request: ShuttleDockerCreateContainerRequest) -> ShuttleDockerContainerInspection {
        let inspection = ShuttleDockerContainerInspection(
            name: request.name,
            image: request.image,
            status: .running,
            mounts: request.mounts,
            workingDirectory: request.workingDirectory
        )
        containers[request.name] = inspection
        return inspection
    }

    func inspectContainer(name: String) -> ShuttleDockerContainerInspection? {
        containers[name]
    }

    func stopContainer(name: String) throws {
        guard let existing = containers[name] else {
            throw ShuttleDockerClientError.containerNotFound(name)
        }
        containers[name] = ShuttleDockerContainerInspection(
            name: existing.name,
            image: existing.image,
            status: .stopped,
            mounts: existing.mounts,
            workingDirectory: existing.workingDirectory
        )
    }

    func exec(request: ShuttleDockerExecRequest) throws -> ShuttleDockerExecResult {
        execCalls.append(request)
        return ShuttleDockerExecResult(
            stdout: request.command.joined(separator: " "),
            stderr: "",
            exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
    }

    func execCallsSnapshot() -> [ShuttleDockerExecRequest] {
        execCalls
    }
}

