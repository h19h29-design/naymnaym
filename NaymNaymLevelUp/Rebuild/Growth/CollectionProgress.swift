import Foundation

enum CollectionProgressError: Error, Equatable {
    case invalidPolicy
}

enum CollectionBadgeCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case nutrition
    case challenge
    case streak
}

struct CollectionRecord: Equatable, Sendable {
    let date: String
    let normalizedMenuName: String
    let status: String
}

struct CollectionBadge: Equatable, Hashable, Sendable {
    let id: String
    let category: CollectionBadgeCategory
    let metric: String
    let threshold: Int
    let title: String
}

struct CollectionProgress: Equatable, Sendable {
    let totalXP: Int
    let badges: [CollectionBadge]
    let earnedBadgeIDs: Set<String>
    let positiveRecordCount: Int
    let activeDayCount: Int
    let longestWeekdayStreak: Int

    var collectedCount: Int {
        earnedBadgeIDs.count
    }

    func earnedCount(for category: CollectionBadgeCategory) -> Int {
        badges.count {
            $0.category == category && earnedBadgeIDs.contains($0.id)
        }
    }

    func badges(for category: CollectionBadgeCategory) -> [CollectionBadge] {
        badges.filter { $0.category == category }
    }

    static func evaluate(
        totalXP: Int,
        records: [CollectionRecord],
        policyData: Data
    ) throws -> CollectionProgress {
        let policy = try CollectionPolicy(data: policyData)
        let positiveRecords = deduplicatedPositiveRecords(
            records,
            positiveStatuses: Set(policy.positiveStatuses)
        )
        let activeDates = Set(positiveRecords.map(\.date))
        let foodGroupCounts = policy.foodGroups.reduce(
            into: [String: Int]()
        ) { counts, group in
            counts[group.id] = positiveRecords.count { record in
                group.keywords.contains { record.normalizedMenuName.contains($0) }
            }
        }
        let metrics = metrics(
            positiveRecords: positiveRecords,
            foodGroupCounts: foodGroupCounts,
            activeDates: activeDates
        )
        let earned = Set(policy.badges.compactMap { badge in
            (metrics[badge.metric, default: 0] >= badge.threshold)
                ? badge.id
                : nil
        })
        return CollectionProgress(
            totalXP: max(totalXP, 0),
            badges: policy.badges,
            earnedBadgeIDs: earned,
            positiveRecordCount: positiveRecords.count,
            activeDayCount: activeDates.count,
            longestWeekdayStreak: metrics["weekday_streak", default: 0]
        )
    }

    private static func deduplicatedPositiveRecords(
        _ records: [CollectionRecord],
        positiveStatuses: Set<String>
    ) -> [CollectionRecord] {
        var bestRecordForMeal: [String: CollectionRecord] = [:]
        for record in records {
            let normalizedMenuName = record.normalizedMenuName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard positiveStatuses.contains(record.status),
                  !normalizedMenuName.isEmpty,
                  Self.validDate(record.date) != nil
            else {
                continue
            }
            let normalized = CollectionRecord(
                date: record.date,
                normalizedMenuName: normalizedMenuName,
                status: record.status
            )
            let identity = "\(normalized.date)|\(normalized.normalizedMenuName)"
            guard let existing = bestRecordForMeal[identity] else {
                bestRecordForMeal[identity] = normalized
                continue
            }
            if statusRank(normalized.status) > statusRank(existing.status) {
                bestRecordForMeal[identity] = normalized
            }
        }
        return bestRecordForMeal.values.sorted { left, right in
            if left.date != right.date {
                return left.date < right.date
            }
            if left.normalizedMenuName != right.normalizedMenuName {
                return left.normalizedMenuName < right.normalizedMenuName
            }
            return left.status < right.status
        }
    }

    private static func metrics(
        positiveRecords: [CollectionRecord],
        foodGroupCounts: [String: Int],
        activeDates: Set<String>
    ) -> [String: Int] {
        let menusByDate = Dictionary(grouping: positiveRecords, by: \.date)
        var values: [String: Int] = [
            "positive_records": positiveRecords.count,
            "one_bite_records": positiveRecords.count { $0.status == "oneBite" },
            "finished_records": positiveRecords.count { $0.status == "finished" },
            "distinct_menus": Set(positiveRecords.map(\.normalizedMenuName)).count,
            "three_menu_days": menusByDate.values.count {
                Set($0.map(\.normalizedMenuName)).count >= 3
            },
            "active_days": activeDates.count,
            "weekday_streak": longestWeekdayStreak(activeDates),
            "distinct_food_groups": foodGroupCounts.values.count { $0 > 0 },
        ]
        for (groupID, count) in foodGroupCounts {
            values["food_group_\(groupID)"] = count
        }
        return values
    }

