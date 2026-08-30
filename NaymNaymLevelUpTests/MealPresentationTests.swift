import Foundation
import XCTest
@testable import NaymNaymLevelUp

final class MealPresentationTests: XCTestCase {
    func testStructuredNutrientsWinOverKeywordRules() throws {
        let engine = try NutritionRuleEngine(ruleData: contractData())
        let item = RebuildMealItem(
            name: "시금치",
            allergyCodes: [],
            nutrients: ["protein"],
            tags: [],
            sourceRawText: "시금치"
        )

        let visual = MealVisualResolver.resolve(item: item, engine: engine)

        XCTAssertEqual(visual.category, .vegetable)
        XCTAssertEqual(visual.confidence, .exact)
        XCTAssertEqual(visual.representativeNutrientIDs, ["protein"])
    }

    func testNutritionInsightExposesOptionalPresentationMetadata() throws {
        let insight = try NutritionRuleEngine(ruleData: contractData())
            .insight(menuName: "시금치나물")

        XCTAssertEqual(insight.foodCategory, .vegetable)
        XCTAssertEqual(insight.confidence, .keyword)
        XCTAssertEqual(insight.iconKey, "food.vegetable")
        XCTAssertEqual(insight.representativeNutrientIDs, ["fiber", "vitamin"])
    }

    func testExactKeywordAndFallbackConfidenceAreDeterministic() throws {
        let engine = try NutritionRuleEngine(ruleData: contractData())
        let exact = RebuildMealItem(
            name: "시금치",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "시금치"
        )
        let keyword = RebuildMealItem(
            name: "시금치나물",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "시금치나물"
        )
        let unknown = RebuildMealItem(
            name: "처음 보는 메뉴",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "처음 보는 메뉴"
        )

        XCTAssertEqual(
            MealVisualResolver.resolve(item: exact, engine: engine).confidence,
            .exact
        )
        XCTAssertEqual(
            MealVisualResolver.resolve(item: keyword, engine: engine).confidence,
            .keyword
        )
        XCTAssertEqual(
            MealVisualResolver.resolve(item: unknown, engine: engine).confidence,
            .fallback
        )
        XCTAssertEqual(
            MealVisualResolver.resolve(item: keyword, engine: engine),
            MealVisualResolver.resolve(item: keyword, engine: engine)
        )
    }

    func testEveryFoodCategoryHasAnIconManifestKey() {
        for category in MealFoodCategory.allCases {
            let key = MealVisualIconManifest.iconKey(for: category)
            XCTAssertFalse(key.isEmpty, "Missing icon key for \(category)")
            XCTAssertTrue(key.hasPrefix("food."))
            XCTAssertNotNil(MealVisualIconManifest.systemSymbol(for: key))
        }
    }

    func testUnknownMenuUsesNeutralFallbackWithoutLoadingMissingAsset() throws {
        let item = RebuildMealItem(
            name: "처음 보는 메뉴",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "처음 보는 메뉴"
        )
        let visual = MealVisualResolver.resolve(
            item: item,
            engine: try NutritionRuleEngine(ruleData: contractData())
        )

        XCTAssertEqual(visual.confidence, .fallback)
        XCTAssertEqual(visual.iconKey, "food.other")
        XCTAssertFalse(visual.iconKey.isEmpty)
        XCTAssertEqual(
            MealVisualIconManifest.systemSymbol(for: visual.iconKey),
            "fork.knife"
        )
    }

    func testPresentationDoesNotMutateOriginalMenuOrAllergyData() throws {
        let item = RebuildMealItem(
            name: "  시금치나물 (5) ",
            allergyCodes: [5, 6],
            nutrients: [],
            tags: ["초록"],
            sourceRawText: "  시금치나물 (5) "
        )
        let original = item

        _ = MealVisualResolver.resolve(
            item: item,
            engine: try NutritionRuleEngine(ruleData: contractData())
        )

        XCTAssertEqual(item, original)
        XCTAssertEqual(item.name, "  시금치나물 (5) ")
        XCTAssertEqual(item.allergyCodes, [5, 6])
    }

    func testRepresentativeCopyContainsNoQuantitiesOrUnsafeWording() throws {
        let item = RebuildMealItem(
            name: "시금치나물",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "시금치나물"
        )
        let visual = MealVisualResolver.resolve(
            item: item,
            engine: try NutritionRuleEngine(ruleData: contractData())
        )
        let copy = visual.representativeCopy

        XCTAssertNil(copy.range(of: #"\d+\s*(g|mg|kcal)"#, options: .regularExpression))
        XCTAssertFalse(copy.contains("결핍"))
        XCTAssertFalse(copy.contains("건강이 나빠"))
        XCTAssertFalse(copy.contains("반드시 먹"))
    }

    func testAllergyAvoidanceCopyContainsNoLossOrRetryLanguage() {
        let copy = MealPresentationCopy.allergyAvoidance

        XCTAssertFalse(copy.contains("놓칠"))
        XCTAssertFalse(copy.contains("손실"))
        XCTAssertFalse(copy.contains("다음에 먹"))
        XCTAssertFalse(copy.contains("다시 먹"))
        XCTAssertFalse(copy.contains("조금만"))
        XCTAssertFalse(copy.contains("retry"))
    }

    func testWholeMealTotalsCarryTheWholeMealSourceLabel() {
        let nutrition = RebuildNutritionInfo(
            carbs: 84,
            protein: 21,
            fat: 16,
            calcium: 180,
            iron: 4,
            vitamin: 10
        )
        let meal = RebuildMealDay(
            date: "2026-08-26",
            menuItems: [],
            calorie: "770 Kcal",
            nutrition: nutrition
        )

        let totals = MealWholeMealTotals(meal: meal)

        XCTAssertTrue(totals.sourceLabel.contains("전체 급식"))
        XCTAssertTrue(totals.sourceLabel.contains("NEIS"))
        XCTAssertEqual(totals.calorie, meal.calorie)
        XCTAssertEqual(totals.nutrition, meal.nutrition)
    }

    private func contractData() throws -> Data {
        try loadRebuildContractData(named: "nutrition-rules.json")
    }
}
