import Foundation

struct ShuttleConfig: Equatable, Sendable {
    struct Repository: Equatable, Sendable {
        let url: String
        let sourceBranch: String
        let sshKeyPath: String
    }

    struct Runtime: Equatable, Sendable {
        struct CommandPolicy: Equatable, Sendable {
            let allow: [String]
            let deny: [String]
        }

        let containerImage: String
        let containerWorkdir: String
        let commandPolicy: CommandPolicy
    }

    struct Refresh: Equatable, Sendable {
        let schedule: String
    }

    struct Retention: Equatable, Sendable {
        let worktreeDays: Int
        let rawLogsDays: Int
        let rawLogsMaxBytes: Int
    }

    struct Limits: Equatable, Sendable {
        let maxRunningShards: Int
        let maxIntegratingShards: Int
        let maxQueuedShards: Int
        let maxLogBytesPerShard: Int
    }

    struct Paths: Equatable, Sendable {
        let databasePath: String
        let gitPath: String
        let worktreesPath: String
        let logsPath: String
    }

    struct PushTarget: Equatable, Sendable {
        let name: String
        let remote: String
        let branch: String
    }

    struct Auth: Equatable, Sendable {
        enum Mode: String, Equatable, Sendable {
            case localAdmin = "local_admin"
        }

        let mode: Mode
    }

    struct Instructions: Equatable, Sendable {
        let filePath: String
    }

    struct Server: Equatable, Sendable {
        let host: String
        let port: Int
    }

    let repository: Repository
    let runtime: Runtime
    let refresh: Refresh
    let retention: Retention
    let limits: Limits
    let paths: Paths
    let pushTargets: [PushTarget]
    let auth: Auth
    let instructions: Instructions
    let server: Server
}
