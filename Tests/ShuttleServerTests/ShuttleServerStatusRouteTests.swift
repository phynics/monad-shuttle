import XCTest
import Hummingbird
import HummingbirdTesting
@testable import ShuttleServer

final class ShuttleServerStatusRouteTests: XCTestCase {
    func testStatusEndpointReturnsReadyAndSubsystemKeys() async throws {
        let statusStore = ShuttleServerStatusStore()
        let router = Router(context: BasicRequestContext.self)
        ShuttleServerRoutes.register(on: router, statusStore: statusStore)
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/status", method: .get) { response in
                XCTAssertEqual(response.status, .ok)

                let payload = try JSONDecoder().decode(ShuttleStatusResponse.self, from: response.body)
                XCTAssertEqual(payload.serverState, .ready)
                XCTAssertEqual(Set(payload.subsystems.keys), [
                    "agent_runtime",
                    "config",
                    "database",
                    "docker",
                    "git",
                    "repo_refresh",
                    "volumes",
                ])
            }
        }
    }

    func testInvalidExplicitConfigPathSetsFatalState() async throws {
        let statusStore = ShuttleServerStatusStore()
        let configuration = ShuttleServerConfiguration(
            host: "127.0.0.1",
            port: 8080,
            configPath: "/path/that/does/not/exist.yml"
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await ShuttleServerApp.makeEnvironment(
                configuration: configuration,
                statusStore: statusStore
            )
        }

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .fatal)
    }

    func testGracefulShutdownMarksServerDraining() async throws {
        let statusStore = ShuttleServerStatusStore()
        let shutdownCoordinator = ShuttleServerShutdownCoordinator(statusStore: statusStore)

        await shutdownCoordinator.beginGracefulShutdown()

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .draining)
    }
}
