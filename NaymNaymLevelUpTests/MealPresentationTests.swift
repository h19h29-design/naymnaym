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

    func testSauceAndSobaDoNotInheritBroadBeefKeyword() throws {
        let engine = try NutritionRuleEngine(ruleData: contractData())

        XCTAssertEqual(
            engine.insight(menuName: "소스").nutrients.map(\.id),
            []
        )
        XCTAssertEqual(
            engine.insight(menuName: "소바").nutrients.map(\.id),
            []
        )
    }

    func testSpecificBeefKeywordStillMatchesProteinAndIron() throws {
        let engine = try NutritionRuleEngine(ruleData: contractData())

        XCTAssertEqual(
            engine.insight(menuName: "소고기불고기").nutrients.map(\.id),
            ["protein", "iron"]
        )
    }

    func testRebuildNutritionParsingTracksOnlyPresentSourceFieldsAndUnits() {
        let nutrition = MealParser.parseRebuildNutrition(
            text: "탄수화물(g) : 84.25<br/>단백질(g) : 21.5<br/>비타민 : 42"
        )

        XCTAssertEqual(
            nutrition.sourceFields,
            [.carbs, .protein, .vitamin]
        )
        XCTAssertEqual(
            nutrition.sourceUnits,
            [.carbs: "g", .protein: "g"]
        )
        XCTAssertEqual(nutrition.carbs, 84.25, accuracy: 0.001)
        XCTAssertEqual(nutrition.vitamin, 42, accuracy: 0.001)
    }

    func testLegacyNutritionPayloadInfersOnlyNonzeroSourceFieldsWithoutInventingUnits() throws {
        let data = try XCTUnwrap(
            """
            {
              "carbs": 84.25,
              "protein": 0,
              "fat": 0,
              "calcium": 180.75,
              "iron": 0,
              "vitamin": 42
            }
            """.data(using: .utf8)
        )

        let nutrition = try JSONDecoder().decode(
            RebuildNutritionInfo.self,
            from: data
        )

        XCTAssertEqual(nutrition.sourceFields, [.carbs, .calcium, .vitamin])
        XCTAssertEqual(nutrition.sourceUnits, [:])
    }

    func testExplicitEmptyNutritionSourceFieldsRemainEmptyForNewPayloads() throws {
        let data = try XCTUnwrap(
            """
            {
              "carbs": 84.25,
              "protein": 21.5,
              "fat": 0,
              "calcium": 180.75,
              "iron": 0,
              "vitamin": 42,
              "sourceFields": [],
              "sourceUnits": {}
            }
            """.data(using: .utf8)
        )

        let nutrition = try JSONDecoder().decode(
            RebuildNutritionInfo.self,
            from: data
        )

        XCTAssertEqual(nutrition.sourceFields, [])
        XCTAssertEqual(nutrition.sourceUnits, [:])
    }

    func testCurrentNutritionSourceUnitArrayDecodesAlternatingKeyAndUnitStrings() throws {
        let data = try XCTUnwrap(
            """
            {
              "carbs": 0,
              "protein": 21.5,
              "fat": 0,
              "calcium": 0,
              "iron": 0,
              "vitamin": 0,
              "sourceFields": ["protein"],
              "sourceUnits": ["protein", "g"]
            }
            """.data(using: .utf8)
        )

        let nutrition = try JSONDecoder().decode(
            RebuildNutritionInfo.self,
            from: data
        )

        XCTAssertEqual(nutrition.sourceUnits, [.protein: "g"])
    }

    func testObjectNutritionSourceUnitMapConservativelyDowngradesToEmpty() throws {
        let data = try XCTUnwrap(
            """
            {
              "carbs": 0,
              "protein": 21.5,
              "fat": 0,
              "calcium": 0,
              "iron": 0,
              "vitamin": 0,
              "sourceFields": ["protein"],
              "sourceUnits": {
                "protein": "g",
                "unknown": "mg",
                "fat": 12
              }
            }
            """.data(using: .utf8)
        )

        let nutrition = try JSONDecoder().decode(
            RebuildNutritionInfo.self,
            from: data
        )

        XCTAssertEqual(nutrition.sourceUnits, [:])
    }

    func testDuplicateNutritionSourceUnitObjectDowngradesToEmptyMap() throws {
        let data = try XCTUnwrap(
            """
            {
              "carbs": 0,
              "protein": 21.5,
              "fat": 0,
              "calcium": 0,
              "iron": 0,
              "vitamin": 0,
              "sourceFields": ["protein"],
              "sourceUnits": {
                "protein": "g",
                "protein": "mg"
              }
            }
            """.data(using: .utf8)
        )

        let nutrition = try JSONDecoder().decode(
            RebuildNutritionInfo.self,
            from: data
        )

        XCTAssertEqual(nutrition.sourceUnits, [:])
    }

    func testMalformedOrUnknownNutritionSourceUnitArrayDowngradesToEmptyMap() throws {
        let invalidArrays: [[Any]] = [
            ["protein"],
            ["protein", 3],
            ["unknown", "mg"],
        ]

        for sourceUnits in invalidArrays {
            let object: [String: Any] = [
                "carbs": 0,
                "protein": 21.5,
                "fat": 0,
                "calcium": 0,
                "iron": 0,
                "vitamin": 0,
                "sourceFields": ["protein"],
                "sourceUnits": sourceUnits,
            ]
            let data = try JSONSerialization.data(
                withJSONObject: object
            )

            let nutrition = try JSONDecoder().decode(
                RebuildNutritionInfo.self,
                from: data
            )

            XCTAssertEqual(nutrition.sourceUnits, [:])
        }
    }

    func testDuplicateNutritionSourceUnitArrayDowngradesToEmptyMap() throws {
        let data = try XCTUnwrap(
            """
            {
              "carbs": 0,
              "protein": 21.5,
              "fat": 0,
              "calcium": 0,
              "iron": 0,
              "vitamin": 0,
              "sourceFields": ["protein"],
              "sourceUnits": ["protein", "g", "protein", "mg"]
            }
            """.data(using: .utf8)
        )

        let nutrition = try JSONDecoder().decode(
            RebuildNutritionInfo.self,
            from: data
        )

        XCTAssertEqual(nutrition.sourceUnits, [:])
    }

    func testWholeMealTotalsOmitMissingZerosPreserveDecimalsAndKeepVitaminUnitNeutral() {
        let nutrition = RebuildNutritionInfo(
            carbs: 84.25,
            protein: 21.5,
            fat: 0,
            calcium: 180.75,
            iron: 3.4,
            vitamin: 42.0,
            sourceFields: [.carbs, .protein, .calcium, .iron, .vitamin],
            sourceUnits: [
                .carbs: "g",
                .protein: "g",
                .calcium: "mg",
                .iron: "mg",
            ]
        )
        let meal = RebuildMealDay(
            date: "2026-08-26",
            menuItems: [],
            calorie: "770.5 Kcal",
            nutrition: nutrition
        )

        let summary = MealWholeMealTotals(meal: meal).nutritionSummary

        XCTAssertEqual(
            summary,
            "탄수화물 84.25 g · 단백질 21.5 g · 칼슘 180.75 mg · 철분 3.4 mg · 비타민 42.0"
        )
        XCTAssertFalse(summary.contains("지방"))
        XCTAssertFalse(summary.contains("지방 0"))
        XCTAssertFalse(summary.contains("비타민 42.0 mg"))
    }

    func testEmptyWholeMealNutritionDoesNotRenderInventedZeroValues() {
        let meal = RebuildMealDay(
            date: "2026-08-26",
            menuItems: [],
            calorie: "정보 없음",
            nutrition: .empty
        )

        XCTAssertEqual(
            MealWholeMealTotals(meal: meal).nutritionSummary,
            "영양 정보 없음"
        )
    }

    func testScheduleWholeMealSummaryOmitsUnavailableFieldsAndPreservesDecimals() {
        let first = RebuildMealDay(
            date: "2026-08-26",
            menuItems: [],
            calorie: "770.5 Kcal",
            nutrition: RebuildNutritionInfo(
                carbs: 0,
                protein: 12.5,
                fat: 0,
                calcium: 0,
                iron: 0,
                vitamin: 0,
                sourceFields: [.protein],
                sourceUnits: [.protein: "g"]
            )
        )
        let second = RebuildMealDay(
            date: "2026-08-27",
            menuItems: [],
            calorie: "정보 없음",
            nutrition: .empty
        )

        let summary = MealScheduleNutritionSummary(meals: [first, second])

        XCTAssertEqual(summary.tiles.map(\.title), ["열량", "단백질"])
        XCTAssertEqual(summary.tiles[0].value, "770.5 kcal")
        XCTAssertEqual(summary.tiles[1].value, "12.5 g")
    }

    func testScheduleAveragesRequireAgreedUnitsAndUseStableTrimmedPrecision() {
        func meal(
            date: String,
            calorie: String,
            protein: Double,
            unit: String?
        ) -> RebuildMealDay {
            RebuildMealDay(
                date: date,
                menuItems: [],
                calorie: calorie,
                nutrition: RebuildNutritionInfo(
                    carbs: 0,
                    protein: protein,
                    fat: 0,
                    calcium: 0,
                    iron: 0,
                    vitamin: 0,
                    sourceFields: [.protein],
                    sourceUnits: unit.map { [.protein: $0] } ?? [:]
                )
            )
        }

        let first = meal(
            date: "2026-08-26",
            calorie: "770.1 Kcal",
            protein: 0.1,
            unit: "g"
        )
        let second = meal(
            date: "2026-08-27",
            calorie: "770.2 Kcal",
            protein: 0.2,
            unit: "g"
        )
        let missingUnit = meal(
            date: "2026-08-28",
            calorie: "770.3 Kcal",
            protein: 0.3,
            unit: nil
        )
        let differentUnit = meal(
            date: "2026-08-29",
            calorie: "770.4 Kcal",
            protein: 0.3,
            unit: "mg"
        )

        let sameUnitSummary = MealScheduleNutritionSummary(meals: [first, second])
        XCTAssertEqual(sameUnitSummary.tiles[0].value, "770.15 kcal")
        XCTAssertEqual(sameUnitSummary.tiles[1].value, "0.15 g")

        let missingUnitSummary = MealScheduleNutritionSummary(
            meals: [first, missingUnit]
        )
        XCTAssertNil(
            missingUnitSummary.tiles.first(where: { $0.title == "단백질" })
        )

        let mixedUnitSummary = MealScheduleNutritionSummary(
            meals: [first, differentUnit]
        )
        XCTAssertNil(
            mixedUnitSummary.tiles.first(where: { $0.title == "단백질" })
        )

        let allUnitlessSummary = MealScheduleNutritionSummary(
            meals: [
                missingUnit,
                meal(
                    date: "2026-08-30",
                    calorie: "770.5 Kcal",
                    protein: 0.5,
                    unit: nil
                ),
            ]
        )
        XCTAssertEqual(
            allUnitlessSummary.tiles.first(where: { $0.title == "단백질" })?.value,
            "0.4"
        )
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

    func testRuleLoadFailureUsesExplicitFallbackVersionSeparateFromValidUnknownMenu() throws {
        let engine = try NutritionRuleEngine(ruleData: contractData())
        let unknown = RebuildMealItem(
            name: "처음 보는 메뉴",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "처음 보는 메뉴"
        )

        let validRulesUnknownMenu = MealVisualResolver.resolve(
            item: unknown,
            engine: engine
        )
        let rulesUnavailable = MealVisualResolver.resolve(
            item: unknown,
            engine: nil as NutritionRuleEngine?
        )

        XCTAssertEqual(validRulesUnknownMenu.confidence, .fallback)
        XCTAssertEqual(
            validRulesUnknownMenu.ruleVersion,
            NutritionRuleEngine.supportedRuleVersion
        )
        XCTAssertEqual(validRulesUnknownMenu.ruleSource, .loadedRules)
        XCTAssertEqual(rulesUnavailable.confidence, .fallback)
        XCTAssertEqual(
            rulesUnavailable.ruleVersion,
            NutrientImpactSnapshot.fallbackRuleVersion
        )
        XCTAssertEqual(rulesUnavailable.ruleSource, .fallbackRulesUnavailable)
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
            vitamin: 10,
            sourceFields: Set(RebuildNutritionInfo.SourceField.allCases),
            sourceUnits: [
                .carbs: "g",
                .protein: "g",
                .fat: "g",
                .calcium: "mg",
                .iron: "mg",
            ]
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

    func testDemoWholeMealTotalsDiscloseSampleSource() {
        let meal = RebuildMealDay(
            date: "2026-08-26",
            menuItems: [],
            calorie: "610 kcal",
            nutrition: .empty
        )

        let totals = MealWholeMealTotals(meal: meal, isDemoMode: true)

        XCTAssertEqual(totals.sourceLabel, "전체 급식 기준 · 체험 급식")
        XCTAssertFalse(totals.sourceLabel.contains("NEIS"))
    }

    func testRecordingAccessibilityPlacesMenuAndAllergyBeforeActionAndTotals() throws {
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
        let descriptor = MealRecordingAccessibilityDescriptor(
            menu: MealAccessibilityDescriptor(item: item, visual: visual),
            wholeMealLabel: "전체 급식 기준 · NEIS 제공",
            callToActionLabel: "먹은 정도 기록"
        )

        let order = descriptor.readingOrder
        let menuIndex = try XCTUnwrap(order.firstIndex(of: "시금치나물"))
        let allergyIndex = try XCTUnwrap(order.firstIndex(of: "알레르기: 1. 난류"))
        let actionIndex = try XCTUnwrap(order.firstIndex(of: "먹은 정도 기록"))
        let totalsIndex = try XCTUnwrap(order.firstIndex(of: "전체 급식 기준 · NEIS 제공"))

        XCTAssertLessThan(menuIndex, allergyIndex)
        XCTAssertLessThan(allergyIndex, totalsIndex)
        XCTAssertLessThan(totalsIndex, actionIndex)
    }

    func testScheduleAccessibilityPlacesAllergyBeforeNutritionAndCallToAction() {
        let descriptor = MealScheduleAccessibilityDescriptor(
            menuLabels: ["시금치나물"],
            allergySummary: "알레르기 정보",
            nutritionSummary: "전체 급식 영양",
            callToActionLabel: "급식 상세 보기"
        )

        XCTAssertEqual(
            descriptor.readingOrder,
            ["시금치나물", "알레르기 정보", "전체 급식 영양", "급식 상세 보기"]
        )
    }

    func testRecordingActionDescriptorNamesMenuPromptAndControls() {
        let descriptor = MealRecordingActionDescriptor(menuName: "시금치나물")

        XCTAssertEqual(descriptor.prompt, "‘시금치나물’ 어떻게 만났나요?")
        XCTAssertEqual(
            descriptor.controlLabel(for: "다 먹었어요"),
            "시금치나물, 다 먹었어요"
        )
        XCTAssertTrue(
            descriptor.statusHint(for: .finished, enabled: true)
                .contains("시금치나물")
        )
        XCTAssertTrue(
            descriptor.statusHint(for: .finished, enabled: false)
                .contains("시금치나물")
        )
    }

    func testRecordingActionDescriptorPutsPromptBeforeSafetyAndStatusControls() {
        let descriptor = MealRecordingActionDescriptor(menuName: "시금치나물")

        XCTAssertEqual(
            descriptor.controlOrder(
                statusTitles: ["다 먹었어요", "한입도전"],
                includesAllergySafety: true
            ),
            [
                "‘시금치나물’ 어떻게 만났나요?",
                "시금치나물, 알레르기로 피했어요",
                "시금치나물, 보호자와 확인하기",
                "시금치나물, 다 먹었어요",
                "시금치나물, 한입도전",
            ]
        )
    }

    func testRecordingActionDescriptorUsesParticleNeutralWording() {
        for menuName in ["시금치나물", "우유", "카레"] {
            let descriptor = MealRecordingActionDescriptor(menuName: menuName)

            XCTAssertEqual(
                descriptor.prompt,
                "‘\(menuName)’ 어떻게 만났나요?"
            )
            XCTAssertTrue(
                descriptor.statusHint(for: .finished, enabled: true)
                    .contains("‘\(menuName)’ 메뉴를")
            )
            XCTAssertTrue(
                descriptor.statusHint(for: .finished, enabled: false)
                    .contains("‘\(menuName)’ 메뉴는")
            )
        }
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
