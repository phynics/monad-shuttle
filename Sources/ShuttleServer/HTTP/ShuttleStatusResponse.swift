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
    public let serverState: ShuttleServerState
    public let subsystems: [String: ShuttleSubsystemHealth]

    public init(serverState: ShuttleServerState, subsystems: [String: ShuttleSubsystemHealth]) {
        self.serverState = serverState
        self.subsystems = subsystems
    }
}
