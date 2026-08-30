import Foundation

enum NutritionMatchConfidence: String, Codable, Sendable {
    case exact
    case keyword
    case fallback

    var childLabel: String {
        switch self {
        case .exact:
            return "메뉴 정보 확인"
        case .keyword:
            return "메뉴 이름으로 확인"
        case .fallback:
            return "일반 안내"
        }
    }
}

enum MealFoodCategory: String, Codable, CaseIterable, Sendable {
    case grain
    case soup
    case meat
    case fish
    case egg
    case bean
    case vegetable
    case fruit
    case dairy
    case noodle
    case bread
    case kimchi
    case other

    var childLabel: String {
        switch self {
        case .grain:
            return "밥"
        case .soup:
            return "국이나 찌개"
        case .meat:
            return "고기"
        case .fish:
            return "생선"
        case .egg:
            return "달걀"
        case .bean:
            return "콩이나 두부"
        case .vegetable:
            return "채소"
        case .fruit:
            return "과일"
        case .dairy:
            return "유제품"
        case .noodle:
            return "면"
        case .bread:
            return "빵이나 떡"
        case .kimchi:
            return "김치"
        case .other:
            return "여러 재료"
        }
    }
}

struct MealVisual: Equatable, Sendable {
    let category: MealFoodCategory
    let iconKey: String
    let confidence: NutritionMatchConfidence
    let representativeNutrientIDs: [String]

    var categoryLabel: String {
        category.childLabel
    }

    var confidenceLabel: String {
        confidence.childLabel
    }

    var representativeCopy: String {
        MealPresentationCopy.representative(
            category: category,
            nutrientIDs: representativeNutrientIDs
        )
    }
}

/// Semantic menu keys are intentionally separate from SF Symbol names.
/// Every key has a verified system fallback so an unavailable art asset can
/// never result in a blank image or an attempt to load the semantic key.
enum MealVisualIconManifest {
    private static let keys: [MealFoodCategory: String] = [
        .grain: "food.grain",
        .soup: "food.soup",
        .meat: "food.meat",
        .fish: "food.fish",
        .egg: "food.egg",
        .bean: "food.bean",
        .vegetable: "food.vegetable",
        .fruit: "food.fruit",
        .dairy: "food.dairy",
        .noodle: "food.noodle",
        .bread: "food.bread",
        .kimchi: "food.kimchi",
        .other: "food.other",
    ]

    // These symbols are present in the iOS 16 SDK supported by the app.
    private static let verifiedSystemFallbacks: [String: String] = [
        "food.grain": "fork.knife",
        "food.soup": "cup.and.saucer.fill",
        "food.meat": "fork.knife",
        "food.fish": "fish.fill",
        "food.egg": "oval.fill",
        "food.bean": "leaf.fill",
        "food.vegetable": "leaf.fill",
        "food.fruit": "leaf.fill",
        "food.dairy": "cup.and.saucer.fill",
        "food.noodle": "fork.knife",
        "food.bread": "fork.knife",
        "food.kimchi": "leaf.fill",
        "food.other": "fork.knife",
    ]

    static var semanticKeys: Set<String> {
        Set(keys.values)
    }

    static var fallbackManifest: [String: String] {
        verifiedSystemFallbacks
    }

    static func iconKey(for category: MealFoodCategory) -> String {
        keys[category] ?? "food.other"
    }

    static func category(for iconKey: String) -> MealFoodCategory? {
        keys.first(where: { $0.value == iconKey })?.key
    }

    static func systemSymbol(for iconKey: String) -> String? {
        verifiedSystemFallbacks[iconKey]
    }

    static func renderTarget(for iconKey: String) -> MealIconRenderTarget {
        .system(systemSymbol(for: iconKey) ?? "fork.knife")
    }
}

enum MealIconRenderTarget: Equatable, Sendable {
    case asset(String)
    case system(String)
}

enum MealPresentationCopy {
    static let allergyAvoidance =
        "안전하게 피한 선택이 가장 중요해요. 보호자와 학교 안내를 먼저 확인해요."

    static func representative(
        category: MealFoodCategory,
        nutrientIDs: [String]
    ) -> String {
        let names = nutrientIDs.compactMap(nutrientName(for:))
        guard !names.isEmpty else {
            return "여러 재료의 영양을 만나는 메뉴예요."
        }
        return "\(category.childLabel)에서 \(names.joined(separator: "와 "))을 만날 수 있어요."
    }

