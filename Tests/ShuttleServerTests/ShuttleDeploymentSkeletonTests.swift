import XCTest
import Foundation

final class ShuttleDeploymentSkeletonTests: XCTestCase {
    func testDockerDeploymentArtifactsExist() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: "Dockerfile"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "compose.yaml"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "deploy/config/shuttle.example.yaml"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: "deploy/env/shuttle.example.env"))
    }
}
