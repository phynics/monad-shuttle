import Hummingbird

public enum ShuttleServerRoutes {
    static func register(
        on router: Router<BasicRequestContext>,
        statusStore: ShuttleServerStatusStore,
        loadedConfig: ShuttleConfig? = nil
    ) {
        router.get("/api/status") { _, _ in
            await statusStore.snapshot()
        }

        router.get("/api/config") { _, _ in
            guard let loadedConfig else {
                throw HTTPError(.notFound)
            }
            return ShuttleConfigResponse(redacting: loadedConfig)
        }
    }
}
