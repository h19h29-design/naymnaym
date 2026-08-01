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
            (1_399, 7),
            (1_400, 8),
            (1_849, 8),
            (1_850, 9),
            (2_349, 9),
            (2_350, 10),
            (2_899, 10),
            (2_900, 11),
            (3_499, 11),
            (3_500, 12),
            (4_149, 12),
            (4_150, 13),
            (4_849, 13),
            (4_850, 14),
            (Int.max, 14),
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
                1_400, 1_850, 2_350, 2_900, 3_500, 4_150, 4_850,
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
                "숲길 수호자",
                "제철 탐험대장",
                "균형 식판 장인",
                "초록별 수호대장",
                "영양 수호대장",
                "황금 도토리 대장",
                "급식 전설",
            ]
        )
        XCTAssertEqual(try policy.title(for: 0), "냠냠 새싹")
        XCTAssertEqual(try policy.title(for: 14), "급식 전설")
        XCTAssertEqual(try policy.title(for: 15), "급식 전설")
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
          "thresholds": [0, 80, 180, 320, 500, 720, 1000, 1400, 1850, 2350, 2900, 3500, 4150, 4850],
          "titles": [
            "냠냠 새싹",
            "한 입 탐험가",
            "냠냠 용사",
            "편식 몬스터 사냥꾼",
            "급식 히어로",
            "영양 마스터",
            "레전드 냠냠러",
            "숲길 수호자",
            "제철 탐험대장",
            "균형 식판 장인",
            "초록별 수호대장",
            "영양 수호대장",
            "황금 도토리 대장",
            "급식 전설"
          ]
        }
        """.utf8
    )
}
