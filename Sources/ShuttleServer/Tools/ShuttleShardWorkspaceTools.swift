import Foundation
import PKShared

enum ShuttleShardWorkspaceToolFactory {
    static func makeFilesystemTools(worktreePath: String) -> [AnyTool] {
        [
            AnyTool(ShuttleReadFileTool(worktreePath: worktreePath)),
            AnyTool(ShuttleListDirectoryTool(worktreePath: worktreePath)),
            AnyTool(ShuttleFindFileTool(worktreePath: worktreePath)),
            AnyTool(ShuttleSearchFileContentTool(worktreePath: worktreePath)),
            AnyTool(ShuttleSearchFilesTool(worktreePath: worktreePath)),
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

private struct ShuttleReadFileTool: Tool, Sendable {
    private let baseTool: ReadFileTool
    private let worktreePath: String

    init(worktreePath: String) {
        self.baseTool = ReadFileTool(currentDirectory: worktreePath, jailRoot: worktreePath)
        self.worktreePath = worktreePath
    }

    var id: String { baseTool.id }
    var name: String { baseTool.name }
    var description: String { baseTool.description }
    var requiresPermission: Bool { baseTool.requiresPermission }
    var usageExample: String? { baseTool.usageExample }
    var parametersSchema: [String: AnyCodable] { baseTool.parametersSchema }

    func canExecute() async -> Bool {
        await baseTool.canExecute()
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let path = ToolParameters(parameters).optional("path", as: String.self) ?? "."
        if let failure = ShuttleShardFilesystemGuard.validateReadablePath(path, worktreePath: worktreePath) {
            return failure
        }
        return try await baseTool.execute(parameters: parameters)
    }
}

private struct ShuttleListDirectoryTool: Tool, Sendable {
    private let baseTool: ListDirectoryTool
    private let worktreePath: String

    init(worktreePath: String) {
        self.baseTool = ListDirectoryTool(currentDirectory: worktreePath, jailRoot: worktreePath)
        self.worktreePath = worktreePath
    }

    var id: String { baseTool.id }
    var name: String { baseTool.name }
    var description: String { baseTool.description }
    var requiresPermission: Bool { baseTool.requiresPermission }
    var usageExample: String? { baseTool.usageExample }
    var parametersSchema: [String: AnyCodable] { baseTool.parametersSchema }

    func canExecute() async -> Bool {
        await baseTool.canExecute()
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let path = ToolParameters(parameters).optional("path", as: String.self) ?? "."
        if let failure = ShuttleShardFilesystemGuard.validateReadablePath(path, worktreePath: worktreePath) {
            return failure
        }
        return try await baseTool.execute(parameters: parameters)
    }
}

private struct ShuttleFindFileTool: Tool, Sendable {
    private let baseTool: FindFileTool
    private let worktreePath: String

    init(worktreePath: String) {
        self.baseTool = FindFileTool(currentDirectory: worktreePath, jailRoot: worktreePath)
        self.worktreePath = worktreePath
    }

    var id: String { baseTool.id }
    var name: String { baseTool.name }
    var description: String { baseTool.description }
    var requiresPermission: Bool { baseTool.requiresPermission }
    var usageExample: String? { baseTool.usageExample }
    var parametersSchema: [String: AnyCodable] { baseTool.parametersSchema }

    func canExecute() async -> Bool {
        await baseTool.canExecute()
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let path = ToolParameters(parameters).optional("path", as: String.self) ?? "."
        if let failure = ShuttleShardFilesystemGuard.validateReadablePath(path, worktreePath: worktreePath) {
            return failure
        }
        return try await baseTool.execute(parameters: parameters)
    }
}

private struct ShuttleSearchFileContentTool: Tool, Sendable {
    private let baseTool: SearchFileContentTool
    private let worktreePath: String

    init(worktreePath: String) {
        self.baseTool = SearchFileContentTool(currentDirectory: worktreePath, jailRoot: worktreePath)
        self.worktreePath = worktreePath
    }

    var id: String { baseTool.id }
    var name: String { baseTool.name }
    var description: String { baseTool.description }
    var requiresPermission: Bool { baseTool.requiresPermission }
    var usageExample: String? { baseTool.usageExample }
    var parametersSchema: [String: AnyCodable] { baseTool.parametersSchema }

    func canExecute() async -> Bool {
        await baseTool.canExecute()
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let path = ToolParameters(parameters).optional("path", as: String.self) ?? "."
        if let failure = ShuttleShardFilesystemGuard.validateReadablePath(path, worktreePath: worktreePath) {
            return failure
        }
        return try await baseTool.execute(parameters: parameters)
    }
}

private struct ShuttleSearchFilesTool: Tool, Sendable {
    let id = "search_files"
    let name = "Search Files"
    let description = "Optimized search for text content across files in the shard workspace."
    let requiresPermission = true

    private let worktreePath: String

    init(worktreePath: String) {
        self.worktreePath = worktreePath
    }

    var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"search_files\", \"arguments\": {\"pattern\": \"TODO:\"}}
        </tool_call>
        """
    }

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        objectSchema(
            properties: [
                "pattern": stringSchema("The text pattern to search for (regex supported)"),
                "path": stringSchema("The directory to search within (default: current directory)"),
                "include": stringSchema("Optional glob pattern for files to include (e.g. '*.swift')"),
            ],
            required: ["pattern"]
        )
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let pattern: String
        do {
            pattern = try params.require("pattern", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        let path = params.optional("path", as: String.self) ?? "."
        if let failure = ShuttleShardFilesystemGuard.validateReadablePath(path, worktreePath: worktreePath) {
            return failure
        }

        let searchURL: URL
        do {
            searchURL = try ShuttleShardFilesystemGuard.resolvePath(path, worktreePath: worktreePath)
        } catch {
            return .failure(error.localizedDescription)
        }

        if !FileManager.default.fileExists(atPath: searchURL.path) {
            return .failure("Path not found: \(path)")
        }

        let includePattern = params.optional("include", as: String.self)
        return runGrepSearch(pattern: pattern, searchURL: searchURL, includePattern: includePattern)
    }

    private func runGrepSearch(pattern: String, searchURL: URL, includePattern: String?) -> ToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")

        var arguments = ["-rn", "--exclude=.git", "--exclude-dir=.git", "--exclude-dir=.build"]
        if let includePattern {
            arguments.append("--include=\(includePattern)")
        }
        arguments.append(pattern)
        arguments.append(searchURL.path)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus == 0 || process.terminationStatus == 1 {
                let output = String(data: outputData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.isEmpty {
                    return .success("No matches found for '\(pattern)'")
                }
                let lines = output.components(separatedBy: .newlines)
                return .success(limitedOutput(lines, limit: 100))
            }

            let errorOutput = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            return .failure("Search failed with status \(process.terminationStatus): \(errorOutput)")
        } catch {
            return .failure("Failed to execute search: \(error.localizedDescription)")
        }
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
        switch ShuttleShardFilesystemGuard.validateMutablePath(
            path,
            worktreePath: worktreePath,
            requiresExistingFile: false
        ) {
        case .success(let resolvedURL):
            url = resolvedURL
        case .failure(let result):
            return result
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
        switch ShuttleShardFilesystemGuard.validateMutablePath(
            path,
            worktreePath: worktreePath,
            requiresExistingFile: true
        ) {
        case .success(let resolvedURL):
            url = resolvedURL
        case .failure(let result):
            return result
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

private enum ShuttleShardFilesystemGuard {
    private static let protectedMetadataName = ".git"

    enum GuardError: LocalizedError {
        case protectedMetadata(String)

        var errorDescription: String? {
            switch self {
            case .protectedMetadata(let path):
                return "Access denied: git metadata path is not available in shard workspaces (\(path))"
            }
        }
    }

    enum ValidationResult {
        case success(URL)
        case failure(ToolResult)
    }

    static func validateReadablePath(_ path: String, worktreePath: String) -> ToolResult? {
        do {
            _ = try resolvePath(path, worktreePath: worktreePath)
            return nil
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func resolvePath(_ path: String, worktreePath: String) throws -> URL {
        let resolvedURL = try PathSanitizer.safelyResolve(
            path: path,
            within: worktreePath,
            jailRoot: worktreePath
        )
        if isProtectedMetadataURL(resolvedURL, worktreePath: worktreePath) {
            throw GuardError.protectedMetadata(path)
        }
        return resolvedURL
    }

    static func validateMutablePath(
        _ path: String,
        worktreePath: String,
        requiresExistingFile: Bool
    ) -> ValidationResult {
        let resolvedURL: URL
        do {
            resolvedURL = try resolvePath(path, worktreePath: worktreePath)
        } catch {
            return .failure(.failure(error.localizedDescription))
        }

        let unresolvedURL = unresolvedPath(path, worktreePath: worktreePath)
        if isSymbolicLink(unresolvedURL) {
            return .failure(.failure("Refusing to mutate symbolic link path: \(path)"))
        }

        if requiresExistingFile {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
                return .failure(.failure("File not found: \(path)"))
            }
            if isDirectory.boolValue {
                return .failure(.failure("Path is a directory: \(path)"))
            }
        }

        if FileManager.default.fileExists(atPath: resolvedURL.path),
           hardLinkCount(at: resolvedURL) > 1 {
            return .failure(.failure("Refusing to mutate hard-linked path: \(path)"))
        }

        return .success(resolvedURL)
    }

    private static func unresolvedPath(_ path: String, worktreePath: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        if path.hasPrefix("~") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        }
        return URL(fileURLWithPath: worktreePath, isDirectory: true)
            .appendingPathComponent(path)
            .standardizedFileURL
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink) == true
    }

    private static func hardLinkCount(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.referenceCount] as? NSNumber)?.intValue ?? 1
    }

    private static func isProtectedMetadataURL(_ url: URL, worktreePath: String) -> Bool {
        let protectedURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
            .appendingPathComponent(protectedMetadataName)
            .standardizedFileURL
        let candidateComponents = url.standardizedFileURL.pathComponents
        let protectedComponents = protectedURL.pathComponents

        guard candidateComponents.count >= protectedComponents.count else {
            return false
        }
        return zip(protectedComponents, candidateComponents).allSatisfy(==)
    }
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

private func limitedOutput(_ lines: [String], limit: Int) -> String {
    guard lines.count > limit else {
        return lines.joined(separator: "\n")
    }
    return lines.prefix(limit).joined(separator: "\n") + "\n... (limit reached)"
}
