import CoreData
import CryptoKit
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
    case unsafePhotoPath(String)
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

final class RebuildMigrationCoordinator {
    private static let supportedTargetVersion = 1
    private static let reconciliationEventID = "legacy:progress-reconciliation"

    private let reader: LegacyDefaultsReader
    private let container: NSPersistentContainer
    private let legacyPhotoDirectory: URL
    private let rebuildPhotoDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let verify: RebuildMigrationVerifier
    private let save: RebuildMigrationSaver

    private(set) var warnings: [MigrationWarning] = []

    init(
        defaults: UserDefaults = .standard,
        container: NSPersistentContainer,
        legacyPhotoDirectory: URL? = nil,
        rebuildPhotoDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        verify: @escaping RebuildMigrationVerifier = { _ in },
        save: @escaping RebuildMigrationSaver = { try $0.save() }
    ) {
        reader = LegacyDefaultsReader(defaults: defaults)
        self.container = container
        self.fileManager = fileManager
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.legacyPhotoDirectory = legacyPhotoDirectory
            ?? documents.appendingPathComponent("MealPhotos", isDirectory: true)
        self.rebuildPhotoDirectory = rebuildPhotoDirectory
            ?? documents.appendingPathComponent("RebuildMealPhotos", isDirectory: true)
        self.now = now
        self.verify = verify
        self.save = save
    }

