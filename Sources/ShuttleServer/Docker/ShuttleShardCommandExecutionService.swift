import Foundation

public struct ShuttleDockerExecRequest: Equatable, Sendable {
    public let containerName: String
    public let workingDirectory: String
    public let command: [String]

    public init(
        containerName: String,
        workingDirectory: String,
        command: [String]
    ) {
        self.containerName = containerName
        self.workingDirectory = workingDirectory
        self.command = command
    }
}

public struct ShuttleDockerExecResult: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let startedAt: Date
    public let endedAt: Date

    public init(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        startedAt: Date,
        endedAt: Date
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

enum ShuttleCommandPolicyError: Error, Equatable, Sendable {
    case emptyCommand
    case commandDenied(String)
    case commandNotAllowed(String)
}

struct ShuttleCommandLogEntry: Codable, Equatable, Sendable {
    let shardID: String
    let command: [String]
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let startedAt: Date
    let endedAt: Date
    let toolName: String?
}

struct ShuttleShardCommandExecutionService {
    let shardStore: ShuttleShardStore
    let dockerAccessController: ShuttleDockerAccessController
    let commandLogStore: ShuttleCommandLogStore
    let config: ShuttleConfig

    func runGeneralCommand(
        shardID: String,
        command: [String]
    ) async throws -> ShuttleDockerExecResult {
        try validate(command: command, mode: .general)
        return try await run(shardID: shardID, toolName: nil, command: command)
    }

    func runNamedCommand(
        shardID: String,
        toolName: String,
        command: [String]
    ) async throws -> ShuttleDockerExecResult {
        try validate(command: command, mode: .named)
        return try await run(shardID: shardID, toolName: toolName, command: command)
    }

    private func run(
        shardID: String,
        toolName: String?,
        command: [String]
    ) async throws -> ShuttleDockerExecResult {
        guard let runtimeMetadata = try shardStore.fetchRuntimeMetadata(shardID: shardID) else {
            throw ShuttleShardStoreError.shardNotFound(shardID)
        }

        let request = ShuttleDockerExecRequest(
            containerName: runtimeMetadata.containerName,
            workingDirectory: config.runtime.containerWorkdir,
            command: command
        )
        let result = try await dockerAccessController.withDockerAccess(operation: "exec_container_command") {
            try await dockerAccessController.execInContainer(request)
        }

        try commandLogStore.append(
            ShuttleCommandLogEntry(
                shardID: shardID,
                command: command,
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode,
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                toolName: toolName
            )
        )
        return result
    }

    private enum Mode {
        case general
        case named
    }

    private func validate(command: [String], mode: Mode) throws {
        guard let executable = command.first, !executable.isEmpty else {
            throw ShuttleCommandPolicyError.emptyCommand
        }
        if config.runtime.commandPolicy.deny.contains(executable) {
            throw ShuttleCommandPolicyError.commandDenied(executable)
        }
        if mode == .general && !config.runtime.commandPolicy.allow.contains(executable) {
            throw ShuttleCommandPolicyError.commandNotAllowed(executable)
        }
    }
}
