import XCTest
@testable import NaymNaymLevelUp

final class AllergyMapTests: XCTestCase {
    func testAllergyMapContainsNineteenCodes() {
        XCTAssertEqual(AllergyMap.allCodes.count, 19)
        XCTAssertEqual(AllergyMap.name(for: 1), "난류")
        XCTAssertEqual(AllergyMap.name(for: 19), "잣")
    }

    func testAllergyLabelIncludesCodeAndName() {
        XCTAssertEqual(AllergyMap.label(for: 15), "15 닭고기")
    }
}

