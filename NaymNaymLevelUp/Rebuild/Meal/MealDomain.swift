import Foundation

struct RebuildSchool: Codable, Equatable, Sendable {
    let name: String
    let officeCode: String
    let schoolCode: String
}

struct RebuildMealItem: Codable, Equatable, Sendable {
    let name: String
    let allergyCodes: [Int]
    let nutrients: [String]
    let tags: [String]
    let sourceRawText: String
}

extension RebuildMealItem {
    /// Presentation normalization never replaces `name` or `sourceRawText`.
    var normalizedPresentationName: String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\([0-9.,\s]+\)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var allergyLabels: [String] {
        allergyCodes.map(AllergyMap.label(for:))
    }
}

struct RebuildNutritionInfo: Codable, Equatable, Sendable {
    enum SourceField: String, Codable, CaseIterable, Hashable, Sendable {
        case carbs
        case protein
        case fat
        case calcium
        case iron
        case vitamin
    }

    let carbs: Double
    let protein: Double
    let fat: Double
    let calcium: Double
    let iron: Double
    let vitamin: Double
    let sourceFields: Set<SourceField>
    let sourceUnits: [SourceField: String]

    init(
        carbs: Double,
        protein: Double,
        fat: Double,
        calcium: Double,
        iron: Double,
        vitamin: Double,
        sourceFields: Set<SourceField> = [],
        sourceUnits: [SourceField: String] = [:]
    ) {
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.calcium = calcium
        self.iron = iron
        self.vitamin = vitamin
        self.sourceFields = sourceFields
        self.sourceUnits = sourceUnits
    }

    private enum CodingKeys: String, CodingKey {
        case carbs
        case protein
        case fat
        case calcium
        case iron
        case vitamin
        case sourceFields
        case sourceUnits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        carbs = try container.decode(Double.self, forKey: .carbs)
        protein = try container.decode(Double.self, forKey: .protein)
        fat = try container.decode(Double.self, forKey: .fat)
        calcium = try container.decode(Double.self, forKey: .calcium)
        iron = try container.decode(Double.self, forKey: .iron)
        vitamin = try container.decode(Double.self, forKey: .vitamin)
        sourceFields = try container.decodeIfPresent(
            Set<SourceField>.self,
            forKey: .sourceFields
        ) ?? []
        sourceUnits = try container.decodeIfPresent(
            [SourceField: String].self,
            forKey: .sourceUnits
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(carbs, forKey: .carbs)
        try container.encode(protein, forKey: .protein)
        try container.encode(fat, forKey: .fat)
        try container.encode(calcium, forKey: .calcium)
        try container.encode(iron, forKey: .iron)
        try container.encode(vitamin, forKey: .vitamin)
        try container.encode(sourceFields, forKey: .sourceFields)
        try container.encode(sourceUnits, forKey: .sourceUnits)
    }

    static let empty = RebuildNutritionInfo(
        carbs: 0,
        protein: 0,
        fat: 0,
        calcium: 0,
        iron: 0,
        vitamin: 0
    )
}

struct RebuildMealDay: Codable, Equatable, Sendable {
    let date: String
    let menuItems: [RebuildMealItem]
    let calorie: String
    let nutrition: RebuildNutritionInfo
}

struct MealDayRoute: Hashable, Identifiable, Sendable {
    let dateKey: String

    var id: String { dateKey }
}

enum MealLoadState: Equatable, Sendable {
    case cached(RebuildMealDay, refreshedAt: Date?)
    case refreshing(RebuildMealDay?)
    case live(RebuildMealDay)
    case empty
    case failed(message: String, cached: RebuildMealDay?)
}

struct RebuildCachedMealDay: Equatable, Sendable {
    let meal: RebuildMealDay
    let refreshedAt: Date?
    let source: String
}

protocol RebuildMealDayStore {
    func load(date: String) throws -> RebuildCachedMealDay?
    func save(
        _ meal: RebuildMealDay,
        refreshedAt: Date,
        source: String
    ) throws
    func remove(date: String) throws
}

protocol RebuildMealClientProtocol {
    func fetch(
        date: String,
        school: RebuildSchool
    ) async throws -> RebuildMealDay?
}
