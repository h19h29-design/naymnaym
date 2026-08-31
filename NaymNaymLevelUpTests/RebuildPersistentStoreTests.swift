import CoreData
import XCTest
@testable import NaymNaymLevelUp

final class RebuildPersistentStoreTests: XCTestCase {
    func testManagedModelDefinesExactRebuildSchemaAndUniqueConstraints() {
        let model = RebuildManagedModel.make()

        let expectedAttributes: [String: [String: NSAttributeType]] = [
            "RebuildProfile": [
                "id": .stringAttributeType,
                "role": .stringAttributeType,
                "nickname": .stringAttributeType,
                "officeCode": .stringAttributeType,
                "schoolCode": .stringAttributeType,
                "allergyCodesJSON": .stringAttributeType,
            ],
            "RebuildMealDay": [
                "date": .stringAttributeType,
                "payloadJSON": .stringAttributeType,
                "fetchedAt": .dateAttributeType,
                "source": .stringAttributeType,
            ],
            "RebuildMealRecord": [
                "id": .stringAttributeType,
                "date": .stringAttributeType,
                "menuName": .stringAttributeType,
                "normalizedMenuName": .stringAttributeType,
                "status": .stringAttributeType,
                "difficultyReasonsJSON": .stringAttributeType,
                "allergyCodesJSON": .stringAttributeType,
                "photoIDsJSON": .stringAttributeType,
                "parentShareEnabled": .booleanAttributeType,
                "updatedAt": .dateAttributeType,
                "deletedAt": .dateAttributeType,
            ],
            "RebuildMealPhoto": [
                "id": .stringAttributeType,
                "recordID": .stringAttributeType,
                "relativePath": .stringAttributeType,
                "createdAt": .dateAttributeType,
            ],
            "RebuildProgressEvent": [
                "id": .stringAttributeType,
                "amount": .integer64AttributeType,
                "occurredAt": .dateAttributeType,
                "sourceRecordID": .stringAttributeType,
            ],
            "RebuildSyncEnvelope": [
                "id": .stringAttributeType,
                "recordType": .stringAttributeType,
                "recordID": .stringAttributeType,
                "state": .stringAttributeType,
                "retryCount": .integer64AttributeType,
                "updatedAt": .dateAttributeType,
            ],
            "RebuildParentLink": [
                "id": .stringAttributeType,
                "inviteCode": .stringAttributeType,
                "connectionState": .stringAttributeType,
                "connectedAt": .dateAttributeType,
            ],
            "RebuildMigrationState": [
                "id": .stringAttributeType,
                "version": .integer64AttributeType,
                "completedAt": .dateAttributeType,
                "sourceDigest": .stringAttributeType,
            ],
        ]
        let expectedOptionalAttributes: [String: Set<String>] = [
            "RebuildProfile": ["officeCode", "schoolCode"],
            "RebuildMealDay": [],
            "RebuildMealRecord": ["deletedAt"],
            "RebuildMealPhoto": [],
            "RebuildProgressEvent": ["sourceRecordID"],
            "RebuildSyncEnvelope": [],
            "RebuildParentLink": ["connectedAt"],
            "RebuildMigrationState": ["sourceDigest"],
        ]
        let expectedManagedObjectClasses: [String: NSManagedObject.Type] = [
            "RebuildProfile": RebuildProfileManagedObject.self,
            "RebuildMealDay": RebuildMealDayManagedObject.self,
            "RebuildMealRecord": RebuildMealRecordManagedObject.self,
            "RebuildMealPhoto": RebuildMealPhotoManagedObject.self,
            "RebuildProgressEvent": RebuildProgressEventManagedObject.self,
            "RebuildSyncEnvelope": RebuildSyncEnvelopeManagedObject.self,
            "RebuildParentLink": RebuildParentLinkManagedObject.self,
            "RebuildMigrationState": RebuildMigrationStateManagedObject.self,
        ]

        XCTAssertEqual(Set(model.entitiesByName.keys), Set(expectedAttributes.keys))
        for (entityName, attributes) in expectedAttributes {
            guard let entity = model.entitiesByName[entityName] else {
                XCTFail("Missing entity \(entityName)")
                continue
            }
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: entity.attributesByName.map { ($0.key, $0.value.attributeType) }),
                attributes,
                "Attribute mismatch for \(entityName)"
            )
            XCTAssertEqual(
                Set(entity.attributesByName.compactMap { $0.value.isOptional ? $0.key : nil }),
                expectedOptionalAttributes[entityName],
                "Optionality mismatch for \(entityName)"
            )
            XCTAssertEqual(
                entity.managedObjectClassName,
                expectedManagedObjectClasses[entityName].map(NSStringFromClass),
                "Managed-object class mismatch for \(entityName)"
            )
            for (attributeName, attribute) in entity.attributesByName {
                if entityName == "RebuildMealRecord", attributeName == "parentShareEnabled" {
                    XCTAssertEqual(attribute.defaultValue as? Bool, false)
                } else {
                    XCTAssertNil(
                        attribute.defaultValue,
                        "Unexpected default for \(entityName).\(attributeName)"
                    )
                }
            }
        }

        let expectedUniqueKeys: [String: String] = [
            "RebuildProfile": "id",
            "RebuildMealDay": "date",
            "RebuildMealRecord": "id",
            "RebuildMealPhoto": "id",
            "RebuildProgressEvent": "id",
            "RebuildSyncEnvelope": "id",
            "RebuildParentLink": "id",
            "RebuildMigrationState": "id",
        ]
        for (entityName, uniqueKey) in expectedUniqueKeys {
            XCTAssertEqual(model.entitiesByName[entityName]?.uniquenessConstraints as? [[String]], [[uniqueKey]])
        }
    }

    func testInMemoryStoreUsesDevNullAndConfiguredViewContext() throws {
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(container.persistentStoreDescriptions.count, 1)
        XCTAssertEqual(container.persistentStoreDescriptions[0].url?.path, "/dev/null")
        XCTAssertEqual(container.persistentStoreDescriptions[0].type, NSSQLiteStoreType)
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.first?.url?.path, "/dev/null")
        XCTAssertTrue(container.viewContext.automaticallyMergesChangesFromParent)
        XCTAssertTrue(
            (container.viewContext.mergePolicy as AnyObject)
                === (NSMergeByPropertyObjectTrumpMergePolicy as AnyObject)
        )
    }

    func testInMemoryStoreCanBeCreatedByBackgroundCallerWithoutDeadlock() throws {
        let completion = expectation(description: "Background store factory returned")
        let outcome = RebuildLockedBox<Result<NSPersistentContainer, Error>?>(nil)

        DispatchQueue.global(qos: .userInitiated).async {
            outcome.withValue {
                $0 = Result { try RebuildPersistentStore.makeInMemory() }
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 5)
        let container = try XCTUnwrap(outcome.value).get()
        let viewContextConfiguration = container.viewContext.performAndWait {
            (
                container.viewContext.automaticallyMergesChangesFromParent,
                container.viewContext.mergePolicy as AnyObject
            )
        }
        XCTAssertTrue(viewContextConfiguration.0)
        XCTAssertTrue(
            viewContextConfiguration.1
                === (NSMergeByPropertyObjectTrumpMergePolicy as AnyObject)
        )
    }

    func testProfileRoundTripAndUpdateUsesStableIdentity() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildProfileRepository(context: container.viewContext)
        let original = RebuildProfile(
            id: "current",
            role: "child",
            nickname: "도토리",
            officeCode: "B10",
            schoolCode: "7130166",
            allergyCodesJSON: "[\"5\",\"6\"]"
        )

        try repository.save(original)
        XCTAssertEqual(try repository.load(), original)

        let updated = RebuildProfile(
            id: "current",
            role: "parent",
            nickname: "밤톨",
            officeCode: nil,
            schoolCode: nil,
            allergyCodesJSON: "[]"
        )
        try repository.save(updated)

        XCTAssertEqual(try repository.load(), updated)
        XCTAssertEqual(try count(entity: RebuildEntityName.profile, in: container.viewContext), 1)
    }

    func testProgressEventIdentityIsIdempotentAndSourceRecordIsPreserved() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildProgressRepository(context: container.viewContext)
        let event = RebuildProgressEvent(
            id: "meal:2026-07-25|시금치 나물|oneBite",
            amount: 18,
            occurredAt: Date(timeIntervalSince1970: 1_785_000_000),
            sourceRecordID: "2026-07-25|시금치 나물|oneBite"
        )

        XCTAssertTrue(try repository.appendIfAbsent(event))
        XCTAssertFalse(try repository.appendIfAbsent(event))
        XCTAssertEqual(try repository.totalXP(), 18)
        XCTAssertEqual(try repository.load(id: event.id), event)
    }

    func testConcurrentProgressAppendAcrossContextsHasOneWinnerAndKeepsWinnerData() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let firstRepository = RebuildProgressRepository(context: container.newBackgroundContext())
        let secondRepository = RebuildProgressRepository(context: container.newBackgroundContext())
        let firstEvent = RebuildProgressEvent(
            id: "meal:shared",
            amount: 18,
            occurredAt: Date(timeIntervalSince1970: 100),
            sourceRecordID: "first-source"
        )
        let secondEvent = RebuildProgressEvent(
            id: "meal:shared",
            amount: 99,
            occurredAt: Date(timeIntervalSince1970: 200),
            sourceRecordID: "second-source"
        )
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let outcomes = RebuildLockedBox<[(RebuildProgressEvent, Result<Bool, Error>)]>([])

        for (repository, event) in [
            (firstRepository, firstEvent),
            (secondRepository, secondEvent),
        ] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                start.wait()
                let result = Result { try repository.appendIfAbsent(event) }
                outcomes.withValue { $0.append((event, result)) }
                group.leave()
            }
        }

        start.signal()
        start.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        let completed = outcomes.value
        XCTAssertEqual(completed.count, 2)
        let values = try completed.map { try $0.1.get() }
        XCTAssertEqual(values.filter { $0 }.count, 1)
        XCTAssertEqual(values.filter { !$0 }.count, 1)

        let winningEvent = try XCTUnwrap(
            completed.first(where: { (try? $0.1.get()) == true })?.0
        )
        let verifier = RebuildProgressRepository(context: container.newBackgroundContext())
        XCTAssertEqual(try verifier.load(id: "meal:shared"), winningEvent)
        XCTAssertEqual(try verifier.totalXP(), winningEvent.amount)
        XCTAssertEqual(
            try count(entity: RebuildEntityName.progressEvent, in: container.newBackgroundContext()),
            1
        )
    }

    func testBackgroundAndMainViewContextAppendsAvoidLockContextInversion() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let serializerEntered = expectation(description: "Append serializer entered")
        let backgroundCompleted = expectation(description: "Background append completed")
        let serializer = RebuildDeadlockDetectingSerializer(
            enteredExpectation: serializerEntered
        )
        let backgroundRepository = RebuildProgressRepository(
            context: container.viewContext,
            serializeAppend: serializer.serialize
        )
        let mainRepository = RebuildProgressRepository(
            context: container.viewContext,
            serializeAppend: serializer.serialize
        )
        let backgroundEvent = RebuildProgressEvent(
            id: "meal:view-context-shared",
            amount: 18,
            occurredAt: Date(timeIntervalSince1970: 100),
            sourceRecordID: "background-first"
        )
        let mainEvent = RebuildProgressEvent(
            id: backgroundEvent.id,
            amount: 99,
            occurredAt: Date(timeIntervalSince1970: 200),
            sourceRecordID: "main-second"
        )
        let backgroundOutcome = RebuildLockedBox<Result<Bool, Error>?>(nil)
        defer { serializer.releaseBlockedBackgroundCaller() }

        DispatchQueue.global(qos: .userInitiated).async {
            backgroundOutcome.withValue {
                $0 = Result {
                    try backgroundRepository.appendIfAbsent(backgroundEvent)
                }
            }
            backgroundCompleted.fulfill()
        }

        wait(for: [serializerEntered], timeout: 2)
        let mainOutcome = Result {
            try mainRepository.appendIfAbsent(mainEvent)
        }
        serializer.releaseBlockedBackgroundCaller()
        wait(for: [backgroundCompleted], timeout: 2)

        XCTAssertTrue(try XCTUnwrap(backgroundOutcome.value).get())
        XCTAssertFalse(try mainOutcome.get())
        XCTAssertEqual(try mainRepository.load(id: backgroundEvent.id), backgroundEvent)
        XCTAssertEqual(try mainRepository.totalXP(), backgroundEvent.amount)
        XCTAssertEqual(
            try count(entity: RebuildEntityName.progressEvent, in: container.viewContext),
            1
        )
    }

    func testDefaultSharedSerializerDoesNotLockBeforeViewContextQueue() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let viewContextRepository = RebuildProgressRepository(
            context: container.viewContext
        )
        let backgroundRepository = RebuildProgressRepository(
            context: container.newBackgroundContext()
        )
        let viewWriterStarted = DispatchSemaphore(value: 0)
        let viewWriterCompleted = expectation(
            description: "view-context writer completed"
        )
        let backgroundWriterCompleted = expectation(
            description: "background-context writer completed"
        )
        let backgroundWriterSignal = DispatchSemaphore(value: 0)
        let viewOutcome = RebuildLockedBox<Result<Bool, Error>?>(nil)
        let backgroundOutcome = RebuildLockedBox<Result<Bool, Error>?>(nil)
        var contenderResult: DispatchTimeoutResult = .timedOut

        container.viewContext.performAndWait {
            DispatchQueue.global(qos: .userInitiated).async {
                viewWriterStarted.signal()
                viewOutcome.withValue {
                    $0 = Result {
                        try viewContextRepository.appendIfAbsent(
                            RebuildProgressEvent(
                                id: "lock-order:view-context",
                                amount: 1,
                                occurredAt: Date(timeIntervalSince1970: 100)
                            )
                        )
                    }
                }
                viewWriterCompleted.fulfill()
            }
            XCTAssertEqual(
                viewWriterStarted.wait(timeout: .now() + 1),
                .success
            )
            Thread.sleep(forTimeInterval: 0.1)

            DispatchQueue.global(qos: .userInitiated).async {
                backgroundOutcome.withValue {
                    $0 = Result {
                        try backgroundRepository.appendIfAbsent(
                            RebuildProgressEvent(
                                id: "lock-order:background-context",
                                amount: 2,
                                occurredAt: Date(timeIntervalSince1970: 200)
                            )
                        )
                    }
                }
                backgroundWriterSignal.signal()
                backgroundWriterCompleted.fulfill()
            }
            contenderResult = backgroundWriterSignal.wait(
                timeout: .now() + 0.5
            )
        }

        wait(
            for: [viewWriterCompleted, backgroundWriterCompleted],
            timeout: 2
        )
        XCTAssertEqual(contenderResult, .success)
        XCTAssertTrue(try XCTUnwrap(viewOutcome.value).get())
        XCTAssertTrue(try XCTUnwrap(backgroundOutcome.value).get())
    }

    func testProgressTotalAccumulatesDistinctEvents() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildProgressRepository(context: container.viewContext)

        XCTAssertTrue(try repository.appendIfAbsent(.init(
            id: "meal:first",
            amount: 18,
            occurredAt: Date(timeIntervalSince1970: 100),
            sourceRecordID: "first"
        )))
        XCTAssertTrue(try repository.appendIfAbsent(.init(
            id: "meal:second",
            amount: 7,
            occurredAt: Date(timeIntervalSince1970: 200),
            sourceRecordID: "second"
        )))

        XCTAssertEqual(try repository.totalXP(), 25)
    }

    func testProgressTotalThrowsTypedErrorOnInt64Overflow() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildProgressRepository(context: container.viewContext)
        XCTAssertTrue(try repository.appendIfAbsent(.init(
            id: "overflow:max",
            amount: .max,
            occurredAt: Date(timeIntervalSince1970: 100)
        )))
        XCTAssertTrue(try repository.appendIfAbsent(.init(
            id: "overflow:one",
            amount: 1,
            occurredAt: Date(timeIntervalSince1970: 200)
        )))

        XCTAssertThrowsError(try repository.totalXP()) { error in
            guard
                let repositoryError = error as? RebuildRepositoryError,
                case .totalXPOverflow = repositoryError
            else {
                return XCTFail("Expected totalXPOverflow, got \(error)")
            }
        }
    }

    func testMigrationVersionMarkUpdatesSingletonAndPreservesMetadata() throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let repository = RebuildMigrationStateRepository(context: container.viewContext)
        let firstCompletion = Date(timeIntervalSince1970: 1_000)
        let secondCompletion = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(try repository.currentVersion, 0)
        try repository.markCompleted(version: 1, sourceDigest: "sha256:first", completedAt: firstCompletion)
        XCTAssertEqual(
            try repository.load(),
            RebuildMigrationState(
                id: RebuildMigrationStateRepository.stateID,
                version: 1,
                completedAt: firstCompletion,
                sourceDigest: "sha256:first"
            )
        )

        try repository.markCompleted(version: 2, sourceDigest: "sha256:second", completedAt: secondCompletion)

        XCTAssertEqual(try repository.currentVersion, 2)
        XCTAssertEqual(
            try repository.load(),
            RebuildMigrationState(
                id: RebuildMigrationStateRepository.stateID,
                version: 2,
                completedAt: secondCompletion,
                sourceDigest: "sha256:second"
            )
        )
        XCTAssertEqual(try count(entity: RebuildEntityName.migrationState, in: container.viewContext), 1)
    }

    func testPersistentStoreDescriptionUsesExactSQLiteFilenameWithoutLoadingStore() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let description = RebuildPersistentStore.makePersistentStoreDescription(storeDirectory: directory)

        XCTAssertEqual(description.type, NSSQLiteStoreType)
        XCTAssertEqual(description.url, directory.appendingPathComponent("NaymRebuild.sqlite"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testPersistentStoreLoadFailureIsPropagated() throws {
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data("not a directory".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        XCTAssertThrowsError(
            try RebuildPersistentStore.makePersistent(storeDirectory: blocker)
        )
    }

    private func count(entity: String, in context: NSManagedObjectContext) throws -> Int {
        try context.performAndWait {
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity))
        }
    }
}

