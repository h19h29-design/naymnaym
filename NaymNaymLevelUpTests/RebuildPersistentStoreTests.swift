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
