import CoreData
import XCTest
@testable import NaymNaymLevelUp

final class RebuildMigrationCoordinatorTests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        suiteNames.removeAll()
        cleanupURLs.removeAll()
        super.tearDown()
    }

    func testMigrationIsIdempotentAndPreservesLegacyDefaults() throws {
        let defaults = makeDefaults()
        let profile = makeProfile()
        UserProfileStore(defaults: defaults).save(profile)
        let sourceBefore = defaults.dictionaryRepresentation()
        let container = try RebuildPersistentStore.makeInMemory()
        let coordinator = RebuildMigrationCoordinator(defaults: defaults, container: container)

        XCTAssertEqual(try coordinator.runIfNeeded(targetVersion: 1), .migrated)
        XCTAssertEqual(try coordinator.runIfNeeded(targetVersion: 1), .alreadyCompleted)
        XCTAssertEqual(UserProfileStore(defaults: defaults).load(), profile)
        assertLegacySource(sourceBefore, remainsIn: defaults)
        XCTAssertEqual(try count(RebuildEntityName.profile, in: container.viewContext), 1)
        XCTAssertEqual(try count(RebuildEntityName.migrationState, in: container.viewContext), 1)
    }

    func testNoLegacyDataDoesNotCreateRowsOrCompletionState() throws {
        let defaults = makeDefaults()
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(defaults: defaults, container: container)
                .runIfNeeded(targetVersion: 1),
            .noLegacyData
        )
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
    }

    func testExistingTargetVersionReturnsAlreadyCompletedWithoutReadingLegacyDataIntoRows() throws {
        let defaults = makeDefaults()
        UserProfileStore(defaults: defaults).save(makeProfile())
        let container = try RebuildPersistentStore.makeInMemory()
        try RebuildMigrationStateRepository(context: container.viewContext)
            .markCompleted(version: 1, sourceDigest: "existing")

        XCTAssertEqual(
            try RebuildMigrationCoordinator(defaults: defaults, container: container)
                .runIfNeeded(targetVersion: 1),
            .alreadyCompleted
        )
        XCTAssertEqual(try count(RebuildEntityName.profile, in: container.viewContext), 0)
        XCTAssertEqual(
            try RebuildMigrationStateRepository(context: container.viewContext).load()?.sourceDigest,
            "existing"
        )
    }

    func testFullMappingPreservesFieldsCountsCanonicalIdentitiesParentLinksAndXP() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let createdAt = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = UserProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            nickname: "냠냠이",
            schoolName: "냠냠초",
            officeCode: "B10",
            schoolCode: "7010111",
            regionName: "서울",
            selectedAllergyCodes: [2, 1],
            createdAt: createdAt,
            userMode: .elementary
        )
        let meal = MealRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            date: "2026-07-25",
            menuName: " 시금치 나물 ",
            eatingStatus: .oneBite,
            difficultyReasons: [.texture, .smell],
            allergyCodes: [2, 1],
            photoIds: ["photo-1"],
            parentShareEnabled: true,
            createdAt: createdAt
        )
        let challenge = ChallengeRecord(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: meal.date,
            menuName: meal.menuName,
            action: .oneBite,
            gainedExp: 18,
            badgeName: "초록 용사",
            nutrients: ["식이섬유"],
            createdAt: createdAt,
            eatingStatus: .oneBite,
            xpBreakdown: XPBreakdown(challenge: 18)
        )
        let photo = MealPhotoRecord(
            id: "photo-1",
            fileName: "lunch.jpg",
            createdAt: createdAt,
            isSharedWithParent: true
        )
        let childLink = ChildLink(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            childNickname: "냠냠이",
            schoolName: "냠냠초",
            mode: .elementary,
            inviteCode: "NYAM-ABCD-EFGH-JKLM",
            createdAt: createdAt,
            registeredAt: createdAt,
            parentConnectedAt: createdAt
        )
        UserProfileStore(defaults: defaults).save(profile)
        ProgressStore(defaults: defaults).save(
            PlayerProgress(level: 2, totalChallenges: 1, recordExp: 22, challengeExp: 18)
        )
        MealRecordStore(defaults: defaults).save([meal])
        ChallengeStore(defaults: defaults).save([challenge])
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        ChildShareLinkStore(defaults: defaults).save(childLink)
        ParentProfileStore(defaults: defaults).save(
            ParentProfile(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                nickname: "보호자",
                childLinks: [childLink]
            )
        )
        let sourcePhotoURL = sourceDirectory.appendingPathComponent(photo.fileName)
        try Data("photo bytes".utf8).write(to: sourcePhotoURL)
        let container = try RebuildPersistentStore.makeInMemory()

        let outcome = try RebuildMigrationCoordinator(
            defaults: defaults,
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory,
            now: { Date(timeIntervalSince1970: 1_790_000_000) }
        ).runIfNeeded(targetVersion: 1)

        XCTAssertEqual(outcome, .migrated)
        let context = container.viewContext
        let mappedProfile = try fetch(RebuildProfileManagedObject.self, RebuildEntityName.profile, in: context).first
        XCTAssertEqual(mappedProfile?.id, profile.id.uuidString)
        XCTAssertEqual(mappedProfile?.role, "child")
        XCTAssertEqual(mappedProfile?.nickname, profile.nickname)
        XCTAssertEqual(mappedProfile?.officeCode, profile.officeCode)
        XCTAssertEqual(mappedProfile?.schoolCode, profile.schoolCode)
        XCTAssertEqual(mappedProfile?.allergyCodesJSON, "[1,2]")

        let mappedMeal = try XCTUnwrap(
            fetch(RebuildMealRecordManagedObject.self, RebuildEntityName.mealRecord, in: context).first
        )
        XCTAssertEqual(mappedMeal.id, "2026-07-25|시금치 나물|oneBite")
        XCTAssertEqual(mappedMeal.normalizedMenuName, "시금치 나물")
        XCTAssertEqual(mappedMeal.status, "oneBite")
        XCTAssertEqual(mappedMeal.difficultyReasonsJSON, "[\"texture\",\"smell\"]")
        XCTAssertEqual(mappedMeal.allergyCodesJSON, "[2,1]")
        XCTAssertEqual(mappedMeal.photoIDsJSON, "[\"photo-1\"]")
        XCTAssertTrue(mappedMeal.parentShareEnabled)
        XCTAssertEqual(mappedMeal.updatedAt, createdAt)

        let mappedPhoto = try XCTUnwrap(
            fetch(RebuildMealPhotoManagedObject.self, RebuildEntityName.mealPhoto, in: context).first
        )
        XCTAssertEqual(mappedPhoto.id, photo.id)
        XCTAssertEqual(mappedPhoto.recordID, mappedMeal.id)
        XCTAssertFalse(mappedPhoto.relativePath.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: targetDirectory.appendingPathComponent(mappedPhoto.relativePath)),
            Data("photo bytes".utf8)
        )

        let links = try fetch(
            RebuildParentLinkManagedObject.self,
            RebuildEntityName.parentLink,
            in: context
        )
        XCTAssertEqual(links.map(\.id), [childLink.id.uuidString])
        XCTAssertEqual(links.first?.inviteCode, childLink.inviteCode)
        XCTAssertEqual(links.first?.connectionState, "connected")
        XCTAssertEqual(links.first?.connectedAt, childLink.parentConnectedAt)

        let progressEvents = try fetch(
            RebuildProgressEventManagedObject.self,
            RebuildEntityName.progressEvent,
            in: context
        )
        XCTAssertEqual(progressEvents.reduce(Int64(0)) { $0 + $1.amount }, 40)
        XCTAssertNotNil(progressEvents.first { $0.id == "meal:2026-07-25|시금치 나물|oneBite" })
        XCTAssertEqual(try count(RebuildEntityName.mealRecord, in: context), 1)
        XCTAssertEqual(try count(RebuildEntityName.mealPhoto, in: context), 1)
        XCTAssertEqual(try count(RebuildEntityName.parentLink, in: context), 1)
        XCTAssertEqual(try count(RebuildEntityName.migrationState, in: context), 1)
    }

    func testMissingPhotoPreservesMetadataAndReturnsStructuredWarning() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "missing-photo",
            fileName: "missing.jpg",
            createdAt: Date(timeIntervalSince1970: 100),
            isSharedWithParent: false
        )
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let container = try RebuildPersistentStore.makeInMemory()
        let coordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory
        )

        XCTAssertEqual(try coordinator.runIfNeeded(targetVersion: 1), .migrated)
        XCTAssertEqual(
            coordinator.warnings,
            [.missingPhotoFile(photoID: "missing-photo", fileName: "missing.jpg")]
        )
        let mapped = try XCTUnwrap(
            fetch(RebuildMealPhotoManagedObject.self, RebuildEntityName.mealPhoto, in: container.viewContext).first
        )
        XCTAssertEqual(mapped.id, photo.id)
        XCTAssertFalse(mapped.relativePath.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: targetDirectory.appendingPathComponent(mapped.relativePath).path
            )
        )
    }

    func testSuccessfulPhotoCopyNeverDeletesSource() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let record = MealPhotoRecord(
            id: "kept-source",
            fileName: "source.jpg",
            createdAt: Date(timeIntervalSince1970: 200),
            isSharedWithParent: false
        )
        let sourceURL = sourceDirectory.appendingPathComponent(record.fileName)
        let sourceData = Data("keep me".utf8)
        try sourceData.write(to: sourceURL)
        MealPhotoMetadataStore(defaults: defaults).save([record])

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testVerificationFailureRollsBackRowsCompletionAndNewlyCopiedFiles() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let record = MealPhotoRecord(
            id: "rollback-verification",
            fileName: "source.jpg",
            createdAt: Date(timeIntervalSince1970: 300),
            isSharedWithParent: false
        )
        try Data("copy then rollback".utf8)
            .write(to: sourceDirectory.appendingPathComponent(record.fileName))
        MealPhotoMetadataStore(defaults: defaults).save([record])
        let container = try RebuildPersistentStore.makeInMemory()
        let coordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory,
            verify: { _ in throw TestFailure.verification }
        )

        XCTAssertThrowsError(try coordinator.runIfNeeded(targetVersion: 1)) { error in
            XCTAssertEqual(error as? TestFailure, .verification)
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path), [])
        XCTAssertNotNil(MealPhotoMetadataStore(defaults: defaults).load().first)
    }

    func testSaveFailureRollsBackRowsCompletionAndNewlyCopiedFiles() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let record = MealPhotoRecord(
            id: "rollback-save",
            fileName: "source.jpg",
            createdAt: Date(timeIntervalSince1970: 400),
            isSharedWithParent: false
        )
        try Data("copy then rollback".utf8)
            .write(to: sourceDirectory.appendingPathComponent(record.fileName))
        MealPhotoMetadataStore(defaults: defaults).save([record])
        let container = try RebuildPersistentStore.makeInMemory()
        let coordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory,
            save: { _ in throw TestFailure.save }
        )

        XCTAssertThrowsError(try coordinator.runIfNeeded(targetVersion: 1)) { error in
            XCTAssertEqual(error as? TestFailure, .save)
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path), [])
        XCTAssertNotNil(MealPhotoMetadataStore(defaults: defaults).load().first)
    }

    func testOnlyTargetVersionOneIsAcceptedAndDigestIsDeterministicButSourceSensitive() throws {
        let firstDefaults = makeDefaults()
        let secondDefaults = makeDefaults()
        UserProfileStore(defaults: firstDefaults).save(makeProfile(nickname: "같은 값"))
        UserProfileStore(defaults: secondDefaults).save(makeProfile(nickname: "같은 값"))
        let firstContainer = try RebuildPersistentStore.makeInMemory()
        let secondContainer = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(defaults: firstDefaults, container: firstContainer)
                .runIfNeeded(targetVersion: 2)
        ) { error in
            XCTAssertEqual(error as? RebuildMigrationError, .unsupportedTargetVersion(2))
        }
        XCTAssertEqual(try totalObjectCount(in: firstContainer.viewContext), 0)

        XCTAssertEqual(
            try RebuildMigrationCoordinator(defaults: firstDefaults, container: firstContainer)
                .runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(
            try RebuildMigrationCoordinator(defaults: secondDefaults, container: secondContainer)
                .runIfNeeded(targetVersion: 1),
            .migrated
        )
        let firstDigest = try XCTUnwrap(
            RebuildMigrationStateRepository(context: firstContainer.viewContext).load()?.sourceDigest
        )
        let secondDigest = try XCTUnwrap(
            RebuildMigrationStateRepository(context: secondContainer.viewContext).load()?.sourceDigest
        )
        XCTAssertEqual(firstDigest, secondDigest)

        let changedDefaults = makeDefaults()
        UserProfileStore(defaults: changedDefaults).save(makeProfile(nickname: "다른 값"))
        let changedContainer = try RebuildPersistentStore.makeInMemory()
        _ = try RebuildMigrationCoordinator(defaults: changedDefaults, container: changedContainer)
            .runIfNeeded(targetVersion: 1)
        let changedDigest = try XCTUnwrap(
            RebuildMigrationStateRepository(context: changedContainer.viewContext).load()?.sourceDigest
        )
        XCTAssertNotEqual(firstDigest, changedDigest)
    }

    func testUnsafeTraversalAndEscapingSymlinkPhotoPathsAreRejected() throws {
        let traversalDefaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        MealPhotoMetadataStore(defaults: traversalDefaults).save([
            MealPhotoRecord(
                id: "unsafe",
                fileName: "../secret.jpg",
                createdAt: Date(),
                isSharedWithParent: false
            )
        ])

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: traversalDefaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }

        let symlinkDefaults = makeDefaults()
        let outsideDirectory = makeDirectory()
        let outsidePhoto = outsideDirectory.appendingPathComponent("outside.jpg")
        try Data("outside".utf8).write(to: outsidePhoto)
        try FileManager.default.createSymbolicLink(
            at: sourceDirectory.appendingPathComponent("link.jpg"),
            withDestinationURL: outsidePhoto
        )
        MealPhotoMetadataStore(defaults: symlinkDefaults).save([
            MealPhotoRecord(
                id: "symlink",
                fileName: "link.jpg",
                createdAt: Date(),
                isSharedWithParent: false
            )
        ])

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: symlinkDefaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }

        let danglingSymlinkDefaults = makeDefaults()
        try FileManager.default.createSymbolicLink(
            atPath: sourceDirectory.appendingPathComponent("dangling.jpg").path,
            withDestinationPath: outsideDirectory.appendingPathComponent("absent.jpg").path
        )
        MealPhotoMetadataStore(defaults: danglingSymlinkDefaults).save([
            MealPhotoRecord(
                id: "dangling-symlink",
                fileName: "dangling.jpg",
                createdAt: Date(),
                isSharedWithParent: false
            )
        ])

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: danglingSymlinkDefaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }
    }

    func testSimultaneousCoordinatorsSerializeWholeAttemptAndKeepOneIntactPhoto() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "concurrent-photo",
            fileName: "concurrent.jpg",
            createdAt: Date(timeIntervalSince1970: 500),
            isSharedWithParent: false
        )
        let photoData = Data("one durable photo".utf8)
        try photoData.write(to: sourceDirectory.appendingPathComponent(photo.fileName))
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let container = try RebuildPersistentStore.makeInMemory()
        let raceGate = TimedRaceGate(participantCount: 2)
        let results = MigrationLockedBox<[Result<MigrationOutcome, Error>]>([])
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()

        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                start.wait()
                let coordinator = RebuildMigrationCoordinator(
                    defaults: defaults,
                    container: container,
                    legacyPhotoDirectory: sourceDirectory,
                    rebuildPhotoDirectory: targetDirectory,
                    verify: { _ in raceGate.arriveAndWait() }
                )
                let result = Result {
                    try coordinator.runIfNeeded(targetVersion: 1)
                }
                results.withValue { $0.append(result) }
                group.leave()
            }
        }
        start.signal()
        start.signal()

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        let outcomes = results.value.compactMap { try? $0.get() }
        XCTAssertEqual(outcomes.filter { $0 == .migrated }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .alreadyCompleted }.count, 1)
        XCTAssertEqual(results.value.count, 2)
        XCTAssertEqual(try count(RebuildEntityName.mealPhoto, in: container.viewContext), 1)
        XCTAssertEqual(try count(RebuildEntityName.migrationState, in: container.viewContext), 1)
        let mappedPhoto = try XCTUnwrap(
            fetch(
                RebuildMealPhotoManagedObject.self,
                RebuildEntityName.mealPhoto,
                in: container.viewContext
            ).first
        )
        XCTAssertEqual(
            try Data(contentsOf: targetDirectory.appendingPathComponent(mappedPhoto.relativePath)),
            photoData
        )
        XCTAssertEqual(
            try Data(contentsOf: sourceDirectory.appendingPathComponent(photo.fileName)),
            photoData
        )
    }

    func testCorruptPresentLegacyPayloadThrowsAndWritesNothing() throws {
        let defaults = makeDefaults()
        let corruptData = Data("{not-json".utf8)
        defaults.set(corruptData, forKey: "user-profile")
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(defaults: defaults, container: container)
                .runIfNeeded(targetVersion: 1)
        )
        XCTAssertEqual(defaults.data(forKey: "user-profile"), corruptData)
        XCTAssertNil(UserProfileStore(defaults: defaults).load())
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
    }

    func testRegistrationDomainValueAloneIsNotLegacyDataForInjectedSuite() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let registeredProfile = try encoder.encode(makeProfile())
        defaults.register(defaults: ["user-profile": registeredProfile])
        XCTAssertNotNil(UserProfileStore(defaults: defaults).load())
        XCTAssertNil(defaults.persistentDomain(forName: domainName)?["user-profile"])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container
            ).runIfNeeded(targetVersion: 1),
            .noLegacyData
        )
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
    }

    func testCanonicalMealAndPhotoIdentityCollisionsThrowWithoutLossyDeduplication() throws {
        let mealDefaults = makeDefaults()
        let firstMeal = MealRecord(
            date: "2026-07-25",
            menuName: " 시금치 나물 ",
            eatingStatus: .oneBite
        )
        let secondMeal = MealRecord(
            date: "2026-07-25",
            menuName: "시금치 나물",
            eatingStatus: .oneBite
        )
        MealRecordStore(defaults: mealDefaults).save([firstMeal, secondMeal])
        let mealContainer = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(defaults: mealDefaults, container: mealContainer)
                .runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(
                error as? RebuildMigrationError,
                .mealIdentityCollision("2026-07-25|시금치 나물|oneBite")
            )
        }
        XCTAssertEqual(try totalObjectCount(in: mealContainer.viewContext), 0)

        let photoDefaults = makeDefaults()
        MealPhotoMetadataStore(defaults: photoDefaults).save([
            MealPhotoRecord(
                id: "duplicate-photo",
                fileName: "first.jpg",
                createdAt: Date(timeIntervalSince1970: 1),
                isSharedWithParent: false
            ),
            MealPhotoRecord(
                id: "duplicate-photo",
                fileName: "second.jpg",
                createdAt: Date(timeIntervalSince1970: 2),
                isSharedWithParent: false
            ),
        ])
        let photoContainer = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(defaults: photoDefaults, container: photoContainer)
                .runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(
                error as? RebuildMigrationError,
                .photoIDCollision("duplicate-photo")
            )
        }
        XCTAssertEqual(try totalObjectCount(in: photoContainer.viewContext), 0)
    }

    func testCanonicalNormalizationAssociatesLegacyWhitespaceAndCaseVariants() throws {
        let defaults = makeDefaults()
        MealRecordStore(defaults: defaults).save([
            MealRecord(
                date: "2026-07-25",
                menuName: " Spinach Rice ",
                eatingStatus: .oneBite
            )
        ])
        ChallengeStore(defaults: defaults).save([
            ChallengeRecord(
                date: "2026-07-25",
                menuName: "spinachrice",
                action: .oneBite,
                gainedExp: 18,
                badgeName: nil,
                nutrients: [],
                eatingStatus: .oneBite,
                xpBreakdown: XPBreakdown(challenge: 18)
            )
        ])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(defaults: defaults, container: container)
                .runIfNeeded(targetVersion: 1),
            .migrated
        )
        let meal = try XCTUnwrap(
            fetch(
                RebuildMealRecordManagedObject.self,
                RebuildEntityName.mealRecord,
                in: container.viewContext
            ).first
        )
        XCTAssertEqual(meal.normalizedMenuName, "spinach rice")
        XCTAssertEqual(meal.id, "2026-07-25|spinach rice|oneBite")
        let events = try fetch(
            RebuildProgressEventManagedObject.self,
            RebuildEntityName.progressEvent,
            in: container.viewContext
        )
        XCTAssertNotNil(events.first { $0.id == "meal:\(meal.id)" })
        XCTAssertNil(events.first { $0.id == "meal:2026-07-25|spinachrice|oneBite" })
    }

    func testTargetRootSymlinkSourceLeafSymlinkAndStaleTargetAreRejected() throws {
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let outsideDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "hardened-photo",
            fileName: "source.jpg",
            createdAt: Date(timeIntervalSince1970: 600),
            isSharedWithParent: false
        )
        let sourceData = Data("trusted source".utf8)
        try sourceData.write(to: sourceDirectory.appendingPathComponent(photo.fileName))

        let rootDefaults = makeDefaults()
        MealPhotoMetadataStore(defaults: rootDefaults).save([photo])
        try FileManager.default.removeItem(at: targetDirectory)
        try FileManager.default.createSymbolicLink(
            at: targetDirectory,
            withDestinationURL: outsideDirectory
        )
        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: rootDefaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outsideDirectory.path), [])

        try FileManager.default.removeItem(at: targetDirectory)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let sourceSymlinkDefaults = makeDefaults()
        let realPhoto = sourceDirectory.appendingPathComponent("real.jpg")
        try sourceData.write(to: realPhoto)
        let symlinkPhoto = MealPhotoRecord(
            id: "source-symlink",
            fileName: "inside-link.jpg",
            createdAt: photo.createdAt,
            isSharedWithParent: false
        )
        try FileManager.default.createSymbolicLink(
            at: sourceDirectory.appendingPathComponent(symlinkPhoto.fileName),
            withDestinationURL: realPhoto
        )
        MealPhotoMetadataStore(defaults: sourceSymlinkDefaults).save([symlinkPhoto])
        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: sourceSymlinkDefaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }

        let discoveryDefaults = makeDefaults()
        MealPhotoMetadataStore(defaults: discoveryDefaults).save([photo])
        try FileManager.default.removeItem(at: sourceDirectory.appendingPathComponent(photo.fileName))
        let discoveryContainer = try RebuildPersistentStore.makeInMemory()
        _ = try RebuildMigrationCoordinator(
            defaults: discoveryDefaults,
            container: discoveryContainer,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory
        ).runIfNeeded(targetVersion: 1)
        let relativePath = try XCTUnwrap(
            fetch(
                RebuildMealPhotoManagedObject.self,
                RebuildEntityName.mealPhoto,
                in: discoveryContainer.viewContext
            ).first?.relativePath
        )
        try Data("stale target".utf8)
            .write(to: targetDirectory.appendingPathComponent(relativePath))
        try sourceData.write(to: sourceDirectory.appendingPathComponent(photo.fileName))
        let staleDefaults = makeDefaults()
        MealPhotoMetadataStore(defaults: staleDefaults).save([photo])

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: staleDefaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(
                error as? RebuildMigrationError,
                .photoContentMismatch(relativePath)
            )
        }

        try FileManager.default.removeItem(
            at: targetDirectory.appendingPathComponent(relativePath)
        )
        try FileManager.default.createSymbolicLink(
            at: targetDirectory.appendingPathComponent(relativePath),
            withDestinationURL: outsideDirectory.appendingPathComponent("outside-target.jpg")
        )
        let targetLeafDefaults = makeDefaults()
        MealPhotoMetadataStore(defaults: targetLeafDefaults).save([photo])
        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: targetLeafDefaults,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }
    }

    func testExtremeXPComponentsThrowOverflowWithoutTrappingOrWriting() throws {
        let defaults = makeDefaults()
        defaults.set(
            Data("""
            {
              "level": 1,
              "exp": 0,
              "recordExp": \(Int.max),
              "challengeExp": \(Int.max),
              "balanceExp": \(Int.max),
              "safetyExp": \(Int.max),
              "totalChallenges": 0,
              "badges": [],
              "currentSkinId": "skin-1"
            }
            """.utf8),
            forKey: "player-progress"
        )
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(defaults: defaults, container: container)
                .runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? RebuildMigrationError, .xpOverflow)
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
    }

    func testCopiedFileCleanupFailureSurfacesPathsAndOriginalFailure() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "cleanup-failure",
            fileName: "cleanup.jpg",
            createdAt: Date(timeIntervalSince1970: 700),
            isSharedWithParent: false
        )
        try Data("copied".utf8).write(
            to: sourceDirectory.appendingPathComponent(photo.fileName)
        )
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                verify: { _ in throw TestFailure.verification },
                removeCopiedFile: { _ in throw TestFailure.cleanup }
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case let .rollbackCleanupFailed(paths, originalFailure) =
                    error as? RebuildMigrationError else {
                return XCTFail("Expected rollbackCleanupFailed, got \(error)")
            }
            XCTAssertEqual(paths.count, 1)
            XCTAssertTrue(paths[0].hasSuffix(".jpg"))
            XCTAssertTrue(originalFailure.contains("verification"))
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path).count, 1)
    }

    func testOrphanPhotoUsesStableNonemptySentinelAndParentLinksDeduplicateByIDAndInvite() throws {
        let defaults = makeDefaults()
        MealPhotoMetadataStore(defaults: defaults).save([
            MealPhotoRecord(
                id: "orphan-photo",
                fileName: "missing.jpg",
                createdAt: Date(timeIntervalSince1970: 800),
                isSharedWithParent: false
            )
        ])
        let first = ChildLink(
            id: UUID(uuidString: "11111111-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            childNickname: "첫째",
            schoolName: "냠냠초",
            mode: .elementary,
            inviteCode: "nyam abcd efgh jklm"
        )
        let second = ChildLink(
            id: UUID(uuidString: "22222222-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            childNickname: "둘째",
            schoolName: "냠냠초",
            mode: .elementary,
            inviteCode: "NYAM-ABCD-EFGH-JKLM"
        )
        var replacement = second
        replacement.inviteCode = "NYAM-BCDE-FGHJ-KLMN"
        ParentProfileStore(defaults: defaults).save(
            ParentProfile(nickname: "보호자", childLinks: [first, second, replacement])
        )
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(defaults: defaults, container: container)
                .runIfNeeded(targetVersion: 1),
            .migrated
        )
        let photo = try XCTUnwrap(
            fetch(
                RebuildMealPhotoManagedObject.self,
                RebuildEntityName.mealPhoto,
                in: container.viewContext
            ).first
        )
        XCTAssertEqual(photo.recordID, "legacy-orphan-photo:orphan-photo")
        let links = try fetch(
            RebuildParentLinkManagedObject.self,
            RebuildEntityName.parentLink,
            in: container.viewContext
        )
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.id, replacement.id.uuidString)
        XCTAssertEqual(links.first?.inviteCode, "NYAM-BCDE-FGHJ-KLMN")
    }

    func testRetryAfterRollbackMigratesOnceAndKeepsSourcePhoto() throws {
        let defaults = makeDefaults()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "retry-photo",
            fileName: "retry.jpg",
            createdAt: Date(timeIntervalSince1970: 900),
            isSharedWithParent: false
        )
        let data = Data("retry safely".utf8)
        let sourceURL = sourceDirectory.appendingPathComponent(photo.fileName)
        try data.write(to: sourceURL)
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                verify: { _ in throw TestFailure.verification }
            ).runIfNeeded(targetVersion: 1)
        )
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(try count(RebuildEntityName.mealPhoto, in: container.viewContext), 1)
        XCTAssertEqual(try count(RebuildEntityName.migrationState, in: container.viewContext), 1)
        XCTAssertEqual(try Data(contentsOf: sourceURL), data)
    }

    private func makeDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
        makeDefaultsWithDomain(file: file, line: line).0
    }

    private func makeDefaultsWithDomain(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (UserDefaults, String) {
        let name = "RebuildMigrationCoordinatorTests.\(file).\(line).\(UUID().uuidString)"
        suiteNames.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RebuildMigrationCoordinatorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cleanupURLs.append(url)
        return url
    }

    private func makeProfile(nickname: String = "냠냠이") -> UserProfile {
        UserProfile(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            nickname: nickname,
            schoolName: "냠냠초",
            officeCode: "B10",
            schoolCode: "7010111",
            regionName: "서울",
            selectedAllergyCodes: [1],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func assertLegacySource(
        _ before: [String: Any],
        remainsIn defaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let after = defaults.dictionaryRepresentation()
        for key in [
            "user-profile",
            "player-progress",
            "challenge-records",
            "meal-records",
            "meal-photo-records",
            "parent-profile",
            "child-share-link",
        ] {
            XCTAssertEqual(before[key] as? Data, after[key] as? Data, file: file, line: line)
        }
    }

    private func fetch<Object: NSManagedObject>(
        _ type: Object.Type,
        _ entityName: String,
        in context: NSManagedObjectContext
    ) throws -> [Object] {
        try context.performAndWait {
            try context.fetch(NSFetchRequest<Object>(entityName: entityName))
        }
    }

    private func count(_ entityName: String, in context: NSManagedObjectContext) throws -> Int {
        try context.performAndWait {
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName))
        }
    }

    private func totalObjectCount(in context: NSManagedObjectContext) throws -> Int {
        try RebuildManagedModel.make().entities.compactMap(\.name).reduce(0) {
            $0 + (try count($1, in: context))
        }
    }
}

private enum TestFailure: Error, Equatable {
    case verification
    case save
    case cleanup
}

private final class MigrationLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storedValue)
    }
}

private final class TimedRaceGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let participantCount: Int
    private var arrivals = 0

    init(participantCount: Int) {
        self.participantCount = participantCount
    }

    func arriveAndWait() {
        condition.lock()
        arrivals += 1
        if arrivals >= participantCount {
            condition.broadcast()
        } else {
            _ = condition.wait(until: Date().addingTimeInterval(0.25))
        }
        condition.unlock()
    }
}
