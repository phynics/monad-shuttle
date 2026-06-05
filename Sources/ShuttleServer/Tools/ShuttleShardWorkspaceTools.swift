import Foundation
import PKShared

enum ShuttleShardWorkspaceToolFactory {
    static func makeFilesystemTools(worktreePath: String) -> [AnyTool] {
        [
            AnyTool(ReadFileTool(currentDirectory: worktreePath, jailRoot: worktreePath)),
            AnyTool(ListDirectoryTool(currentDirectory: worktreePath, jailRoot: worktreePath)),
            AnyTool(FindFileTool(currentDirectory: worktreePath, jailRoot: worktreePath)),
            AnyTool(SearchFileContentTool(currentDirectory: worktreePath, jailRoot: worktreePath)),
            AnyTool(SearchFilesTool(currentDirectory: worktreePath, jailRoot: worktreePath)),
            AnyTool(ShuttleWriteFileTool(worktreePath: worktreePath)),
            AnyTool(ShuttleDeleteFileTool(worktreePath: worktreePath)),
        ]
    }

    static func makeGitTools(
        shardID: String,
        commandService: ShuttleShardCommandExecutionService
    ) -> [AnyTool] {
        [
            AnyTool(ShuttleGitStatusTool(shardID: shardID, commandService: commandService)),
            AnyTool(ShuttleGitDiffTool(shardID: shardID, commandService: commandService)),
            AnyTool(ShuttleGitLogTool(shardID: shardID, commandService: commandService)),
        ]
    }

    static func makeAllTools(
        shardID: String,
        worktreePath: String,
        commandService: ShuttleShardCommandExecutionService
    ) -> [AnyTool] {
        makeFilesystemTools(worktreePath: worktreePath)
            + makeGitTools(shardID: shardID, commandService: commandService)
    }
}

struct ShuttleWriteFileTool: Tool, Sendable {
    let id = "write_file"
    let name = "Write File"
    let description = "Write UTF-8 text to a file inside the shard workspace"
    let requiresPermission = true
    let usageExample: String? = """
    <tool_call>
    {"name": "write_file", "arguments": {"path": "Sources/New.swift", "content": "struct New {}\\n"}}
    </tool_call>
    """

    private let worktreePath: String

    init(worktreePath: String) {
        self.worktreePath = worktreePath
    }

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        objectSchema(
            properties: [
                "path": stringSchema("The file path to write, relative to the shard workspace"),
                "content": stringSchema("The UTF-8 text content to write"),
            ],
            required: ["path", "content"]
        )
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let path: String
        let content: String
        do {
            path = try params.require("path", as: String.self)
            content = try params.require("content", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        let url: URL
        do {
            url = try PathSanitizer.safelyResolve(
                path: path,
                within: worktreePath,
                jailRoot: worktreePath
            )
        } catch {
            return .failure(error.localizedDescription)
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .failure("Path is a directory: \(path)")
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return .success("Wrote \(content.utf8.count) bytes to \(relativePath(for: url))")
        } catch {
            return .failure("Failed to write file: \(error.localizedDescription)")
        }
    }

    private func relativePath(for url: URL) -> String {
        url.path
            .replacingOccurrences(of: URL(fileURLWithPath: worktreePath).standardizedFileURL.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct ShuttleDeleteFileTool: Tool, Sendable {
    let id = "delete_file"
    let name = "Delete File"
    let description = "Delete a file inside the shard workspace"
    let requiresPermission = true
    let usageExample: String? = """
    <tool_call>
    {"name": "delete_file", "arguments": {"path": "Sources/Old.swift"}}
    </tool_call>
    """

    private let worktreePath: String

    init(worktreePath: String) {
        self.worktreePath = worktreePath
    }

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        objectSchema(
            properties: [
                "path": stringSchema("The file path to delete, relative to the shard workspace"),
            ],
            required: ["path"]
        )
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let path: String
        do {
            path = try params.require("path", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        let url: URL
        do {
            url = try PathSanitizer.safelyResolve(
                path: path,
                within: worktreePath,
                jailRoot: worktreePath
            )
        } catch {
            return .failure(error.localizedDescription)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure("File not found: \(path)")
        }
        guard !isDirectory.boolValue else {
            return .failure("Path is a directory: \(path)")
        }

        do {
            try FileManager.default.removeItem(at: url)
            return .success("Deleted \(path)")
        } catch {
            return .failure("Failed to delete file: \(error.localizedDescription)")
        }
    }
}

private struct ShuttleGitStatusTool: Tool, Sendable {
    let id = "git_status"
    let name = "Git Status"
    let description = "Show short git status for the shard workspace"
    let requiresPermission = false

    let shardID: String
    let commandService: ShuttleShardCommandExecutionService

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        objectSchema(properties: [:], required: [])
    }

    func execute(parameters _: [String: Any]) async throws -> ToolResult {
        try await runGitTool(
            shardID: shardID,
            toolName: id,
            command: ["git", "status", "--short"],
            commandService: commandService
        )
    }
}

private struct ShuttleGitDiffTool: Tool, Sendable {
    let id = "git_diff"
    let name = "Git Diff"
    let description = "Show git diff for the shard workspace"
    let requiresPermission = false

    let shardID: String
    let commandService: ShuttleShardCommandExecutionService

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        objectSchema(properties: [:], required: [])
    }

    func execute(parameters _: [String: Any]) async throws -> ToolResult {
        try await runGitTool(
            shardID: shardID,
            toolName: id,
            command: ["git", "diff", "--"],
            commandService: commandService
        )
    }
}

private struct ShuttleGitLogTool: Tool, Sendable {
    let id = "git_log"
    let name = "Git Log"
    let description = "Show recent git commits for the shard workspace"
    let requiresPermission = false

    let shardID: String
    let commandService: ShuttleShardCommandExecutionService

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        objectSchema(
            properties: [
                "limit": [
                    "type": AnyCodable("integer"),
                    "description": AnyCodable("Maximum number of commits to show, default 20"),
                ],
            ],
            required: []
        )
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let limit = min(max(params.optional("limit", as: Int.self) ?? 20, 1), 100)
        return try await runGitTool(
            shardID: shardID,
            toolName: id,
            command: ["git", "log", "--oneline", "-\(limit)"],
            commandService: commandService
        )
    }
}

private func runGitTool(
    shardID: String,
    toolName: String,
    command: [String],
    commandService: ShuttleShardCommandExecutionService
) async throws -> ToolResult {
    let result = try await commandService.runNamedCommand(
        shardID: shardID,
        toolName: toolName,
        command: command
    )
    guard result.exitCode == 0 else {
        let error = result.stderr.isEmpty ? "Command failed with exit code \(result.exitCode)" : result.stderr
        return .failure(error)
    }
    return .success(result.stdout)
}

private func objectSchema(
    properties: [String: [String: AnyCodable]],
    required: [String]
) -> [String: AnyCodable] {
    [
        "type": AnyCodable("object"),
        "properties": AnyCodable(properties),
        "required": AnyCodable(required),
    ]
}

private func stringSchema(_ description: String) -> [String: AnyCodable] {
    [
        "type": AnyCodable("string"),
        "description": AnyCodable(description),
    ]
}
