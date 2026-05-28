import XCTest
@testable import ShuttleWebUI

final class ShuttleWebUISmokeTests: XCTestCase {
    func testTargetNameIsStable() {
        XCTAssertEqual(ShuttleWebUIBootstrap.targetName, "ShuttleWebUI")
    }
}
