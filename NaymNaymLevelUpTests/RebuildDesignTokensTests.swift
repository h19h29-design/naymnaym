import XCTest
@testable import NaymNaymLevelUp

final class RebuildDesignTokensTests: XCTestCase {
    func testApprovedTokensAreExact() {
        XCTAssertEqual(RebuildDesignTokens.minimumActionSize, 48)
        XCTAssertEqual(RebuildDesignTokens.spacing, [4, 8, 12, 16, 24, 32])
        XCTAssertEqual(RebuildDesignTokens.hex(.forest700), "#1F5E43")
        XCTAssertEqual(RebuildDesignTokens.hex(.cream50), "#FFF9EC")
    }
}
