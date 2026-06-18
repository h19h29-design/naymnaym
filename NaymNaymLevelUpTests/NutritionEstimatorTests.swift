import XCTest
@testable import NaymNaymLevelUp

final class NutritionEstimatorTests: XCTestCase {
    func testVegetableNamesMapToFiberAndVitamin() {
        let nutrients = NutritionEstimator.estimateNutrients(forName: "콩나물무침")

        XCTAssertTrue(nutrients.contains("식이섬유"))
        XCTAssertTrue(nutrients.contains("비타민"))
    }

    func testStudentExplanationUsesEducationalLanguage() {
        let item = MealItem(name: "시금치나물", allergyCodes: [], nutrients: ["식이섬유"], tags: ["장 건강"], sourceRawText: "시금치나물")
        let explanation = NutritionEstimator.makeStudentExplanation(for: item)

        XCTAssertTrue(explanation.contains("놓칠 수 있어요"))
        XCTAssertTrue(explanation.contains("교육용 참고 안내"))
        XCTAssertFalse(explanation.contains("부족합니다"))
        XCTAssertFalse(explanation.contains("치료"))
    }
}