@MainActor
final class RebuildDemoIsolationTests: XCTestCase {
    func testDemoSessionUsesOneRetainedInMemoryContainer() throws {
        let liveContainer = try RebuildPersistentStore.makeInMemory()
        let session = RebuildChildSessionStore(
            profile: .demoFixture,
            persistentContainer: liveContainer
        )

        let demoContainer = try XCTUnwrap(session.container)

        XCTAssertFalse(demoContainer === liveContainer)
        XCTAssertEqual(
            demoContainer.persistentStoreCoordinator.persistentStores.first?.url?.path,
            "/dev/null"
        )
        XCTAssertTrue(demoContainer === session.container)
        XCTAssertTrue(
            session.nutrientImpactSidecar is InMemoryNutrientImpactSidecar
        )
        XCTAssertTrue(
            session.growthStageStateStore is RebuildInMemoryGrowthStageStateStore
        )
        XCTAssertEqual(session.legacyRights, .empty)
    }

    func testLiveSessionKeepsSuppliedPersistentContainer() throws {
        let liveContainer = try RebuildPersistentStore.makeInMemory()
        let session = RebuildChildSessionStore(
            profile: .liveFixture,
            persistentContainer: liveContainer
        )

        XCTAssertTrue(session.container === liveContainer)
        XCTAssertFalse(
            session.nutrientImpactSidecar is InMemoryNutrientImpactSidecar
        )
        XCTAssertNil(session.growthStageStateStore)
        XCTAssertNil(session.legacyRights)
    }

