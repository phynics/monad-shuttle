import Hummingbird

public struct ShuttleConfigResponse: ResponseCodable, Equatable, Sendable {
    public struct Repository: Codable, Equatable, Sendable {
        public let url: String
        public let sourceBranch: String
        public let sshKeyPath: String
    }

    public struct Runtime: Codable, Equatable, Sendable {
        public struct CommandPolicy: Codable, Equatable, Sendable {
            public let allow: [String]
            public let deny: [String]
        }

        public let containerImage: String
        public let containerWorkdir: String
        public let commandPolicy: CommandPolicy
    }

    public struct Refresh: Codable, Equatable, Sendable {
        public let schedule: String
    }

    public struct Retention: Codable, Equatable, Sendable {
        public let worktreeDays: Int
        public let rawLogsDays: Int
        public let rawLogsMaxBytes: Int
    }

    public struct Limits: Codable, Equatable, Sendable {
        public let maxRunningShards: Int
        public let maxIntegratingShards: Int
        public let maxQueuedShards: Int
        public let maxLogBytesPerShard: Int
    }

    public struct PushTarget: Codable, Equatable, Sendable {
        public let name: String
        public let remote: String
        public let branch: String
    }

    public struct Paths: Codable, Equatable, Sendable {
        public let database: String
        public let git: String
        public let worktrees: String
        public let logs: String
    }

    public struct Auth: Codable, Equatable, Sendable {
        public let mode: String
    }

    public struct Instructions: Codable, Equatable, Sendable {
        public let filePath: String
    }

    public struct Server: Codable, Equatable, Sendable {
        public let host: String
        public let port: Int
    }

    public let repository: Repository
    public let runtime: Runtime
    public let refresh: Refresh
    public let retention: Retention
    public let limits: Limits
    public let paths: Paths
    public let pushTargets: [PushTarget]
    public let auth: Auth
    public let instructions: Instructions
    public let server: Server

    init(redacting config: ShuttleConfig) {
        self.repository = .init(
            url: config.repository.url,
            sourceBranch: config.repository.sourceBranch,
            sshKeyPath: "<redacted>"
        )
        self.runtime = .init(
            containerImage: config.runtime.containerImage,
            containerWorkdir: config.runtime.containerWorkdir,
            commandPolicy: .init(
                allow: config.runtime.commandPolicy.allow,
                deny: config.runtime.commandPolicy.deny
            )
        )
        self.refresh = .init(schedule: config.refresh.schedule)
        self.retention = .init(
            worktreeDays: config.retention.worktreeDays,
            rawLogsDays: config.retention.rawLogsDays,
            rawLogsMaxBytes: config.retention.rawLogsMaxBytes
        )
        self.limits = .init(
            maxRunningShards: config.limits.maxRunningShards,
            maxIntegratingShards: config.limits.maxIntegratingShards,
            maxQueuedShards: config.limits.maxQueuedShards,
            maxLogBytesPerShard: config.limits.maxLogBytesPerShard
        )
        self.paths = .init(
            database: config.paths.databasePath,
            git: config.paths.gitPath,
            worktrees: config.paths.worktreesPath,
            logs: config.paths.logsPath
        )
        self.pushTargets = config.pushTargets.map {
            .init(name: $0.name, remote: $0.remote, branch: $0.branch)
        }
        self.auth = .init(mode: config.auth.mode.rawValue)
        self.instructions = .init(filePath: config.instructions.filePath)
        self.server = .init(host: config.server.host, port: config.server.port)
    }
}
