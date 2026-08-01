import XCTest
@testable import NaymNaymLevelUp

final class CollectionProgressTests: XCTestCase {
    func testPositiveRecordsUnlockFoodChallengeAndWeekdayStreakBadges() throws {
        let records = [
            collectionRecord("2026-07-27", "시금치나물", "finished"),
            collectionRecord("2026-07-27", "닭갈비", "oneBite"),
            collectionRecord("2026-07-27", "우유", "finished"),
            collectionRecord("2026-07-28", "사과", "half"),
            collectionRecord("2026-07-29", "현미밥", "finished"),
            collectionRecord("2026-07-29", "된장국", "oneBite"),
            collectionRecord("2026-07-29", "김", "finished"),
            collectionRecord("2026-07-30", "보리밥", "finished"),
            collectionRecord("2026-07-30", "수제비", "oneBite"),
            collectionRecord("2026-07-30", "단무지", "half"),
            collectionRecord("2026-07-31", "카레라이스", "finished"),
            collectionRecord("2026-07-31", "시금치나물", "allergyAvoided"),
            collectionRecord("2026-07-31", "브로콜리", "difficultToday"),
        ]

        let progress = try CollectionProgress.evaluate(
            totalXP: 500,
            records: records,
            policyData: Self.policy
        )

        XCTAssertEqual(progress.totalXP, 500)
        XCTAssertEqual(progress.positiveRecordCount, 11)
        XCTAssertEqual(progress.activeDayCount, 5)
        XCTAssertEqual(progress.longestWeekdayStreak, 5)
        XCTAssertTrue(progress.earnedBadgeIDs.isSuperset(of: [
            "nutrition_vegetable_1",
            "nutrition_protein_1",
            "nutrition_dairy_1",
            "nutrition_fruit_1",
            "nutrition_groups_4",
            "challenge_first_positive",
            "challenge_one_bite_1",
            "challenge_finished_1",
            "challenge_new_menu_3",
            "challenge_three_menu_days_3",
            "streak_record_days_3",
            "streak_weekday_5",
        ]))
        XCTAssertFalse(progress.earnedBadgeIDs.contains("nutrition_vegetable_5"))
    }

    private func collectionRecord(
        _ date: String,
        _ menu: String,
        _ status: String
    ) -> CollectionRecord {
        CollectionRecord(date: date, normalizedMenuName: menu, status: status)
    }

    private static let policy = Data(
        """
        {
          "version": 1,
          "positiveStatuses": ["oneBite", "half", "finished"],
          "foodGroups": [
            { "id": "vegetable", "keywords": ["시금치", "브로콜리"] },
            { "id": "protein", "keywords": ["닭"] },
            { "id": "dairy", "keywords": ["우유"] },
            { "id": "fruit", "keywords": ["사과"] }
          ],
          "badges": [
            { "id": "nutrition_vegetable_1", "category": "nutrition", "metric": "food_group_vegetable", "threshold": 1, "title": "채소 첫걸음" },
            { "id": "nutrition_vegetable_5", "category": "nutrition", "metric": "food_group_vegetable", "threshold": 5, "title": "채소 친구" },
            { "id": "nutrition_protein_1", "category": "nutrition", "metric": "food_group_protein", "threshold": 1, "title": "단백질 첫걸음" },
            { "id": "nutrition_dairy_1", "category": "nutrition", "metric": "food_group_dairy", "threshold": 1, "title": "유제품 첫걸음" },
            { "id": "nutrition_fruit_1", "category": "nutrition", "metric": "food_group_fruit", "threshold": 1, "title": "과일 첫걸음" },
            { "id": "nutrition_groups_4", "category": "nutrition", "metric": "distinct_food_groups", "threshold": 4, "title": "무지개 식판" },
            { "id": "challenge_first_positive", "category": "challenge", "metric": "positive_records", "threshold": 1, "title": "첫 기록" },
            { "id": "challenge_one_bite_1", "category": "challenge", "metric": "one_bite_records", "threshold": 1, "title": "한 입 용기" },
            { "id": "challenge_finished_1", "category": "challenge", "metric": "finished_records", "threshold": 1, "title": "완식 첫걸음" },
            { "id": "challenge_new_menu_3", "category": "challenge", "metric": "distinct_menus", "threshold": 3, "title": "새 메뉴 탐험" },
            { "id": "challenge_three_menu_days_3", "category": "challenge", "metric": "three_menu_days", "threshold": 3, "title": "식판 탐험가" },
            { "id": "streak_record_days_3", "category": "streak", "metric": "active_days", "threshold": 3, "title": "기록 습관" },
            { "id": "streak_weekday_5", "category": "streak", "metric": "weekday_streak", "threshold": 5, "title": "주간 완주" }
          ]
        }
        """.utf8
    )
}
