import XCTest
@testable import ShuttleServer

final class ShuttleServerSmokeTests: XCTestCase {
    func testStartupBannerMentionsTargetName() {
        XCTAssertEqual(ShuttleServerApp.makeStartupBanner(), "ShuttleServer bootstrap ready")
    }
}
