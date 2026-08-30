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

    func testCanonicalMetadataWinsOverBroadKeywordCollision() throws {
        let engine = try NutritionRuleEngine(ruleData: contractData())
        let item = RebuildMealItem(
            name: "콩나물",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "콩나물"
        )

        let visual = MealVisualResolver.resolve(item: item, engine: engine)

        XCTAssertEqual(visual.category, .vegetable)
        XCTAssertEqual(visual.iconKey, "food.vegetable")
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

    func testDecodedRuleConfidenceAffectsDeterministicKeywordOutput() throws {
        let fallbackEngine = try NutritionRuleEngine(
            ruleData: contractData(overridingFirstRuleConfidence: "fallback")
        )
        let exactEngine = try NutritionRuleEngine(
            ruleData: contractData(overridingFirstRuleConfidence: "exact")
        )
        let item = RebuildMealItem(
            name: "시금치나물",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "시금치나물"
        )

        XCTAssertEqual(
            MealVisualResolver.resolve(item: item, engine: fallbackEngine).confidence,
            .fallback
        )
        XCTAssertEqual(
            MealVisualResolver.resolve(item: item, engine: exactEngine).confidence,
            .exact
        )
        XCTAssertEqual(
            fallbackEngine.insight(menuName: item.name).confidence,
            .fallback
        )
    }

    func testInjectedResolverUsesOneCachedImmutableEngine() throws {
        let engine = try NutritionRuleEngine(ruleData: contractData())
        let resolver = MealVisualResolver(engine: engine)
        let item = RebuildMealItem(
            name: "시금치나물",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "시금치나물"
        )

        XCTAssertEqual(
            resolver.resolve(item: item),
            MealVisualResolver.resolve(item: item, engine: engine)
        )
        XCTAssertNotNil(MealVisualResolver.bundled)
        XCTAssertEqual(
            MealVisualResolver.bundled?.resolve(item: item),
            MealVisualResolver.resolve(item: item)
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

    func testIconRenderTargetSupportsAssetPathAndVerifiedSystemFallback() {
        XCTAssertEqual(
            MealVisualIconManifest.renderTarget(for: "food.vegetable"),
            .system("leaf.fill")
        )
        XCTAssertEqual(
            MealVisualIconManifest.renderTarget(
                for: "food.vegetable",
                availableAssetKeys: ["food.vegetable"]
            ),
            .asset("food.vegetable")
        )
        XCTAssertEqual(
            MealVisualIconManifest.renderTarget(for: "food.unknown"),
            .system("fork.knife")
        )
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
        XCTAssertEqual(
            visual.representativeCopy,
            "메뉴 이름을 중심으로 확인해 주세요."
        )
        XCTAssertFalse(visual.representativeCopy.contains("여러 재료"))
        XCTAssertFalse(visual.representativeCopy.contains("영양"))
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
        XCTAssertTrue(totals.nutritionSummary.contains("탄수화물"))
        XCTAssertTrue(totals.nutritionSummary.contains("단백질"))
    }

    func testRepresentativeChipsAndAccessibilityDescriptorKeepSafeOrder() throws {
        let item = RebuildMealItem(
            name: "시금치나물",
            allergyCodes: [1],
            nutrients: [],
            tags: [],
            sourceRawText: "시금치나물"
        )
        let visual = MealVisualResolver.resolve(
            item: item,
            engine: try NutritionRuleEngine(ruleData: contractData())
        )
        let descriptor = MealAccessibilityDescriptor(
            item: item,
            visual: visual,
            currentState: "기록 완료"
        )

        XCTAssertEqual(visual.representativeNutrientLabels, ["식이섬유", "비타민"])
        XCTAssertEqual(
            descriptor.readingOrder,
            [
                "시금치나물",
                "알레르기: 1. 난류",
                "채소",
                "대표 영양소: 식이섬유",
                "대표 영양소: 비타민",
                "기록 완료",
            ]
        )
        XCTAssertEqual(
            descriptor.spokenLabel,
            descriptor.readingOrder.joined(separator: ", ")
        )
    }

    func testMonthCellSummaryIsCompactDateIconAndAdditionalCount() {
        let vegetable = MealVisual(
            category: .vegetable,
            iconKey: "food.vegetable",
            confidence: .keyword,
            representativeNutrientIDs: ["fiber"]
        )
        let fish = MealVisual(
            category: .fish,
            iconKey: "food.fish",
            confidence: .keyword,
            representativeNutrientIDs: ["protein"]
        )

        let summary = MealMonthCellSummary(
            dateLabel: "26",
            visuals: [vegetable, fish]
        )

        XCTAssertEqual(summary.dateLabel, "26")
        XCTAssertEqual(summary.representativeIconKey, "food.vegetable")
        XCTAssertEqual(summary.additionalMenuCount, 1)
        XCTAssertEqual(summary.additionalMenuLabel, "+1")
        XCTAssertEqual(summary.compactLabels, ["26", "+1"])
    }

    private func contractData(
        overridingFirstRuleConfidence confidence: String? = nil
    ) throws -> Data {
        let data = try loadRebuildContractData(named: "nutrition-rules.json")
        guard let confidence else { return data }
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var rules = try XCTUnwrap(object["rules"] as? [[String: Any]])
        rules[0]["confidence"] = confidence
        object["rules"] = rules
        return try JSONSerialization.data(withJSONObject: object)
    }
}
