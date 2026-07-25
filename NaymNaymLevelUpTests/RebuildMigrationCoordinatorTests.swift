import CoreData
import Darwin
import XCTest
@testable import NaymNaymLevelUp

final class RebuildMigrationCoordinatorTests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var suiteNames: [String] = []
    private var domainNamesByDefaults: [ObjectIdentifier: String] = [:]

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        suiteNames.removeAll()
        domainNamesByDefaults.removeAll()
        cleanupURLs.removeAll()
        super.tearDown()
    }

    func testMigrationIsIdempotentAndPreservesLegacyDefaults() throws {
        let defaults = makeDefaults()
        let profile = makeProfile()
        UserProfileStore(defaults: defaults).save(profile)
        let sourceBefore = defaults.dictionaryRepresentation()
        let container = try RebuildPersistentStore.makeInMemory()
        let coordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            legacyDefaultsDomainName: domainName(for: defaults),
            container: container
        )

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
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container
            )
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
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container
            )
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
            legacyDefaultsDomainName: domainName(for: defaults),
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
            legacyDefaultsDomainName: domainName(for: defaults),
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
                legacyDefaultsDomainName: domainName(for: defaults),
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testEqualPhotoBytesShareOneContentAddressedCacheFile() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let data = Data("same verified bytes".utf8)
        let first = MealPhotoRecord(
            id: "content-a",
            fileName: "first.jpg",
            createdAt: Date(timeIntervalSince1970: 250),
            isSharedWithParent: false
        )
        let second = MealPhotoRecord(
            id: "content-b",
            fileName: "second.jpg",
            createdAt: Date(timeIntervalSince1970: 251),
            isSharedWithParent: false
        )
        try data.write(to: sourceDirectory.appendingPathComponent(first.fileName))
        try data.write(to: sourceDirectory.appendingPathComponent(second.fileName))
        MealPhotoMetadataStore(defaults: defaults).save([first, second])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let photos = try fetch(
            RebuildMealPhotoManagedObject.self,
            RebuildEntityName.mealPhoto,
            in: container.viewContext
        )
        XCTAssertEqual(Set(photos.map(\.relativePath)).count, 1)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path).count,
            1
        )
    }

    func testVerificationFailureRollsBackRowsButKeepsAppendOnlyVerifiedPhoto() throws {
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
            legacyDefaultsDomainName: domainName(for: defaults),
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory,
            verify: { _ in throw TestFailure.verification }
        )

        XCTAssertThrowsError(try coordinator.runIfNeeded(targetVersion: 1)) { error in
            XCTAssertEqual(error as? TestFailure, .verification)
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path).count,
            1
        )
        XCTAssertNotNil(MealPhotoMetadataStore(defaults: defaults).load().first)
    }

    func testSaveFailureRollsBackRowsButKeepsAppendOnlyVerifiedPhoto() throws {
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
            legacyDefaultsDomainName: domainName(for: defaults),
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory,
            save: { _ in throw TestFailure.save }
        )

        XCTAssertThrowsError(try coordinator.runIfNeeded(targetVersion: 1)) { error in
            XCTAssertEqual(error as? TestFailure, .save)
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path).count,
            1
        )
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
            try RebuildMigrationCoordinator(
                defaults: firstDefaults,
                legacyDefaultsDomainName: domainName(for: firstDefaults),
                container: firstContainer
            )
                .runIfNeeded(targetVersion: 2)
        ) { error in
            XCTAssertEqual(error as? RebuildMigrationError, .unsupportedTargetVersion(2))
        }
        XCTAssertEqual(try totalObjectCount(in: firstContainer.viewContext), 0)

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: firstDefaults,
                legacyDefaultsDomainName: domainName(for: firstDefaults),
                container: firstContainer
            )
                .runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: secondDefaults,
                legacyDefaultsDomainName: domainName(for: secondDefaults),
                container: secondContainer
            )
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
        _ = try RebuildMigrationCoordinator(
            defaults: changedDefaults,
            legacyDefaultsDomainName: domainName(for: changedDefaults),
            container: changedContainer
        )
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
                legacyDefaultsDomainName: domainName(for: traversalDefaults),
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
                legacyDefaultsDomainName: domainName(for: symlinkDefaults),
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
                legacyDefaultsDomainName: domainName(for: danglingSymlinkDefaults),
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

    func testOverlappingCoordinatorFailsFastThenRetrySeesCompletion() throws {
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
        let defaultsDomainName = domainName(for: defaults)
        let verifyEntered = DispatchSemaphore(value: 0)
        let allowFirstToFinish = DispatchSemaphore(value: 0)
        let firstResult = MigrationLockedBox<Result<MigrationOutcome, Error>?>(nil)
        let group = DispatchGroup()
        let firstCoordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            legacyDefaultsDomainName: defaultsDomainName,
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory,
            verify: { _ in
                verifyEntered.signal()
                XCTAssertEqual(
                    allowFirstToFinish.wait(timeout: .now() + 2),
                    .success
                )
            }
        )

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try firstCoordinator.runIfNeeded(targetVersion: 1)
            }
            firstResult.withValue { $0 = result }
            group.leave()
        }
        XCTAssertEqual(verifyEntered.wait(timeout: .now() + 2), .success)
        let overlappingCoordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            legacyDefaultsDomainName: defaultsDomainName,
            container: container,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory
        )
        XCTAssertThrowsError(
            try overlappingCoordinator.runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(
                error as? RebuildMigrationError,
                .migrationInProgress
            )
        }
        allowFirstToFinish.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(try firstResult.value?.get(), .migrated)
        XCTAssertEqual(
            try overlappingCoordinator.runIfNeeded(targetVersion: 1),
            .alreadyCompleted
        )
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
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container
            )
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
            try RebuildMigrationCoordinator(
                defaults: mealDefaults,
                legacyDefaultsDomainName: domainName(for: mealDefaults),
                container: mealContainer
            )
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
            try RebuildMigrationCoordinator(
                defaults: photoDefaults,
                legacyDefaultsDomainName: domainName(for: photoDefaults),
                container: photoContainer
            )
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
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container
            )
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
                legacyDefaultsDomainName: domainName(for: rootDefaults),
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
                legacyDefaultsDomainName: domainName(for: sourceSymlinkDefaults),
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }

        let seedDefaults = makeDefaults()
        MealPhotoMetadataStore(defaults: seedDefaults).save([photo])
        let seedContainer = try RebuildPersistentStore.makeInMemory()
        _ = try RebuildMigrationCoordinator(
            defaults: seedDefaults,
            legacyDefaultsDomainName: domainName(for: seedDefaults),
            container: seedContainer,
            legacyPhotoDirectory: sourceDirectory,
            rebuildPhotoDirectory: targetDirectory
        ).runIfNeeded(targetVersion: 1)
        let relativePath = try XCTUnwrap(
            fetch(
                RebuildMealPhotoManagedObject.self,
                RebuildEntityName.mealPhoto,
                in: seedContainer.viewContext
            ).first?.relativePath
        )
        try Data("stale target".utf8)
            .write(to: targetDirectory.appendingPathComponent(relativePath))
        let staleDefaults = makeDefaults()
        MealPhotoMetadataStore(defaults: staleDefaults).save([photo])

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: staleDefaults,
                legacyDefaultsDomainName: domainName(for: staleDefaults),
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
                legacyDefaultsDomainName: domainName(for: targetLeafDefaults),
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
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container
            )
                .runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? RebuildMigrationError, .xpOverflow)
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
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
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container
            )
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
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                verify: { _ in throw TestFailure.verification }
            ).runIfNeeded(targetVersion: 1)
        )
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        let cachedURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: targetDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        XCTAssertEqual(try Data(contentsOf: cachedURL), data)
        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName(for: defaults),
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(try count(RebuildEntityName.mealPhoto, in: container.viewContext), 1)
        XCTAssertEqual(try count(RebuildEntityName.migrationState, in: container.viewContext), 1)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: targetDirectory,
                includingPropertiesForKeys: nil
            ),
            [cachedURL]
        )
        XCTAssertEqual(try Data(contentsOf: sourceURL), data)
    }

    func testFailedMigrationNeverDeletesReplacementAtCachedPhotoPath() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "replacement-photo",
            fileName: "replacement.jpg",
            createdAt: Date(timeIntervalSince1970: 1_000),
            isSharedWithParent: false
        )
        let sourceData = Data("migration-owned".utf8)
        let replacementData = Data("replacement-owned-elsewhere".utf8)
        try sourceData.write(
            to: sourceDirectory.appendingPathComponent(photo.fileName)
        )
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let container = try RebuildPersistentStore.makeInMemory()
        let replacedURL = MigrationLockedBox<URL?>(nil)

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                verify: { _ in
                    let leaf = try XCTUnwrap(
                        FileManager.default.contentsOfDirectory(
                            at: targetDirectory,
                            includingPropertiesForKeys: nil
                        ).first
                    )
                    try FileManager.default.removeItem(at: leaf)
                    try replacementData.write(to: leaf)
                    replacedURL.withValue { $0 = leaf }
                    throw TestFailure.verification
                }
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? TestFailure, .verification)
        }
        let replacementURL = try XCTUnwrap(replacedURL.value)
        XCTAssertEqual(try Data(contentsOf: replacementURL), replacementData)
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
    }

    func testFailedMigrationNeverDeletesMatchingTargetAdoptedAfterEEXIST() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "adopted-photo",
            fileName: "adopted.jpg",
            createdAt: Date(timeIntervalSince1970: 1_100),
            isSharedWithParent: false
        )
        let data = Data("already durable".utf8)
        try data.write(to: sourceDirectory.appendingPathComponent(photo.fileName))
        MealPhotoMetadataStore(defaults: defaults).save([photo])

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let adoptedURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: targetDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        let retryContainer = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: retryContainer,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                verify: { _ in throw TestFailure.verification }
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? TestFailure, .verification)
        }
        XCTAssertEqual(try Data(contentsOf: adoptedURL), data)
        XCTAssertEqual(try totalObjectCount(in: retryContainer.viewContext), 0)
    }

    func testOverlappingInProgressAndLaterCompletedCallsDoNotClearWarnings() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        MealPhotoMetadataStore(defaults: defaults).save([
            MealPhotoRecord(
                id: "queued-warning",
                fileName: "missing.jpg",
                createdAt: Date(timeIntervalSince1970: 1_200),
                isSharedWithParent: false
            )
        ])
        let verifyEntered = DispatchSemaphore(value: 0)
        let secondStarted = DispatchSemaphore(value: 0)
        let results = MigrationLockedBox<[Result<MigrationOutcome, Error>]>([])
        let group = DispatchGroup()
        let coordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            legacyDefaultsDomainName: domainName,
            container: try RebuildPersistentStore.makeInMemory(),
            legacyPhotoDirectory: makeDirectory(),
            rebuildPhotoDirectory: makeDirectory(),
            verify: { _ in
                verifyEntered.signal()
                XCTAssertEqual(
                    secondStarted.wait(timeout: .now() + 2),
                    .success
                )
            }
        )

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try coordinator.runIfNeeded(targetVersion: 1)
            }
            results.withValue { $0.append(result) }
            group.leave()
        }
        XCTAssertEqual(verifyEntered.wait(timeout: .now() + 2), .success)
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            secondStarted.signal()
            let result = Result {
                try coordinator.runIfNeeded(targetVersion: 1)
            }
            results.withValue { $0.append(result) }
            group.leave()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        let outcomes = results.value.compactMap { try? $0.get() }
        XCTAssertEqual(outcomes.filter { $0 == .migrated }.count, 1)
        let migrationErrors = results.value.compactMap { result -> RebuildMigrationError? in
            guard case let .failure(error) = result else {
                return nil
            }
            return error as? RebuildMigrationError
        }
        XCTAssertEqual(migrationErrors, [.migrationInProgress])
        XCTAssertEqual(
            try coordinator.runIfNeeded(targetVersion: 1),
            .alreadyCompleted
        )
        XCTAssertEqual(
            coordinator.warnings,
            [.missingPhotoFile(photoID: "queued-warning", fileName: "missing.jpg")]
        )
    }

    func testSourceAndTargetDirectoryAncestorSymlinksAreRejected() throws {
        let root = makeDirectory()
        let outside = makeDirectory()
        let sourceThroughLink = root.appendingPathComponent("source-link/source")
        let outsideSource = outside.appendingPathComponent("source")
        try FileManager.default.createDirectory(
            at: outsideSource,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("source-link"),
            withDestinationURL: outside
        )
        let photo = MealPhotoRecord(
            id: "ancestor-symlink",
            fileName: "photo.jpg",
            createdAt: Date(timeIntervalSince1970: 1_300),
            isSharedWithParent: false
        )
        try Data("outside source".utf8).write(
            to: outsideSource.appendingPathComponent(photo.fileName)
        )
        let (sourceDefaults, sourceDomain) = makeDefaultsWithDomain()
        MealPhotoMetadataStore(defaults: sourceDefaults).save([photo])

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: sourceDefaults,
                legacyDefaultsDomainName: sourceDomain,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceThroughLink,
                rebuildPhotoDirectory: makeDirectory()
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }

        let directSource = makeDirectory()
        try Data("trusted source".utf8).write(
            to: directSource.appendingPathComponent(photo.fileName)
        )
        let targetOutside = makeDirectory()
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("target-link"),
            withDestinationURL: targetOutside
        )
        let targetThroughLink = root.appendingPathComponent("target-link/nested")
        let (targetDefaults, targetDomain) = makeDefaultsWithDomain()
        MealPhotoMetadataStore(defaults: targetDefaults).save([photo])

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: targetDefaults,
                legacyDefaultsDomainName: targetDomain,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: directSource,
                rebuildPhotoDirectory: targetThroughLink
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            guard case .unsafePhotoPath = error as? RebuildMigrationError else {
                return XCTFail("Expected unsafePhotoPath, got \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: targetOutside.appendingPathComponent("nested").path
            )
        )
    }

    func testDefaultPhotoDirectoriesCanonicalizePlatformDocumentContainerBase() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let root = makeDirectory()
        let realDocuments = root.appendingPathComponent("real-documents")
        try FileManager.default.createDirectory(
            at: realDocuments,
            withIntermediateDirectories: true
        )
        let aliasedDocuments = root.appendingPathComponent("documents-alias")
        try FileManager.default.createSymbolicLink(
            at: aliasedDocuments,
            withDestinationURL: realDocuments
        )
        let sourceDirectory = realDocuments.appendingPathComponent("MealPhotos")
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let photo = MealPhotoRecord(
            id: "canonical-default-base",
            fileName: "canonical.jpg",
            createdAt: Date(timeIntervalSince1970: 1_250),
            isSharedWithParent: false
        )
        let data = Data("canonical container".utf8)
        try data.write(to: sourceDirectory.appendingPathComponent(photo.fileName))
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let fileManager = DocumentDirectoryFileManager(
            documentDirectory: aliasedDocuments
        )
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                fileManager: fileManager
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let cachedFiles = try FileManager.default.contentsOfDirectory(
            at: realDocuments.appendingPathComponent("RebuildMealPhotos"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(cachedFiles.count, 1)
        XCTAssertEqual(try Data(contentsOf: cachedFiles[0]), data)
    }

    func testCreatingTargetComponentsSyncsEachParentDirectory() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let sourceDirectory = makeDirectory()
        let targetRoot = makeDirectory()
        let targetDirectory = targetRoot
            .appendingPathComponent("first")
            .appendingPathComponent("second")
        let photo = MealPhotoRecord(
            id: "mkdir-sync",
            fileName: "mkdir-sync.jpg",
            createdAt: Date(timeIntervalSince1970: 1_260),
            isSharedWithParent: false
        )
        try Data("directory durability".utf8).write(
            to: sourceDirectory.appendingPathComponent(photo.fileName)
        )
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let parentSyncCount = MigrationLockedBox(0)

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: RebuildPersistentStore.makeInMemory(),
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                syncCreatedDirectoryParent: { descriptor in
                    let path = try migrationDescriptorPath(descriptor)
                    if path == targetRoot.path
                        || path == targetDirectory.deletingLastPathComponent().path {
                        parentSyncCount.withValue { $0 += 1 }
                    }
                }
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(parentSyncCount.value, 2)
    }

    func testRetryResyncsRetainedCreatedDirectoryParentBeforeCompletion() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let sourceDirectory = makeDirectory()
        let targetRoot = makeDirectory()
        let retainedDirectory = targetRoot.appendingPathComponent("retained")
        let targetDirectory = retainedDirectory.appendingPathComponent("final")
        let photo = MealPhotoRecord(
            id: "mkdir-retry-sync",
            fileName: "mkdir-retry-sync.jpg",
            createdAt: Date(timeIntervalSince1970: 1_270),
            isSharedWithParent: false
        )
        try Data("retry directory durability".utf8).write(
            to: sourceDirectory.appendingPathComponent(photo.fileName)
        )
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let container = try RebuildPersistentStore.makeInMemory()
        let failRetainedParentSync: RebuildMigrationDirectorySync = { descriptor in
            if try migrationDescriptorPath(descriptor) == targetRoot.path {
                throw TestFailure.directorySync
            }
        }

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                syncCreatedDirectoryParent: failRetainedParentSync
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? TestFailure, .directorySync)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: retainedDirectory.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: targetDirectory.path)
        )
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                syncCreatedDirectoryParent: failRetainedParentSync
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? TestFailure, .directorySync)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: targetDirectory.path)
        )
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)

        let retrySyncedParents = MigrationLockedBox<[String]>([])
        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                syncCreatedDirectoryParent: { descriptor in
                    let path = try migrationDescriptorPath(descriptor)
                    retrySyncedParents.withValue {
                        $0.append(path)
                    }
                }
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertTrue(retrySyncedParents.value.contains(targetRoot.path))
    }

    func testAssociationRemovesOnlyASCIISpaceAndPreservesUnicodeWhitespace() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let nonBreakingSpace = "\u{00A0}"
        let spacedName = "Bean\(nonBreakingSpace)Rice"
        MealRecordStore(defaults: defaults).save([
            MealRecord(
                date: "2026-07-25",
                menuName: spacedName,
                eatingStatus: .oneBite
            ),
            MealRecord(
                date: "2026-07-25",
                menuName: "BeanRice",
                eatingStatus: .oneBite
            ),
        ])
        ChallengeStore(defaults: defaults).save([
            ChallengeRecord(
                date: "2026-07-25",
                menuName: "Bean Rice",
                action: .oneBite,
                gainedExp: 5,
                badgeName: nil,
                nutrients: [],
                eatingStatus: .oneBite,
                xpBreakdown: XPBreakdown(challenge: 5)
            )
        ])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let meals = try fetch(
            RebuildMealRecordManagedObject.self,
            RebuildEntityName.mealRecord,
            in: container.viewContext
        )
        XCTAssertEqual(meals.count, 2)
        XCTAssertTrue(
            meals.contains {
                $0.id == "2026-07-25|bean\(nonBreakingSpace)rice|oneBite"
            }
        )
        let events = try fetch(
            RebuildProgressEventManagedObject.self,
            RebuildEntityName.progressEvent,
            in: container.viewContext
        )
        XCTAssertNotNil(
            events.first { $0.id == "meal:2026-07-25|beanrice|oneBite" }
        )
        XCTAssertNil(
            events.first {
                $0.id == "meal:2026-07-25|bean\(nonBreakingSpace)rice|oneBite"
            }
        )
    }

    func testAssociationTrimsEdgeUnicodeWhitespaceBeforeLegacyMatching() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let nonBreakingSpace = "\u{00A0}"
        MealRecordStore(defaults: defaults).save([
            MealRecord(
                date: "2026-07-25",
                menuName: "\(nonBreakingSpace)Bean Rice\(nonBreakingSpace)",
                eatingStatus: .oneBite
            )
        ])
        ChallengeStore(defaults: defaults).save([
            ChallengeRecord(
                date: "2026-07-25",
                menuName: "BeanRice",
                action: .oneBite,
                gainedExp: 5,
                badgeName: nil,
                nutrients: [],
                eatingStatus: .oneBite,
                xpBreakdown: XPBreakdown(challenge: 5)
            )
        ])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let meals = try fetch(
            RebuildMealRecordManagedObject.self,
            RebuildEntityName.mealRecord,
            in: container.viewContext
        )
        XCTAssertEqual(meals.first?.id, "2026-07-25|bean rice|oneBite")
        XCTAssertEqual(meals.first?.normalizedMenuName, "bean rice")
        let events = try fetch(
            RebuildProgressEventManagedObject.self,
            RebuildEntityName.progressEvent,
            in: container.viewContext
        )
        XCTAssertNotNil(
            events.first { $0.id == "meal:2026-07-25|bean rice|oneBite" }
        )
        XCTAssertNil(
            events.first { $0.id == "meal:2026-07-25|beanrice|oneBite" }
        )
    }

    func testAssociationParityTrimsTabsAndNewlinesOnlyAtEdges() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        MealRecordStore(defaults: defaults).save([
            MealRecord(
                date: "2026-07-25",
                menuName: "\t Bean Rice \n",
                eatingStatus: .oneBite
            )
        ])
        ChallengeStore(defaults: defaults).save([
            ChallengeRecord(
                date: "2026-07-25",
                menuName: "BEANRICE",
                action: .oneBite,
                gainedExp: 5,
                badgeName: nil,
                nutrients: [],
                eatingStatus: .oneBite,
                xpBreakdown: XPBreakdown(challenge: 5)
            )
        ])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let event = try XCTUnwrap(
            fetch(
                RebuildProgressEventManagedObject.self,
                RebuildEntityName.progressEvent,
                in: container.viewContext
            ).first
        )
        XCTAssertEqual(event.id, "meal:2026-07-25|bean rice|oneBite")
    }

    func testOldChallengePayloadHasStableDigestIdentityAndTimestampAcrossRetry() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        defaults.set(
            Data("""
            [
              {
                "date": "2026-07-25",
                "menuName": "Old Payload",
                "action": "oneBite",
                "gainedExp": 7,
                "badgeName": null,
                "nutrients": []
              }
            ]
            """.utf8),
            forKey: LegacyDefaultsReader.Key.challenges
        )
        let reader = LegacyDefaultsReader(
            defaults: defaults,
            persistentDomainName: domainName
        )
        let firstSnapshot = try reader.readSnapshot()
        let secondSnapshot = try reader.readSnapshot()
        XCTAssertEqual(
            try reader.sourceDigest(for: firstSnapshot),
            try reader.sourceDigest(for: secondSnapshot)
        )
        XCTAssertEqual(firstSnapshot.challenges.first?.id, secondSnapshot.challenges.first?.id)
        XCTAssertEqual(
            firstSnapshot.challenges.first?.createdAt,
            secondSnapshot.challenges.first?.createdAt
        )

        let container = try RebuildPersistentStore.makeInMemory()
        let failedEvent = MigrationLockedBox<(String, Date)?>(nil)
        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                save: { context in
                    let request = NSFetchRequest<RebuildProgressEventManagedObject>(
                        entityName: RebuildEntityName.progressEvent
                    )
                    let event = try XCTUnwrap(context.fetch(request).first)
                    failedEvent.withValue {
                        $0 = (event.sourceRecordID ?? "", event.occurredAt)
                    }
                    throw TestFailure.save
                }
            ).runIfNeeded(targetVersion: 1)
        )
        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let migratedEvent = try XCTUnwrap(
            fetch(
                RebuildProgressEventManagedObject.self,
                RebuildEntityName.progressEvent,
                in: container.viewContext
            ).first
        )
        XCTAssertEqual(failedEvent.value?.0, migratedEvent.sourceRecordID)
        XCTAssertEqual(failedEvent.value?.1, migratedEvent.occurredAt)
    }

    func testMigrationChallengeDecodePreservesExplicitRawNegativeXPComponents() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        defaults.set(
            Data("""
            [
              {
                "id": "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB",
                "date": "2026-07-25",
                "menuName": "Raw XP",
                "action": "oneBite",
                "gainedExp": 99,
                "badgeName": null,
                "nutrients": [],
                "createdAt": "2026-07-25T00:00:00Z",
                "recordExp": -7,
                "challengeExp": 3,
                "safetyExp": -2
              }
            ]
            """.utf8),
            forKey: LegacyDefaultsReader.Key.challenges
        )
        let runtimeRecord = try XCTUnwrap(
            ChallengeStore(defaults: defaults).load().first
        )
        XCTAssertEqual(
            [
                runtimeRecord.recordExp,
                runtimeRecord.challengeExp,
                runtimeRecord.balanceExp,
                runtimeRecord.safetyExp,
            ],
            [-7, 3, 0, -2]
        )
        let reader = LegacyDefaultsReader(
            defaults: defaults,
            persistentDomainName: domainName
        )
        let snapshot = try reader.readSnapshot()
        let migrationRecord = try XCTUnwrap(snapshot.challenges.first)
        XCTAssertEqual(
            [
                migrationRecord.recordExp,
                migrationRecord.challengeExp,
                migrationRecord.balanceExp,
                migrationRecord.safetyExp,
            ],
            [-7, 3, 0, -2]
        )
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        let event = try XCTUnwrap(
            fetch(
                RebuildProgressEventManagedObject.self,
                RebuildEntityName.progressEvent,
                in: container.viewContext
            ).first
        )
        XCTAssertEqual(event.amount, -6)
    }

    func testSynchronousReentryFailsFastWithoutDeadlockOrCorruption() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        UserProfileStore(defaults: defaults).save(makeProfile())
        let container = try RebuildPersistentStore.makeInMemory()
        let reentryError = MigrationLockedBox<RebuildMigrationError?>(nil)
        var coordinator: RebuildMigrationCoordinator!
        coordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            legacyDefaultsDomainName: domainName,
            container: container,
            save: { context in
                do {
                    _ = try coordinator.runIfNeeded(targetVersion: 1)
                    XCTFail("Synchronous re-entry unexpectedly succeeded")
                } catch {
                    reentryError.withValue {
                        $0 = error as? RebuildMigrationError
                    }
                }
                try context.save()
            }
        )

        XCTAssertEqual(try coordinator.runIfNeeded(targetVersion: 1), .migrated)
        XCTAssertEqual(reentryError.value, .migrationInProgress)
        XCTAssertEqual(try count(RebuildEntityName.profile, in: container.viewContext), 1)
        XCTAssertEqual(try count(RebuildEntityName.migrationState, in: container.viewContext), 1)
    }

    func testCrossThreadCallbackReentryFailsFastWithoutDeadlock() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        UserProfileStore(defaults: defaults).save(makeProfile())
        let container = try RebuildPersistentStore.makeInMemory()
        let callbackResult = MigrationLockedBox<Result<MigrationOutcome, Error>?>(nil)
        var coordinator: RebuildMigrationCoordinator!
        coordinator = RebuildMigrationCoordinator(
            defaults: defaults,
            legacyDefaultsDomainName: domainName,
            container: container,
            verify: { _ in
                let finished = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result {
                        try coordinator.runIfNeeded(targetVersion: 1)
                    }
                    callbackResult.withValue { $0 = result }
                    finished.signal()
                }
                XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
            }
        )

        XCTAssertEqual(try coordinator.runIfNeeded(targetVersion: 1), .migrated)
        guard case let .failure(error)? = callbackResult.value else {
            return XCTFail("Expected fail-fast callback re-entry error")
        }
        XCTAssertEqual(error as? RebuildMigrationError, .migrationInProgress)
        XCTAssertEqual(try count(RebuildEntityName.migrationState, in: container.viewContext), 1)
    }

    func testInjectedSuiteWithoutExplicitPersistentDomainIsRejected() throws {
        let defaults = makeDefaults()
        UserProfileStore(defaults: defaults).save(makeProfile())
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                container: container
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(
                error as? RebuildMigrationError,
                .missingPersistentDefaultsDomain
            )
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
    }

    func testPhotoReferencedByMultipleMealsIsRejectedAsAmbiguous() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        MealRecordStore(defaults: defaults).save([
            MealRecord(
                date: "2026-07-25",
                menuName: "First",
                eatingStatus: .oneBite,
                photoIds: ["shared-photo"]
            ),
            MealRecord(
                date: "2026-07-25",
                menuName: "Second",
                eatingStatus: .oneBite,
                photoIds: ["shared-photo"]
            ),
        ])
        MealPhotoMetadataStore(defaults: defaults).save([
            MealPhotoRecord(
                id: "shared-photo",
                fileName: "missing.jpg",
                createdAt: Date(timeIntervalSince1970: 1_400),
                isSharedWithParent: false
            )
        ])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(
                error as? RebuildMigrationError,
                .ambiguousPhotoReference("shared-photo")
            )
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
    }

    func testTargetDirectorySyncFailureKeepsAppendOnlyPhotoForRetry() throws {
        let (defaults, domainName) = makeDefaultsWithDomain()
        let sourceDirectory = makeDirectory()
        let targetDirectory = makeDirectory()
        let photo = MealPhotoRecord(
            id: "directory-sync",
            fileName: "directory-sync.jpg",
            createdAt: Date(timeIntervalSince1970: 1_500),
            isSharedWithParent: false
        )
        try Data("sync before marker".utf8).write(
            to: sourceDirectory.appendingPathComponent(photo.fileName)
        )
        MealPhotoMetadataStore(defaults: defaults).save([photo])
        let container = try RebuildPersistentStore.makeInMemory()

        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                syncTargetDirectory: { _ in throw TestFailure.directorySync }
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? TestFailure, .directorySync)
        }
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path).count,
            1
        )
        let failedReuseSyncCount = MigrationLockedBox(0)
        XCTAssertThrowsError(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                syncTargetDirectory: { _ in
                    failedReuseSyncCount.withValue { $0 += 1 }
                    throw TestFailure.directorySync
                }
            ).runIfNeeded(targetVersion: 1)
        ) { error in
            XCTAssertEqual(error as? TestFailure, .directorySync)
        }
        XCTAssertEqual(failedReuseSyncCount.value, 1)
        XCTAssertEqual(try totalObjectCount(in: container.viewContext), 0)

        let successfulReuseSyncCount = MigrationLockedBox(0)
        XCTAssertEqual(
            try RebuildMigrationCoordinator(
                defaults: defaults,
                legacyDefaultsDomainName: domainName,
                container: container,
                legacyPhotoDirectory: sourceDirectory,
                rebuildPhotoDirectory: targetDirectory,
                syncTargetDirectory: { _ in
                    successfulReuseSyncCount.withValue { $0 += 1 }
                }
            ).runIfNeeded(targetVersion: 1),
            .migrated
        )
        XCTAssertEqual(successfulReuseSyncCount.value, 1)
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
        domainNamesByDefaults[ObjectIdentifier(defaults)] = name
        return (defaults, name)
    }

    private func domainName(
        for defaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        guard let domainName = domainNamesByDefaults[ObjectIdentifier(defaults)] else {
            XCTFail("Missing explicit defaults domain for test fixture", file: file, line: line)
            return ""
        }
        return domainName
    }

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RebuildMigrationCoordinatorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let resolvedURL = url.resolvingSymlinksInPath()
        cleanupURLs.append(resolvedURL)
        return resolvedURL
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
    case directorySync
}

private func migrationDescriptorPath(_ descriptor: Int32) throws -> String {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return String(cString: buffer)
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

private final class DocumentDirectoryFileManager: FileManager, @unchecked Sendable {
    private let documentDirectory: URL

    init(documentDirectory: URL) {
        self.documentDirectory = documentDirectory
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .documentDirectory, domainMask == .userDomainMask {
            return [documentDirectory]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
