import CoreData
import Foundation

enum GrowthPolicyError: Error, Equatable {
    case missingContract
    case invalidContract
}

struct GrowthPolicy: Equatable, Sendable {
    let thresholds: [Int]
    let titles: [String]

    init(data: Data) throws {
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any],
                  Set(dictionary.keys) == Set([
                    "version",
                    "thresholds",
                    "titles",
                  ])
            else {
                throw GrowthPolicyError.invalidContract
            }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1,
                  (2...14).contains(document.thresholds.count),
                  document.thresholds.first == 0,
                  zip(
                    document.thresholds,
                    document.thresholds.dropFirst()
                  ).allSatisfy(<),
                  document.titles.count == document.thresholds.count,
                  Set(document.titles).count == document.titles.count,
                  document.titles.allSatisfy({
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  })
            else {
                throw GrowthPolicyError.invalidContract
            }
            thresholds = document.thresholds
            titles = document.titles
        } catch let error as GrowthPolicyError {
            throw error
        } catch {
            throw GrowthPolicyError.invalidContract
        }
    }

    func level(totalXP: Int) -> Int {
        let safeXP = max(totalXP, 0)
        return (thresholds.lastIndex(where: { safeXP >= $0 }) ?? 0) + 1
    }

    func title(for level: Int) -> String {
        titles[min(max(level - 1, 0), titles.count - 1)]
    }

    func currentThreshold(totalXP: Int) -> Int {
        thresholds[level(totalXP: totalXP) - 1]
    }

    func nextThreshold(totalXP: Int) -> Int? {
        thresholds[safe: level(totalXP: totalXP)]
    }

    func progress(totalXP: Int) -> Double {
        let current = currentThreshold(totalXP: totalXP)
        guard let next = nextThreshold(totalXP: totalXP) else {
            return 1
        }
        return min(
            max(Double(max(totalXP, 0) - current) / Double(next - current), 0),
            1
        )
    }

    static func load(
        _ dataProvider: () throws -> Data
    ) throws -> GrowthPolicy {
        do {
            return try GrowthPolicy(data: dataProvider())
        } catch let error as GrowthPolicyError {
            throw error
        } catch {
            throw GrowthPolicyError.missingContract
        }
    }

    static func bundled(bundle: Bundle = .main) throws -> GrowthPolicy {
        try load {
            try loadRebuildContractData(
                named: "growth-policy.json",
                bundle: bundle
            )
        }
    }

    private struct Document: Decodable {
        let version: Int
        let thresholds: [Int]
        let titles: [String]
    }
}

struct GrowthSnapshot: Equatable, Sendable {
    let totalXP: Int
    let recentEvents: [RebuildProgressEvent]

    static let empty = GrowthSnapshot(totalXP: 0, recentEvents: [])
}

struct CollectionSnapshot: Equatable, Sendable {
    let totalXP: Int
    let records: [CollectionRecord]
}

protocol CollectionSnapshotProviding {
    func loadCollection() async throws -> CollectionSnapshot
}

protocol GrowthSnapshotProviding {
    func load(limit: Int) async throws -> GrowthSnapshot
}

actor CoreDataGrowthSnapshotProvider: GrowthSnapshotProviding {
    private let repository: RebuildProgressRepository

    init(container: NSPersistentContainer) {
        repository = RebuildProgressRepository(
            context: container.newBackgroundContext()
        )
    }

    func load(limit: Int) throws -> GrowthSnapshot {
        let total = try repository.totalXP()
        guard total <= Int64(Int.max) else {
            throw RebuildRepositoryError.totalXPOverflow
        }
        return GrowthSnapshot(
            totalXP: Int(total),
            recentEvents: try repository.recentPositiveEvents(limit: limit)
        )
    }
}

actor CoreDataCollectionSnapshotProvider: CollectionSnapshotProviding {
    private let repository: RebuildProgressRepository

    init(container: NSPersistentContainer) {
        repository = RebuildProgressRepository(
            context: container.newBackgroundContext()
        )
    }

    func loadCollection() throws -> CollectionSnapshot {
        let total = try repository.totalXP()
        guard total <= Int64(Int.max) else {
            throw RebuildRepositoryError.totalXPOverflow
        }
        return CollectionSnapshot(
            totalXP: Int(total),
            records: try repository.activeCollectionRecords()
        )
    }
}

struct UnavailableGrowthSnapshotProvider: GrowthSnapshotProviding {
    func load(limit: Int) async throws -> GrowthSnapshot {
        throw RebuildOnboardingError.persistenceUnavailable
    }
}

struct UnavailableCollectionSnapshotProvider: CollectionSnapshotProviding {
    func loadCollection() async throws -> CollectionSnapshot {
        throw RebuildOnboardingError.persistenceUnavailable
    }
}

struct GrowthEventPresentation: Equatable {
    let title: String
    let xpText: String
    let dateText: String

    init(event: RebuildProgressEvent) {
        if event.id == "legacy:progress-reconciliation" {
            title = "이전 성장 기록 정리"
        } else if event.id.hasPrefix("meal:"),
                  let canonicalTitle = Self.canonicalMealTitle(id: event.id) {
            title = canonicalTitle
        } else {
            title = "성장 XP 획득"
        }
        xpText = "+\(event.amount) XP"
        dateText = Self.dateFormatter.string(from: event.occurredAt)
    }

    private static func canonicalMealTitle(id: String) -> String? {
        let identity = String(id.dropFirst("meal:".count))
        let parts = identity.split(
            separator: "|",
            omittingEmptySubsequences: false
        ).map(String.init)
        let menu = parts[safe: 1] ?? ""
        let normalizedMenu = menu
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard parts.count == 3,
              isCanonicalDate(parts[0]),
              !normalizedMenu.isEmpty,
              menu == normalizedMenu,
              let status = statusLabels[parts[2]]
        else {
            return nil
        }
        return "\(normalizedMenu) · \(status)"
    }

    private static let statusLabels = [
        "finished": "다 먹었어요",
        "half": "절반 먹었어요",
        "oneBite": "한 입 도전",
        "smelledOnly": "냄새 맡기",
        "difficultToday": "오늘은 어려웠어요",
        "allergyAvoided": "알레르기 안전 기록",
    ]

    private static func isCanonicalDate(_ value: String) -> Bool {
        guard value.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil,
        let date = canonicalDateFormatter.date(from: value)
        else {
            return false
        }
        return canonicalDateFormatter.string(from: date) == value
    }

    private static let canonicalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
