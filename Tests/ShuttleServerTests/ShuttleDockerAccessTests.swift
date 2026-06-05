import XCTest
@testable import ShuttleServer

final class ShuttleDockerAccessTests: XCTestCase {
    func testProbeHealthMarksDockerSubsystemHealthy() async throws {
        let statusStore = ShuttleServerStatusStore()
        let accessController = ShuttleDockerAccessController(
            client: .init(probeAvailability: {
                .available(detail: "Docker socket accessible")
            }),
            statusStore: statusStore
        )

        let availability = await accessController.probeHealth()
        let snapshot = await statusStore.snapshot()

        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(snapshot.subsystems["docker"], .init(status: .ok, detail: "Docker socket accessible"))
    }

    func testProbeHealthMarksDockerSubsystemFailedWithoutFailingServer() async throws {
        let statusStore = ShuttleServerStatusStore()
        let accessController = ShuttleDockerAccessController(
            client: .init(probeAvailability: {
                .unavailable(detail: "Missing Docker socket at /var/run/docker.sock")
            }),
            statusStore: statusStore
        )

        let availability = await accessController.probeHealth()
        let snapshot = await statusStore.snapshot()

        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(snapshot.serverState, .ready)
        XCTAssertEqual(
            snapshot.subsystems["docker"],
            .init(status: .failed, detail: "Missing Docker socket at /var/run/docker.sock")
        )
    }

    func testContainerOperationFailsWithStructuredErrorWhenDockerIsUnavailable() async throws {
        let statusStore = ShuttleServerStatusStore()
        let accessController = ShuttleDockerAccessController(
            client: .init(probeAvailability: {
                .unavailable(detail: "Docker socket unavailable")
            }),
            statusStore: statusStore
        )

        do {
            _ = try await accessController.withDockerAccess(operation: "create_container") {
                XCTFail("Operation body should not run when Docker is unavailable")
                return "unexpected"
            }
            XCTFail("Expected Docker access error")
        } catch let error as ShuttleDockerAccessError {
            XCTAssertEqual(
                error,
                .unavailable(operation: "create_container", detail: "Docker socket unavailable")
            )
        }
    }

    func testMakeEnvironmentUsesInjectedDockerClientForHealth() async throws {
        let statusStore = ShuttleServerStatusStore()
        let configuration = ShuttleServerConfiguration()

        _ = try await ShuttleServerApp.makeEnvironment(
            configuration: configuration,
            statusStore: statusStore,
            dockerClient: .init(probeAvailability: {
                .unavailable(detail: "Injected Docker probe failure")
            })
        )

        let snapshot = await statusStore.snapshot()
        XCTAssertEqual(snapshot.serverState, .ready)
        XCTAssertEqual(
            snapshot.subsystems["docker"],
            .init(status: .failed, detail: "Injected Docker probe failure")
        )
    }
}
