import CoreData
import CryptoKit
import Darwin
import Foundation

enum MigrationOutcome: Equatable {
    case noLegacyData
    case migrated
    case alreadyCompleted
}

enum MigrationWarning: Equatable {
    case missingPhotoFile(photoID: String, fileName: String)
}

enum RebuildMigrationError: Error, Equatable {
    case unsupportedTargetVersion(Int)
    case verificationMismatch(field: String, expected: Int64, actual: Int64)
    case mealIdentityCollision(String)
    case photoIDCollision(String)
    case progressEventIdentityCollision(String)
    case ambiguousPhotoReference(String)
    case unsafePhotoPath(String)
    case photoContentMismatch(String)
    case photoIOFailure(operation: String, path: String, code: Int32)
    case temporaryPhotoCleanupFailed(path: String, originalFailure: String)
    case missingPersistentDefaultsDomain
    case migrationInProgress
    case unexpectedManagedObjectType(String)
    case xpOverflow
}

struct MigrationVerification: Equatable {
    let profileCount: Int
    let mealRecordCount: Int
    let photoCount: Int
    let totalXP: Int64
}

typealias RebuildMigrationVerifier = (MigrationVerification) throws -> Void
typealias RebuildMigrationSaver = (NSManagedObjectContext) throws -> Void
typealias RebuildMigrationDirectorySync = (Int32) throws -> Void

private struct MigratedMealRecords {
    let recordsByIdentity: [String: MealRecord]
    let identityByAssociationKey: [String: String]
}

private struct NormalizedLegacyMealName {
    let canonical: String
    let associationKey: String
}

final class RebuildMigrationCoordinator {
    private static let supportedTargetVersion = 1
    private static let reconciliationEventID = "legacy:progress-reconciliation"
    private static let admissionLock = NSLock()
    private static var attemptIsActive = false

    private let reader: LegacyDefaultsReader?
    private let container: NSPersistentContainer
    private let legacyPhotoDirectory: URL
    private let rebuildPhotoDirectory: URL
    private let now: () -> Date
    private let verify: RebuildMigrationVerifier
    private let save: RebuildMigrationSaver
    private let syncTargetDirectory: RebuildMigrationDirectorySync?
    private let syncCreatedDirectoryParent: RebuildMigrationDirectorySync?
    private let warningsLock = NSLock()
    private var publishedWarnings: [MigrationWarning] = []

    var warnings: [MigrationWarning] {
        warningsLock.lock()
        defer { warningsLock.unlock() }
        return publishedWarnings
    }

