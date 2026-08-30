import Foundation
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

    func testMissingStageAssetUsesVerifiedOneToSevenFallback() {
        for stageID in 1...7 {
            let resolution = GrowthStageArtResolver.resolve(stageID: stageID)
            XCTAssertEqual(resolution.artStageID, stageID)
            XCTAssertFalse(resolution.usesNeutralFallback)
        }

        for stageID in 8...12 {
            let resolution = GrowthStageArtResolver.resolve(stageID: stageID)
            XCTAssertEqual(resolution.artStageID, 7)
            XCTAssertTrue(resolution.usesNeutralFallback)
        }
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
}
