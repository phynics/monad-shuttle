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

    func testShardDetailAssetsArePresent() {
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("routeShardID"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/completion-report"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/request-finish"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/answer"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/abandon"))
        XCTAssertTrue(ShuttleWebUIAssets.css.contains(".detail-layout"))
    }

    func testPushAndConflictAssetsArePresent() {
        XCTAssertTrue(ShuttleWebUIAssets.html.contains("id=\"push-panel\""))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/api/conflicts/"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/api/pushes"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("Idempotency-Key"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("Push anyway?"))
        XCTAssertTrue(ShuttleWebUIAssets.javascript.contains("/api/config"))
    }
}
