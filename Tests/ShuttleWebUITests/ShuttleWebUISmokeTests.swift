import XCTest
@testable import ShuttleWebUI

final class ShuttleWebUISmokeTests: XCTestCase {
    func testTargetNameIsStable() {
        XCTAssertEqual(ShuttleWebUIBootstrap.targetName, "ShuttleWebUI")
    }

    func testOperatorQueueAssetsArePresent() {
        XCTAssertTrue(ShuttleWebUIAssets.html.contains("id=\"queue\""))
        XCTAssertTrue(ShuttleWebUIAssets.html.contains("/assets/shuttle.css"))
        XCTAssertTrue(ShuttleWebUIAssets.html.contains("/assets/shuttle.js"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/api/status"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/api/shards"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/api/conflicts"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/api/events?limit=8"))
        XCTAssertTrue(ShuttleWebUIAssets.css.contains(".queue-grid"))
    }
}
