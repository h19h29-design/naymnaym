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

    func testParentSummaryDoesNotTreatAlreadyEatsAsSkipped() {
        let record = ChallengeRecord(
            date: "20260618",
            menuName: "현미밥",
            action: .alreadyEats,
            gainedExp: 0,
            badgeName: nil,
            nutrients: ["탄수화물"]
        )

        let summary = NutritionEstimator.makeParentSummary(records: [record])

        XCTAssertFalse(summary.contains("자주 안 먹었어요"))
        XCTAssertTrue(summary.contains("한 입 도전 기록이 많지 않아요"))
    }
}
