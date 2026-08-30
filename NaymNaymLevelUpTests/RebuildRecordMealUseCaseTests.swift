import CoreData
import XCTest
@testable import NaymNaymLevelUp

final class RebuildRecordMealUseCaseTests: XCTestCase {
    func testSharedSpinachFixtureAwardsOnce() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)
        let command = command()

        let first = try useCase.execute(command)
        let second = try useCase.execute(command)

        XCTAssertEqual(
            try NutritionRuleEngine().insight(menuName: command.menuName).nutrients.map(\.id),
            ["fiber", "vitamin"]
        )
        XCTAssertEqual(
            first,
            RecordMealResult(xpGranted: 18, totalXP: 18, motion: .mealSuccess)
        )
        XCTAssertEqual(second.xpGranted, 0)
        XCTAssertEqual(second.totalXP, 18)
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testNutritionUsesContractOrderDeduplicationAndChildSafeCopy() throws {
        let insight = try NutritionRuleEngine().insight(menuName: "멸치 김치")

        XCTAssertEqual(
            insight.nutrients,
            [
                NutritionInsight.Nutrient(
                    id: "vitamin",
                    childName: "비타민",
                    alternatives: ["귤", "토마토"]
                ),
                NutritionInsight.Nutrient(
                    id: "protein",
                    childName: "단백질",
                    alternatives: ["달걀", "두부"]
                ),
                NutritionInsight.Nutrient(
                    id: "iron",
                    childName: "철분",
                    alternatives: ["소고기", "두부"]
                ),
                NutritionInsight.Nutrient(
                    id: "calcium",
                    childName: "칼슘",
                    alternatives: ["우유", "멸치"]
                ),
            ]
        )
        XCTAssertEqual(insight.ruleVersion, 1)
        XCTAssertEqual(insight.omissionCopy, "영양소를 조금 놓칠 수 있어요.")
        XCTAssertEqual(
            insight.educationNotice,
            "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요."
        )
    }

    func testNutritionOutputFollowsNutrientOrderWhenRulesAreReordered() throws {
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try contractData(named: "nutrition-rules.json")
            ) as? [String: Any]
        )
        document["rules"] = Array(
            try XCTUnwrap(document["rules"] as? [[String: Any]]).reversed()
        )
        let reordered = try JSONSerialization.data(withJSONObject: document)

        let insight = try NutritionRuleEngine(ruleData: reordered)
            .insight(menuName: "멸치 김치")

        XCTAssertEqual(
            insight.nutrients.map(\.id),
            ["vitamin", "protein", "iron", "calcium"]
        )
    }

    func testNutritionRejectsUnsafeOrChangedContractCopy() throws {
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try contractData(named: "nutrition-rules.json")
            ) as? [String: Any]
        )
        document["omissionCopy"] = "반드시 먹어야 해요."
        document["educationNotice"] = "이 음식은 병을 치료해요."
        let unsafe = try JSONSerialization.data(withJSONObject: document)

        XCTAssertThrowsError(try NutritionRuleEngine(ruleData: unsafe)) { error in
            XCTAssertEqual(error as? RebuildContractLoadError, .invalid("nutrition-rules.json"))
        }
    }

    func testMalformedNutritionContractFailsDeterministically() throws {
        let malformed = Data(#"{"version":1,"rules":[]}"#.utf8)

        XCTAssertThrowsError(try NutritionRuleEngine(ruleData: malformed)) { error in
            XCTAssertEqual(error as? RebuildContractLoadError, .invalid("nutrition-rules.json"))
        }
    }

    func testNutritionContractRejectsIntegralFloatingPointVersion() throws {
        let canonical = try XCTUnwrap(
            String(
                data: try contractData(named: "nutrition-rules.json"),
                encoding: .utf8
            )
        )
        let floatingPointVersion = Data(
            canonical.replacingOccurrences(
                of: #""version": 1"#,
                with: #""version": 1.0"#
            ).utf8
        )

        XCTAssertThrowsError(
            try NutritionRuleEngine(ruleData: floatingPointVersion)
        ) { error in
            XCTAssertEqual(
                error as? RebuildContractLoadError,
                .invalid("nutrition-rules.json")
            )
        }
    }

    func testNearBaseCapGrantsOnlyRemainingFiveXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:2026-07-25|기존|finished",
            amount: 45,
            sourceRecordID: "2026-07-25|기존|finished",
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(result, RecordMealResult(xpGranted: 5, totalXP: 50, motion: .mealSuccess))
    }

    func testDailyTotalCapStopsBaseAfterChallengeUsage() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:2026-07-25|기존|finished",
            amount: 30,
            sourceRecordID: "2026-07-25|기존|finished",
            in: container
        )
        try seedEvent(
            id: "challenge:2026-07-25|기존|finished",
            amount: 70,
            sourceRecordID: "2026-07-25|기존|finished",
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(result, RecordMealResult(xpGranted: 0, totalXP: 100, motion: .mealSuccess))
    }

    func testStatusTransitionLeavesOneActiveRecordAndOneAwardEvent() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)
        let transitionedAt = Date(timeIntervalSince1970: 1_753_430_401)

        let first = try useCase.execute(command())
        let transitioned = try useCase.execute(
            command(
                status: .finished,
                occurredAt: transitionedAt
            )
        )

        XCTAssertEqual(first.xpGranted, 18)
        XCTAssertEqual(transitioned.xpGranted, 0)
        XCTAssertEqual(transitioned.totalXP, 18)
        XCTAssertEqual(try activeRecords(in: container).count, 1)
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
        XCTAssertEqual(try eventAmounts(in: container), [18])
    }

    func testStatusTransitionPreservesPhotosAndSourceRecordID() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let legacyRecordID = "2026-07-25|시금치나물|oneBite"
        try seedRecord(
            command(
                recordID: legacyRecordID,
                photoIDs: ["photo-before"],
                parentShareEnabled: true
            ),
            in: container
        )
        try seedEvent(
            id: "meal:\(legacyRecordID)",
            amount: 18,
            sourceRecordID: legacyRecordID,
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(
            command(
                status: .finished,
                photoIDs: ["photo-after"],
                parentShareEnabled: false,
                occurredAt: Date(timeIntervalSince1970: 1_753_430_401)
            )
        )

        let activeRows = try activeRecords(in: container)
        XCTAssertEqual(activeRows.count, 1)
        let active = try XCTUnwrap(activeRows.first)
        XCTAssertEqual(result.xpGranted, 0)
        XCTAssertEqual(active.id, legacyRecordID)
        XCTAssertEqual(active.status, RebuildEatingStatus.finished.rawValue)
        XCTAssertEqual(
            try decode([String].self, from: active.photoIDsJSON),
            ["photo-before", "photo-after"]
        )
        XCTAssertTrue(active.parentShareEnabled)
        XCTAssertEqual(try onlyEvent(in: container).sourceRecordID, legacyRecordID)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testStableCommandPreservesCustomRecordAndMatchingAwardEvent() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let customRecordID = "550e8400-e29b-41d4-a716-446655440000"
        try seedRecord(
            command(
                recordID: customRecordID,
                status: .oneBite,
                photoIDs: ["photo-before"]
            ),
            in: container
        )
        try seedEvent(
            id: "meal:\(customRecordID)",
            amount: 18,
            sourceRecordID: customRecordID,
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(
            command(
                status: .finished,
                photoIDs: ["photo-after"],
                occurredAt: Date(timeIntervalSince1970: 1_753_430_401)
            )
        )

        let record = try XCTUnwrap(try activeRecords(in: container).first)
        let event = try onlyEvent(in: container)
        XCTAssertEqual(
            result,
            RecordMealResult(xpGranted: 0, totalXP: 18, motion: .mealSuccess)
        )
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(record.id, customRecordID)
        XCTAssertEqual(record.status, RebuildEatingStatus.finished.rawValue)
        XCTAssertEqual(
            try decode([String].self, from: record.photoIDsJSON),
            ["photo-before", "photo-after"]
        )
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
        XCTAssertEqual(event.id, "meal:\(customRecordID)")
        XCTAssertEqual(event.sourceRecordID, customRecordID)
        XCTAssertEqual(event.amount, 18)
    }

    func testNewestRevisionThenOlderPreparedRevisionRejectsBeforeSidecarOrMutation() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let sidecar = TestNutrientImpactSidecar()
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            nutrientImpactSidecar: sidecar
        )
        let olderAt = Date(timeIntervalSince1970: 1_753_430_400)
        let newestAt = olderAt.addingTimeInterval(10)

        _ = try useCase.execute(
            command(
                status: .finished,
                photoIDs: ["newest-photo"],
                occurredAt: newestAt,
                nutritionSnapshot: try nutritionSnapshot(
                    status: .finished,
                    updatedAt: newestAt
                )
            )
        )
        let installCountAfterNewest = sidecar.installCount

        XCTAssertThrowsError(
            try useCase.execute(
                command(
                    status: .half,
                    photoIDs: ["older-photo"],
                    occurredAt: olderAt,
                    nutritionSnapshot: try nutritionSnapshot(
                        status: .half,
                        updatedAt: olderAt
                    )
                )
            )
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .staleRevision)
        }

        let active = try XCTUnwrap(try activeRecords(in: container).first)
        XCTAssertEqual(sidecar.installCount, installCountAfterNewest)
        XCTAssertEqual(active.status, RebuildEatingStatus.finished.rawValue)
        XCTAssertEqual(active.updatedAt, newestAt)
        XCTAssertEqual(
            try decode([String].self, from: active.photoIDsJSON),
            ["newest-photo"]
        )
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testEqualTimestampAllowsExactReplayButRejectsDifferentPayload() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)

        _ = try useCase.execute(command())
        let replay = try useCase.execute(command())

        XCTAssertEqual(replay.xpGranted, 0)
        XCTAssertThrowsError(
            try useCase.execute(command(status: .finished))
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .conflictingRevision)
        }
        let active = try XCTUnwrap(try activeRecords(in: container).first)
        XCTAssertEqual(active.status, RebuildEatingStatus.oneBite.rawValue)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testNewestLegacyDuplicateWinsAndOthersAreSoftDeleted() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|oneBite",
                status: .oneBite,
                photoIDs: ["older-photo"],
                occurredAt: Date(timeIntervalSince1970: 1_753_430_300)
            ),
            in: container
        )
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|half",
                status: .half,
                photoIDs: ["newer-photo"],
                occurredAt: Date(timeIntervalSince1970: 1_753_430_350)
            ),
            in: container
        )

        _ = try RecordMealUseCase(container: container).execute(
            command(status: .finished)
        )

        let rows = try allRecords(in: container)
        let activeRows = rows.filter { $0.deletedAt == nil }
        let inactiveRows = rows.filter { $0.deletedAt != nil }
        XCTAssertEqual(activeRows.count, 1)
        XCTAssertEqual(inactiveRows.count, 1)
        let active = try XCTUnwrap(activeRows.first)
        let inactive = try XCTUnwrap(inactiveRows.first)
        XCTAssertEqual(rows.count, 2, "legacy rows must never be physically deleted")
        XCTAssertEqual(active.id, "2026-07-25|시금치나물|half")
        XCTAssertEqual(active.status, RebuildEatingStatus.finished.rawValue)
        XCTAssertEqual(
            try decode([String].self, from: active.photoIDsJSON),
            ["newer-photo", "older-photo"]
        )
        XCTAssertEqual(inactive.id, "2026-07-25|시금치나물|oneBite")
    }

    func testCorruptLoserPhotoJSONFailsClosedBeforeSoftDelete() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|oneBite",
                status: .oneBite,
                photoIDs: ["older-photo"],
                occurredAt: Date(timeIntervalSince1970: 1_753_430_300)
            ),
            in: container
        )
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|half",
                status: .half,
                photoIDs: ["newer-photo"],
                occurredAt: Date(timeIntervalSince1970: 1_753_430_350)
            ),
            in: container
        )
        let loser = try XCTUnwrap(
            try allRecords(in: container).first {
                $0.id.hasSuffix("|oneBite")
            }
        )
        try container.viewContext.performAndWait {
            loser.photoIDsJSON = "{"
            try container.viewContext.save()
        }

        XCTAssertThrowsError(
            try RecordMealUseCase(container: container).execute(
                command(
                    status: .finished,
                    occurredAt: Date(timeIntervalSince1970: 1_753_430_400)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? RebuildContractLoadError,
                .invalid("meal-record.json")
            )
        }

        let rows = try allRecords(in: container)
        XCTAssertEqual(rows.filter { $0.deletedAt == nil }.count, 2)
        XCTAssertEqual(
            rows.first { $0.id.hasSuffix("|half") }?.status,
            RebuildEatingStatus.half.rawValue
        )
        XCTAssertEqual(loser.photoIDsJSON, "{")
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testEqualTimestampLegacyDuplicateUsesStableIDTieBreaker() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let tiedDate = Date(timeIntervalSince1970: 1_753_430_350)
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|oneBite",
                status: .oneBite,
                occurredAt: tiedDate
            ),
            in: container
        )
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|half",
                status: .half,
                occurredAt: tiedDate
            ),
            in: container
        )

        _ = try RecordMealUseCase(container: container).execute(
            command(status: .finished)
        )

        let active = try XCTUnwrap(try activeRecords(in: container).first)
        XCTAssertEqual(active.id, "2026-07-25|시금치나물|half")
        XCTAssertEqual(try allRecords(in: container).count, 2)
    }

    func testStableCommandIDCollisionWithDifferentLogicalRowFailsBeforeSidecar() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물",
                date: "2026-07-24",
                menuName: "다른메뉴"
            ),
            in: container
        )
        let sidecar = TestNutrientImpactSidecar()
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            nutrientImpactSidecar: sidecar
        )

        XCTAssertThrowsError(
            try useCase.execute(
                command(nutritionSnapshot: try nutritionSnapshot())
            )
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .recordIdentityCollision)
        }

        XCTAssertEqual(sidecar.installCount, 0)
        XCTAssertEqual(try allRecords(in: container).count, 1)
        XCTAssertEqual(try activeRecords(in: container).first?.date, "2026-07-24")
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testCurrentLogicalRecordWinsWhenStableCommandIDIsAlreadyUnrelated() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물",
                date: "2026-07-24",
                menuName: "다른메뉴"
            ),
            in: container
        )
        let currentID = "2026-07-25|시금치나물|oneBite"
        try seedRecord(
            command(
                recordID: currentID,
                status: .oneBite,
                occurredAt: Date(timeIntervalSince1970: 1_753_430_300)
            ),
            in: container
        )

        _ = try RecordMealUseCase(container: container).execute(
            command(
                status: .finished,
                occurredAt: Date(timeIntervalSince1970: 1_753_430_500)
            )
        )

        let rows = try allRecords(in: container)
        XCTAssertEqual(rows.count, 2)
        let current = try XCTUnwrap(rows.first { $0.id == currentID })
        XCTAssertEqual(current.status, RebuildEatingStatus.finished.rawValue)
        XCTAssertNil(current.deletedAt)
        XCTAssertEqual(
            rows.first { $0.id == "2026-07-25|시금치나물" }?.date,
            "2026-07-24"
        )
    }

    func testInvalidStoredPhotoJSONFailsClosedWithoutChangingExistingData() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|half",
                status: .half,
                photoIDs: ["photo-before"],
                parentShareEnabled: true
            ),
            in: container
        )
        let original = try XCTUnwrap(try activeRecords(in: container).first)
        try container.viewContext.performAndWait {
            original.photoIDsJSON = "{"
            try container.viewContext.save()
        }

        XCTAssertThrowsError(
            try RecordMealUseCase(container: container).execute(
                command(
                    status: .finished,
                    photoIDs: ["photo-after"],
                    parentShareEnabled: false
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? RebuildContractLoadError,
                .invalid("meal-record.json")
            )
        }

        let unchanged = try XCTUnwrap(try activeRecords(in: container).first)
        XCTAssertEqual(try allRecords(in: container).count, 1)
        XCTAssertEqual(unchanged.id, "2026-07-25|시금치나물|half")
        XCTAssertEqual(unchanged.status, RebuildEatingStatus.half.rawValue)
        XCTAssertEqual(unchanged.photoIDsJSON, "{")
        XCTAssertTrue(unchanged.parentShareEnabled)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testLogicalAwardMatchingDoesNotTreatRiceAsRiceballPrefix() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:2026-07-25|riceball|finished",
            amount: 10,
            sourceRecordID: "2026-07-25|riceball|finished",
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(
            command(
                recordID: "2026-07-25|rice",
                menuName: "rice"
            )
        )

        XCTAssertEqual(result.xpGranted, 18)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 2)
    }

    func testCrossStatusRecordOrEventAloneSealsAward() throws {
        let recordContainer = try RebuildPersistentStore.makeInMemory()
        try seedRecord(
            command(
                recordID: "2026-07-25|시금치나물|finished",
                status: .finished
            ),
            in: recordContainer
        )
        let recordSealed = try RecordMealUseCase(
            container: recordContainer
        ).execute(
            command(
                occurredAt: Date(timeIntervalSince1970: 1_753_430_401)
            )
        )

        XCTAssertEqual(recordSealed.xpGranted, 0)
        XCTAssertEqual(recordSealed.totalXP, 0)
        XCTAssertEqual(try activeRecords(in: recordContainer).count, 1)
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: recordContainer), 1)
        XCTAssertEqual(
            try count(RebuildEntityName.progressEvent, in: recordContainer),
            1
        )

        let eventContainer = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:2026-07-25|시금치나물|finished",
            amount: 10,
            sourceRecordID: "2026-07-25|시금치나물|finished",
            in: eventContainer
        )
        let eventSealed = try RecordMealUseCase(
            container: eventContainer
        ).execute(command())

        XCTAssertEqual(eventSealed.xpGranted, 0)
        XCTAssertEqual(eventSealed.totalXP, 10)
        XCTAssertEqual(
            try count(RebuildEntityName.mealRecord, in: eventContainer),
            1
        )
        XCTAssertEqual(
            try count(RebuildEntityName.progressEvent, in: eventContainer),
            1
        )
    }

    func testMultipleLegacyEventsRemainImmutableWithoutAddingXPOrEvent() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:2026-07-25|시금치나물|oneBite",
            amount: 18,
            sourceRecordID: "2026-07-25|시금치나물|oneBite",
            in: container
        )
        try seedEvent(
            id: "meal:2026-07-25|시금치나물|finished",
            amount: 12,
            sourceRecordID: "2026-07-25|시금치나물|finished",
            in: container
        )

        let before = try eventAmounts(in: container).sorted()
        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(result.xpGranted, 0)
        XCTAssertEqual(try eventAmounts(in: container).sorted(), before)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 2)
        XCTAssertEqual(try activeRecords(in: container).count, 1)
    }

    func testRecordOnlyRepairCreatesAtMostOneZeroXPEvent() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedRecord(
            command(recordID: "2026-07-25|시금치나물|oneBite"),
            in: container
        )
        let useCase = try RecordMealUseCase(container: container)

        let first = try useCase.execute(
            command(
                status: .finished,
                occurredAt: Date(timeIntervalSince1970: 1_753_430_401)
            )
        )
        let second = try useCase.execute(
            command(
                status: .half,
                occurredAt: Date(timeIntervalSince1970: 1_753_430_402)
            )
        )

        XCTAssertEqual(first.xpGranted, 0)
        XCTAssertEqual(second.xpGranted, 0)
        XCTAssertEqual(try eventAmounts(in: container), [0])
    }

    func testMigratedMealEventWithUUIDSourceCountsTowardSeoulDailyBaseCap() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:migrated-uuid",
            amount: 45,
            sourceRecordID: "550e8400-e29b-41d4-a716-446655440000",
            occurredAt: Date(timeIntervalSince1970: 1_784_948_400),
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(result, RecordMealResult(xpGranted: 5, totalXP: 50, motion: .mealSuccess))
    }

    func testMigratedChallengeEventWithNilSourceCountsTowardSeoulDailyTotalCap() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "challenge:migrated-no-source",
            amount: 95,
            sourceRecordID: nil,
            occurredAt: Date(timeIntervalSince1970: 1_784_948_400),
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(result, RecordMealResult(xpGranted: 5, totalXP: 100, motion: .mealSuccess))
    }

    func testCanonicalSourceDateWinsOverBackfilledOccurredAtDate() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:backfilled-canonical-source",
            amount: 100,
            sourceRecordID: "2026-07-24|기존|finished",
            occurredAt: Date(timeIntervalSince1970: 1_784_948_400),
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(
            result,
            RecordMealResult(xpGranted: 18, totalXP: 118, motion: .mealSuccess)
        )
    }

    func testNegativeCorrectionsNeverCancelPositiveDailyOrLifetimeXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:positive",
            amount: 45,
            sourceRecordID: "2026-07-25|기존|finished",
            in: container
        )
        try seedEvent(
            id: "meal:negative-correction",
            amount: -40,
            sourceRecordID: "2026-07-25|교정|finished",
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(result, RecordMealResult(xpGranted: 5, totalXP: 50, motion: .mealSuccess))
    }

    func testHalfStatusIsAcceptedAndAwardsConfiguredXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)

        let result = try useCase.execute(
            command(
                status: .half
            )
        )

        XCTAssertEqual(
            result,
            RecordMealResult(xpGranted: 12, totalXP: 12, motion: .mealSuccess)
        )
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testMismatchedCanonicalIdentitiesAreRejectedWithoutWrites() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)

        XCTAssertThrowsError(
            try useCase.execute(command(recordID: "not-canonical"))
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .invalidRecordIdentity)
        }
        XCTAssertThrowsError(
            try useCase.execute(
                command(
                    recordID: "2026-02-30|시금치나물",
                    date: "2026-02-30"
                )
            )
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .invalidRecordIdentity)
        }
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testCanonicalIdentityTrimsAndLowercasesWithoutRemovingInteriorSpaces() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let command = command(
            recordID: "2026-07-25|spinach 나물",
            menuName: "  SPINACH 나물 \n"
        )

        _ = try RecordMealUseCase(container: container).execute(command)

        let request = NSFetchRequest<RebuildMealRecordManagedObject>(
            entityName: RebuildEntityName.mealRecord
        )
        let record = try XCTUnwrap(container.viewContext.performAndWait {
            try container.viewContext.fetch(request).first
        })
        XCTAssertEqual(record.id, "2026-07-25|spinach 나물")
        XCTAssertEqual(record.normalizedMenuName, "spinach 나물")
        XCTAssertEqual(record.menuName, "  SPINACH 나물 \n")
    }

    func testAllergySafetyIsRejectedBeforePersistence() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)

        XCTAssertThrowsError(
            try useCase.execute(
                command(
                    allergyCodes: [5],
                    childAllergyCodes: [1, 5],
                    itemAllergyCodes: [5, 6]
                )
            )
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .allergySafetyRequired)
        }
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)

        let safety = try useCase.execute(
            command(
                status: .allergyAvoided,
                allergyCodes: [5],
                childAllergyCodes: [1, 5],
                itemAllergyCodes: [5, 6]
            )
        )
        XCTAssertEqual(safety, RecordMealResult(xpGranted: 8, totalXP: 8, motion: .mealSuccess))
    }

    func testMismatchedAllergyIntersectionRejectsBeforeSidecarOrPersistence() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let sidecar = TestNutrientImpactSidecar()
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            nutrientImpactSidecar: sidecar
        )

        XCTAssertThrowsError(
            try useCase.execute(
                command(
                    status: .allergyAvoided,
                    allergyCodes: [5],
                    childAllergyCodes: [5, 6],
                    itemAllergyCodes: [6],
                    nutritionSnapshot: try nutritionSnapshot(
                        status: .allergyAvoided
                    )
                )
            )
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .allergyContextMismatch)
        }

        XCTAssertEqual(sidecar.installCount, 0)
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testExistingParentShareValueIsPreservedAndOnlyNewRowsUseCommandValue() throws {
        let existingContainer = try RebuildPersistentStore.makeInMemory()
        try seedRecord(command(parentShareEnabled: false), in: existingContainer)

        _ = try RecordMealUseCase(container: existingContainer).execute(
            command(
                parentShareEnabled: true,
                occurredAt: Date(timeIntervalSince1970: 1_753_430_401)
            )
        )

        XCTAssertFalse(
            try XCTUnwrap(try activeRecords(in: existingContainer).first)
                .parentShareEnabled
        )

        let newContainer = try RebuildPersistentStore.makeInMemory()
        _ = try RecordMealUseCase(container: newContainer).execute(
            command(parentShareEnabled: true)
        )
        XCTAssertTrue(
            try XCTUnwrap(try activeRecords(in: newContainer).first)
                .parentShareEnabled
        )
    }

    func testDifficultRecordUsesComfortMotionAndNeverDeductsXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let result = try RecordMealUseCase(container: container).execute(
            command(
                status: .difficultToday,
                difficultyReasons: [.texture]
            )
        )

        XCTAssertEqual(result, RecordMealResult(xpGranted: 3, totalXP: 3, motion: .comfort))
    }

    func testUpdatingExistingCanonicalRecordCannotCreateMissingXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedRecord(command(parentShareEnabled: false), in: container)

        let result = try RecordMealUseCase(container: container).execute(
            command(parentShareEnabled: true)
        )

        XCTAssertEqual(result.xpGranted, 0)
        XCTAssertEqual(result.totalXP, 0)
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
        XCTAssertEqual(try onlyEvent(in: container).amount, 0)
    }

    func testExistingEventWithoutRecordRepairsRecordWithoutDuplicateXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "meal:2026-07-25|시금치나물|oneBite",
            amount: 18,
            sourceRecordID: "2026-07-25|시금치나물|oneBite",
            in: container
        )

        let result = try RecordMealUseCase(container: container).execute(command())

        XCTAssertEqual(result.xpGranted, 0)
        XCTAssertEqual(result.totalXP, 18)
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testSidecarInstallOccursBeforeCoreDataTransaction() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let mutationProbe = CoreDataMutationProbe(container: container)
        let sidecar = TestNutrientImpactSidecar(
            mutationObserved: { mutationProbe.hasMutation },
            saveObserved: { mutationProbe.hasSave }
        )
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            nutrientImpactSidecar: sidecar
        )

        let result = try useCase.execute(
            command(nutritionSnapshot: try nutritionSnapshot())
        )

        XCTAssertEqual(sidecar.installCount, 1)
        XCTAssertEqual(sidecar.loadCount, 2)
        XCTAssertFalse(sidecar.mutationObservedAtInstall)
        XCTAssertEqual(sidecar.saveObservedAtLoads, [false, true])
        XCTAssertEqual(result.nutritionGuidance?.source, .recordedRevision)
        XCTAssertEqual(
            result.nutritionGuidance?.snapshot,
            sidecar.installedSnapshot
        )
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testPostSaveSidecarMissUsesCurrentGuidanceWithoutRollingBackRecord() throws {
        for postSaveReadBack in [
            TestSidecarReadBack.missing,
            .mismatched,
            .failure,
        ] {
            let container = try RebuildPersistentStore.makeInMemory()
            let sidecar = TestNutrientImpactSidecar(
                postSaveReadBack: postSaveReadBack
            )
            let useCase = try RecordMealUseCase(
                container: container,
                policyData: try contractData(named: "xp-policy.json"),
                nutrientImpactSidecar: sidecar
            )

            let result = try useCase.execute(
                command(nutritionSnapshot: try nutritionSnapshot())
            )

            XCTAssertEqual(sidecar.loadCount, 2)
            XCTAssertEqual(result.nutritionGuidance?.source, .currentGuidance)
            XCTAssertEqual(
                result.nutritionGuidance?.source.childLabel,
                "현재 기준 안내"
            )
            XCTAssertEqual(
                result.nutritionGuidance?.snapshot,
                sidecar.installedSnapshot
            )
            XCTAssertEqual(try activeRecords(in: container).count, 1)
            XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
        }
    }

    func testSidecarFailureDoesNotWriteRecordOrXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let sidecar = TestNutrientImpactSidecar(installError: .writeFailed)
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            nutrientImpactSidecar: sidecar
        )

        XCTAssertThrowsError(
            try useCase.execute(
                command(nutritionSnapshot: try nutritionSnapshot())
            )
        ) { error in
            XCTAssertEqual(error as? NutrientImpactSidecarError, .writeFailed)
        }
        XCTAssertEqual(sidecar.installCount, 1)
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testSidecarExactReadBackIsRequiredBeforeCoreDataWrites() throws {
        for readBack in [
            TestSidecarReadBack.missing,
            .mismatched,
        ] {
            let container = try RebuildPersistentStore.makeInMemory()
            let sidecar = TestNutrientImpactSidecar(readBack: readBack)
            let useCase = try RecordMealUseCase(
                container: container,
                policyData: try contractData(named: "xp-policy.json"),
                nutrientImpactSidecar: sidecar
            )

            XCTAssertThrowsError(
                try useCase.execute(
                    command(nutritionSnapshot: try nutritionSnapshot())
                )
            ) { error in
                XCTAssertEqual(
                    error as? NutrientImpactSidecarError,
                    .readBackFailed
                )
            }
            XCTAssertEqual(sidecar.installCount, 1)
            XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
            XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
        }
    }

    func testMismatchedIncomingNutritionIdentityIsRejectedBeforeInstall() throws {
        let defaultDate = Date(timeIntervalSince1970: 1_753_430_400)
        let mismatches: [NutrientImpactSnapshot] = [
            try nutritionSnapshot(recordID: "2026-07-25|다른메뉴"),
            try nutritionSnapshot(date: "2026-07-24"),
            try nutritionSnapshot(normalizedMenuName: "다른메뉴"),
            try nutritionSnapshot(status: .finished),
            try nutritionSnapshot(
                updatedAt: defaultDate.addingTimeInterval(1)
            ),
        ]

        for mismatch in mismatches {
            let container = try RebuildPersistentStore.makeInMemory()
            let sidecar = TestNutrientImpactSidecar()
            let useCase = try RecordMealUseCase(
                container: container,
                policyData: try contractData(named: "xp-policy.json"),
                nutrientImpactSidecar: sidecar
            )

            XCTAssertThrowsError(
                try useCase.execute(
                    command(nutritionSnapshot: mismatch)
                )
            ) { error in
                XCTAssertEqual(
                    error as? NutrientImpactSidecarError,
                    .invalidSnapshot
                )
            }
            XCTAssertEqual(sidecar.installCount, 0)
            XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
            XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
        }
    }

    func testCoreDataFailureLeavesNoMatchingActiveRevision() throws {
        let container = try makeValidationFailingContainer()
        let sidecar = TestNutrientImpactSidecar()
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            nutrientImpactSidecar: sidecar
        )
        let snapshot = try nutritionSnapshot()

        XCTAssertThrowsError(
            try useCase.execute(command(nutritionSnapshot: snapshot))
        )

        XCTAssertEqual(sidecar.installedSnapshot, snapshot)
        XCTAssertEqual(try activeRecords(in: container).count, 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testNutritionSnapshotRebindsToPreservedLegacyWinner() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let legacyRecordID = "2026-07-25|시금치나물|half"
        try seedRecord(
            command(recordID: legacyRecordID, status: .half),
            in: container
        )
        let sidecar = TestNutrientImpactSidecar()
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            nutrientImpactSidecar: sidecar
        )
        let revisionDate = Date(timeIntervalSince1970: 1_753_430_500)

        _ = try useCase.execute(
            command(
                status: .finished,
                occurredAt: revisionDate,
                nutritionSnapshot: try nutritionSnapshot(
                    status: .finished,
                    updatedAt: revisionDate
                )
            )
        )

        XCTAssertEqual(sidecar.installedSnapshot?.recordID, legacyRecordID)
        XCTAssertEqual(sidecar.installedSnapshot?.status, .finished)
        XCTAssertEqual(sidecar.installedSnapshot?.recordUpdatedAt, revisionDate)
        XCTAssertEqual(try activeRecords(in: container).first?.id, legacyRecordID)
    }

    func testFailedCoreDataSaveRollsBackRecordAndProgressTogether() throws {
        let container = try makeValidationFailingContainer()
        let useCase = try RecordMealUseCase(container: container)

        XCTAssertThrowsError(try useCase.execute(command()))
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testTotalOverflowBeforeSaveRollsBackNewRecordAndEvent() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        try seedEvent(
            id: "legacy:overflow-max",
            amount: .max,
            sourceRecordID: "2025-07-25|legacy|finished",
            in: container
        )

        XCTAssertThrowsError(
            try RecordMealUseCase(container: container).execute(command())
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .xpOverflow)
        }
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
    }

    func testConcurrentDuplicateCommandsHaveOneWinner() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let first = try RecordMealUseCase(container: container)
        let second = try RecordMealUseCase(container: container)
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let results = Task4LockedBox<[Result<RecordMealResult, Error>]>([])

        for useCase in [first, second] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                start.wait()
                let outcome = Result { try useCase.execute(self.command()) }
                results.withValue { $0.append(outcome) }
                group.leave()
            }
        }
        start.signal()
        start.signal()

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        let values = try results.value.map { try $0.get() }
        XCTAssertEqual(values.map(\.xpGranted).sorted(), [0, 18])
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 1)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 1)
        XCTAssertEqual(try onlyEvent(in: container).amount, 18)
    }

    func testConcurrentRepositoryWriterIsSerializedBeforeMealCapReadAndWrite() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let serializerEntered = expectation(description: "repository owns ledger serializer")
        let releaseRepository = DispatchSemaphore(value: 0)
        let entryCount = Task4LockedBox(0)
        let serializer = RebuildProgressLedgerSerializer {
            let isFirstEntry = entryCount.withValue { count in
                defer { count += 1 }
                return count == 0
            }
            if isFirstEntry {
                serializerEntered.fulfill()
                _ = releaseRepository.wait(timeout: .now() + 2)
            }
        }
        let repository = RebuildProgressRepository(
            context: container.newBackgroundContext(),
            ledgerSerializer: serializer
        )
        let useCase = try RecordMealUseCase(
            container: container,
            policyData: try contractData(named: "xp-policy.json"),
            ledgerSerializer: serializer
        )
        let repositoryOutcome = Task4LockedBox<Result<Bool, Error>?>(nil)
        let mealOutcome = Task4LockedBox<Result<RecordMealResult, Error>?>(nil)
        let repositoryCompleted = expectation(description: "repository completed")
        let mealCompleted = expectation(description: "meal completed")

        DispatchQueue.global(qos: .userInitiated).async {
            repositoryOutcome.withValue {
                $0 = Result {
                    try repository.appendIfAbsent(
                        RebuildProgressEvent(
                            id: "challenge:concurrent-cap",
                            amount: 90,
                            occurredAt: Date(timeIntervalSince1970: 1_753_430_400),
                            sourceRecordID: "2026-07-25|challenge|finished"
                        )
                    )
                }
            }
            repositoryCompleted.fulfill()
        }
        wait(for: [serializerEntered], timeout: 2)

        DispatchQueue.global(qos: .userInitiated).async {
            mealOutcome.withValue {
                $0 = Result { try useCase.execute(self.command()) }
            }
            mealCompleted.fulfill()
        }
        releaseRepository.signal()
        wait(for: [repositoryCompleted, mealCompleted], timeout: 5)

        XCTAssertTrue(try XCTUnwrap(repositoryOutcome.value).get())
        XCTAssertEqual(
            try XCTUnwrap(mealOutcome.value).get(),
            RecordMealResult(xpGranted: 10, totalXP: 100, motion: .mealSuccess)
        )
        XCTAssertEqual(try repository.totalXP(), 100)
    }

    func testMalformedXPPolicyFailsBeforeAnyWrite() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        var policy = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try contractData(named: "xp-policy.json")
            ) as? [String: Any]
        )
        var statusXP = try XCTUnwrap(policy["statusXP"] as? [String: Any])
        statusXP["oneBite"] = -18
        policy["statusXP"] = statusXP
        let malformed = try JSONSerialization.data(withJSONObject: policy)

        XCTAssertThrowsError(
            try RecordMealUseCase(container: container, policyData: malformed)
        ) { error in
            XCTAssertEqual(error as? RebuildContractLoadError, .invalid("xp-policy.json"))
        }
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
    }

    func testXPPolicyCannotDemoteHalfToLegacyStatus() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        var policy = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try contractData(named: "xp-policy.json")
            ) as? [String: Any]
        )
        policy["activeStatuses"] = [
            "oneBite", "finished", "smelledOnly", "difficultToday", "allergyAvoided",
        ]
        policy["legacyReadCompatibleStatuses"] = ["half"]
        let tampered = try JSONSerialization.data(withJSONObject: policy)

        XCTAssertThrowsError(
            try RecordMealUseCase(container: container, policyData: tampered)
        ) { error in
            XCTAssertEqual(error as? RebuildContractLoadError, .invalid("xp-policy.json"))
        }
    }

    func testXPPolicyCannotEnableStatusTransitionAwards() throws {
        var policy = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try contractData(named: "xp-policy.json")
            ) as? [String: Any]
        )
        policy["statusTransitionsGrantAdditionalXP"] = true

        XCTAssertThrowsError(
            try RecordMealUseCase(
                container: try RebuildPersistentStore.makeInMemory(),
                policyData: try JSONSerialization.data(withJSONObject: policy)
            )
        ) { error in
            XCTAssertEqual(
                error as? RebuildContractLoadError,
                .invalid("xp-policy.json")
            )
        }
    }

    func testXPPolicyRejectsIntegralFloatingPointNumbers() throws {
        let canonical = try XCTUnwrap(
            String(
                data: try contractData(named: "xp-policy.json"),
                encoding: .utf8
            )
        )
        let replacements = [
            (#""version": 1"#, #""version": 1.0"#),
            (#""oneBite": 18"#, #""oneBite": 18.0"#),
            (#""base": 50"#, #""base": 50.0"#),
        ]

        for (source, replacement) in replacements {
            let floatingPointPolicy = Data(
                canonical.replacingOccurrences(
                    of: source,
                    with: replacement
                ).utf8
            )

            XCTAssertThrowsError(
                try RecordMealUseCase(
                    container: try RebuildPersistentStore.makeInMemory(),
                    policyData: floatingPointPolicy
                ),
                "Expected \(replacement) to be rejected"
            ) { error in
                XCTAssertEqual(
                    error as? RebuildContractLoadError,
                    .invalid("xp-policy.json")
                )
            }
        }
    }

    private func command(
        recordID: String = "2026-07-25|시금치나물",
        date: String = "2026-07-25",
        menuName: String = "시금치나물",
        status: RebuildEatingStatus = .oneBite,
        difficultyReasons: [RebuildDifficultyReason] = [],
        allergyCodes: [Int] = [],
        childAllergyCodes: [Int]? = nil,
        itemAllergyCodes: [Int]? = nil,
        photoIDs: [String] = [],
        parentShareEnabled: Bool = false,
        occurredAt: Date = Date(timeIntervalSince1970: 1_753_430_400),
        nutritionSnapshot: NutrientImpactSnapshot? = nil
    ) -> RecordMealCommand {
        RecordMealCommand(
            recordID: recordID,
            date: date,
            menuName: menuName,
            status: status,
            difficultyReasons: difficultyReasons,
            allergyCodes: allergyCodes,
            childAllergyCodes: childAllergyCodes ?? allergyCodes,
            itemAllergyCodes: itemAllergyCodes ?? allergyCodes,
            photoIDs: photoIDs,
            parentShareEnabled: parentShareEnabled,
            occurredAt: occurredAt,
            nutritionSnapshot: nutritionSnapshot
        )
    }

    private func nutritionSnapshot(
        recordID: String = "2026-07-25|시금치나물",
        date: String = "2026-07-25",
        normalizedMenuName: String = "시금치나물",
        status: RebuildEatingStatus = .oneBite,
        updatedAt: Date = Date(timeIntervalSince1970: 1_753_430_400)
    ) throws -> NutrientImpactSnapshot {
        try XCTUnwrap(
            NutrientImpactSnapshotFactory.make(
                recordID: recordID,
                date: date,
                normalizedMenuName: normalizedMenuName,
                status: status,
                recordUpdatedAt: updatedAt,
                nutrientIDs: ["fiber", "vitamin"]
            )
        )
    }

    private func contractData(named filename: String) throws -> Data {
        try loadRebuildContractData(named: filename)
    }

    private func seedEvent(
        id: String,
        amount: Int64,
        sourceRecordID: String?,
        occurredAt: Date = Date(timeIntervalSince1970: 1_753_430_400),
        in container: NSPersistentContainer
    ) throws {
        try container.viewContext.performAndWait {
            let event = RebuildProgressEventManagedObject(
                entity: try XCTUnwrap(
                    container.managedObjectModel.entitiesByName[RebuildEntityName.progressEvent]
                ),
                insertInto: container.viewContext
            )
            event.id = id
            event.amount = amount
            event.occurredAt = occurredAt
            event.sourceRecordID = sourceRecordID
            try container.viewContext.save()
        }
    }

    private func seedRecord(
        _ command: RecordMealCommand,
        in container: NSPersistentContainer
    ) throws {
        try container.viewContext.performAndWait {
            let record = RebuildMealRecordManagedObject(
                entity: try XCTUnwrap(
                    container.managedObjectModel.entitiesByName[RebuildEntityName.mealRecord]
                ),
                insertInto: container.viewContext
            )
            record.id = command.recordID
            record.date = command.date
            record.menuName = command.menuName
            record.normalizedMenuName = command.menuName
            record.status = command.status.rawValue
            record.difficultyReasonsJSON = try encode(command.difficultyReasons)
            record.allergyCodesJSON = try encode(command.allergyCodes)
            record.photoIDsJSON = try encode(command.photoIDs)
            record.parentShareEnabled = command.parentShareEnabled
            record.updatedAt = command.occurredAt
            try container.viewContext.save()
        }
    }

    private func activeRecords(
        in container: NSPersistentContainer
    ) throws -> [RebuildMealRecordManagedObject] {
        try allRecords(in: container).filter { $0.deletedAt == nil }
    }

    private func allRecords(
        in container: NSPersistentContainer
    ) throws -> [RebuildMealRecordManagedObject] {
        let request = NSFetchRequest<RebuildMealRecordManagedObject>(
            entityName: RebuildEntityName.mealRecord
        )
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        return try container.viewContext.performAndWait {
            try container.viewContext.fetch(request)
        }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from value: String
    ) throws -> Value {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }

    private func onlyEvent(
        in container: NSPersistentContainer
    ) throws -> RebuildProgressEventManagedObject {
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        return try XCTUnwrap(container.viewContext.performAndWait {
            try container.viewContext.fetch(request).first
        })
    }

    private func eventAmounts(
        in container: NSPersistentContainer
    ) throws -> [Int64] {
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        return try container.viewContext.performAndWait {
            try container.viewContext.fetch(request).map(\.amount)
        }
    }

    private func count(
        _ entityName: String,
        in container: NSPersistentContainer
    ) throws -> Int {
        try container.viewContext.performAndWait {
            try container.viewContext.count(
                for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            )
        }
    }

    private func makeValidationFailingContainer() throws -> NSPersistentContainer {
        let model = RebuildManagedModel.make()
        let status = try XCTUnwrap(
            model.entitiesByName[RebuildEntityName.mealRecord]?
                .attributesByName["status"]
        )
        status.setValidationPredicates(
            [NSPredicate(value: false)],
            withValidationWarnings: ["forced failure"]
        )

        let container = NSPersistentContainer(
            name: "FailingMealRecording",
            managedObjectModel: model
        )
        let description = NSPersistentStoreDescription(
            url: URL(fileURLWithPath: "/dev/null")
        )
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw loadError
        }
        return container
    }
}

private final class Task4LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    @discardableResult
    func withValue<Result>(_ operation: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation(&storage)
    }
}

