import CoreData
import Foundation

enum GrowthPolicyError: Error, Equatable {
    case missingContract
    case invalidContract
}

struct GrowthPolicy: Equatable, Sendable {
    static let canonicalThresholds = [
        0, 80, 180, 320, 500, 720, 1_000,
        1_300, 1_650, 2_050, 2_500, 3_000,
    ]
    static let canonicalTitles = [
        "냠냠 새싹",
        "한 입 탐험가",
        "냠냠 용사",
        "편식 몬스터 사냥꾼",
        "급식 히어로",
        "영양 마스터",
        "레전드 냠냠러",
        "별빛 셰프",
        "균형 수호자",
        "숲의 영양 기사",
        "황금 한입 챔피언",
        "전설의 급식대장",
    ]

    let thresholds: [Int]
    let titles: [String]

    private init(thresholds: [Int], titles: [String]) {
        self.thresholds = thresholds
        self.titles = titles
    }

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
                  document.thresholds == Self.canonicalThresholds,
                  document.titles == Self.canonicalTitles,
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

    static func bundledOrEmbeddedDefault(
        bundle: Bundle = .main,
        diagnostic: (String) -> Void = { _ in
            NSLog("Growth policy fallback activated.")
        }
    ) -> GrowthPolicy {
        bundledOrEmbeddedDefault(
            dataProvider: {
                try loadRebuildContractData(
                    named: "growth-policy.json",
                    bundle: bundle
                )
            },
            diagnostic: diagnostic
        )
    }

