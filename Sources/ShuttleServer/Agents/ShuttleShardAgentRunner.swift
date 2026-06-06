import Foundation
import PositronicKit
import PKShared

enum ShuttleShardAgentRunnerError: Error, Equatable, Sendable {
    case shardNotFound(String)
    case missingRuntimeMetadata(String)
    case invalidShardState(String)
    case missingInstructions(String)
}

struct ShuttleShardAgentRunResult: Sendable {
    let timelineID: UUID
    let events: [ChatEvent]
}

struct ShuttleShardAgentRunner {
    let config: ShuttleConfig
    let shardStore: ShuttleShardStore
    let commandService: ShuttleShardCommandExecutionService
    let lifecycleService: ShuttleShardLifecycleService
    let transcriptStore: ShuttleAgentTranscriptStore
    let llmService: any LLMServiceProtocol
    let auditEventStore: ShuttleAuditEventStore?

    init(
        config: ShuttleConfig,
        shardStore: ShuttleShardStore,
        commandService: ShuttleShardCommandExecutionService,
        lifecycleService: ShuttleShardLifecycleService,
        transcriptStore: ShuttleAgentTranscriptStore,
        llmService: any LLMServiceProtocol,
        auditEventStore: ShuttleAuditEventStore? = nil
    ) {
        self.config = config
        self.shardStore = shardStore
        self.commandService = commandService
        self.lifecycleService = lifecycleService
        self.transcriptStore = transcriptStore
        self.llmService = llmService
        self.auditEventStore = auditEventStore
    }

    func runShard(
        shardID: String,
        maxTurns: Int = 5
    ) async throws -> ShuttleShardAgentRunResult {
        let shard = try requireShard(id: shardID)
        let runtimeMetadata = try requireRuntimeMetadata(shardID: shardID)
        try moveToRunningIfNeeded(shard: shard)

        let tools = ShuttleShardWorkspaceToolFactory.makeAllTools(
            shardID: shardID,
            worktreePath: runtimeMetadata.worktreePath,
            commandService: commandService,
            lifecycleService: lifecycleService
        )
        let systemInstructions = try buildSystemInstructions(
            shardID: shardID,
            worktreePath: runtimeMetadata.worktreePath
        )
        let timelineID = UUID()

        let messageStore = InMemoryMessageStore()
        let timelineStore = InMemoryTimelinePersistence()
        let workspaceStore = InMemoryWorkspacePersistence()
        let memoryStore = InMemoryMemoryStore()
        let toolStore = InMemoryToolPersistence()
        let agentInstanceStore = InMemoryAgentInstanceStore()
        let requestOriginStore = InMemoryRequestOriginStore()
        let agentTemplateStore = InMemoryAgentTemplateStore()

        let workspaceID = UUID()
        let workspace = WorkspaceReference(
            id: workspaceID,
            uri: WorkspaceURI(parsing: "pk://shuttle/shards/\(shardID)")!,
            location: .runtimeTimeline,
            tools: tools.map(\.toolReference),
            rootPath: runtimeMetadata.worktreePath,
            trustLevel: .full,
            metadata: [
                "shard_id": AnyCodable(shardID),
                "branch_name": AnyCodable(runtimeMetadata.branchName),
            ],
            contextInjection: "All shard tools are scoped to the shard working directory."
        )
        try await workspaceStore.saveWorkspace(workspace)
        try await timelineStore.saveTimeline(
            Timeline(
                id: timelineID,
                title: shard.title,
                workingDirectory: runtimeMetadata.worktreePath,
                attachedWorkspaceIds: [workspaceID]
            )
        )

        let runtime = PositronicKitCore(
            llmService: llmService,
            messageStore: messageStore,
            agentInstanceStore: agentInstanceStore,
            requestOriginStore: requestOriginStore,
            timelinePersistence: timelineStore,
            workspacePersistence: workspaceStore,
            memoryStore: memoryStore,
            toolPersistence: toolStore,
            agentTemplateStore: agentTemplateStore,
            workspaceRoot: URL(fileURLWithPath: runtimeMetadata.worktreePath, isDirectory: true)
        )

        let stream = try await runtime.run(
            timelineId: timelineID,
            message: shard.spec,
            tools: tools,
            systemInstructions: systemInstructions,
            maxTurns: maxTurns
        )

        var events: [ChatEvent] = []
        for try await event in stream {
            events.append(event)
            try transcriptStore.append(shardID: shardID, event: event)
        }

        return ShuttleShardAgentRunResult(
            timelineID: timelineID,
            events: events
        )
    }

    private func requireShard(id: String) throws -> ShuttleStoredShard {
        guard let shard = try shardStore.fetchShard(id: id) else {
            throw ShuttleShardAgentRunnerError.shardNotFound(id)
        }
        return shard
    }

    private func requireRuntimeMetadata(shardID: String) throws -> ShuttleStoredShardRuntimeMetadata {
        guard let runtimeMetadata = try shardStore.fetchRuntimeMetadata(shardID: shardID) else {
            throw ShuttleShardAgentRunnerError.missingRuntimeMetadata(shardID)
        }
        return runtimeMetadata
    }

    private func moveToRunningIfNeeded(shard: ShuttleStoredShard) throws {
        switch shard.state {
        case .queued:
            try shardStore.updateState(shardID: shard.id, to: .running)
        case .running, .needsInput, .integrating:
            break
        case .done, .failed, .abandoned:
            throw ShuttleShardAgentRunnerError.invalidShardState(shard.state.rawValue)
        }
    }

    private func buildSystemInstructions(
        shardID: String,
        worktreePath: String
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: config.instructions.filePath) else {
            throw ShuttleShardAgentRunnerError.missingInstructions(config.instructions.filePath)
        }

        let deploymentInstructions = try String(contentsOfFile: config.instructions.filePath, encoding: .utf8)
        let agentsPath = URL(fileURLWithPath: worktreePath, isDirectory: true)
            .appendingPathComponent("AGENTS.md")
            .path
        let repositoryGuidance: String?
        if FileManager.default.fileExists(atPath: agentsPath) {
            repositoryGuidance = try String(contentsOfFile: agentsPath, encoding: .utf8)
        } else {
            repositoryGuidance = nil
        }

        var sections = [
            """
            Shuttle deployment instructions:
            \(deploymentInstructions)
            """,
            """
            Shard execution rules:
            - Use only the provided shard tools.
            - All file, git, and command actions are scoped to the shard working directory.
            - Use `finish_shard` when the shard is complete, or `request_input` when blocked.
            """,
        ]
        if let repositoryGuidance, !repositoryGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(
                """
                Repository guidance from AGENTS.md:
                \(repositoryGuidance)
                """
            )
        }

        if let auditEventStore,
           let pendingInstructions = try? auditEventStore.fetchPendingSystemInstructions(shardID: shardID),
           !pendingInstructions.isEmpty {
            sections.append(
                """
                Pending system instructions:
                \(pendingInstructions.joined(separator: "\n"))
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }
}
