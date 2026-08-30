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
                  document.thresholds.count == 12,
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

struct GrowthStageStateV2: Codable, Equatable, Sendable {
    static let key = "growth-stage-state-v2"
    static let currentVersion = 1
    static let validStageRange = 1...12

    let version: Int
    let highestUnlockedStageID: Int
    let selectedStageID: Int?
}

struct LegacyGrowthRights: Equatable, Sendable {
    let level: Int?
    let currentSkinID: String?
    let badges: [String]

    static let empty = LegacyGrowthRights(
        level: nil,
        currentSkinID: nil,
        badges: []
    )
}

struct GrowthEntitlement: Equatable, Sendable {
    let highestUnlockedStageID: Int
    let selectedStageID: Int
    let legacyBadgeIDs: [String]
}

struct GrowthEntitlementProgressPresentation: Equatable, Sendable {
    let level: Int
    let currentThreshold: Int
    let nextThreshold: Int?
    let progress: Double
    let remainingXP: Int?

    static func resolve(
        policy: GrowthPolicy,
        totalXP: Int,
        highestUnlockedStageID: Int
    ) -> GrowthEntitlementProgressPresentation {
        let level = min(
            max(highestUnlockedStageID, 1),
            policy.thresholds.count
        )
        let safeXP = max(totalXP, 0)
        let currentThreshold = policy.thresholds[level - 1]
        guard level < policy.thresholds.count else {
            return GrowthEntitlementProgressPresentation(
                level: level,
                currentThreshold: currentThreshold,
                nextThreshold: nil,
                progress: 1,
                remainingXP: nil
            )
        }

        let nextThreshold = policy.thresholds[level]
        let fraction = Double(safeXP - currentThreshold)
            / Double(nextThreshold - currentThreshold)
        return GrowthEntitlementProgressPresentation(
            level: level,
            currentThreshold: currentThreshold,
            nextThreshold: nextThreshold,
            progress: min(max(fraction, 0), 1),
            remainingXP: max(nextThreshold - safeXP, 0)
        )
    }
}

protocol GrowthStageStateStore: Sendable {
    func read() -> GrowthStageStateV2?
    func writeMonotonic(_ state: GrowthStageStateV2)
}

struct UserDefaultsGrowthStageStateStore: GrowthStageStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let writeLock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func read() -> GrowthStageStateV2? {
        guard let data = defaults.data(forKey: GrowthStageStateV2.key),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let version = dictionary["version"] as? Int,
              version == GrowthStageStateV2.currentVersion,
              dictionary["highestUnlockedStageID"] != nil,
              Set(dictionary.keys).isSubset(of: [
                  "version",
                  "highestUnlockedStageID",
                  "selectedStageID",
              ]),
              let decoded = try? JSONDecoder().decode(
                  GrowthStageStateV2.self,
                  from: data
              )
        else {
            return nil
        }

        guard GrowthStageStateV2.validStageRange.contains(decoded.highestUnlockedStageID) else {
            return nil
        }
        let highest = decoded.highestUnlockedStageID
        let selected: Int? = decoded.selectedStageID.flatMap { stageID in
            guard let stageID = Self.validStage(stageID), stageID <= highest else {
                return nil
            }
            return stageID
        }
        return GrowthStageStateV2(
            version: GrowthStageStateV2.currentVersion,
            highestUnlockedStageID: highest,
            selectedStageID: selected
        )
    }

    func writeMonotonic(_ state: GrowthStageStateV2) {
        guard state.version == GrowthStageStateV2.currentVersion else {
            return
        }
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        let existing = read()
        let existingHighest = existing?.highestUnlockedStageID ?? 1
        let candidateHighest = Self.clampStage(state.highestUnlockedStageID)
        let highest = max(existingHighest, candidateHighest)
        let selected = Self.validStage(state.selectedStageID)
            .flatMap { $0 <= highest ? $0 : nil }
            ?? existing?.selectedStageID.flatMap { $0 <= highest ? $0 : nil }

        let canonical = GrowthStageStateV2(
            version: GrowthStageStateV2.currentVersion,
            highestUnlockedStageID: highest,
            selectedStageID: selected
        )
        guard let data = try? JSONEncoder().encode(canonical) else {
            return
        }
        defaults.set(data, forKey: GrowthStageStateV2.key)
    }

    private static func validStage(_ stageID: Int?) -> Int? {
        guard let stageID,
              GrowthStageStateV2.validStageRange.contains(stageID)
        else {
            return nil
        }
        return stageID
    }

    private static func clampStage(_ stageID: Int) -> Int {
        min(
            max(stageID, GrowthStageStateV2.validStageRange.lowerBound),
            GrowthStageStateV2.validStageRange.upperBound
        )
    }
}