private final class CoreDataMutationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var mutation = false
    private var save = false
    private var mutationObserver: NSObjectProtocol?
    private var saveObserver: NSObjectProtocol?

    init(container: NSPersistentContainer) {
        mutationObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: nil,
            queue: nil
        ) { [weak self, weak container] notification in
            guard let self,
                  let container,
                  let context = notification.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === container.persistentStoreCoordinator
            else {
                return
            }
            let changedKeys = [
                NSInsertedObjectsKey,
                NSUpdatedObjectsKey,
                NSDeletedObjectsKey,
            ]
            let changed = changedKeys.contains { key in
                guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else {
                    return false
                }
                return !objects.isEmpty
            }
            if changed {
                lock.lock()
                mutation = true
                lock.unlock()
            }
        }
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { [weak self, weak container] notification in
            guard let self,
                  let container,
                  let context = notification.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === container.persistentStoreCoordinator
            else {
                return
            }
            lock.lock()
            save = true
            lock.unlock()
        }
    }

    deinit {
        if let mutationObserver {
            NotificationCenter.default.removeObserver(mutationObserver)
        }
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
    }

    var hasMutation: Bool {
        lock.lock()
        defer { lock.unlock() }
        return mutation
    }

    var hasSave: Bool {
        lock.lock()
        defer { lock.unlock() }
        return save
    }
}

