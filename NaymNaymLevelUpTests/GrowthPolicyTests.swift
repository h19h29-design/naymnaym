import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import NaymNaymLevelUp

final class GrowthPolicyTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    private var policy: GrowthPolicy {
        get throws {
            try GrowthPolicy(data: Self.canonicalPolicy)
        }
    }

    func testEveryLevelBoundaryMatchesSharedContract() throws {
        let cases = [
            (-1, 1),
            (0, 1),
            (79, 1),
            (80, 2),
            (179, 2),
            (180, 3),
            (319, 3),
            (320, 4),
            (499, 4),
            (500, 5),
            (719, 5),
            (720, 6),
            (999, 6),
            (1_000, 7),
            (1_299, 7),
            (1_300, 8),
            (1_649, 8),
            (1_650, 9),
            (2_049, 9),
            (2_050, 10),
            (2_499, 10),
            (2_500, 11),
            (2_999, 11),
            (3_000, 12),
            (4_850, 12),
            (Int.max, 12),
        ]

        for (totalXP, expectedLevel) in cases {
            XCTAssertEqual(
                try policy.level(totalXP: totalXP),
                expectedLevel,
                "Unexpected level for \(totalXP) XP"
            )
        }
    }

    func testDocumentKeepsExactThresholdsAndTitles() throws {
        XCTAssertEqual(
            try policy.thresholds,
            [
                0, 80, 180, 320, 500, 720, 1_000,
                1_300, 1_650, 2_050, 2_500, 3_000,
            ]
        )
        XCTAssertEqual(
            try policy.titles,
            [
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
        )
        XCTAssertEqual(try policy.title(for: 0), "냠냠 새싹")
        XCTAssertEqual(try policy.title(for: 12), "전설의 급식대장")
        XCTAssertEqual(try policy.title(for: 13), "전설의 급식대장")
    }

    func testPolicyRejectsAnyStageCountOtherThanTwelve() {
        for stageCount in [7, 13] {
            let thresholds = Array(0..<stageCount)
            let titles = thresholds.map { "stage-\($0)" }
            let data = try! JSONSerialization.data(withJSONObject: [
                "version": 1,
                "thresholds": thresholds,
                "titles": titles,
            ])

            XCTAssertThrowsError(
                try GrowthPolicy(data: data),
                "A \(stageCount)-stage policy must be rejected"
            ) { error in
                XCTAssertEqual(error as? GrowthPolicyError, .invalidContract)
            }
        }
    }

    func testHighestUnlockedIsMonotonicUnionOfXPLegacyLevelSkinAndStoredState() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsGrowthStageStateStore(defaults: defaults)
        store.writeMonotonic(
            GrowthStageStateV2(
                version: 1,
                highestUnlockedStageID: 9,
                selectedStageID: 9
            )
        )

        let result = GrowthEntitlementResolver.resolve(
            policy: try policy,
            totalXP: 0,
            legacy: LegacyGrowthRights(
                level: 6,
                currentSkinID: "skin-7",
                badges: []
            ),
            stored: store.read()
        )

        XCTAssertEqual(result.highestUnlockedStageID, 9)
        XCTAssertEqual(result.selectedStageID, 9)

        let xpDrivenResult = GrowthEntitlementResolver.resolve(
            policy: try policy,
            totalXP: 2_500,
            legacy: LegacyGrowthRights(
                level: 3,
                currentSkinID: "skin-2",
                badges: []
            ),
            stored: GrowthStageStateV2(
                version: 1,
                highestUnlockedStageID: 8,
                selectedStageID: 8
            )
        )

        XCTAssertEqual(xpDrivenResult.highestUnlockedStageID, 11)
        XCTAssertEqual(xpDrivenResult.selectedStageID, 8)
    }

    func testStoredSelectionMustBeValidAndMonotonicWritesNeverLowerHighest() throws {
        let defaults = makeDefaults()
        let store = UserDefaultsGrowthStageStateStore(defaults: defaults)

        store.writeMonotonic(
            GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion,
                highestUnlockedStageID: 9,
                selectedStageID: 5
            )
        )
        let persistedObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: XCTUnwrap(defaults.data(forKey: GrowthStageStateV2.key))
            ) as? [String: Any]
        )
        XCTAssertEqual(
            Set(persistedObject.keys),
            Set(["version", "highestUnlockedStageID", "selectedStageID"])
        )
        store.writeMonotonic(
            GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion,
                highestUnlockedStageID: 4,
                selectedStageID: 4
            )
        )

        XCTAssertEqual(store.read()?.highestUnlockedStageID, 9)
        XCTAssertEqual(store.read()?.selectedStageID, 4)

        let policy = try! policy
        let selected = GrowthEntitlementResolver.resolve(
            policy: policy,
            totalXP: 0,
            legacy: LegacyGrowthRights(
                level: 7,
                currentSkinID: "skin-5",
                badges: []
            ),
            stored: GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion,
                highestUnlockedStageID: 9,
                selectedStageID: 9
            )
        )
        XCTAssertEqual(selected.selectedStageID, 9)

        let invalidStoredSelection = GrowthEntitlementResolver.resolve(
            policy: policy,
            totalXP: 0,
            legacy: LegacyGrowthRights(
                level: 7,
                currentSkinID: "skin-5",
                badges: []
            ),
            stored: GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion,
                highestUnlockedStageID: 9,
                selectedStageID: 10
            )
        )
        XCTAssertEqual(invalidStoredSelection.highestUnlockedStageID, 9)
        XCTAssertEqual(invalidStoredSelection.selectedStageID, 5)

        let noStoredSelection = GrowthEntitlementResolver.resolve(
            policy: policy,
            totalXP: 0,
            legacy: .empty,
            stored: GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion,
                highestUnlockedStageID: 9,
                selectedStageID: nil
            )
        )
        XCTAssertEqual(noStoredSelection.highestUnlockedStageID, 9)
        XCTAssertEqual(noStoredSelection.selectedStageID, 9)

        defaults.set(
            Data(#"{"version":1,"highestUnlockedStageID":9,"selectedStageID":10}"#.utf8),
            forKey: GrowthStageStateV2.key
        )
        XCTAssertEqual(store.read()?.highestUnlockedStageID, 9)
        XCTAssertNil(store.read()?.selectedStageID)

        store.writeMonotonic(
            GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion + 1,
                highestUnlockedStageID: 12,
                selectedStageID: 12
            )
        )
        XCTAssertEqual(store.read()?.highestUnlockedStageID, 9)
    }

    func testConcurrentOutOfOrderWritesCannotLowerHighestStage() throws {
        let suiteName = "GrowthPolicyTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = try XCTUnwrap(
            InterleavingUserDefaults(suiteName: suiteName)
        )
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsGrowthStageStateStore(defaults: defaults)
        let writes = DispatchGroup()

        writes.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            store.writeMonotonic(
                GrowthStageStateV2(
                    version: GrowthStageStateV2.currentVersion,
                    highestUnlockedStageID: 9,
                    selectedStageID: 9
                )
            )
            writes.leave()
        }

        XCTAssertEqual(
            defaults.firstReadStarted.wait(timeout: .now() + 2),
            .success
        )

        writes.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            store.writeMonotonic(
                GrowthStageStateV2(
                    version: GrowthStageStateV2.currentVersion,
                    highestUnlockedStageID: 12,
                    selectedStageID: 12
                )
            )
            writes.leave()
        }

        XCTAssertEqual(writes.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(store.read()?.highestUnlockedStageID, 12)
    }

    func testMalformedStoredHighestRejectsItsSelection() throws {
        let result = GrowthEntitlementResolver.resolve(
            policy: try policy,
            totalXP: 0,
            legacy: LegacyGrowthRights(
                level: 7,
                currentSkinID: "skin-7",
                badges: []
            ),
            stored: GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion,
                highestUnlockedStageID: 0,
                selectedStageID: 1
            )
        )

        XCTAssertEqual(result.highestUnlockedStageID, 7)
        XCTAssertEqual(result.selectedStageID, 7)
    }

    func testGrowthProgressPresentationUsesSameEntitlementStageAsProgressCard() throws {
        let preservedRights = GrowthEntitlementProgressPresentation.resolve(
            policy: try policy,
            totalXP: 0,
            highestUnlockedStageID: 7
        )

        XCTAssertEqual(preservedRights.level, 7)
        XCTAssertEqual(preservedRights.currentThreshold, 1_000)
        XCTAssertEqual(preservedRights.nextThreshold, 1_300)
        XCTAssertEqual(preservedRights.remainingXP, 1_300)
        XCTAssertEqual(preservedRights.progress, 0, accuracy: 0.0001)

        let progressingRights = GrowthEntitlementProgressPresentation.resolve(
            policy: try policy,
            totalXP: 1_100,
            highestUnlockedStageID: 7
        )

        XCTAssertEqual(progressingRights.level, 7)
        XCTAssertEqual(progressingRights.progress, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(progressingRights.remainingXP, 200)
    }

    func testMalformedAndPartialV2PayloadCannotLowerLegacyRights() throws {
        let defaults = makeDefaults()
        let payloads = [
            Data(#"{"version":1,"highestUnlockedStageID":2}"#.utf8),
            Data(#"{"version":2,"highestUnlockedStageID":12,"selectedStageID":12}"#.utf8),
            Data(#"{"version":1,"highestUnlockedStageID":0,"selectedStageID":0}"#.utf8),
            Data(#"{"version":1,"highestUnlockedStageID":99,"selectedStageID":99}"#.utf8),
            Data(#"{"version":1,"highestUnlockedStageID":2,"unexpected":true}"#.utf8),
            Data("not-json".utf8),
        ]

        for payload in payloads {
            defaults.set(payload, forKey: GrowthStageStateV2.key)
            let result = GrowthEntitlementResolver.resolve(
                policy: try policy,
                totalXP: 1_000,
                legacy: LegacyGrowthRights(
                    level: 7,
                    currentSkinID: "skin-7",
                    badges: ["legacy-badge"]
                ),
                stored: UserDefaultsGrowthStageStateStore(defaults: defaults).read()
            )

            XCTAssertEqual(result.highestUnlockedStageID, 7)
            XCTAssertEqual(result.selectedStageID, 7)
            XCTAssertEqual(result.legacyBadgeIDs, ["legacy-badge"])
        }

        defaults.set(
            Data(#"{"version":2,"highestUnlockedStageID":12,"selectedStageID":1}"#.utf8),
            forKey: GrowthStageStateV2.key
        )
        let wrongVersionResult = GrowthEntitlementResolver.resolve(
            policy: try policy,
            totalXP: 0,
            legacy: LegacyGrowthRights(
                level: 7,
                currentSkinID: "skin-7",
                badges: []
            ),
            stored: UserDefaultsGrowthStageStateStore(defaults: defaults).read()
        )
        XCTAssertEqual(wrongVersionResult.highestUnlockedStageID, 7)
        XCTAssertEqual(wrongVersionResult.selectedStageID, 7)
    }

    func testLegacyBadgeAndSkinRightsAreVisibleWithoutChangingLegacyPayload() throws {
        let defaults = makeDefaults()
        let original = Data(
            #"{"level":0,"exp":0,"recordExp":0,"challengeExp":0,"balanceExp":0,"safetyExp":0,"totalChallenges":4,"badges":["legacy-a","legacy-a","legacy-b"],"currentSkinId":"skin-7"}"#.utf8
        )
        defaults.set(original, forKey: LegacyDefaultsReader.Key.progress)

        let rights = try LegacyDefaultsReader(
            defaults: defaults,
            persistentDomainName: suiteNames[0]
        ).readGrowthRights()
        let result = GrowthEntitlementResolver.resolve(
            policy: try policy,
            totalXP: 0,
            legacy: rights,
            stored: nil
        )

        XCTAssertEqual(result.highestUnlockedStageID, 7)
        XCTAssertEqual(result.selectedStageID, 7)
        XCTAssertEqual(result.legacyBadgeIDs, ["legacy-a", "legacy-a", "legacy-b"])

        UserDefaultsGrowthStageStateStore(defaults: defaults).writeMonotonic(
            GrowthStageStateV2(
                version: GrowthStageStateV2.currentVersion,
                highestUnlockedStageID: result.highestUnlockedStageID,
                selectedStageID: result.selectedStageID
            )
        )
        XCTAssertEqual(defaults.data(forKey: LegacyDefaultsReader.Key.progress), original)
    }

    func testMissingStageAssetRetainsRequestedStageAndUsesNeutralFallback() {
        for stageID in 1...7 {
            let resolution = GrowthStageArtResolver.resolve(stageID: stageID)
            XCTAssertEqual(resolution.artStageID, stageID)
            XCTAssertFalse(resolution.usesNeutralFallback)
        }

        for stageID in 8...12 {
            let resolution = GrowthStageArtResolver.resolve(stageID: stageID)
            XCTAssertEqual(resolution.artStageID, stageID)
            XCTAssertTrue(resolution.usesNeutralFallback)
        }
    }

    func testRoadmapUsesPolicyRowsAndPreservesLockedTitles() throws {
        let roadmap = GrowthStageRoadmapPresentation.items(
            policy: try policy,
            selectedStageID: 8,
            highestUnlockedStageID: 7
        )

        XCTAssertEqual(roadmap.map(\.stageID), Array(1...12))
        XCTAssertEqual(roadmap.map(\.threshold), try policy.thresholds)
        XCTAssertEqual(roadmap.map(\.title), try policy.titles)

        let locked = try XCTUnwrap(roadmap.first { $0.stageID == 8 })
        XCTAssertTrue(locked.isSelected)
        XCTAssertFalse(locked.isUnlocked)
        XCTAssertTrue(locked.usesNeutralFallback)
        XCTAssertTrue(locked.accessibilityLabel.contains("별빛 셰프"))
        XCTAssertTrue(locked.accessibilityLabel.contains("잠김"))
        XCTAssertTrue(locked.accessibilityLabel.contains("그림 준비 중"))
    }

    func testRoadmapDetailIncludesThresholdUnlockStateAndFallbackAccessibility() throws {
        let detail = GrowthStageRoadmapPresentation.detail(
            policy: try policy,
            stageID: 8,
            highestUnlockedStageID: 7
        )

        XCTAssertEqual(detail.stageID, 8)
        XCTAssertEqual(detail.title, "별빛 셰프")
        XCTAssertEqual(detail.threshold, 1_300)
        XCTAssertFalse(detail.isUnlocked)
        XCTAssertEqual(detail.unlockStateText, "1300 XP에 해금")
        XCTAssertTrue(detail.usesNeutralFallback)
        XCTAssertTrue(detail.accessibilityLabel.contains("레벨 8"))
        XCTAssertTrue(detail.accessibilityLabel.contains("별빛 셰프"))
        XCTAssertTrue(detail.accessibilityLabel.contains("1300 XP에 해금"))
        XCTAssertTrue(detail.accessibilityLabel.contains("그림 준비 중"))
    }

    func testStageDetailsProvideStoryAndUserRewardForEveryPolicyStage() throws {
        let policy = try policy
        let details = policy.thresholds.indices.map { index in
            GrowthStageRoadmapPresentation.detail(
                policy: policy,
                stageID: index + 1,
                highestUnlockedStageID: policy.thresholds.count
            )
        }

        XCTAssertEqual(details.count, policy.thresholds.count)
        XCTAssertTrue(
            details.allSatisfy { !$0.story.isEmpty },
            "every stage needs story copy"
        )
        XCTAssertTrue(
            details.allSatisfy { !$0.reward.isEmpty },
            "every stage needs reward copy"
        )
        XCTAssertEqual(details[0].story, "밝게 시작하는 공통 마스코트")
        XCTAssertEqual(details[0].reward, "새싹과 작은 잎")
        XCTAssertEqual(details[6].reward, "황금빛 레전드 모습")
        XCTAssertEqual(
            details[7].story,
            "별빛이 켜진 저녁 숲에서 새로운 맛을 천천히 만나 봐요."
        )
        XCTAssertEqual(details[7].reward, "별빛 모자와 저녁 숲")
        XCTAssertTrue(
            details[7].accessibilityLabel.contains(details[7].story),
            "detail accessibility label omitted story"
        )
        XCTAssertTrue(
            details[7].accessibilityLabel.contains("보상 \(details[7].reward)"),
            "detail accessibility label omitted reward"
        )
    }

    func testVerifiedStageDetailAccessibilityDoesNotAnnouncePendingArt() throws {
        let detail = GrowthStageRoadmapPresentation.detail(
            policy: try policy,
            stageID: 7,
            highestUnlockedStageID: 7
        )

        XCTAssertFalse(detail.usesNeutralFallback)
        let semantics = GrowthStageDetailAccessibilitySemantics.make(
            detail: detail,
            artState: .verified(unlocked: detail.isUnlocked)
        )
        XCTAssertFalse(semantics.spokenLabel.contains("그림 준비 중"))
    }

    func testNeutralFallbackAccessibilityLabelIsStageSpecific() {
        XCTAssertEqual(
            MascotNeutralFallbackView.accessibilityLabel(stageID: 8),
            "레벨 8, 그림 준비 중"
        )
    }

    func testGrowthStageDetailAccessibilityComposesRuntimeArtState() throws {
        let policy = try policy
        let verifiedDetail = GrowthStageRoadmapPresentation.detail(
            policy: policy,
            stageID: 7,
            highestUnlockedStageID: 7
        )
        let verified = GrowthStageDetailAccessibilitySemantics.make(
            detail: verifiedDetail,
            artState: .verified(unlocked: true)
        )

        XCTAssertNil(verified.parentLabel)
        XCTAssertTrue(verified.spokenLabel.contains("레벨 7 해금 캐릭터"))
        XCTAssertFalse(verified.spokenLabel.contains("그림 준비 중"))

        let runtimeFailure = GrowthStageDetailAccessibilitySemantics.make(
            detail: verifiedDetail,
            artState: .pending
        )
        XCTAssertEqual(runtimeFailure.artLabel, "레벨 7, 그림 준비 중")
        XCTAssertTrue(runtimeFailure.childArtIsPending)
        XCTAssertTrue(
            runtimeFailure.spokenLabel.contains("레벨 7, 그림 준비 중")
        )
        XCTAssertTrue(
            runtimeFailure.spokenLabel.contains("보상: 황금빛 레전드 모습")
        )

        let neutralDetail = GrowthStageRoadmapPresentation.detail(
            policy: policy,
            stageID: 8,
            highestUnlockedStageID: 7
        )
        let neutralFallback = GrowthStageDetailAccessibilitySemantics.make(
            detail: neutralDetail,
            artState: .pending
        )
        XCTAssertEqual(neutralFallback.artLabel, "레벨 8, 그림 준비 중")
        XCTAssertTrue(neutralFallback.spokenLabel.contains("그림 준비 중"))
    }

    @MainActor
    func testGrowthStageDetailAccessibilityUsesRuntimeLoaderState() async throws {
        let detail = GrowthStageRoadmapPresentation.detail(
            policy: try policy,
            stageID: 7,
            highestUnlockedStageID: 7
        )
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1, height: 1)
        ).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: context.format.bounds.size))
        }
        let gate = AccessibilityLoaderGate()
        let loader = MascotRestArtLoader(
            loadImage: { _, _ in
                await gate.wait()
                return image
            }
        )
        let loadingLabel = "레벨 7 캐릭터를 불러오는 중, 선택한 단계, 레전드 냠냠러, "
            + "1000 XP · 해금 완료, "
            + "이야기: 자기만의 속도로 성장한 레전드, "
            + "보상: 황금빛 레전드 모습"
        var appliedLabels: [String] = []
        let loadingHost = makeHost(
            GrowthStageDetailView(
                detail: detail,
                restArtLoader: loader,
                onAccessibilityLabelChange: { label in
                    appliedLabels.append(label)
                }
            )
        )
        defer { tearDownHost(loadingHost) }

        try await waitUntil {
            loader.isLoading
        }

        XCTAssertEqual(
            appliedLabels.last,
            loadingLabel
        )

        gate.open()
        try await waitUntil {
            loader.renderedImage(for: detail.stageID) != nil
        }
        await settleMainQueue()

        let verifiedLabel = "레벨 7 해금 캐릭터, 선택한 단계, 레전드 냠냠러, "
            + "1000 XP · 해금 완료, "
            + "이야기: 자기만의 속도로 성장한 레전드, "
            + "보상: 황금빛 레전드 모습"
        XCTAssertEqual(
            appliedLabels.last,
            verifiedLabel
        )

        tearDownHost(loadingHost)

        let failedLoader = MascotRestArtLoader(
            loadImage: { _, _ in
                throw MascotRigAssetError.missingAsset("composite-rest")
            }
        )
        var failureLabels: [String] = []
        let failureHost = makeHost(
            GrowthStageDetailView(
                detail: detail,
                restArtLoader: failedLoader,
                onAccessibilityLabelChange: { label in
                    failureLabels.append(label)
                }
            )
        )
        defer { tearDownHost(failureHost) }

        let failureLabel = "레벨 7, 그림 준비 중, 선택한 단계, 레전드 냠냠러, "
            + "1000 XP · 해금 완료, "
            + "이야기: 자기만의 속도로 성장한 레전드, "
            + "보상: 황금빛 레전드 모습"
        try await waitUntil {
            failedLoader.canRetry(for: detail.stageID)
                && failureLabels.last == failureLabel
        }
        await settleMainQueue()

        XCTAssertEqual(
            failureLabels.last,
            failureLabel
        )
        XCTAssertEqual(
            failureLabels.last.map {
                $0.components(separatedBy: "그림 준비 중").count - 1
            } ?? 0,
            1
        )
    }

    @MainActor
    func testGrowthStageDetailAccessibilityUsesCurrentStageArtOnFirstTransitionRender() async throws {
        let policy = try policy
        let stageSeven = GrowthStageRoadmapPresentation.detail(
            policy: policy,
            stageID: 7,
            highestUnlockedStageID: 7,
            selectedStageID: 7
        )
        let stageEight = GrowthStageRoadmapPresentation.detail(
            policy: policy,
            stageID: 8,
            highestUnlockedStageID: 7,
            selectedStageID: 8
        )
        let gate = AccessibilityLoaderGate()
        let loader = MascotRestArtLoader(
            loadImage: { _, _ in
                await gate.wait()
                return UIGraphicsImageRenderer(
                    size: CGSize(width: 1, height: 1)
                ).image { context in
                    UIColor.green.setFill()
                    context.fill(context.format.bounds)
                }
            }
        )
        let model = GrowthStageDetailTransitionModel(detail: stageSeven)
        var appliedLabels: [String] = []
        let host = makeHost(
            GrowthStageDetailTransitionHarness(
                model: model,
                restArtLoader: loader,
                onAccessibilityLabelChange: { label in
                    appliedLabels.append(label)
                }
            )
        )
        defer {
            gate.open()
            tearDownHost(host)
        }

        try await waitUntil {
            appliedLabels.contains {
                $0.hasPrefix("레벨 7 캐릭터를 불러오는 중")
            }
        }

        let stageEightStart = appliedLabels.count
        model.detail = stageEight
        try await waitUntil {
            appliedLabels.count > stageEightStart
        }
        XCTAssertTrue(
            appliedLabels[stageEightStart].hasPrefix("레벨 8, 그림 준비 중"),
            "first stage 8 accessibility label used stale stage art state: \(appliedLabels[stageEightStart])"
        )

        try await waitUntil {
            appliedLabels.last?.hasPrefix("레벨 8, 그림 준비 중") == true
        }

        let stageSevenReturnStart = appliedLabels.count
        model.detail = stageSeven
        try await waitUntil {
            appliedLabels.count > stageSevenReturnStart
        }
        XCTAssertTrue(
            appliedLabels[stageSevenReturnStart].hasPrefix("레벨 7 캐릭터를 불러오는 중"),
            "first stage 7 accessibility label used stale stage art state: \(appliedLabels[stageSevenReturnStart])"
        )
    }

    func testMalformedOrMissingPolicyNeverSilentlyFallsBack() {
        XCTAssertThrowsError(
            try GrowthPolicy(
                data: Data(
                    """
                    {
                      "version": 1,
                      "thresholds": [0, 80, 80, 320, 500, 720, 1000],
                      "titles": ["1", "2", "3", "4", "5", "6", "7"]
                    }
                    """.utf8
                )
            )
        ) { error in
            XCTAssertEqual(error as? GrowthPolicyError, .invalidContract)
        }

        XCTAssertThrowsError(
            try GrowthPolicy.load {
                throw CocoaError(.fileNoSuchFile)
            }
        ) { error in
            XCTAssertEqual(error as? GrowthPolicyError, .missingContract)
        }
    }

    private static let canonicalPolicy = Data(
        """
        {
          "version": 1,
          "thresholds": [0, 80, 180, 320, 500, 720, 1000, 1300, 1650, 2050, 2500, 3000],
          "titles": [
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
            "전설의 급식대장"
          ]
        }
        """.utf8
    )

    private func makeDefaults() -> UserDefaults {
        let suiteName = "GrowthPolicyTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func makeHost<Content: View>(
        _ content: Content
    ) -> (window: UIWindow, controller: UIHostingController<AnyView>) {
        let controller = UIHostingController(rootView: AnyView(content))
        let container = UIViewController()
        container.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
        controller.didMove(toParent: container)

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.rootViewController = container
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return (window, controller)
    }

    @MainActor
    private func tearDownHost(
        _ host: (window: UIWindow, controller: UIHostingController<AnyView>)
    ) {
        guard host.window.rootViewController != nil || !host.window.isHidden else {
            return
        }
        host.window.isHidden = true
        host.window.rootViewController = nil
        host.window.resignKey()
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for SwiftUI loader state")
    }

    @MainActor
    private func settleMainQueue() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}

@MainActor
private final class AccessibilityLoaderGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiters = continuations
        continuations.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@MainActor
private final class GrowthStageDetailTransitionModel: ObservableObject {
    @Published var detail: GrowthStageDetailPresentation

    init(detail: GrowthStageDetailPresentation) {
        self.detail = detail
    }
}

@MainActor
private struct GrowthStageDetailTransitionHarness: View {
    @ObservedObject var model: GrowthStageDetailTransitionModel
    let restArtLoader: MascotRestArtLoader
    let onAccessibilityLabelChange: (String) -> Void

    var body: some View {
        GrowthStageDetailView(
            detail: model.detail,
            restArtLoader: restArtLoader,
            onAccessibilityLabelChange: onAccessibilityLabelChange
        )
    }
}

private final class InterleavingUserDefaults: UserDefaults, @unchecked Sendable {
    let firstReadStarted = DispatchSemaphore(value: 0)

    private let readLock = NSLock()
    private var readCount = 0

    override func data(forKey defaultName: String) -> Data? {
        let value = super.data(forKey: defaultName)
        guard defaultName == GrowthStageStateV2.key else {
            return value
        }

        readLock.lock()
        readCount += 1
        let isFirstRead = readCount == 1
        readLock.unlock()

        if isFirstRead {
            firstReadStarted.signal()
            Thread.sleep(forTimeInterval: 0.2)
        }
        return value
    }
}