    private static func longestWeekdayStreak(_ activeDates: Set<String>) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let weekdays = activeDates.compactMap { date -> Date? in
            guard let parsed = validDate(date),
                  (2...6).contains(calendar.component(.weekday, from: parsed))
            else {
                return nil
            }
            return parsed
        }
        .sorted()

        var longest = 0
        var current = 0
        var previous: Date?
        for date in weekdays {
            if let previous {
                let gap = calendar.dateComponents(
                    [.day],
                    from: previous,
                    to: date
                ).day ?? 0
                let crossesWeekend =
                    calendar.component(.weekday, from: previous) == 6 &&
                    calendar.component(.weekday, from: date) == 2 &&
                    gap == 3
                current = (gap == 1 || crossesWeekend) ? current + 1 : 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = date
        }
        return longest
    }

    private static func statusRank(_ status: String) -> Int {
        switch status {
        case "finished": 3
        case "half": 2
        case "oneBite": 1
        default: 0
        }
    }

    private static func validDate(_ value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else {
            return nil
        }
        return date
    }
}

private struct CollectionPolicy: Sendable {
    struct FoodGroup: Equatable, Sendable {
        let id: String
        let keywords: [String]
    }

    let positiveStatuses: [String]
    let foodGroups: [FoodGroup]
    let badges: [CollectionBadge]

    init(data: Data) throws {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any],
                  Set(dictionary.keys) == Set([
                    "version",
                    "positiveStatuses",
                    "foodGroups",
                    "badges",
                  ])
            else {
                throw CollectionProgressError.invalidPolicy
            }
            let document = try JSONDecoder().decode(Document.self, from: data)
            let groups = document.foodGroups.map {
                FoodGroup(
                    id: $0.id,
                    keywords: $0.keywords.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }
                )
            }
            let decodedBadges = try document.badges.map { badge in
                guard let category = CollectionBadgeCategory(rawValue: badge.category) else {
                    throw CollectionProgressError.invalidPolicy
                }
                return CollectionBadge(
                    id: badge.id,
                    category: category,
                    metric: badge.metric,
                    threshold: badge.threshold,
                    title: badge.title
                )
            }
            let groupIDs = Set(groups.map(\.id))
            let validMetric: (String) -> Bool = { metric in
                [
                    "positive_records",
                    "one_bite_records",
                    "finished_records",
                    "distinct_menus",
                    "three_menu_days",
                    "active_days",
                    "weekday_streak",
                    "distinct_food_groups",
                ].contains(metric) ||
                    (metric.hasPrefix("food_group_") &&
                        groupIDs.contains(String(metric.dropFirst("food_group_".count))))
            }
            guard document.version == 1,
                  !document.positiveStatuses.isEmpty,
                  Set(document.positiveStatuses).count == document.positiveStatuses.count,
                  groups.count >= 1,
                  groupIDs.count == groups.count,
                  groups.allSatisfy({ group in
                      !group.id.isEmpty &&
                          !group.keywords.isEmpty &&
                          group.keywords.allSatisfy { !$0.isEmpty }
                  }),
                  !decodedBadges.isEmpty,
                  Set(decodedBadges.map(\.id)).count == decodedBadges.count,
                  decodedBadges.allSatisfy({ badge in
                      !badge.id.isEmpty &&
                          !badge.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                          badge.threshold > 0 &&
                          validMetric(badge.metric)
                  })
            else {
                throw CollectionProgressError.invalidPolicy
            }
            positiveStatuses = document.positiveStatuses
            foodGroups = groups
            badges = decodedBadges
        } catch let error as CollectionProgressError {
            throw error
        } catch {
            throw CollectionProgressError.invalidPolicy
        }
    }

    private struct Document: Decodable {
        let version: Int
        let positiveStatuses: [String]
        let foodGroups: [DocumentFoodGroup]
        let badges: [DocumentBadge]
    }

    private struct DocumentFoodGroup: Decodable {
        let id: String
        let keywords: [String]
    }

    private struct DocumentBadge: Decodable {
        let id: String
        let category: String
        let metric: String
        let threshold: Int
        let title: String
    }
}
