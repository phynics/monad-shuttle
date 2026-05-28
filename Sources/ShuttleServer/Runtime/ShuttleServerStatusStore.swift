public actor ShuttleServerStatusStore {
    private var serverState: ShuttleServerState
    private var subsystems: [String: ShuttleSubsystemHealth]

    public init(
        serverState: ShuttleServerState = .ready,
        subsystems: [String: ShuttleSubsystemHealth] = ShuttleServerStatusStore.defaultSubsystems
    ) {
        self.serverState = serverState
        self.subsystems = subsystems
    }

    public func snapshot() -> ShuttleStatusResponse {
        ShuttleStatusResponse(serverState: serverState, subsystems: subsystems)
    }

    public func setServerState(_ state: ShuttleServerState) {
        self.serverState = state
    }

    public func setSubsystem(_ name: String, status: ShuttleSubsystemHealth) {
        self.subsystems[name] = status
    }

    public static let defaultSubsystems: [String: ShuttleSubsystemHealth] = [
        "database": .init(status: .ok),
        "git": .init(status: .ok),
        "docker": .init(status: .ok),
        "config": .init(status: .ok),
        "volumes": .init(status: .ok),
        "repo_refresh": .init(status: .ok),
        "agent_runtime": .init(status: .ok),
    ]
}
