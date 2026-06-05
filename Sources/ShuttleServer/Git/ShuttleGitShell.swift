import Foundation

struct ShuttleGitShellResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
}

enum ShuttleGitShellError: Error, Equatable, Sendable {
    case commandFailed(command: [String], status: Int32, stderr: String)
    case invalidOutputEncoding([String])
}

enum ShuttleGitShell {
    static func run(
        _ arguments: [String],
        workingDirectory: String? = nil
    ) throws -> ShuttleGitShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard let stdout = String(data: stdoutData, encoding: .utf8),
              let stderr = String(data: stderrData, encoding: .utf8) else {
            throw ShuttleGitShellError.invalidOutputEncoding(arguments)
        }

        guard process.terminationStatus == 0 else {
            throw ShuttleGitShellError.commandFailed(
                command: arguments,
                status: process.terminationStatus,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return ShuttleGitShellResult(
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
