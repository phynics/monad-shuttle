import Hummingbird

public enum ShuttleServerRoutes {
    static func register(
        on router: Router<BasicRequestContext>,
        statusStore: ShuttleServerStatusStore,
        loadedConfig: ShuttleConfig? = nil,
        repositoryStateStore: ShuttleRepositoryStateStore? = nil
    ) {
        router.get("/api/status") { _, _ in
            let repository: ShuttleStatusResponse.Repository?
            if let repositoryStateStore,
               let storedState = try repositoryStateStore.fetch() {
                repository = .init(
                    integrationState: storedState.integrationState.rawValue,
                    sourceBranch: storedState.sourceBranch,
                    shuttleMainBranch: storedState.shuttleMainBranch,
                    blockedConflictID: storedState.blockedConflictID
                )
            } else {
                repository = nil
            }
            return await statusStore.snapshot(repository: repository)
        }

        router.get("/api/config") { _, _ in
            guard let loadedConfig else {
                throw HTTPError(.notFound)
            }
            return ShuttleConfigResponse(redacting: loadedConfig)
        }
    }
}