    init(
        defaults: UserDefaults = .standard,
        legacyDefaultsDomainName: String? = nil,
        container: NSPersistentContainer,
        legacyPhotoDirectory: URL? = nil,
        rebuildPhotoDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        verify: @escaping RebuildMigrationVerifier = { _ in },
        save: @escaping RebuildMigrationSaver = { try $0.save() },
        syncTargetDirectory: RebuildMigrationDirectorySync? = nil,
        syncCreatedDirectoryParent: RebuildMigrationDirectorySync? = nil
    ) {
        let domainName = legacyDefaultsDomainName
            ?? (defaults === UserDefaults.standard ? Bundle.main.bundleIdentifier : nil)
        reader = domainName.map {
            LegacyDefaultsReader(defaults: defaults, persistentDomainName: $0)
        }
        self.container = container
        let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].resolvingSymlinksInPath()
        self.legacyPhotoDirectory = legacyPhotoDirectory
            ?? documents.appendingPathComponent("MealPhotos", isDirectory: true)
        self.rebuildPhotoDirectory = rebuildPhotoDirectory
            ?? documents.appendingPathComponent("RebuildMealPhotos", isDirectory: true)
        self.now = now
        self.verify = verify
        self.save = save
        self.syncTargetDirectory = syncTargetDirectory
        self.syncCreatedDirectoryParent = syncCreatedDirectoryParent
    }

    func runIfNeeded(targetVersion: Int = 1) throws -> MigrationOutcome {
        Self.admissionLock.lock()
        guard !Self.attemptIsActive else {
            Self.admissionLock.unlock()
            throw RebuildMigrationError.migrationInProgress
        }
        Self.attemptIsActive = true
        Self.admissionLock.unlock()
        defer {
            Self.admissionLock.lock()
            Self.attemptIsActive = false
            Self.admissionLock.unlock()
        }
        return try runSerialized(targetVersion: targetVersion)
    }

    private func runSerialized(targetVersion: Int) throws -> MigrationOutcome {
        guard targetVersion == Self.supportedTargetVersion else {
            throw RebuildMigrationError.unsupportedTargetVersion(targetVersion)
        }

        guard let reader else {
            throw RebuildMigrationError.missingPersistentDefaultsDomain
        }
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "legacy-defaults-migration-v\(targetVersion)"

        if try completedVersion(in: context) >= targetVersion {
            return .alreadyCompleted
        }

        let snapshot = try reader.readSnapshot()
        guard snapshot.hasLegacyData else {
            return .noLegacyData
        }
        try validateSourceIdentities(snapshot)
        let sourceDigest = try reader.sourceDigest(for: snapshot)
        var attemptWarnings: [MigrationWarning] = []

        let outcome: MigrationOutcome = try context.performAndWait {
            do {
                let mappedProfile = try insertProfile(from: snapshot, into: context)
                let mappedMeals = try insertMealRecords(snapshot.mealRecords, into: context)
                try insertParentLinks(from: snapshot, into: context)
                try insertPhotos(
                    snapshot.mealPhotoRecords,
                    mealRecords: mappedMeals,
                    into: context,
                    warnings: &attemptWarnings
                )
                try insertProgressEvents(
                    from: snapshot,
                    mealRecords: mappedMeals,
                    into: context
                )

                let expectedXP = try expectedXP(from: snapshot)
                let verification = try verifyInsertedRows(
                    expectedProfileCount: mappedProfile == nil ? 0 : 1,
                    expectedMealCount: snapshot.mealRecords.count,
                    expectedPhotoCount: snapshot.mealPhotoRecords.count,
                    expectedXP: expectedXP,
                    in: context
                )
                try verify(verification)
                try insertMigrationState(
                    version: targetVersion,
                    sourceDigest: sourceDigest,
                    into: context
                )
                try save(context)
                return .migrated
            } catch {
                context.rollback()
                throw error
            }
        }
        publishWarnings(attemptWarnings)
        return outcome
    }

    private func completedVersion(in context: NSManagedObjectContext) throws -> Int {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildMigrationStateManagedObject>(
                entityName: RebuildEntityName.migrationState
            )
            request.predicate = NSPredicate(
                format: "id == %@",
                RebuildMigrationStateRepository.stateID
            )
            request.fetchLimit = 1
            return try context.fetch(request).first.map { Int($0.version) } ?? 0
        }
    }

    private func validateSourceIdentities(_ snapshot: LegacySnapshot) throws {
        var mealIdentities = Set<String>()
        var mealAssociationKeys: [String: String] = [:]
        var mealIdentityByPhotoID: [String: String] = [:]
        for record in snapshot.mealRecords {
            let normalizedName = normalizeMenuName(record.menuName)
            let identity = recordIdentity(
                date: record.date,
                normalizedMenuName: normalizedName.canonical,
                status: record.eatingStatus.rawValue
            )
            guard mealIdentities.insert(identity).inserted else {
                throw RebuildMigrationError.mealIdentityCollision(identity)
            }
            let associationKey = mealAssociationKey(
                date: record.date,
                normalizedName: normalizedName,
                status: record.eatingStatus.rawValue
            )
            if let previousIdentity = mealAssociationKeys[associationKey] {
                throw RebuildMigrationError.mealIdentityCollision(previousIdentity)
            }
            mealAssociationKeys[associationKey] = identity
            for photoID in Set(record.photoIds) {
                if let previousIdentity = mealIdentityByPhotoID[photoID],
                   previousIdentity != identity {
                    throw RebuildMigrationError.ambiguousPhotoReference(photoID)
                }
                mealIdentityByPhotoID[photoID] = identity
            }
        }

        var photoIDs = Set<String>()
        for photo in snapshot.mealPhotoRecords {
            guard photoIDs.insert(photo.id).inserted else {
                throw RebuildMigrationError.photoIDCollision(photo.id)
            }
        }

        var eventIDs = Set<String>()
        for challenge in snapshot.challenges {
            let status = challenge.eatingStatus ?? status(for: challenge.action)
            let normalizedName = normalizeMenuName(challenge.menuName)
            let associationKey = mealAssociationKey(
                date: challenge.date,
                normalizedName: normalizedName,
                status: status.rawValue
            )
            let identity = mealAssociationKeys[associationKey]
                ?? recordIdentity(
                    date: challenge.date,
                    normalizedMenuName: normalizedName.canonical,
                    status: status.rawValue
                )
            let eventID = "meal:\(identity)"
            guard eventIDs.insert(eventID).inserted else {
                throw RebuildMigrationError.progressEventIdentityCollision(eventID)
            }
        }
    }

    @discardableResult
    private func insertProfile(
        from snapshot: LegacySnapshot,
        into context: NSManagedObjectContext
    ) throws -> RebuildProfileManagedObject? {
        if let profile = snapshot.profile {
            let object = try insert(
                RebuildProfileManagedObject.self,
                entityName: RebuildEntityName.profile,
                into: context
            )
            object.id = profile.id.uuidString
            object.role = profile.effectiveMode == .parent ? "parent" : "child"
            object.nickname = profile.nickname
            object.officeCode = profile.officeCode.nilIfEmpty
            object.schoolCode = profile.schoolCode.nilIfEmpty
            object.allergyCodesJSON = try encodeJSON(profile.selectedAllergyCodes.sorted())
            return object
        }

        guard snapshot.hasStoredParentProfile else {
            return nil
        }
        let object = try insert(
            RebuildProfileManagedObject.self,
            entityName: RebuildEntityName.profile,
            into: context
        )
        object.id = snapshot.parentProfile.id.uuidString
        object.role = "parent"
        object.nickname = snapshot.parentProfile.nickname
        object.officeCode = nil
        object.schoolCode = nil
        object.allergyCodesJSON = "[]"
        return object
    }

    private func insertMealRecords(
        _ records: [MealRecord],
        into context: NSManagedObjectContext
    ) throws -> MigratedMealRecords {
        var recordsByIdentity: [String: MealRecord] = [:]
        var identityByAssociationKey: [String: String] = [:]
        for record in records {
            let normalizedName = normalizeMenuName(record.menuName)
            let identity = recordIdentity(
                date: record.date,
                normalizedMenuName: normalizedName.canonical,
                status: record.eatingStatus.rawValue
            )
            recordsByIdentity[identity] = record
            identityByAssociationKey[
                mealAssociationKey(
                    date: record.date,
                    normalizedName: normalizedName,
                    status: record.eatingStatus.rawValue
                )
            ] = identity
            let object = try insert(
                RebuildMealRecordManagedObject.self,
                entityName: RebuildEntityName.mealRecord,
                into: context
            )
            object.id = identity
            object.date = record.date
            object.menuName = record.menuName
            object.normalizedMenuName = normalizedName.canonical
            object.status = record.eatingStatus.rawValue
            object.difficultyReasonsJSON = try encodeJSON(
                record.difficultyReasons.map(\.rawValue)
            )
            object.allergyCodesJSON = try encodeJSON(record.allergyCodes)
            object.photoIDsJSON = try encodeJSON(record.photoIds)
            object.parentShareEnabled = record.parentShareEnabled
            object.updatedAt = record.createdAt
            object.deletedAt = nil
        }
        return MigratedMealRecords(
            recordsByIdentity: recordsByIdentity,
            identityByAssociationKey: identityByAssociationKey
        )
    }

    private func insertParentLinks(
        from snapshot: LegacySnapshot,
        into context: NSManagedObjectContext
    ) throws {
        var links: [UUID: ChildLink] = [:]
        var linkIDByInviteCode: [String: UUID] = [:]

        func upsert(_ link: ChildLink) {
            let normalizedInviteCode = CloudKitParentLinkService()
                .normalizeInviteCode(link.inviteCode)
            if let previous = links[link.id] {
                let previousCode = CloudKitParentLinkService()
                    .normalizeInviteCode(previous.inviteCode)
                if linkIDByInviteCode[previousCode] == link.id {
                    linkIDByInviteCode.removeValue(forKey: previousCode)
                }
            }
            if !normalizedInviteCode.isEmpty,
               let duplicateID = linkIDByInviteCode[normalizedInviteCode],
               duplicateID != link.id {
                links.removeValue(forKey: duplicateID)
            }
            var normalizedLink = link
            normalizedLink.inviteCode = normalizedInviteCode
            links[link.id] = normalizedLink
            if !normalizedInviteCode.isEmpty {
                linkIDByInviteCode[normalizedInviteCode] = link.id
            }
        }

        if snapshot.hasStoredParentProfile {
            for link in snapshot.parentProfile.childLinks {
                upsert(link)
            }
        }
        if let childLink = snapshot.childLink {
            upsert(childLink)
        }

        for link in links.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let object = try insert(
                RebuildParentLinkManagedObject.self,
                entityName: RebuildEntityName.parentLink,
                into: context
            )
            object.id = link.id.uuidString
            object.inviteCode = link.inviteCode
            object.connectionState = link.parentConnectedAt == nil ? "invitePending" : "connected"
            object.connectedAt = link.parentConnectedAt
        }
    }

    private func insertPhotos(
        _ photos: [MealPhotoRecord],
        mealRecords: MigratedMealRecords,
        into context: NSManagedObjectContext,
        warnings: inout [MigrationWarning]
    ) throws {
        let sortedMealRecords = mealRecords.recordsByIdentity.sorted { $0.key < $1.key }

        for photo in photos {
            let relativePath = try migratePhotoFile(
                photo,
                warnings: &warnings
            )
            let object = try insert(
                RebuildMealPhotoManagedObject.self,
                entityName: RebuildEntityName.mealPhoto,
                into: context
            )
            object.id = photo.id
            object.recordID = sortedMealRecords.first {
                $0.value.photoIds.contains(photo.id)
            }?.key ?? orphanPhotoRecordID(photoID: photo.id)
            object.relativePath = relativePath
            object.createdAt = photo.createdAt
        }
    }

    private func insertProgressEvents(
        from snapshot: LegacySnapshot,
        mealRecords: MigratedMealRecords,
        into context: NSManagedObjectContext
    ) throws {
        var insertedIDs = Set<String>()
        var insertedXP = Int64(0)
        let sortedChallenges = snapshot.challenges.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        for challenge in sortedChallenges {
            let status = challenge.eatingStatus ?? status(for: challenge.action)
            let normalizedName = normalizeMenuName(challenge.menuName)
            let associationKey = mealAssociationKey(
                date: challenge.date,
                normalizedName: normalizedName,
                status: status.rawValue
            )
            let identity = mealRecords.identityByAssociationKey[associationKey]
                ?? recordIdentity(
                    date: challenge.date,
                    normalizedMenuName: normalizedName.canonical,
                    status: status.rawValue
                )
            let eventID = "meal:\(identity)"
            guard insertedIDs.insert(eventID).inserted else {
                throw RebuildMigrationError.progressEventIdentityCollision(eventID)
            }
            let amount = try checkedChallengeXP(challenge)
            let (newTotal, overflow) = insertedXP.addingReportingOverflow(amount)
            guard !overflow else {
                throw RebuildMigrationError.xpOverflow
            }
            insertedXP = newTotal
            let object = try insert(
                RebuildProgressEventManagedObject.self,
                entityName: RebuildEntityName.progressEvent,
                into: context
            )
            object.id = eventID
            object.amount = amount
            object.occurredAt = challenge.createdAt
            object.sourceRecordID = challenge.id.uuidString
        }

        let expected = try expectedXP(from: snapshot)
        let (remainder, overflow) = expected.subtractingReportingOverflow(insertedXP)
        guard !overflow else {
            throw RebuildMigrationError.xpOverflow
        }
        if remainder != 0 || (snapshot.hasStoredProgress && insertedIDs.isEmpty) {
            let object = try insert(
                RebuildProgressEventManagedObject.self,
                entityName: RebuildEntityName.progressEvent,
                into: context
            )
            object.id = Self.reconciliationEventID
            object.amount = remainder
            object.occurredAt = snapshot.challenges.map(\.createdAt).max()
                ?? snapshot.profile?.createdAt
                ?? Date(timeIntervalSince1970: 0)
            object.sourceRecordID = nil
        }
    }

    private func insertMigrationState(
        version: Int,
        sourceDigest: String,
        into context: NSManagedObjectContext
    ) throws {
        let object = try insert(
            RebuildMigrationStateManagedObject.self,
            entityName: RebuildEntityName.migrationState,
            into: context
        )
        object.id = RebuildMigrationStateRepository.stateID
        object.version = Int64(version)
        object.completedAt = now()
        object.sourceDigest = sourceDigest
    }

    private func verifyInsertedRows(
        expectedProfileCount: Int,
        expectedMealCount: Int,
        expectedPhotoCount: Int,
        expectedXP: Int64,
        in context: NSManagedObjectContext
    ) throws -> MigrationVerification {
        let profileCount = try count(RebuildEntityName.profile, in: context)
        let mealCount = try count(RebuildEntityName.mealRecord, in: context)
        let photoCount = try count(RebuildEntityName.mealPhoto, in: context)
        let totalXP = try progressTotal(in: context)
        try requireMatch(
            field: "profileCount",
            expected: Int64(expectedProfileCount),
            actual: Int64(profileCount)
        )
        try requireMatch(
            field: "mealRecordCount",
            expected: Int64(expectedMealCount),
            actual: Int64(mealCount)
        )
        try requireMatch(
            field: "photoCount",
            expected: Int64(expectedPhotoCount),
            actual: Int64(photoCount)
        )
        try requireMatch(field: "totalXP", expected: expectedXP, actual: totalXP)
        return MigrationVerification(
            profileCount: profileCount,
            mealRecordCount: mealCount,
            photoCount: photoCount,
            totalXP: totalXP
        )
    }

    private func expectedXP(from snapshot: LegacySnapshot) throws -> Int64 {
        if snapshot.hasStoredProgress {
            return try checkedProgressXP(snapshot.progress)
        }
        var total = Int64(0)
        for challenge in snapshot.challenges {
            let (next, overflow) = total.addingReportingOverflow(
                try checkedChallengeXP(challenge)
            )
            guard !overflow else {
                throw RebuildMigrationError.xpOverflow
            }
            total = next
        }
        return total
    }

    private func checkedProgressXP(_ progress: PlayerProgress) throws -> Int64 {
        try checkedXPTotal([
            progress.recordExp,
            progress.challengeExp,
            progress.balanceExp,
            progress.safetyExp,
        ])
    }

    private func checkedChallengeXP(_ challenge: ChallengeRecord) throws -> Int64 {
        try checkedXPTotal([
            challenge.recordExp,
            challenge.challengeExp,
            challenge.balanceExp,
            challenge.safetyExp,
        ])
    }

    private func checkedXPTotal(_ components: [Int]) throws -> Int64 {
        var total = Int64(0)
        for component in components {
            guard let value = Int64(exactly: component) else {
                throw RebuildMigrationError.xpOverflow
            }
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow else {
                throw RebuildMigrationError.xpOverflow
            }
            total = next
        }
        return total
    }

    private func count(
        _ entityName: String,
        in context: NSManagedObjectContext
    ) throws -> Int {
        try context.count(
            for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        )
    }

    private func progressTotal(in context: NSManagedObjectContext) throws -> Int64 {
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        var total = Int64(0)
        for event in try context.fetch(request) {
            let (next, overflow) = total.addingReportingOverflow(event.amount)
            guard !overflow else {
                throw RebuildMigrationError.xpOverflow
            }
            total = next
        }
        return total
    }

    private func requireMatch(
        field: String,
        expected: Int64,
        actual: Int64
    ) throws {
        guard expected == actual else {
            throw RebuildMigrationError.verificationMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }

    private func migratePhotoFile(
        _ photo: MealPhotoRecord,
        warnings: inout [MigrationWarning]
    ) throws -> String {
        guard
            !photo.fileName.isEmpty,
            photo.fileName != ".",
            photo.fileName != "..",
            URL(fileURLWithPath: photo.fileName).lastPathComponent == photo.fileName,
            !photo.fileName.contains("/"),
            !photo.fileName.contains("\\")
        else {
            throw RebuildMigrationError.unsafePhotoPath(photo.fileName)
        }

        guard let sourceData = try readSourcePhoto(named: photo.fileName) else {
            warnings.append(
                .missingPhotoFile(photoID: photo.id, fileName: photo.fileName)
            )
            return missingPhotoDestinationName(for: photo)
        }
        let relativePath = contentAddressedDestinationName(for: sourceData)

        let targetDirectoryDescriptor = try openVerifiedTargetDirectory(
            createIfMissing: true
        )
        return try withDescriptor(
            targetDirectoryDescriptor,
            path: rebuildPhotoDirectory.path,
            closeOperation: "close target directory"
        ) { descriptor in
            let targetURL = rebuildPhotoDirectory.appendingPathComponent(relativePath)
            if try validateExistingTarget(
                named: relativePath,
                expectedData: sourceData,
                directoryDescriptor: descriptor
            ) {
                return relativePath
            }
            try installTarget(
                named: relativePath,
                data: sourceData,
                directoryDescriptor: descriptor,
                targetURL: targetURL
            )
            return relativePath
        }
    }

    private func contentAddressedDestinationName(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func missingPhotoDestinationName(for photo: MealPhotoRecord) -> String {
        let input = Data("\(photo.id)|\(photo.fileName)".utf8)
        let digest = SHA256.hash(data: input)
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return "missing-\(digest)"
    }

    private func readSourcePhoto(named fileName: String) throws -> Data? {
        guard let directoryDescriptor = try openDirectoryByWalking(
            legacyPhotoDirectory,
            missingIsAllowed: true,
            createIfMissing: false
        ) else {
            return nil
        }
        return try withDescriptor(
            directoryDescriptor,
            path: legacyPhotoDirectory.path,
            closeOperation: "close source directory"
        ) { directoryDescriptor in
            let descriptor = fileName.withCString {
                openat(
                    directoryDescriptor,
                    $0,
                    O_RDONLY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard descriptor >= 0 else {
                let code = errno
                if code == ENOENT {
                    return nil
                }
                if code == ELOOP || code == ENOTDIR {
                    throw RebuildMigrationError.unsafePhotoPath(fileName)
                }
                throw posixError(operation: "open source photo", path: fileName, code: code)
            }
            return try withDescriptor(
                descriptor,
                path: fileName,
                closeOperation: "close source photo"
            ) { descriptor in
                try requireRegularFile(descriptor: descriptor, path: fileName)
                return try readAll(descriptor: descriptor, path: fileName)
            }
        }
    }

    private func openVerifiedTargetDirectory(createIfMissing: Bool) throws -> Int32 {
        guard let descriptor = try openDirectoryByWalking(
            rebuildPhotoDirectory,
            missingIsAllowed: false,
            createIfMissing: createIfMissing
        ) else {
            throw posixError(
                operation: "open target directory",
                path: rebuildPhotoDirectory.path,
                code: ENOENT
            )
        }
        return descriptor
    }

    private func openDirectoryByWalking(
        _ url: URL,
        missingIsAllowed: Bool,
        createIfMissing: Bool
    ) throws -> Int32? {
        let path = url.path
        guard url.isFileURL, path.hasPrefix("/") else {
            throw RebuildMigrationError.unsafePhotoPath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw RebuildMigrationError.unsafePhotoPath(path)
        }

        var currentDescriptor = open(
            "/",
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard currentDescriptor >= 0 else {
            throw posixError(operation: "open filesystem root", path: "/", code: errno)
        }

        do {
            for component in components {
                let name = String(component)
                var createdComponent = false
                var nextDescriptor = name.withCString {
                    openat(
                        currentDescriptor,
                        $0,
                        O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
                    )
                }
                if nextDescriptor < 0, errno == ENOENT, createIfMissing {
                    let createResult = name.withCString {
                        mkdirat(currentDescriptor, $0, S_IRWXU)
                    }
                    if createResult != 0, errno != EEXIST {
                        throw posixError(
                            operation: "create directory component",
                            path: path,
                            code: errno
                        )
                    }
                    createdComponent = createResult == 0
                    nextDescriptor = name.withCString {
                        openat(
                            currentDescriptor,
                            $0,
                            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
                        )
                    }
                }
                guard nextDescriptor >= 0 else {
                    let code = errno
                    if missingIsAllowed, code == ENOENT {
                        let descriptorToClose = currentDescriptor
                        currentDescriptor = -1
                        try closeDescriptor(
                            descriptorToClose,
                            path: path,
                            operation: "close directory component"
                        )
                        return nil
                    }
                    if code == ELOOP || code == ENOTDIR {
                        throw RebuildMigrationError.unsafePhotoPath(path)
                    }
                    throw posixError(
                        operation: "open directory component",
                        path: path,
                        code: code
                    )
                }
                if createdComponent {
                    do {
                        try synchronizeCreatedDirectoryParent(
                            currentDescriptor,
                            path: path
                        )
                    } catch {
                        let syncFailure = error
                        do {
                            try closeDescriptor(
                                nextDescriptor,
                                path: path,
                                operation: "close created directory after sync failure"
                            )
                        } catch {
                            throw error
                        }
                        throw syncFailure
                    }
                }
                let previousDescriptor = currentDescriptor
                currentDescriptor = nextDescriptor
                do {
                    try closeDescriptor(
                        previousDescriptor,
                        path: path,
                        operation: "close directory component"
                    )
                } catch {
                    let closeFailure = error
                    let descriptorToClose = currentDescriptor
                    currentDescriptor = -1
                    do {
                        try closeDescriptor(
                            descriptorToClose,
                            path: path,
                            operation: "close next directory after failure"
                        )
                    } catch {
                        throw error
                    }
                    throw closeFailure
                }
            }
            return currentDescriptor
        } catch {
            let traversalFailure = error
            if currentDescriptor >= 0 {
                let descriptorToClose = currentDescriptor
                currentDescriptor = -1
                do {
                    try closeDescriptor(
                        descriptorToClose,
                        path: path,
                        operation: "close directory after failure"
                    )
                } catch {
                    throw error
                }
            }
            throw traversalFailure
        }
    }

    private func validateExistingTarget(
        named fileName: String,
        expectedData: Data,
        directoryDescriptor: Int32
    ) throws -> Bool {
        let descriptor = fileName.withCString {
            openat(
                directoryDescriptor,
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            let code = errno
            if code == ENOENT {
                return false
            }
            if code == ELOOP || code == ENOTDIR {
                throw RebuildMigrationError.unsafePhotoPath(fileName)
            }
            throw posixError(operation: "open target photo", path: fileName, code: code)
        }
        return try withDescriptor(
            descriptor,
            path: fileName,
            closeOperation: "close target photo"
        ) { descriptor in
            try requireRegularFile(descriptor: descriptor, path: fileName)
            let existingData = try readAll(descriptor: descriptor, path: fileName)
            guard existingData == expectedData else {
                throw RebuildMigrationError.photoContentMismatch(fileName)
            }
            return true
        }
    }

    private func installTarget(
        named fileName: String,
        data: Data,
        directoryDescriptor: Int32,
        targetURL: URL
    ) throws {
        let temporaryName = ".migration-\(UUID().uuidString)"
        let temporaryDescriptor = temporaryName.withCString {
            openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard temporaryDescriptor >= 0 else {
            throw posixError(
                operation: "create temporary photo",
                path: temporaryName,
                code: errno
            )
        }

        var descriptorIsOpen = true
        do {
            try writeAll(data, descriptor: temporaryDescriptor, path: temporaryName)
            if fsync(temporaryDescriptor) != 0 {
                throw posixError(
                    operation: "sync temporary photo",
                    path: temporaryName,
                    code: errno
                )
            }
            descriptorIsOpen = false
            try closeDescriptor(
                temporaryDescriptor,
                path: temporaryName,
                operation: "close temporary photo"
            )

            let renameResult = temporaryName.withCString { temporaryPointer in
                fileName.withCString { targetPointer in
                    renameatx_np(
                        directoryDescriptor,
                        temporaryPointer,
                        directoryDescriptor,
                        targetPointer,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            if renameResult == 0 {
                try synchronizeTargetDirectory(directoryDescriptor)
                return
            }

            let renameCode = errno
            try removeTemporaryTarget(
                named: temporaryName,
                directoryDescriptor: directoryDescriptor,
                originalFailure: posixError(
                    operation: "install target photo",
                    path: targetURL.path,
                    code: renameCode
                )
            )
            if renameCode == EEXIST,
               try validateExistingTarget(
                    named: fileName,
                    expectedData: data,
                    directoryDescriptor: directoryDescriptor
               ) {
                return
            }
            throw posixError(
                operation: "install target photo",
                path: targetURL.path,
                code: renameCode
            )
        } catch {
            var failure = error
            if descriptorIsOpen {
                descriptorIsOpen = false
                do {
                    try closeDescriptor(
                        temporaryDescriptor,
                        path: temporaryName,
                        operation: "close temporary photo after failure"
                    )
                } catch {
                    failure = error
                }
            }
            try removeTemporaryTarget(
                named: temporaryName,
                directoryDescriptor: directoryDescriptor,
                originalFailure: failure
            )
            throw failure
        }
    }

    private func removeTemporaryTarget(
        named fileName: String,
        directoryDescriptor: Int32,
        originalFailure: Error
    ) throws {
        let result = fileName.withCString {
            unlinkat(directoryDescriptor, $0, 0)
        }
        guard result != 0, errno != ENOENT else {
            return
        }
        throw RebuildMigrationError.temporaryPhotoCleanupFailed(
            path: rebuildPhotoDirectory.appendingPathComponent(fileName).path,
            originalFailure: String(reflecting: originalFailure)
        )
    }

    private func synchronizeTargetDirectory(_ descriptor: Int32) throws {
        if let syncTargetDirectory {
            try syncTargetDirectory(descriptor)
            return
        }
        guard fsync(descriptor) == 0 else {
            throw posixError(
                operation: "sync target directory",
                path: rebuildPhotoDirectory.path,
                code: errno
            )
        }
    }

    private func synchronizeCreatedDirectoryParent(
        _ descriptor: Int32,
        path: String
    ) throws {
        if let syncCreatedDirectoryParent {
            try syncCreatedDirectoryParent(descriptor)
            return
        }
        guard fsync(descriptor) == 0 else {
            throw posixError(
                operation: "sync created directory parent",
                path: path,
                code: errno
            )
        }
    }

    private func withDescriptor<Value>(
        _ descriptor: Int32,
        path: String,
        closeOperation: String,
        body: (Int32) throws -> Value
    ) throws -> Value {
        var descriptorNeedsClose = true
        do {
            let value = try body(descriptor)
            descriptorNeedsClose = false
            try closeDescriptor(
                descriptor,
                path: path,
                operation: closeOperation
            )
            return value
        } catch {
            let bodyFailure = error
            if descriptorNeedsClose {
                descriptorNeedsClose = false
                do {
                    try closeDescriptor(
                        descriptor,
                        path: path,
                        operation: "\(closeOperation) after failure"
                    )
                } catch {
                    throw error
                }
            }
            throw bodyFailure
        }
    }

    private func closeDescriptor(
        _ descriptor: Int32,
        path: String,
        operation: String
    ) throws {
        guard Darwin.close(descriptor) == 0 else {
            throw posixError(operation: operation, path: path, code: errno)
        }
    }

    private func requireRegularFile(descriptor: Int32, path: String) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError(operation: "inspect photo", path: path, code: errno)
        }
        guard isRegularFile(metadata.st_mode) else {
            throw RebuildMigrationError.unsafePhotoPath(path)
        }
    }

    private func readAll(descriptor: Int32, path: String) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 {
                return data
            }
            guard count > 0 else {
                if errno == EINTR {
                    continue
                }
                throw posixError(operation: "read photo", path: path, code: errno)
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private func writeAll(_ data: Data, descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                guard count > 0 else {
                    if errno == EINTR {
                        continue
                    }
                    throw posixError(operation: "write photo", path: path, code: errno)
                }
                offset += count
            }
        }
    }

    private func isRegularFile(_ mode: mode_t) -> Bool {
        (mode & S_IFMT) == S_IFREG
    }

    private func posixError(
        operation: String,
        path: String,
        code: Int32
    ) -> RebuildMigrationError {
        .photoIOFailure(operation: operation, path: path, code: code)
    }

    private func normalizeMenuName(_ value: String) -> NormalizedLegacyMealName {
        let canonical = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let associationKey = canonical.replacingOccurrences(of: " ", with: "")
        return NormalizedLegacyMealName(
            canonical: canonical,
            associationKey: associationKey
        )
    }

    private func publishWarnings(_ warnings: [MigrationWarning]) {
        warningsLock.lock()
        publishedWarnings = warnings
        warningsLock.unlock()
    }

    private func mealAssociationKey(
        date: String,
        normalizedName: NormalizedLegacyMealName,
        status: String
    ) -> String {
        "\(date)|\(normalizedName.associationKey)|\(status)"
    }

    private func recordIdentity(
        date: String,
        normalizedMenuName: String,
        status: String
    ) -> String {
        "\(date)|\(normalizedMenuName)|\(status)"
    }

    private func orphanPhotoRecordID(photoID: String) -> String {
        "legacy-orphan-photo:\(photoID)"
    }

    private func status(for action: ChallengeRecord.Action) -> EatingStatus {
        switch action {
        case .oneBite:
            return .oneBite
        case .alreadyEats:
            return .finished
        case .skipped:
            return .difficultToday
        }
    }

    private func encodeJSON<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func insert<Object: NSManagedObject>(
        _ type: Object.Type,
        entityName: String,
        into context: NSManagedObjectContext
    ) throws -> Object {
        let object = NSEntityDescription.insertNewObject(
            forEntityName: entityName,
            into: context
        )
        guard let typed = object as? Object else {
            context.delete(object)
            throw RebuildMigrationError.unexpectedManagedObjectType(entityName)
        }
        return typed
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