    func runIfNeeded(targetVersion: Int = 1) throws -> MigrationOutcome {
        guard targetVersion == Self.supportedTargetVersion else {
            throw RebuildMigrationError.unsupportedTargetVersion(targetVersion)
        }

        warnings = []
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
        let sourceDigest = try reader.sourceDigest(for: snapshot)
        var newlyCopiedFiles: [URL] = []

        do {
            return try context.performAndWait {
                do {
                    let mappedProfile = try insertProfile(from: snapshot, into: context)
                    let mappedMeals = try insertMealRecords(snapshot.mealRecords, into: context)
                    try insertParentLinks(from: snapshot, into: context)
                    let mappedPhotos = try insertPhotos(
                        snapshot.mealPhotoRecords,
                        mealRecords: mappedMeals,
                        into: context,
                        newlyCopiedFiles: &newlyCopiedFiles
                    )
                    try insertProgressEvents(from: snapshot, into: context)

                    let expectedXP = try expectedXP(from: snapshot)
                    let verification = try verifyInsertedRows(
                        expectedProfileCount: mappedProfile == nil ? 0 : 1,
                        expectedMealCount: mappedMeals.count,
                        expectedPhotoCount: mappedPhotos,
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
        } catch {
            for url in newlyCopiedFiles.reversed() {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
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
    ) throws -> [String: MealRecord] {
        var mapped: [String: MealRecord] = [:]
        for record in records {
            let normalizedName = normalizeMenuName(record.menuName)
            let identity = recordIdentity(
                date: record.date,
                normalizedMenuName: normalizedName,
                status: record.eatingStatus.rawValue
            )
            guard mapped[identity] == nil else {
                continue
            }
            mapped[identity] = record
            let object = try insert(
                RebuildMealRecordManagedObject.self,
                entityName: RebuildEntityName.mealRecord,
                into: context
            )
            object.id = identity
            object.date = record.date
            object.menuName = record.menuName
            object.normalizedMenuName = normalizedName
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
        return mapped
    }

    private func insertParentLinks(
        from snapshot: LegacySnapshot,
        into context: NSManagedObjectContext
    ) throws {
        var links: [UUID: ChildLink] = [:]
        if snapshot.hasStoredParentProfile {
            for link in snapshot.parentProfile.childLinks {
                links[link.id] = link
            }
        }
        if let childLink = snapshot.childLink {
            links[childLink.id] = childLink
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
        mealRecords: [String: MealRecord],
        into context: NSManagedObjectContext,
        newlyCopiedFiles: inout [URL]
    ) throws -> Int {
        var mappedPhotoIDs = Set<String>()
        let sortedMealRecords = mealRecords.sorted { $0.key < $1.key }

        for photo in photos where mappedPhotoIDs.insert(photo.id).inserted {
            let relativePath = try migratePhotoFile(
                photo,
                newlyCopiedFiles: &newlyCopiedFiles
            )
            let object = try insert(
                RebuildMealPhotoManagedObject.self,
                entityName: RebuildEntityName.mealPhoto,
                into: context
            )
            object.id = photo.id
            object.recordID = sortedMealRecords.first {
                $0.value.photoIds.contains(photo.id)
            }?.key ?? ""
            object.relativePath = relativePath
            object.createdAt = photo.createdAt
        }
        return mappedPhotoIDs.count
    }

    private func insertProgressEvents(
        from snapshot: LegacySnapshot,
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
            let identity = recordIdentity(
                date: challenge.date,
                normalizedMenuName: normalizeMenuName(challenge.menuName),
                status: status.rawValue
            )
            let eventID = "meal:\(identity)"
            guard insertedIDs.insert(eventID).inserted else {
                continue
            }
            let amount = Int64(challenge.xpBreakdown.total)
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
            return Int64(snapshot.progress.exp)
        }
        var total = Int64(0)
        for challenge in snapshot.challenges {
            let (next, overflow) = total.addingReportingOverflow(
                Int64(challenge.xpBreakdown.total)
            )
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
        newlyCopiedFiles: inout [URL]
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

        let sourceRoot = legacyPhotoDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
        let source = sourceRoot.appendingPathComponent(photo.fileName).standardizedFileURL
        guard isDescendant(source, of: sourceRoot) else {
            throw RebuildMigrationError.unsafePhotoPath(photo.fileName)
        }
        if let symlinkDestination = try? fileManager.destinationOfSymbolicLink(
            atPath: source.path
        ) {
            let destinationURL: URL
            if symlinkDestination.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: symlinkDestination)
            } else {
                destinationURL = source.deletingLastPathComponent()
                    .appendingPathComponent(symlinkDestination)
            }
            guard isDescendant(
                destinationURL.standardizedFileURL.resolvingSymlinksInPath(),
                of: sourceRoot
            ) else {
                throw RebuildMigrationError.unsafePhotoPath(photo.fileName)
            }
        }
        guard fileManager.fileExists(atPath: source.path) else {
            let relativePath = safeDestinationName(for: photo)
            warnings.append(
                .missingPhotoFile(photoID: photo.id, fileName: photo.fileName)
            )
            return relativePath
        }

        let resolvedSource = source.resolvingSymlinksInPath()
        guard isDescendant(resolvedSource, of: sourceRoot) else {
            throw RebuildMigrationError.unsafePhotoPath(photo.fileName)
        }

        try fileManager.createDirectory(
            at: rebuildPhotoDirectory,
            withIntermediateDirectories: true
        )
        let targetRoot = rebuildPhotoDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
        let relativePath = safeDestinationName(for: photo)
        let target = targetRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard isDescendant(target, of: targetRoot) else {
            throw RebuildMigrationError.unsafePhotoPath(relativePath)
        }
        if fileManager.fileExists(atPath: target.path) {
            let resolvedTarget = target.resolvingSymlinksInPath()
            guard isDescendant(resolvedTarget, of: targetRoot) else {
                throw RebuildMigrationError.unsafePhotoPath(relativePath)
            }
            return relativePath
        }

        let temporary = targetRoot.appendingPathComponent(
            ".\(UUID().uuidString).migration-copy"
        )
        do {
            try fileManager.copyItem(at: resolvedSource, to: temporary)
            try fileManager.moveItem(at: temporary, to: target)
            newlyCopiedFiles.append(target)
            return relativePath
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func safeDestinationName(for photo: MealPhotoRecord) -> String {
        let input = Data("\(photo.id)|\(photo.fileName)".utf8)
        let digest = SHA256.hash(data: input)
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        let sourceExtension = URL(fileURLWithPath: photo.fileName).pathExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return sourceExtension.isEmpty ? digest : "\(digest).\(sourceExtension)"
    }

    private func isDescendant(_ child: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        return childPath.hasPrefix(rootPath + "/")
    }

    private func normalizeMenuName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recordIdentity(
        date: String,
        normalizedMenuName: String,
        status: String
    ) -> String {
        "\(date)|\(normalizedMenuName)|\(status)"
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
