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

    func testLegacyHalfAndMismatchedCanonicalIdentityAreRejectedWithoutWrites() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)

        XCTAssertThrowsError(
            try useCase.execute(
                command(
                    recordID: "2026-07-25|시금치나물|half",
                    status: .half
                )
            )
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .inactiveStatus("half"))
        }
        XCTAssertThrowsError(
            try useCase.execute(command(recordID: "not-canonical"))
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .invalidRecordIdentity)
        }
        XCTAssertThrowsError(
            try useCase.execute(
                command(
                    recordID: "2026-02-30|시금치나물|oneBite",
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
            recordID: "2026-07-25|spinach 나물|oneBite",
            menuName: "  SPINACH 나물 \n"
        )

        _ = try RecordMealUseCase(container: container).execute(command)

        let request = NSFetchRequest<RebuildMealRecordManagedObject>(
            entityName: RebuildEntityName.mealRecord
        )
        let record = try XCTUnwrap(container.viewContext.performAndWait {
            try container.viewContext.fetch(request).first
        })
        XCTAssertEqual(record.id, "2026-07-25|spinach 나물|oneBite")
        XCTAssertEqual(record.normalizedMenuName, "spinach 나물")
        XCTAssertEqual(record.menuName, "  SPINACH 나물 \n")
    }

    func testAllergyRiskCannotBeRecordedAsChallengeAndSafetyRecordWins() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let useCase = try RecordMealUseCase(container: container)

        XCTAssertThrowsError(
            try useCase.execute(command(allergyCodes: [5]))
        ) { error in
            XCTAssertEqual(error as? RecordMealError, .allergySafetyRequired)
        }

        let safety = try useCase.execute(
            command(
                recordID: "2026-07-25|시금치나물|allergyAvoided",
                status: .allergyAvoided,
                allergyCodes: [5]
            )
        )
        XCTAssertEqual(safety, RecordMealResult(xpGranted: 8, totalXP: 8, motion: .mealSuccess))
    }

    func testDifficultRecordUsesComfortMotionAndNeverDeductsXP() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let result = try RecordMealUseCase(container: container).execute(
            command(
                recordID: "2026-07-25|시금치나물|difficultToday",
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

    func testFailedCoreDataSaveRollsBackRecordAndProgressTogether() throws {
        let container = try makeValidationFailingContainer()
        let useCase = try RecordMealUseCase(container: container)

        XCTAssertThrowsError(try useCase.execute(command()))
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: container), 0)
        XCTAssertEqual(try count(RebuildEntityName.progressEvent, in: container), 0)
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

    func testXPPolicyCannotPromoteLegacyHalfToActive() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        var policy = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try contractData(named: "xp-policy.json")
            ) as? [String: Any]
        )
        policy["activeStatuses"] = [
            "half", "finished", "smelledOnly", "difficultToday", "allergyAvoided",
        ]
        policy["legacyReadCompatibleStatuses"] = ["oneBite"]
        let tampered = try JSONSerialization.data(withJSONObject: policy)

        XCTAssertThrowsError(
            try RecordMealUseCase(container: container, policyData: tampered)
        ) { error in
            XCTAssertEqual(error as? RebuildContractLoadError, .invalid("xp-policy.json"))
        }
    }

    private func command(
        recordID: String = "2026-07-25|시금치나물|oneBite",
        date: String = "2026-07-25",
        menuName: String = "시금치나물",
        status: RebuildEatingStatus = .oneBite,
        difficultyReasons: [RebuildDifficultyReason] = [],
        allergyCodes: [Int] = [],
        photoIDs: [String] = [],
        parentShareEnabled: Bool = false
    ) -> RecordMealCommand {
        RecordMealCommand(
            recordID: recordID,
            date: date,
            menuName: menuName,
            status: status,
            difficultyReasons: difficultyReasons,
            allergyCodes: allergyCodes,
            photoIDs: photoIDs,
            parentShareEnabled: parentShareEnabled,
            occurredAt: Date(timeIntervalSince1970: 1_753_430_400)
        )
    }

    private func contractData(named filename: String) throws -> Data {
        try loadRebuildContractData(named: filename)
    }

    private func seedEvent(
        id: String,
        amount: Int64,
        sourceRecordID: String,
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
            event.occurredAt = Date(timeIntervalSince1970: 1_753_430_400)
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
            record.difficultyReasonsJSON = "[]"
            record.allergyCodesJSON = "[]"
            record.photoIDsJSON = "[]"
            record.parentShareEnabled = command.parentShareEnabled
            record.updatedAt = command.occurredAt
            try container.viewContext.save()
        }
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

    func withValue(_ operation: (inout Value) -> Void) {
        lock.lock()
        operation(&storage)
        lock.unlock()
    }
}
