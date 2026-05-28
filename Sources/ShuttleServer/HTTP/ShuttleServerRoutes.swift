import Hummingbird

public enum ShuttleServerRoutes {
    public static func register(
        on router: Router<BasicRequestContext>,
        statusStore: ShuttleServerStatusStore
    ) {
        router.get("/api/status") { _, _ in
            await statusStore.snapshot()
        }
    }
}