    func testChildCompositionUsesOneContainerAcrossTodayScheduleGrowthAndCollection() async throws {
        let liveContainer = try RebuildPersistentStore.makeInMemory()
        let composition = RebuildChildComposition(
            profile: .demoFixture,
            persistentContainer: liveContainer
        )
        let demoContainer = try XCTUnwrap(composition.session.container)
        let progressRepository = RebuildProgressRepository(
            context: demoContainer.viewContext
        )
        XCTAssertTrue(try progressRepository.appendIfAbsent(
            RebuildProgressEvent(
                id: "composition:shared",
                amount: 42,
                occurredAt: Date(timeIntervalSince1970: 10),
                sourceRecordID: "composition:shared"
            )
        ))

        let growth = try await composition.growthProvider.load(limit: 10)
        let collection = try await composition.collectionProvider.loadCollection()
        await composition.todayViewModel.load()

        XCTAssertTrue(composition.session.container === demoContainer)
        XCTAssertEqual(growth.totalXP, 42)
        XCTAssertEqual(collection.totalXP, 42)
        XCTAssertEqual(composition.todayViewModel.totalXP, 42)

        let date = Date()
        await composition.mealScheduleViewModel.load(dates: [date])
        XCTAssertEqual(
            try CoreDataRebuildMealDayStore(context: demoContainer.viewContext)
                .load(date: MealScheduleCalendar.key(for: date))?.source,
            "demo"
        )
    }