    static func bundledOrEmbeddedDefault(
        dataProvider: () throws -> Data,
        diagnostic: (String) -> Void = { _ in
            NSLog("Growth policy fallback activated.")
        }
    ) -> GrowthPolicy {
        do {
            return try load(dataProvider)
        } catch {
            diagnostic("Growth policy fallback activated.")
            return GrowthPolicy(
                thresholds: canonicalThresholds,
                titles: canonicalTitles
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

struct GrowthStageRoadmapItem: Equatable, Identifiable, Sendable {
    let stageID: Int
    let title: String
    let threshold: Int
    let isSelected: Bool
    let isUnlocked: Bool
    let usesNeutralFallback: Bool

    var id: Int { stageID }

    var accessibilityIdentifier: String {
        "growth_stage_roadmap_stage_\(stageID)"
    }

    var accessibilityLabel: String {
        var components = [
            "레벨 \(stageID)",
            title,
            isSelected ? "선택됨" : "선택 안 됨",
        ]
        components.append(
            isUnlocked
                ? "해금됨"
                : "잠김, \(threshold) XP에 해금"
        )
        if usesNeutralFallback {
            components.append(MascotArtAccessibility.pendingArtText)
        }
        return components.joined(separator: ", ")
    }
}

struct GrowthStageStoryReward: Equatable, Sendable {
    let story: String
    let reward: String
}

enum GrowthStageStoryRewardCatalog {
    private static let entries: [GrowthStageStoryReward] = [
        GrowthStageStoryReward(
            story: "밝게 시작하는 공통 마스코트",
            reward: "새싹과 작은 잎"
        ),
        GrowthStageStoryReward(
            story: "낯선 반찬을 살펴보는 탐험가",
            reward: "탐험 손수건"
        ),
        GrowthStageStoryReward(
            story: "한 입 도전을 이어가는 용사",
            reward: "작은 용기 배지"
        ),
        GrowthStageStoryReward(
            story: "어려운 메뉴를 차분히 마주하는 캐릭터",
            reward: "방패와 몬스터 발자국"
        ),
        GrowthStageStoryReward(
            story: "꾸준한 기록으로 성장한 히어로",
            reward: "히어로 망토"
        ),
        GrowthStageStoryReward(
            story: "영양 균형을 이해하는 마스터",
            reward: "영양 별 장식"
        ),
        GrowthStageStoryReward(
            story: "자기만의 속도로 성장한 레전드",
            reward: "황금빛 레전드 모습"
        ),
        GrowthStageStoryReward(
            story: "별빛이 켜진 저녁 숲에서 새로운 맛을 천천히 만나 봐요.",
            reward: "별빛 모자와 저녁 숲"
        ),
        GrowthStageStoryReward(
            story: "여러 맛을 살피며 한 끼의 균형을 찾아가요.",
            reward: "균형 식판 문양"
        ),
        GrowthStageStoryReward(
            story: "깊은 숲을 지키며 영양을 알아가는 길을 걸어요.",
            reward: "잎 방패와 깊은 숲"
        ),
        GrowthStageStoryReward(
            story: "작은 한입을 이어 황금빛 도전을 완성해요.",
            reward: "황금 도토리·한입 메달"
        ),
        GrowthStageStoryReward(
            story: "지금까지의 한입을 모아 축제 숲의 전설이 돼요.",
            reward: "완성 왕관과 축제 숲"
        ),
    ]

    static func copy(for stageID: Int) -> GrowthStageStoryReward {
        let boundedStageID = min(max(stageID, 1), entries.count)
        return entries[boundedStageID - 1]
    }
}

struct GrowthStageDetailPresentation: Equatable, Sendable {
    let stageID: Int
    let title: String
    let threshold: Int
    let isSelected: Bool
    let isUnlocked: Bool
    let usesNeutralFallback: Bool
    let story: String
    let reward: String

    var unlockStateText: String {
        isUnlocked ? "해금 완료" : "\(threshold) XP에 해금"
    }

    var accessibilityLabel: String {
        var components = [
            "레벨 \(stageID)",
            title,
            "\(threshold) XP",
            unlockStateText,
            "이야기 \(story)",
            "보상 \(reward)",
        ]
        if isSelected {
            components.append("선택됨")
        }
        if usesNeutralFallback {
            components.append(MascotArtAccessibility.pendingArtText)
        }
        return components.joined(separator: ", ")
    }
}

/// The semantic values spoken by the selected-stage detail's combined tree.
///
/// The parent intentionally has no fixed label. The runtime detail view applies
/// this merged label from the art child's loader state, so loading and failure
/// remain stage-specific without exposing parent and child as duplicate elements.
struct GrowthStageDetailAccessibilitySemantics: Equatable, Sendable {
    let identifier: String
    let parentLabel: String?
    let artLabel: String
    let selectionLabel: String
    let stageLabel: String
    let titleLabel: String
    let thresholdStateLabel: String
    let storyLabel: String
    let rewardLabel: String
    let childArtIsPending: Bool

    var spokenLabel: String {
        [
            artLabel,
            selectionLabel,
            titleLabel,
            thresholdStateLabel,
            storyLabel,
            rewardLabel,
        ]
        .joined(separator: ", ")
    }

    static func make(
        detail: GrowthStageDetailPresentation,
        artState: MascotArtAccessibilityState
    ) -> Self {
        let childArtIsPending: Bool
        switch artState {
        case .pending:
            childArtIsPending = true
        case .verified, .loading:
            childArtIsPending = false
        }

        return Self(
            identifier: "growth_stage_roadmap_detail",
            parentLabel: nil,
            artLabel: MascotArtAccessibility.label(
                stageID: detail.stageID,
                state: artState
            ),
            selectionLabel: "선택한 단계",
            stageLabel: "레벨 \(detail.stageID)",
            titleLabel: detail.title,
            thresholdStateLabel:
                "\(detail.threshold) XP · \(detail.unlockStateText)",
            storyLabel: "이야기: \(detail.story)",
            rewardLabel: "보상: \(detail.reward)",
            childArtIsPending: childArtIsPending
        )
    }
}

enum GrowthStageRoadmapPresentation {
    static func items(
        policy: GrowthPolicy,
        selectedStageID: Int,
        highestUnlockedStageID: Int
    ) -> [GrowthStageRoadmapItem] {
        let selected = clamp(
            selectedStageID,
            count: policy.thresholds.count
        )
        let highestUnlocked = clamp(
            highestUnlockedStageID,
            count: policy.thresholds.count
        )

        return policy.thresholds.enumerated().map { index, threshold in
            let stageID = index + 1
            return GrowthStageRoadmapItem(
                stageID: stageID,
                title: policy.title(for: stageID),
                threshold: threshold,
                isSelected: stageID == selected,
                isUnlocked: stageID <= highestUnlocked,
                usesNeutralFallback: GrowthStageArtResolver.resolve(
                    stageID: stageID
                ).usesNeutralFallback
            )
        }
    }

    static func detail(
        policy: GrowthPolicy,
        stageID: Int,
        highestUnlockedStageID: Int,
        selectedStageID: Int? = nil
    ) -> GrowthStageDetailPresentation {
        let safeStageID = clamp(stageID, count: policy.thresholds.count)
        let highestUnlocked = clamp(
            highestUnlockedStageID,
            count: policy.thresholds.count
        )
        let art = GrowthStageArtResolver.resolve(stageID: safeStageID)
        let storyReward = GrowthStageStoryRewardCatalog.copy(
            for: safeStageID
        )
        return GrowthStageDetailPresentation(
            stageID: safeStageID,
            title: policy.title(for: safeStageID),
            threshold: policy.thresholds[safeStageID - 1],
            isSelected: selectedStageID.map {
                clamp($0, count: policy.thresholds.count) == safeStageID
            } ?? true,
            isUnlocked: safeStageID <= highestUnlocked,
            usesNeutralFallback: art.usesNeutralFallback,
            story: storyReward.story,
            reward: storyReward.reward
        )
    }

    private static func clamp(_ stageID: Int, count: Int) -> Int {
        guard count > 0 else { return 1 }
        return min(max(stageID, 1), count)
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

final class RebuildInMemoryGrowthStageStateStore:
    GrowthStageStateStore,
    @unchecked Sendable {
    private let lock = NSLock()
    private var state: GrowthStageStateV2?

    func read() -> GrowthStageStateV2? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func writeMonotonic(_ candidate: GrowthStageStateV2) {
        guard candidate.version == GrowthStageStateV2.currentVersion else {
            return
        }
        lock.lock()
        defer { lock.unlock() }

        let existingHighest = state?.highestUnlockedStageID ?? 1
        let candidateHighest = min(
            max(
                candidate.highestUnlockedStageID,
                GrowthStageStateV2.validStageRange.lowerBound
            ),
            GrowthStageStateV2.validStageRange.upperBound
        )
        let highest = max(existingHighest, candidateHighest)
        let selected = validStage(candidate.selectedStageID)
            .flatMap { $0 <= highest ? $0 : nil }
            ?? state?.selectedStageID.flatMap { $0 <= highest ? $0 : nil }
        state = GrowthStageStateV2(
            version: GrowthStageStateV2.currentVersion,
            highestUnlockedStageID: highest,
            selectedStageID: selected
        )
    }

    private func validStage(_ stageID: Int?) -> Int? {
        guard let stageID,
              GrowthStageStateV2.validStageRange.contains(stageID)
        else {
            return nil
        }
        return stageID
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
    static var highestVerifiedStageID: Int {
        MascotRigLevelCatalog.verifiedLevelIDs.max() ?? 0
    }

    static func resolve(stageID: Int) -> GrowthStageArtResolution {
        let safeStageID = min(
            max(stageID, GrowthStageStateV2.validStageRange.lowerBound),
            GrowthStageStateV2.validStageRange.upperBound
        )
        let hasVerifiedArt = MascotRigLevelCatalog.hasVerifiedArt(
            for: safeStageID
        )
        return GrowthStageArtResolution(
            stageID: safeStageID,
            artStageID: safeStageID,
            usesNeutralFallback: !hasVerifiedArt
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
        let normalizedMenu = MealRecordIdentityNormalizer.normalizedMenuName(
            menu
        )
        guard parts.count == 2 || parts.count == 3,
              isCanonicalDate(parts[0]),
              !normalizedMenu.isEmpty,
              menu == normalizedMenu
        else {
            return nil
        }
        guard parts.count == 3 else {
            return "\(normalizedMenu) · 급식 기록"
        }
        guard let status = statusLabels[parts[2]] else {
            return nil
        }
        return "\(normalizedMenu) · \(status)"
    }

    private static let statusLabels = [
        "finished": "다 먹었어요",
        "half": "반 정도 먹었어요",
        "oneBite": "한 입 도전",
        "smelledOnly": "냄새만 맡았어요",
        "difficultToday": "오늘은 안 먹어요",
        "allergyAvoided": "알레르기로 피했어요",
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
