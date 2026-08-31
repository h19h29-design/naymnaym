import Foundation
import SwiftUI

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
            return "메뉴"
        }
    }
}

enum NutritionRuleResolutionSource: Equatable, Sendable {
    case loadedRules
    case fallbackRulesUnavailable
}

struct MealVisual: Equatable, Sendable {
    let category: MealFoodCategory
    let iconKey: String
    let confidence: NutritionMatchConfidence
    let representativeNutrientIDs: [String]
    let ruleVersion: Int
    let ruleSource: NutritionRuleResolutionSource

    init(
        category: MealFoodCategory,
        iconKey: String,
        confidence: NutritionMatchConfidence,
        representativeNutrientIDs: [String],
        ruleVersion: Int = NutritionRuleEngine.supportedRuleVersion,
        ruleSource: NutritionRuleResolutionSource = .loadedRules
    ) {
        self.category = category
        self.iconKey = iconKey
        self.confidence = confidence
        self.representativeNutrientIDs = representativeNutrientIDs
        self.ruleVersion = ruleVersion
        self.ruleSource = ruleSource
    }

    var categoryLabel: String {
        category.childLabel
    }

    var confidenceLabel: String {
        confidence.childLabel
    }

    var representativeNutrientLabels: [String] {
        Array(
            representativeNutrientIDs
                .compactMap(MealPresentationCopy.nutrientName(for:))
                .prefix(3)
        )
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
        renderTarget(for: iconKey, availableAssetKeys: [])
    }

    static func renderTarget(
        for iconKey: String,
        availableAssetKeys: Set<String>
    ) -> MealIconRenderTarget {
        guard semanticKeys.contains(iconKey) else {
            return .system("fork.knife")
        }
        if availableAssetKeys.contains(iconKey) {
            return .asset(iconKey)
        }
        return .system(systemSymbol(for: iconKey) ?? "fork.knife")
    }
}

enum MealIconRenderTarget: Equatable, Sendable {
    case asset(String)
    case system(String)
}

struct MealVisualIcon: View {
    let iconKey: String

    @ViewBuilder
    var body: some View {
        switch MealVisualIconManifest.renderTarget(for: iconKey) {
        case let .asset(name):
            Image(name)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        case let .system(symbol):
            Image(systemName: symbol)
                .accessibilityHidden(true)
        }
    }
}

struct MealNutrientChips: View {
    let nutrientLabels: [String]

    init(nutrientIDs: [String]) {
        nutrientLabels = Array(
            nutrientIDs
                .compactMap(MealPresentationCopy.nutrientName(for:))
                .prefix(3)
        )
    }

    @ViewBuilder
    var body: some View {
        if nutrientLabels.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(nutrientLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(RebuildDesignTokens.leaf300.opacity(0.28))
                        .clipShape(Capsule())
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                nutrientLabels
                    .map { "대표 영양소: \($0)" }
                    .joined(separator: ", ")
            )
        }
    }
}

enum MealPresentationCopy {
    static let allergyAvoidance =
        "안전하게 피한 선택이 가장 중요해요. 보호자와 학교 안내를 먼저 확인해요."

    static func wholeMealSourceLabel(
        isDemoMode: Bool,
        isAveraged: Bool = false
    ) -> String {
        let source = isDemoMode ? "체험 급식" : "NEIS 제공"
        let average = isAveraged ? " (기간 평균)" : ""
        return "전체 급식 기준 · \(source)\(average)"
    }

