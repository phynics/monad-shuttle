import Hummingbird

public enum ShuttleServerState: String, Codable, Equatable, Sendable {
    case ready
    case draining
    case fatal
}

public enum ShuttleSubsystemState: String, Codable, Equatable, Sendable {
    case ok
    case failed
}

public struct ShuttleSubsystemHealth: Codable, Equatable, Sendable {
    public let status: ShuttleSubsystemState
    public let detail: String?

    public init(status: ShuttleSubsystemState, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

public struct ShuttleStatusResponse: ResponseCodable, Equatable, Sendable {
    public struct Repository: Codable, Equatable, Sendable {
        public let integrationState: String
        public let sourceBranch: String?
        public let shuttleMainBranch: String?
        public let blockedConflictID: String?

        public init(
            integrationState: String,
            sourceBranch: String? = nil,
            shuttleMainBranch: String? = nil,
            blockedConflictID: String? = nil
        ) {
            self.integrationState = integrationState
            self.sourceBranch = sourceBranch
            self.shuttleMainBranch = shuttleMainBranch
            self.blockedConflictID = blockedConflictID
        }
    }

    public let serverState: ShuttleServerState
    public let subsystems: [String: ShuttleSubsystemHealth]
    public let repository: Repository?

    public init(
        serverState: ShuttleServerState,
        subsystems: [String: ShuttleSubsystemHealth],
        repository: Repository? = nil
    ) {
        self.serverState = serverState
        self.subsystems = subsystems
        self.repository = repository
    }
}
