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
    let carbs: Double
    let protein: Double
    let fat: Double
    let calcium: Double
    let iron: Double
    let vitamin: Double

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
