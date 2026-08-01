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

    func testCollectionSnapshotReturnsOnlyActiveMealRecordsInStableOrder() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let progress = RebuildProgressRepository(context: container.viewContext)
        XCTAssertTrue(
            try progress.appendIfAbsent(
                RebuildProgressEvent(
                    id: "meal:2026-07-31|현미밥|finished",
                    amount: 18,
                    occurredAt: Date(timeIntervalSince1970: 100)
                )
            )
        )
        try insertMealRecord(
            id: "2026-07-31|현미밥|finished",
            date: "2026-07-31",
            menu: "현미밥",
            status: "finished",
            in: container
        )
        try insertMealRecord(
            id: "2026-07-30|시금치나물|oneBite",
            date: "2026-07-30",
            menu: "시금치나물",
            status: "oneBite",
            in: container
        )
        try insertMealRecord(
            id: "2026-07-29|우유|allergyAvoided",
            date: "2026-07-29",
            menu: "우유",
            status: "allergyAvoided",
            deletedAt: Date(timeIntervalSince1970: 1),
            in: container
        )

        let snapshot = try await CoreDataCollectionSnapshotProvider(
            container: container
        ).loadCollection()

        XCTAssertEqual(snapshot.totalXP, 18)
        XCTAssertEqual(
            snapshot.records,
            [
                CollectionRecord(
                    date: "2026-07-30",
                    normalizedMenuName: "시금치나물",
                    status: "oneBite"
                ),
                CollectionRecord(
                    date: "2026-07-31",
                    normalizedMenuName: "현미밥",
                    status: "finished"
                ),
            ]
        )
    }

    private func insertMealRecord(
        id: String,
        date: String,
        menu: String,
        status: String,
        deletedAt: Date? = nil,
        in container: NSPersistentContainer
    ) throws {
        try container.viewContext.performAndWait {
            let entity = try XCTUnwrap(
                container.managedObjectModel.entitiesByName[RebuildEntityName.mealRecord]
            )
            let record = RebuildMealRecordManagedObject(
                entity: entity,
                insertInto: container.viewContext
            )
            record.id = id
            record.date = date
            record.menuName = menu
            record.normalizedMenuName = menu.lowercased()
            record.status = status
            record.difficultyReasonsJSON = "[]"
            record.allergyCodesJSON = "[]"
            record.photoIDsJSON = "[]"
            record.parentShareEnabled = false
            record.updatedAt = Date(timeIntervalSince1970: 10)
            record.deletedAt = deletedAt
            try container.viewContext.save()
        }
    }
}
