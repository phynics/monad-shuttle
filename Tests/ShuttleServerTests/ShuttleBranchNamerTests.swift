import XCTest
@testable import ShuttleServer

final class ShuttleBranchNamerTests: XCTestCase {
    func testGeneratesHumanReadableBranchNameFromTitle() {
        let branchName = ShuttleBranchNamer.makeBranchName(
            shardID: "123e4567-e89b-12d3-a456-426614174000",
            title: "Add repository bootstrap",
            spec: "ignored",
            existingBranchNames: []
        )

        XCTAssertEqual(branchName, "shuttle/shards/add-repository-bootstrap-123e4567")
    }

    func testSanitizesUnsafeCharactersAndFallsBackToSpecSummary() {
        let branchName = ShuttleBranchNamer.makeBranchName(
            shardID: "ABCDEF12-3456-7890-ABCD-EF1234567890",
            title: "   ",
            spec: "Fix / merge: weird\tcharacters && spacing!!!",
            existingBranchNames: []
        )

        XCTAssertEqual(branchName, "shuttle/shards/fix-merge-weird-characters-spacing-abcdef12")
    }

    func testTruncatesLongSlug() {
        let branchName = ShuttleBranchNamer.makeBranchName(
            shardID: "f47ac10b-58cc-4372-a567-0e02b2c3d479",
            title: "This title is intentionally very long so the branch slug should be truncated before the suffix is appended",
            spec: "ignored",
            existingBranchNames: []
        )

        XCTAssertEqual(branchName, "shuttle/shards/this-title-is-intentionally-very-long-so-the-bra-f47ac10b")
    }

    func testCollisionExtendsSuffixUntilUnique() {
        let shardID = "123e4567-e89b-12d3-a456-426614174000"
        let existing = [
            "shuttle/shards/add-repository-bootstrap-123e4567",
        ]

        let branchName = ShuttleBranchNamer.makeBranchName(
            shardID: shardID,
            title: "Add repository bootstrap",
            spec: "ignored",
            existingBranchNames: existing
        )

        XCTAssertEqual(branchName, "shuttle/shards/add-repository-bootstrap-123e4567e89b")
    }
}
