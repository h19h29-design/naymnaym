import Foundation

enum MealRecordIdentityNormalizer {
    static func normalizedMenuName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum MealNutrientCanonicalizer {
    static let orderedIDs = [
        "fiber", "vitamin", "protein", "iron", "calcium", "carbohydrate",
    ]

    private static let aliases: [String: String] = [
        "fiber": "fiber",
        "식이섬유": "fiber",
        "vitamin": "vitamin",
        "비타민": "vitamin",
        "protein": "protein",
        "단백질": "protein",
        "iron": "iron",
        "철분": "iron",
        "철": "iron",
        "calcium": "calcium",
        "칼슘": "calcium",
        "carbohydrate": "carbohydrate",
        "탄수화물": "carbohydrate",
    ]

    static func canonicalID(for value: String) -> String? {
        aliases[
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ]
    }

    static func orderedKnownIDs(from values: [String]) -> [String] {
        let selected = Set(values.compactMap(canonicalID(for:)))
        return orderedIDs.filter(selected.contains)
    }

    static func canonicalizedIfAllKnown(_ values: [String]) -> [String]? {
        guard values.allSatisfy({ canonicalID(for: $0) != nil }) else {
            return nil
        }
        return orderedKnownIDs(from: values)
    }

    static func validatedCanonicalIDs(_ values: [String]) -> [String]? {
        guard values.allSatisfy({ aliases[$0] == $0 }),
              values == orderedKnownIDs(from: values) else {
            return nil
        }
        return values
    }
}

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
        if container.contains(.sourceFields) {
            sourceFields = try container.decodeIfPresent(
                Set<SourceField>.self,
                forKey: .sourceFields
            ) ?? []
        } else {
            sourceFields = Self.inferredSourceFields(
                carbs: carbs,
                protein: protein,
                fat: fat,
                calcium: calcium,
                iron: iron,
                vitamin: vitamin
            )
        }
        sourceUnits = try container.decodeIfPresent(
            DecodedSourceUnits.self,
            forKey: .sourceUnits
        )?.values ?? [:]
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

    private static func inferredSourceFields(
        carbs: Double,
        protein: Double,
        fat: Double,
        calcium: Double,
        iron: Double,
        vitamin: Double
    ) -> Set<SourceField> {
        let values: [(SourceField, Double)] = [
            (.carbs, carbs),
            (.protein, protein),
            (.fat, fat),
            (.calcium, calcium),
            (.iron, iron),
            (.vitamin, vitamin),
        ]
        return Set(
            values.compactMap { field, value in
                value == 0 ? nil : field
            }
        )
    }

    private struct DecodedSourceUnits: Decodable {
        let values: [SourceField: String]

        init(from decoder: Decoder) throws {
            if (try? decoder.container(keyedBy: DynamicCodingKey.self)) != nil {
                values = [:]
                return
            }

            guard var unkeyed = try? decoder.unkeyedContainer() else {
                values = [:]
                return
            }

            var decoded: [SourceField: String] = [:]
            while !unkeyed.isAtEnd {
                guard let rawField = try? unkeyed.decode(String.self),
                      let field = SourceField(rawValue: rawField),
                      let unit = try? unkeyed.decode(String.self),
                      !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      decoded.updateValue(unit, forKey: field) == nil
                else {
                    values = [:]
                    return
                }
            }
            values = decoded
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

struct RebuildMealDay: Codable, Equatable, Sendable {
    let date: String
    let menuItems: [RebuildMealItem]
    let calorie: String
    let nutrition: RebuildNutritionInfo
}

struct RebuildMealRecordRevision: Equatable, Sendable {
    let recordID: String
    let date: String
    let normalizedMenuName: String
    let status: RebuildEatingStatus
    let updatedAt: Date
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
    var source: RebuildMealSource { get }

    func fetch(
        date: String,
        school: RebuildSchool
    ) async throws -> RebuildMealDay?
}

enum RebuildMealSource: String, Sendable {
    case neis
    case demo
}

extension RebuildMealClientProtocol {
    var source: RebuildMealSource { .neis }
}
