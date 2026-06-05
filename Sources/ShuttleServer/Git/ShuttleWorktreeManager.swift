import Foundation

struct ShuttleCreatedWorktree: Equatable, Sendable {
    let branchName: String
    let worktreePath: String
    let baseCommit: String
}

enum ShuttleWorktreeManagerError: Error, Equatable, Sendable {
    case duplicateBranch(String)
    case existingWorktreePath(String)
    case missingWorktree(String)
}

struct ShuttleWorktreeManager {
    let bareRepositoryPath: String
    let worktreesRootPath: String

    init(
        bareRepositoryPath: String,
        worktreesRootPath: String
    ) {
        self.bareRepositoryPath = bareRepositoryPath
        self.worktreesRootPath = worktreesRootPath
    }

    func createWorktree(
        shardID: String,
        branchName: String
    ) throws -> ShuttleCreatedWorktree {
        let baseCommit = try ShuttleGitShell.run(
            ["--git-dir", bareRepositoryPath, "rev-parse", "refs/heads/\(ShuttleRepositoryBootstrapper.shuttleMainBranch)"]
        ).stdout
        let worktreePath = Self.deterministicWorktreePath(
            rootPath: worktreesRootPath,
            shardID: shardID,
            branchName: branchName
        )

        if branchExists(branchName: branchName) {
            throw ShuttleWorktreeManagerError.duplicateBranch(branchName)
        }

        if FileManager.default.fileExists(atPath: worktreePath) {
            throw ShuttleWorktreeManagerError.existingWorktreePath(worktreePath)
        }

        let parentDirectory = URL(fileURLWithPath: worktreePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        _ = try ShuttleGitShell.run(
            [
                "--git-dir",
                bareRepositoryPath,
                "worktree",
                "add",
                "-b",
                branchName,
                worktreePath,
                ShuttleRepositoryBootstrapper.shuttleMainBranch,
            ]
        )

        return ShuttleCreatedWorktree(
            branchName: branchName,
            worktreePath: worktreePath,
            baseCommit: baseCommit
        )
    }

    func retainReadOnly(worktreePath: String) throws {
        guard FileManager.default.fileExists(atPath: worktreePath) else {
            throw ShuttleWorktreeManagerError.missingWorktree(worktreePath)
        }

        try applyReadOnlyAttributes(atPath: worktreePath)

        if let enumerator = FileManager.default.enumerator(atPath: worktreePath) {
            while let relativePath = enumerator.nextObject() as? String {
                let absolutePath = URL(fileURLWithPath: worktreePath, isDirectory: true)
                    .appendingPathComponent(relativePath).path
                try applyReadOnlyAttributes(atPath: absolutePath)
            }
        }
    }

    func removeWorktree(
        branchName: String,
        worktreePath: String
    ) throws {
        if FileManager.default.fileExists(atPath: worktreePath) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: worktreePath)
            _ = try ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "worktree", "remove", "--force", worktreePath]
            )
        }

        if branchExists(branchName: branchName) {
            _ = try ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "branch", "-D", branchName]
            )
        }
    }

    func branchExists(branchName: String) -> Bool {
        (try? ShuttleGitShell.run(
            ["--git-dir", bareRepositoryPath, "show-ref", "--verify", "refs/heads/\(branchName)"]
        )) != nil
    }

    static func deterministicWorktreePath(
        rootPath: String,
        shardID: String,
        branchName: String
    ) -> String {
        let branchDirectoryName = branchName
            .lowercased()
            .replacingOccurrences(of: "/", with: "--")
            .replacingOccurrences(of: " ", with: "-")
        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(shardID, isDirectory: true)
            .appendingPathComponent(branchDirectoryName, isDirectory: true)
            .path
    }

    private func applyReadOnlyAttributes(atPath path: String) throws {
        let isDirectory = try isDirectoryPath(path)
        let permissions: NSNumber = isDirectory ? 0o555 : 0o444
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
    }

    private func isDirectoryPath(_ path: String) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.type] as? FileAttributeType) == .typeDirectory
    }
}