    static func nutrientName(for id: String) -> String? {
        switch id {
        case "fiber":
            return "식이섬유"
        case "vitamin":
            return "비타민"
        case "protein":
            return "단백질"
        case "iron":
            return "철분"
        case "calcium":
            return "칼슘"
        case "carbohydrate":
            return "탄수화물"
        default:
            return nil
        }
    }
}

struct MealWholeMealTotals: Equatable, Sendable {
    let calorie: String
    let nutrition: RebuildNutritionInfo
    let sourceLabel: String

    init(meal: RebuildMealDay) {
        calorie = meal.calorie
        nutrition = meal.nutrition
        sourceLabel = "전체 급식 기준 · NEIS 제공"
    }
}

enum MealVisualResolver {
    static func resolve(item: RebuildMealItem) -> MealVisual {
        guard let engine = try? NutritionRuleEngine() else {
            return fallback()
        }
        return resolve(item: item, engine: engine)
    }

    static func resolve(
        item: RebuildMealItem,
        engine: NutritionRuleEngine
    ) -> MealVisual {
        let presentationName = item.normalizedPresentationName
        let matches = engine.presentationMatches(menuName: presentationName)
        let structuredNutrients = engine.orderedKnownNutrientIDs(
            from: item.nutrients
        )
        let selectedMatch = matches.first(where: { $0.confidence == .exact })
            ?? matches.first(where: { $0.confidence == .keyword })

        if let selectedMatch {
            let category = category(
                for: presentationName,
                metadata: selectedMatch.foodCategory
            )
            let nutrientIDs = structuredNutrients.isEmpty
                ? engine.orderedKnownNutrientIDs(
                    from: selectedMatch.representativeNutrientIDs
                        ?? selectedMatch.nutrientIDs
                )
                : structuredNutrients
            let confidence: NutritionMatchConfidence = structuredNutrients.isEmpty
                ? selectedMatch.confidence
                : .exact
            let iconKey = validatedIconKey(
                selectedMatch.iconKey,
                category: category
            )
            return MealVisual(
                category: category,
                iconKey: iconKey,
                confidence: confidence,
                representativeNutrientIDs: nutrientIDs
            )
        }

        guard !structuredNutrients.isEmpty else {
            return fallback()
        }

        let category = category(for: presentationName, metadata: nil)
        return MealVisual(
            category: category,
            iconKey: MealVisualIconManifest.iconKey(for: category),
            confidence: .exact,
            representativeNutrientIDs: structuredNutrients
        )
    }

    static func fallback() -> MealVisual {
        MealVisual(
            category: .other,
            iconKey: MealVisualIconManifest.iconKey(for: .other),
            confidence: .fallback,
            representativeNutrientIDs: []
        )
    }

    private static func validatedIconKey(
        _ candidate: String?,
        category: MealFoodCategory
    ) -> String {
        guard let candidate,
              MealVisualIconManifest.systemSymbol(for: candidate) != nil
        else {
            return MealVisualIconManifest.iconKey(for: category)
        }
        return candidate
    }

    private static func category(
        for menuName: String,
        metadata: MealFoodCategory?
    ) -> MealFoodCategory {
        let normalized = menuName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        // Specific ingredients win over broad menu words such as "고기".
        let orderedRules: [(MealFoodCategory, [String])] = [
            (.kimchi, ["김치", "깍두기", "석박지", "겉절이"]),
            (.fish, ["생선", "고등어", "멸치", "연어", "오징어", "새우"]),
            (.egg, ["계란", "달걀", "오믈렛", "후라이"]),
            (.bean, ["두부", "콩", "된장", "청국장"]),
            (.dairy, ["우유", "치즈", "요구르트", "요거트"]),
            (.fruit, ["과일", "사과", "귤", "토마토", "배", "포도"]),
            (.vegetable, [
                "나물", "시금치", "콩나물", "채소", "샐러드", "오이",
                "상추", "깻잎", "브로콜리", "당근", "버섯",
            ]),
            (.soup, ["국", "탕", "찌개", "스프", "전골"]),
            (.noodle, ["면", "국수", "우동", "라면", "잡채"]),
            (.bread, ["빵", "떡", "토스트"]),
            (.grain, ["밥", "라이스", "죽", "카레"]),
            (.meat, ["닭", "돼지", "소고기", "고기", "불고기"]),
        ]
        if let match = orderedRules.first(where: { _, keywords in
            keywords.contains(where: normalized.contains)
        }) {
            return match.0
        }
        return metadata ?? .other
    }
}