    func testChildNavigationIdentityChangesForProfileAndDemoModeSwitches() {
        let live = RebuildChildNavigationIdentity(
            profileID: "same-profile",
            isDemoMode: false
        )
        let demo = RebuildChildNavigationIdentity(
            profileID: "same-profile",
            isDemoMode: true
        )
        let otherProfile = RebuildChildNavigationIdentity(
            profileID: "other-profile",
            isDemoMode: false
        )

        XCTAssertNotEqual(live, demo)
        XCTAssertNotEqual(live, otherProfile)
        XCTAssertNotEqual(demo, otherProfile)
    }

    func testDemoCacheAndRecordXPStayOutOfLiveContainer() async throws {
        let liveContainer = try RebuildPersistentStore.makeInMemory()
        let liveStore = CoreDataRebuildMealDayStore(
            context: liveContainer.viewContext
        )
        let liveMeal = RebuildMealDay(
            date: "2026-08-30",
            menuItems: [
                RebuildMealItem(
                    name: "실제 급식",
                    allergyCodes: [],
                    nutrients: ["탄수화물"],
                    tags: [],
                    sourceRawText: "실제 급식"
                )
            ],
            calorie: "700 kcal",
            nutrition: .empty
        )
        try liveStore.save(
            liveMeal,
            refreshedAt: Date(timeIntervalSince1970: 1_753_401_600),
            source: "neis"
        )
        let liveUseCase = try RecordMealUseCase(container: liveContainer)
        let liveRecordResult = try liveUseCase.execute(
            RecordMealCommand(
                recordID: "2026-08-30|실제 급식",
                date: "2026-08-30",
                menuName: "실제 급식",
                status: .oneBite,
                difficultyReasons: [],
                allergyCodes: [],
                childAllergyCodes: [],
                itemAllergyCodes: [],
                photoIDs: ["live-photo"],
                parentShareEnabled: false,
                occurredAt: Date(timeIntervalSince1970: 1_753_401_601)
            )
        )
        XCTAssertEqual(liveRecordResult.xpGranted, 18)
        XCTAssertEqual(liveRecordResult.totalXP, 18)

        let session = RebuildChildSessionStore(
            profile: .demoFixture,
            persistentContainer: liveContainer
        )
        let demoContainer = try XCTUnwrap(session.container)
        let demoStore = CoreDataRebuildMealDayStore(
            context: demoContainer.viewContext
        )
        let demoRepository = RebuildMealRepository(
            store: demoStore,
            client: RebuildDemoMealClient(),
            now: { Date(timeIntervalSince1970: 1_753_405_602) }
        )

        await demoRepository.refresh(
            date: "2026-08-30",
            school: RebuildSchool(
                name: "냠냠 초등학교",
                officeCode: "B10",
                schoolCode: "7010111"
            )
        )

        XCTAssertEqual(try liveStore.load(date: "2026-08-30")?.meal, liveMeal)
        XCTAssertEqual(try liveStore.load(date: "2026-08-30")?.source, "neis")
        XCTAssertEqual(try demoStore.load(date: "2026-08-30")?.source, "demo")

        let demoUseCase = try RecordMealUseCase(
            container: demoContainer,
            nutrientImpactSidecar: session.nutrientImpactSidecar
        )
        let demoRecordResult = try demoUseCase.execute(
            RecordMealCommand(
                recordID: "2026-08-30|체험 급식",
                date: "2026-08-30",
                menuName: "체험 급식",
                status: .oneBite,
                difficultyReasons: [],
                allergyCodes: [],
                childAllergyCodes: [],
                itemAllergyCodes: [],
                photoIDs: ["demo-photo"],
                parentShareEnabled: false,
                occurredAt: Date(timeIntervalSince1970: 1_753_405_603),
                nutritionSnapshot: try XCTUnwrap(
                    NutrientImpactSnapshotFactory.make(
                        recordID: "2026-08-30|체험 급식",
                        date: "2026-08-30",
                        normalizedMenuName: "체험 급식",
                        status: .oneBite,
                        recordUpdatedAt: Date(timeIntervalSince1970: 1_753_405_603),
                        nutrientIDs: ["fiber", "vitamin"]
                    )
                )
            )
        )
        XCTAssertEqual(demoRecordResult.nutritionGuidance?.source, .recordedRevision)

        let liveProgress = RebuildProgressRepository(
            context: liveContainer.viewContext
        )
        let demoProgress = RebuildProgressRepository(
            context: demoContainer.viewContext
        )
        XCTAssertEqual(try liveProgress.totalXP(), 18)
        XCTAssertEqual(try demoProgress.totalXP(), 18)
        XCTAssertEqual(
            try count(entity: RebuildEntityName.mealRecord, in: liveContainer.viewContext),
            1
        )
        XCTAssertEqual(
            try count(entity: RebuildEntityName.mealRecord, in: demoContainer.viewContext),
            1
        )
        let livePhotoIDs = try await CoreDataTodayMealPhotoMetadataStore(
            container: liveContainer
        ).photoIDs(
            date: "2026-08-30",
            normalizedMenuName: "체험 급식"
        )
        XCTAssertEqual(livePhotoIDs, [])
    }

