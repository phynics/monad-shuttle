import Foundation

struct ShuttleRepositoryBootstrapResult: Equatable, Sendable {
    let bareRepositoryPath: String
    let sourceBranch: String
    let shuttleMainBranch: String
}

enum ShuttleRepositoryBootstrapper {
    static let shuttleMainBranch = "shuttle-main"

    static func bootstrap(config: ShuttleConfig) throws -> ShuttleRepositoryBootstrapResult {
        let bareRepositoryPath = repositoryPath(for: config)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: bareRepositoryPath) {
            _ = try ShuttleGitShell.run(["clone", "--bare", config.repository.url, bareRepositoryPath])
        } else {
            let originURL = try ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "remote", "get-url", "origin"]
            ).stdout
            guard originURL == config.repository.url else {
                throw ShuttleStartupError.gitOperationFailed(
                    "Existing bare repository origin mismatch. expected=\(config.repository.url) actual=\(originURL)"
                )
            }
        }

        _ = try ShuttleGitShell.run(
            [
                "--git-dir",
                bareRepositoryPath,
                "fetch",
                "origin",
                "refs/heads/\(config.repository.sourceBranch):refs/remotes/origin/\(config.repository.sourceBranch)",
            ]
        )

        let upstreamRef = "refs/remotes/origin/\(config.repository.sourceBranch)"
        do {
            _ = try ShuttleGitShell.run(["--git-dir", bareRepositoryPath, "show-ref", "--verify", upstreamRef])
        } catch {
            throw ShuttleStartupError.gitOperationFailed(
                "Missing fetched upstream branch ref: \(upstreamRef)"
            )
        }

        let shuttleMainRef = "refs/heads/\(shuttleMainBranch)"
        let shuttleMainExists = (try? ShuttleGitShell.run(
            ["--git-dir", bareRepositoryPath, "show-ref", "--verify", shuttleMainRef]
        )) != nil

        if !shuttleMainExists {
            _ = try ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "branch", shuttleMainBranch, upstreamRef]
            )
        } else {
            _ = try ShuttleGitShell.run(
                ["--git-dir", bareRepositoryPath, "rev-parse", "--verify", shuttleMainRef]
            )
        }

        return ShuttleRepositoryBootstrapResult(
            bareRepositoryPath: bareRepositoryPath,
            sourceBranch: config.repository.sourceBranch,
            shuttleMainBranch: shuttleMainBranch
        )
    }

    static func repositoryPath(for config: ShuttleConfig) -> String {
        (config.paths.gitPath as NSString).appendingPathComponent("repository.git")
    }
}