private enum TestSidecarReadBack {
    case installed
    case missing
    case mismatched
    case failure
}

private final class TestNutrientImpactSidecar: NutrientImpactSidecar, @unchecked Sendable {
    private let lock = NSLock()
    private let installError: NutrientImpactSidecarError?
    private let mutationObserved: @Sendable () -> Bool
    private let readBack: TestSidecarReadBack
    private let postSaveReadBack: TestSidecarReadBack
    private let saveObserved: @Sendable () -> Bool
    private var storedSnapshot: NutrientImpactSnapshot?
    private var storedInstallCount = 0
    private var storedLoadCount = 0
    private var storedMutationObservedAtInstall = false
    private var storedSaveObservedAtLoads: [Bool] = []

    init(
        installError: NutrientImpactSidecarError? = nil,
        readBack: TestSidecarReadBack = .installed,
        postSaveReadBack: TestSidecarReadBack = .installed,
        mutationObserved: @escaping @Sendable () -> Bool = { false },
        saveObserved: @escaping @Sendable () -> Bool = { false }
    ) {
        self.installError = installError
        self.readBack = readBack
        self.postSaveReadBack = postSaveReadBack
        self.mutationObserved = mutationObserved
        self.saveObserved = saveObserved
    }

    func install(_ snapshot: NutrientImpactSnapshot) throws {
        let observed = mutationObserved()
        lock.lock()
        storedInstallCount += 1
        storedMutationObservedAtInstall = observed
        lock.unlock()
        if let installError {
            throw installError
        }
        lock.lock()
        storedSnapshot = snapshot
        lock.unlock()
    }

