public struct ShuttleServerShutdownCoordinator: Sendable {
    private let statusStore: ShuttleServerStatusStore

    public init(statusStore: ShuttleServerStatusStore) {
        self.statusStore = statusStore
    }

    public func beginGracefulShutdown() async {
        await statusStore.setServerState(.draining)
    }
}
