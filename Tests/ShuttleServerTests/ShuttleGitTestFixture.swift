import Foundation
import XCTest
@testable import ShuttleServer

struct ShuttleGitTestFixture {
    let root: URL
    let originBareRepository: URL
    let workingRepository: URL
    let branch: String

    static func create(branch: String = "main") throws -> ShuttleGitTestFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let origin = root.appendingPathComponent("origin.git", isDirectory: true)
        let working = root.appendingPathComponent("working", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try runGit(["init", "--bare", origin.path], in: root.path)
        try runGit(["init", working.path], in: root.path)
        try runGit(["config", "user.name", "Shuttle Tests"], in: working.path)
        try runGit(["config", "user.email", "shuttle-tests@example.com"], in: working.path)
        try runGit(["checkout", "-b", branch], in: working.path)

        let readme = working.appendingPathComponent("README.md")
        try "# Fixture\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: working.path)
        try runGit(["commit", "-m", "Initial commit"], in: working.path)
        try runGit(["remote", "add", "origin", origin.path], in: working.path)
        try runGit(["push", "-u", "origin", branch], in: working.path)

        return ShuttleGitTestFixture(
            root: root,
            originBareRepository: origin,
            workingRepository: working,
            branch: branch
        )
    }

    func addCommitAndPush(
        fileName: String,
        contents: String,
        commitMessage: String
    ) throws -> String {
        let fileURL = workingRepository.appendingPathComponent(fileName)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try Self.runGit(["add", fileName], in: workingRepository.path)
        try Self.runGit(["commit", "-m", commitMessage], in: workingRepository.path)
        try Self.runGit(["push", "origin", branch], in: workingRepository.path)
        return try Self.headCommit(in: workingRepository.path)
    }

    func originBranchCommit() throws -> String {
        try Self.runGit(["rev-parse", branch], in: originBareRepository.path).stdout
    }

    static func headCommit(in repositoryPath: String) throws -> String {
        try runGit(["rev-parse", "HEAD"], in: repositoryPath).stdout
    }

    @discardableResult
    static func runGit(_ arguments: [String], in workingDirectory: String) throws -> ShuttleGitShellResult {
        try ShuttleGitShell.run(arguments, workingDirectory: workingDirectory)
    }
}