enum GrowthEntitlementResolver {
    static func resolve(
        policy: GrowthPolicy,
        totalXP: Int,
        legacy: LegacyGrowthRights,
        stored: GrowthStageStateV2?
    ) -> GrowthEntitlement {
        let xpStage = clampStage(policy.level(totalXP: totalXP))
        let legacyLevel = validStage(legacy.level)
        let legacySkinStage = legacySkinStage(for: legacy.currentSkinID)
        let validStored: GrowthStageStateV2? = {
            guard let stored,
                  stored.version == GrowthStageStateV2.currentVersion,
                  validStage(stored.highestUnlockedStageID) != nil
            else {
                return nil
            }
            return stored
        }()
        let storedHighest: Int? = {
            guard let validStored else {
                return nil
            }
            return validStage(validStored.highestUnlockedStageID)
        }()

        let highest = [
            xpStage,
            legacyLevel,
            legacySkinStage,
            storedHighest,
        ]
        .compactMap { $0 }
        .max() ?? 1

        let selected = validSelectedStage(
            validStored?.selectedStageID,
            highest: highest
        )
            ?? legacySkinStage.flatMap { $0 <= highest ? $0 : nil }
            ?? highest

        return GrowthEntitlement(
            highestUnlockedStageID: highest,
            selectedStageID: selected,
            legacyBadgeIDs: legacy.badges
        )
    }

    private static func validSelectedStage(
        _ stageID: Int?,
        highest: Int
    ) -> Int? {
        guard let stageID = validStage(stageID), stageID <= highest else {
            return nil
        }
        return stageID
    }

    private static func validStage(_ stageID: Int?) -> Int? {
        guard let stageID,
              GrowthStageStateV2.validStageRange.contains(stageID)
        else {
            return nil
        }
        return stageID
    }

    private static func clampStage(_ stageID: Int) -> Int {
        min(
            max(stageID, GrowthStageStateV2.validStageRange.lowerBound),
            GrowthStageStateV2.validStageRange.upperBound
        )
    }

    private static func legacySkinStage(for skinID: String?) -> Int? {
        guard let skinID,
              skinID.hasPrefix("skin-"),
              let suffix = Int(skinID.dropFirst("skin-".count)),
              (1...7).contains(suffix),
              skinID == "skin-\(suffix)"
        else {
            return nil
        }
        return suffix
    }
}

struct GrowthStageArtResolution: Equatable, Sendable {
    let stageID: Int
    let artStageID: Int
    let usesNeutralFallback: Bool
}

enum GrowthStageArtResolver {
    static let highestVerifiedStageID = 7

    static func resolve(stageID: Int) -> GrowthStageArtResolution {
        let safeStageID = min(
            max(stageID, GrowthStageStateV2.validStageRange.lowerBound),
            GrowthStageStateV2.validStageRange.upperBound
        )
        return GrowthStageArtResolution(
            stageID: safeStageID,
            artStageID: min(safeStageID, highestVerifiedStageID),
            usesNeutralFallback: safeStageID > highestVerifiedStageID
        )
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
