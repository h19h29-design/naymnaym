import XCTest
@testable import NaymNaymLevelUp

final class NutritionEstimatorTests: XCTestCase {
    func testCoachRequestExcludesIdentityAndUnknownNutrients() throws {
        let request = MealCoachRequest(question: .benefits, nutrientIDs: ["단백질", "unknown", "protein"],
            wholeMeal: ["protein": 23, "carbs": 0, "fat": .infinity, "calcium": 100], sessionID: UUID())
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["question", "nutrients", "wholeMeal", "sessionId"]))
        XCTAssertEqual(json["nutrients"] as? [String], ["protein"])
        XCTAssertEqual(json["wholeMeal"] as? [String: Double], ["protein": 23])
    }

    func testCoachAnswerRejectsInvalidProviderSourceAndMissingFields() throws {
        let good = Data(#"{"source":"ai","summary":"식단 구성을 살펴봤어.","benefit":"단백질은 몸을 구성해.","caution":"한 끼로 판단하지 않아.","tip":"네 속도로 만나 보자."}"#.utf8)
        XCTAssertEqual(try MealCoachAnswer.decode(good).source, "ai")
        XCTAssertThrowsError(try MealCoachAnswer.decode(Data(#"{"source":"ai","summary":"hello"}"#.utf8)))
        XCTAssertThrowsError(try MealCoachAnswer.decode(Data(String(decoding: good, as: UTF8.self).replacingOccurrences(of: "\"ai\"", with: "\"mock\"").utf8)))
    }

    func testCoachDevelopmentConfigCannotSelectExternalHostsOrProviderKeyRoute() {
        XCTAssertNotNil(MealCoachConfiguration(endpoint: "http://127.0.0.1:64918/v1/meal-coach", accessToken: String(repeating: "x", count: 40)))
        for endpoint in ["https://opencode.ai/zen/go/v1/chat/completions", "http://example.org/v1/meal-coach", "http://127.0.0.1:64918/other", "http://127.0.0.1:64918/v1/meal-coach?key=anything"] {
            XCTAssertNil(MealCoachConfiguration(endpoint: endpoint, accessToken: String(repeating: "x", count: 40)))
        }
        XCTAssertNil(MealCoachConfiguration(endpoint: "http://127.0.0.1:64918/v1/meal-coach", accessToken: "short"))
    }

    func testCoachFallbackDoesNotPretendToBeAIOrDiagnoseOmission() {
        let answer = MealCoachAnswer.basic(question: .omission, nutrientIDs: ["protein"])
        XCTAssertEqual(answer.source, "basic")
        XCTAssertTrue(answer.caution.contains("한 끼"))
        XCTAssertFalse(answer.caution.contains("결핍입니다"))
        XCTAssertTrue(answer.benefit.contains("단백질"))
    }

    func testCoachNeverAttributesWholeMealAmountsToOneSelectedDish() {
        let meal = RebuildMealDay(date: "2026-09-13", menuItems: [
            RebuildMealItem(name: "현미밥", allergyCodes: [], nutrients: ["carbohydrate"], tags: [], sourceRawText: "현미밥")
        ], calorie: "610 kcal", nutrition: RebuildNutritionInfo(carbs: 78, protein: 23, fat: 14, calcium: 0, iron: 0, vitamin: 0,
            sourceFields: [.carbs, .protein, .fat], sourceUnits: [.carbs: "g", .protein: "g", .fat: "g"]))
        XCTAssertEqual(MealCoachRequest.wholeMealValues(meal, selectedIndex: -1), ["carbs": 78, "protein": 23, "fat": 14])
        XCTAssertEqual(MealCoachRequest.wholeMealValues(meal, selectedIndex: 0), [:])
        XCTAssertEqual(MealCoachRequest.nutrientIDs(meal: meal, selectedIndex: 0), ["carbohydrate"])
    }

    func testVegetableNamesMapToFiberAndVitamin() {
        let nutrients = NutritionEstimator.estimateNutrients(forName: "콩나물무침")

        XCTAssertTrue(nutrients.contains("식이섬유"))
        XCTAssertTrue(nutrients.contains("비타민"))
    }

    func testSauceAndSobaDoNotInferProteinOrIron() {
        for name in ["소스", "소바"] {
            let nutrients = NutritionEstimator.estimateNutrients(forName: name)

            XCTAssertFalse(nutrients.contains("단백질"), name)
            XCTAssertFalse(nutrients.contains("철분"), name)
        }
    }

    func testBeefStillInfersProteinAndIron() {
        let nutrients = NutritionEstimator.estimateNutrients(forName: "소고기불고기")

        XCTAssertTrue(nutrients.contains("단백질"))
        XCTAssertTrue(nutrients.contains("철분"))
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
        XCTAssertTrue(summary.contains("변화 흐름"))
    }

    func testParentSummaryFocusesOnChangeInsteadOfScoreComparison() {
        let difficult = ChallengeRecord(
            date: "20260619",
            menuName: "시금치나물",
            action: .skipped,
            gainedExp: 3,
            badgeName: nil,
            nutrients: ["식이섬유", "비타민"],
            createdAt: Date(timeIntervalSince1970: 1),
            eatingStatus: .difficultToday
        )
        let oneBite = ChallengeRecord(
            date: "20260620",
            menuName: "시금치나물",
            action: .oneBite,
            gainedExp: 43,
            badgeName: "초록 용사",
            nutrients: ["식이섬유", "비타민"],
            createdAt: Date(timeIntervalSince1970: 2),
            eatingStatus: .oneBite
        )

        let summary = NutritionEstimator.makeParentSummary(records: [oneBite, difficult])

        XCTAssertTrue(summary.contains("어려워했지만"))
        XCTAssertTrue(summary.contains("한 입 도전까지 성공"))
        XCTAssertFalse(summary.contains("점수"))
    }
}