    static func representative(
        category: MealFoodCategory,
        nutrientIDs: [String]
    ) -> String {
        let names = nutrientIDs.compactMap(nutrientName(for:))
        guard !names.isEmpty else {
            return "메뉴 이름을 중심으로 확인해 주세요."
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

    init(meal: RebuildMealDay, isDemoMode: Bool = false) {
        calorie = meal.calorie
        nutrition = meal.nutrition
        sourceLabel = MealPresentationCopy.wholeMealSourceLabel(
            isDemoMode: isDemoMode
        )
    }

    var nutritionSummary: String {
        let items = [
            summaryItem(.carbs, label: "탄수화물", value: nutrition.carbs),
            summaryItem(.protein, label: "단백질", value: nutrition.protein),
            summaryItem(.fat, label: "지방", value: nutrition.fat),
            summaryItem(.calcium, label: "칼슘", value: nutrition.calcium),
            summaryItem(.iron, label: "철분", value: nutrition.iron),
            summaryItem(.vitamin, label: "비타민", value: nutrition.vitamin),
        ].compactMap { $0 }
        return items.isEmpty ? "영양 정보 없음" : items.joined(separator: " · ")
    }

    private func summaryItem(
        _ field: RebuildNutritionInfo.SourceField,
        label: String,
        value: Double
    ) -> String? {
        guard nutrition.sourceFields.contains(field) else { return nil }
        // NEIS does not provide a reliable unit for vitamin in this parser;
        // keep it unit-neutral instead of inventing an mg suffix.
        let unit = field == .vitamin
            ? nil
            : nutrition.sourceUnits[field]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let suffix = unit.map { " \($0)" } ?? ""
        return "\(label) \(String(value))\(suffix)"
    }
}

struct MealRecordingAccessibilityDescriptor: Equatable, Sendable {
    let menu: MealAccessibilityDescriptor
    let wholeMealLabel: String
    let callToActionLabel: String

    var readingOrder: [String] {
        menu.readingOrder + [wholeMealLabel, callToActionLabel]
    }
}

struct MealScheduleAccessibilityDescriptor: Equatable, Sendable {
    let menuLabels: [String]
    let allergySummary: String
    let nutritionSummary: String
    let callToActionLabel: String?

    var readingOrder: [String] {
        menuLabels
            + [allergySummary, nutritionSummary]
            + (callToActionLabel.map { [$0] } ?? [])
    }
}

struct MealRecordingActionDescriptor: Equatable, Sendable {
    let menuName: String

    var prompt: String {
        "‘\(menuName)’ 어떻게 만났나요?"
    }

    func controlLabel(for title: String) -> String {
        "\(menuName), \(title)"
    }

    func statusHint(
        for status: RebuildEatingStatus,
        enabled: Bool
    ) -> String {
        enabled
            ? "‘\(menuName)’ 메뉴를 \(status.childTitle) 상태로 기록합니다"
            : "‘\(menuName)’ 메뉴는 알레르기 주의라 안전하게 피하기만 기록할 수 있습니다"
    }

    var allergyAvoidanceLabel: String {
        controlLabel(for: RebuildEatingStatus.allergyAvoided.childTitle)
    }

    var allergyAvoidanceHint: String {
        "‘\(menuName)’ 메뉴의 알레르기 회피로 안전하게 기록합니다"
    }

    var guardianConfirmationLabel: String {
        controlLabel(for: "보호자와 확인하기")
    }

    var guardianConfirmationHint: String {
        "‘\(menuName)’ 메뉴의 알레르기 보호자 확인 안내를 엽니다"
    }

    func controlOrder(
        statusTitles: [String],
        includesAllergySafety: Bool
    ) -> [String] {
        var labels = [prompt]
        if includesAllergySafety {
            labels.append(allergyAvoidanceLabel)
            labels.append(guardianConfirmationLabel)
        }
        labels.append(contentsOf: statusTitles.map { controlLabel(for: $0) })
        return labels
    }
}

struct MealAccessibilityDescriptor: Equatable, Sendable {
    let menuName: String
    let allergyWarning: String?
    let categoryLabel: String
    let representativeNutrientLabels: [String]
    let currentState: String?

    init(
        item: RebuildMealItem,
        visual: MealVisual,
        currentState: String? = nil
    ) {
        menuName = item.name
        allergyWarning = item.allergyLabels.isEmpty
            ? nil
            : "알레르기: \(item.allergyLabels.joined(separator: " · "))"
        categoryLabel = visual.categoryLabel
        representativeNutrientLabels = visual.representativeNutrientLabels
        self.currentState = currentState
    }

    var readingOrder: [String] {
        var values = [menuName]
        if let allergyWarning {
            values.append(allergyWarning)
        }
        values.append(categoryLabel)
        values.append(
            contentsOf: representativeNutrientLabels.map {
                "대표 영양소: \($0)"
            }
        )
        if let currentState {
            values.append(currentState)
        }
        return values
    }

    var spokenLabel: String {
        readingOrder.joined(separator: ", ")
    }
}

struct MealMonthCellSummary: Equatable, Sendable {
    let dateLabel: String
    let representativeIconKey: String?
    let additionalMenuCount: Int

    init(dateLabel: String, visuals: [MealVisual]) {
        self.dateLabel = dateLabel
        representativeIconKey = visuals.first?.iconKey
        additionalMenuCount = max(visuals.count - 1, 0)
    }

    var additionalMenuLabel: String? {
        additionalMenuCount > 0 ? "+\(additionalMenuCount)" : nil
    }

    var compactLabels: [String] {
        [dateLabel] + (additionalMenuLabel.map { [$0] } ?? [])
    }
}

struct MealVisualResolver {
    let engine: NutritionRuleEngine

    init(engine: NutritionRuleEngine) {
        self.engine = engine
    }

    static let bundled: MealVisualResolver? = {
        guard let engine = try? NutritionRuleEngine() else { return nil }
        return MealVisualResolver(engine: engine)
    }()

    func resolve(item: RebuildMealItem) -> MealVisual {
        Self.resolve(item: item, engine: engine)
    }

    static func resolve(item: RebuildMealItem) -> MealVisual {
        guard let bundled else {
            return fallback(
                ruleVersion: NutritionRuleEngine.unavailableFallbackRuleVersion,
                ruleSource: .fallbackRulesUnavailable
            )
        }
        return bundled.resolve(item: item)
    }

    static func resolve(
        item: RebuildMealItem,
        engine: NutritionRuleEngine?
    ) -> MealVisual {
        guard let engine else {
            return fallback(
                ruleVersion: NutritionRuleEngine.unavailableFallbackRuleVersion,
                ruleSource: .fallbackRulesUnavailable
            )
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
        let selectedMatch = matches.first(where: { $0.matchKind == .exact })
            ?? matches.first(where: { $0.matchKind == .keyword })

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
                representativeNutrientIDs: nutrientIDs,
                ruleVersion: engine.ruleVersion,
                ruleSource: .loadedRules
            )
        }

        guard !structuredNutrients.isEmpty else {
            return fallback(
                ruleVersion: engine.ruleVersion,
                ruleSource: .loadedRules
            )
        }

        let category = category(for: presentationName, metadata: nil)
        return MealVisual(
            category: category,
            iconKey: MealVisualIconManifest.iconKey(for: category),
            confidence: .exact,
            representativeNutrientIDs: structuredNutrients,
            ruleVersion: engine.ruleVersion,
            ruleSource: .loadedRules
        )
    }

    static func fallback(
        ruleVersion: Int = NutritionRuleEngine.unavailableFallbackRuleVersion,
        ruleSource: NutritionRuleResolutionSource = .fallbackRulesUnavailable
    ) -> MealVisual {
        MealVisual(
            category: .other,
            iconKey: MealVisualIconManifest.iconKey(for: .other),
            confidence: .fallback,
            representativeNutrientIDs: [],
            ruleVersion: ruleVersion,
            ruleSource: ruleSource
        )
    }

    private static func validatedIconKey(
        _ candidate: String?,
        category: MealFoodCategory
    ) -> String {
        guard let candidate,
              MealVisualIconManifest.systemSymbol(for: candidate) != nil,
              MealVisualIconManifest.category(for: candidate) == category
        else {
            return MealVisualIconManifest.iconKey(for: category)
        }
        return candidate
    }

    private static func category(
        for menuName: String,
        metadata: MealFoodCategory?
    ) -> MealFoodCategory {
        if let metadata {
            return metadata
        }
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
        return .other
    }
}