    func testDemoWholeMealSourceLabelsNeverSayNEIS() {
        XCTAssertEqual(
            MealPresentationCopy.wholeMealSourceLabel(isDemoMode: true),
            "전체 급식 기준 · 체험 급식"
        )
        XCTAssertEqual(
            MealPresentationCopy.wholeMealSourceLabel(
                isDemoMode: true,
                isAveraged: true
            ),
            "전체 급식 기준 · 체험 급식 (기간 평균)"
        )
        XCTAssertEqual(
            MealPresentationCopy.wholeMealSourceLabel(isDemoMode: false),
            "전체 급식 기준 · NEIS 제공"
        )
    }

    private func count(
        entity: String,
        in context: NSManagedObjectContext
    ) throws -> Int {
        try context.performAndWait {
            try context.count(
                for: NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            )
        }
    }
}

private extension RebuildUserProfile {
    static var demoFixture: RebuildUserProfile {
        RebuildUserProfile(
            id: "demo-profile",
            role: .child,
            nickname: "체험 아이",
            school: RebuildOnboardingSchool(
                name: "냠냠 초등학교",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [],
            destination: .today,
            isDemoMode: true
        )
    }

    static var liveFixture: RebuildUserProfile {
        RebuildUserProfile(
            id: "live-profile",
            role: .child,
            nickname: "실제 아이",
            school: RebuildOnboardingSchool(
                name: "냠냠 초등학교",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [],
            destination: .today,
            isDemoMode: false
        )
    }
}

private final class RebuildLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        withValue { $0 }
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storedValue)
    }
}

private final class RebuildDeadlockDetectingSerializer: @unchecked Sendable {
    private enum ProbeError: Error {
        case mainThreadWouldDeadlock
        case backgroundReleaseTimedOut
    }

    private let lock = NSLock()
    private let enteredExpectation: XCTestExpectation
    private let backgroundRelease = DispatchSemaphore(value: 0)
    private var hasFulfilledEnteredExpectation = false

    init(enteredExpectation: XCTestExpectation) {
        self.enteredExpectation = enteredExpectation
    }

    func serialize(_ operation: () throws -> Bool) throws -> Bool {
        if Thread.isMainThread {
            guard lock.try() else {
                throw ProbeError.mainThreadWouldDeadlock
            }
        } else {
            lock.lock()
        }
        defer { lock.unlock() }

        if !hasFulfilledEnteredExpectation {
            hasFulfilledEnteredExpectation = true
            enteredExpectation.fulfill()
        }
        if !Thread.isMainThread {
            guard backgroundRelease.wait(timeout: .now() + 2) == .success else {
                throw ProbeError.backgroundReleaseTimedOut
            }
        }
        return try operation()
    }

    func releaseBlockedBackgroundCaller() {
        backgroundRelease.signal()
    }
}