    func load(
        matching record: RebuildMealRecordRevision
    ) throws -> NutrientImpactSnapshot? {
        let observedSave = saveObserved()
        lock.lock()
        defer { lock.unlock() }
        storedLoadCount += 1
        storedSaveObservedAtLoads.append(observedSave)
        guard let snapshot = storedSnapshot,
              snapshot.recordID == record.recordID,
              snapshot.date == record.date,
              snapshot.normalizedMenuName == record.normalizedMenuName,
              snapshot.status == record.status,
              snapshot.recordUpdatedAt == record.updatedAt else {
            return nil
        }
        let mode = storedLoadCount == 1 ? readBack : postSaveReadBack
        switch mode {
        case .installed:
            return snapshot
        case .missing:
            return nil
        case .mismatched:
            return NutrientImpactSnapshot(
                schemaVersion: snapshot.schemaVersion,
                ruleVersion: snapshot.ruleVersion,
                recordID: snapshot.recordID + "-mismatch",
                date: snapshot.date,
                normalizedMenuName: snapshot.normalizedMenuName,
                status: snapshot.status,
                recordUpdatedAt: snapshot.recordUpdatedAt,
                nutrients: snapshot.nutrients,
                headline: snapshot.headline,
                explanation: snapshot.explanation,
                alternatives: snapshot.alternatives,
                disclaimer: snapshot.disclaimer
            )
        case .failure:
            throw NutrientImpactSidecarError.readBackFailed
        }
    }

    var installedSnapshot: NutrientImpactSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    var installCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedInstallCount
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedLoadCount
    }

    var saveObservedAtLoads: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return storedSaveObservedAtLoads
    }

    var mutationObservedAtInstall: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedMutationObservedAtInstall
    }
}
