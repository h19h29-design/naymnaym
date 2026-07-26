import CoreData
import XCTest
@testable import NaymNaymLevelUp

final class GrowthRepositoryTests: XCTestCase {
    func testRecentPositiveEventsFilterAndOrderNewestThenIDDescending() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildProgressRepository(
            context: container.viewContext
        )
        let sharedTime = Date(timeIntervalSince1970: 200)

        for event in [
            RebuildProgressEvent(
                id: "meal:older",
                amount: 7,
                occurredAt: Date(timeIntervalSince1970: 100)
            ),
            RebuildProgressEvent(
                id: "meal:same-a",
                amount: 8,
                occurredAt: sharedTime
            ),
            RebuildProgressEvent(
                id: "meal:same-z",
                amount: 9,
                occurredAt: sharedTime
            ),
            RebuildProgressEvent(
                id: "meal:zero",
                amount: 0,
                occurredAt: Date(timeIntervalSince1970: 300)
            ),
            RebuildProgressEvent(
                id: "legacy:negative",
                amount: -99,
                occurredAt: Date(timeIntervalSince1970: 400)
            ),
        ] {
            XCTAssertTrue(try repository.appendIfAbsent(event))
        }

        XCTAssertEqual(
            try repository.recentPositiveEvents(limit: 10).map(\.id),
            ["meal:same-z", "meal:same-a", "meal:older"]
        )
    }

    func testRecentPositiveEventsApplyRequestedAndSafetyLimits() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildProgressRepository(
            context: container.viewContext
        )

        for index in 0..<25 {
            XCTAssertTrue(
                try repository.appendIfAbsent(
                    RebuildProgressEvent(
                        id: String(format: "event:%02d", index),
                        amount: 1,
                        occurredAt: Date(
                            timeIntervalSince1970: TimeInterval(index)
                        )
                    )
                )
            )
        }

        XCTAssertEqual(
            try repository.recentPositiveEvents(limit: 3).map(\.id),
            ["event:24", "event:23", "event:22"]
        )
        XCTAssertEqual(
            try repository.recentPositiveEvents(limit: 10_000).count,
            20
        )
        XCTAssertEqual(
            try repository.recentPositiveEvents(limit: 0),
            []
        )
    }

    func testCanonicalMealEventPresentationUsesOnlyEventIDIdentity() {
        let presentation = GrowthEventPresentation(
            event: RebuildProgressEvent(
                id: "meal:2026-07-25|시금치 나물|oneBite",
                amount: 18,
                occurredAt: Date(timeIntervalSince1970: 100),
                sourceRecordID: "550e8400-e29b-41d4-a716-446655440000"
            )
        )

        XCTAssertEqual(presentation.title, "시금치 나물 · 한 입 도전")
        XCTAssertEqual(presentation.xpText, "+18 XP")
    }

    func testCanonicalMealPresentationRejectsNoncanonicalIdentityAndSupportsHalf() {
        let cases: [(id: String, expectedTitle: String)] = [
            (
                "meal:2026-07-25|오이|half",
                "오이 · 절반 먹었어요"
            ),
            (
                "meal:2026-02-30|오이|finished",
                "성장 XP 획득"
            ),
            (
                "meal:2026-07-25| 오이 |finished",
                "성장 XP 획득"
            ),
            (
                "meal:2026-07-25|SPINACH|finished",
                "성장 XP 획득"
            ),
            (
                "meal:2026-07-25|spinach|finished",
                "spinach · 다 먹었어요"
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                GrowthEventPresentation(
                    event: RebuildProgressEvent(
                        id: testCase.id,
                        amount: 12,
                        occurredAt: Date(timeIntervalSince1970: 100)
                    )
                ).title,
                testCase.expectedTitle,
                testCase.id
            )
        }
    }

    func testLegacyIdentityNeverInventsMealCopyFromSourceRecordID() {
        let presentation = GrowthEventPresentation(
            event: RebuildProgressEvent(
                id: "legacy:550e8400-e29b-41d4-a716-446655440000",
                amount: 12,
                occurredAt: Date(timeIntervalSince1970: 100),
                sourceRecordID: "2026-07-25|시금치 나물|finished"
            )
        )

        XCTAssertEqual(presentation.title, "성장 XP 획득")
        XCTAssertEqual(presentation.xpText, "+12 XP")
    }

    func testMalformedMealAndReconciliationEventsUseTruthfulLabels() {
        XCTAssertEqual(
            GrowthEventPresentation(
                event: RebuildProgressEvent(
                    id: "meal:migrated-uuid",
                    amount: 9,
                    occurredAt: Date(timeIntervalSince1970: 100),
                    sourceRecordID: "2026-07-25|김치|finished"
                )
            ).title,
            "성장 XP 획득"
        )
        XCTAssertEqual(
            GrowthEventPresentation(
                event: RebuildProgressEvent(
                    id: "legacy:progress-reconciliation",
                    amount: 40,
                    occurredAt: Date(timeIntervalSince1970: 100)
                )
            ).title,
            "이전 성장 기록 정리"
        )
    }
}
