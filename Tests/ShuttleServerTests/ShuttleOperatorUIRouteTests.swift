import Hummingbird
import HummingbirdTesting
import XCTest
@testable import ShuttleServer

final class ShuttleOperatorUIRouteTests: XCTestCase {
    func testServesOperatorQueueShellAndAssets() async throws {
        let environment = ShuttleServerApp.Environment(
            configuration: .init(host: "127.0.0.1", port: 8080),
            loadedConfig: nil,
            managedRepository: nil,
            statusStore: ShuttleServerStatusStore()
        )
        let app = Application(router: ShuttleServerApp.makeRouter(environment: environment))

        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/html; charset=utf-8")
                XCTAssertTrue(String(buffer: response.body).contains("Shuttle"))
                XCTAssertTrue(String(buffer: response.body).contains("id=\"queue\""))
            }

            try await client.execute(uri: "/assets/shuttle.css", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "text/css; charset=utf-8")
                XCTAssertTrue(String(buffer: response.body).contains(".queue-grid"))
            }

            try await client.execute(uri: "/assets/shuttle.js", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "application/javascript; charset=utf-8")
                XCTAssertTrue(String(buffer: response.body).contains("/api/status"))
            }
        }
    }
}
