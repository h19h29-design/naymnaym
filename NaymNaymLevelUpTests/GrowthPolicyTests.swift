import XCTest
@testable import NaymNaymLevelUp

final class GrowthPolicyTests: XCTestCase {
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
}
