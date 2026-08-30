import CoreData
import CoreFoundation
import Foundation

enum RebuildEatingStatus: String, Codable, CaseIterable, Sendable {
    case oneBite
    case finished
    case half
    case smelledOnly
    case difficultToday
    case allergyAvoided
}

enum RebuildDifficultyReason: String, Codable, CaseIterable, Sendable {
    case texture
    case smell
    case taste
    case appearance
    case spicy
    case color
    case newFood
    case allergy
    case other
}

enum RebuildMotionState: String, Codable, Sendable {
    case idle
    case tapReaction
    case mealSuccess
    case levelUp
    case comfort
    case reducedMotion
}

struct RecordMealCommand: Equatable, Sendable {
    let recordID: String
    let date: String
    let menuName: String
    let status: RebuildEatingStatus
    let difficultyReasons: [RebuildDifficultyReason]
    let allergyCodes: [Int]
    let childAllergyCodes: [Int]
    let itemAllergyCodes: [Int]
    let photoIDs: [String]
    let parentShareEnabled: Bool
    let occurredAt: Date
    let nutritionSnapshot: NutrientImpactSnapshot?

    init(
        recordID: String,
        date: String,
        menuName: String,
        status: RebuildEatingStatus,
        difficultyReasons: [RebuildDifficultyReason],
        allergyCodes: [Int],
        childAllergyCodes: [Int],
        itemAllergyCodes: [Int],
        photoIDs: [String],
        parentShareEnabled: Bool,
        occurredAt: Date,
        nutritionSnapshot: NutrientImpactSnapshot? = nil
    ) {
        self.recordID = recordID
        self.date = date
        self.menuName = menuName
        self.status = status
        self.difficultyReasons = difficultyReasons
        self.allergyCodes = allergyCodes
        self.childAllergyCodes = childAllergyCodes
        self.itemAllergyCodes = itemAllergyCodes
        self.photoIDs = photoIDs
        self.parentShareEnabled = parentShareEnabled
        self.occurredAt = occurredAt
        self.nutritionSnapshot = nutritionSnapshot
    }
}

struct RecordMealResult: Equatable, Sendable {
    let xpGranted: Int
    let totalXP: Int
    let motion: RebuildMotionState
    let nutritionGuidance: NutrientImpactGuidance?

    init(
        xpGranted: Int,
        totalXP: Int,
        motion: RebuildMotionState,
        nutritionGuidance: NutrientImpactGuidance? = nil
    ) {
        self.xpGranted = xpGranted
        self.totalXP = totalXP
        self.motion = motion
        self.nutritionGuidance = nutritionGuidance
    }
}

enum NutrientImpactGuidanceSource: Equatable, Sendable {
    case recordedRevision
    case currentGuidance

    var childLabel: String {
        switch self {
        case .recordedRevision:
            return "기록 당시 안내"
        case .currentGuidance:
            return "현재 기준 안내"
        }
    }
}

struct NutrientImpactGuidance: Equatable, Sendable {
    let snapshot: NutrientImpactSnapshot
    let source: NutrientImpactGuidanceSource
}

enum RecordMealError: Error, Equatable {
    case invalidRecordIdentity
    case recordIdentityCollision
    case inactiveStatus(String)
    case allergySafetyRequired
    case allergyContextMismatch
    case staleRevision
    case conflictingRevision
    case xpOverflow
}

enum MealSafetyPolicy {
    static func allowedStatuses(
        childAllergyCodes: Set<Int>,
        itemAllergyCodes: Set<Int>
    ) -> Set<RebuildEatingStatus> {
        childAllergyCodes.isDisjoint(with: itemAllergyCodes)
            ? Set(RebuildEatingStatus.allCases)
            : [.allergyAvoided]
    }

    static func validate(
        childAllergyCodes: Set<Int>,
        itemAllergyCodes: Set<Int>,
        status: RebuildEatingStatus
    ) throws {
        guard allowedStatuses(
            childAllergyCodes: childAllergyCodes,
            itemAllergyCodes: itemAllergyCodes
        ).contains(status) else {
            throw RecordMealError.allergySafetyRequired
        }
    }
}

final class RecordMealUseCase: @unchecked Sendable {
    private struct InstalledNutritionRevision {
        let snapshot: NutrientImpactSnapshot
        let revision: RebuildMealRecordRevision
    }

    private let container: NSPersistentContainer
    private let ledgerSerializer: RebuildProgressLedgerSerializer
    private let nutrientImpactSidecar: any NutrientImpactSidecar
    private let policy: XPPolicyDocument

    init(
        container: NSPersistentContainer,
        bundle: Bundle = .main,
        nutrientImpactSidecar: any NutrientImpactSidecar =
            NoopNutrientImpactSidecar.shared
    ) throws {
        self.container = container
        ledgerSerializer = .shared
        self.nutrientImpactSidecar = nutrientImpactSidecar
        policy = try Self.decodePolicy(
            try loadRebuildContractData(named: "xp-policy.json", bundle: bundle)
        )
    }

    init(
        container: NSPersistentContainer,
        policyData: Data,
        ledgerSerializer: RebuildProgressLedgerSerializer = .shared,
        nutrientImpactSidecar: any NutrientImpactSidecar =
            NoopNutrientImpactSidecar.shared
    ) throws {
        self.container = container
        self.ledgerSerializer = ledgerSerializer
        self.nutrientImpactSidecar = nutrientImpactSidecar
        policy = try Self.decodePolicy(policyData)
    }

    func execute(_ command: RecordMealCommand) throws -> RecordMealResult {
        let normalizedMenuName = try validate(command)
        let encodedDifficultyReasons = try encode(command.difficultyReasons)
        let encodedAllergyCodes = try encode(command.allergyCodes)

        let context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        return try context.performAndWait {
            try ledgerSerializer.serialize {
                do {
                    let logicalRecords = try fetchLogicalRecords(
                        date: command.date,
                        normalizedMenuName: normalizedMenuName,
                        in: context
                    )
                    let activeRecords = logicalRecords
                        .filter { $0.deletedAt == nil }
                        .sorted(by: recordWinnerComesFirst)
                    let reusableStableRecord = activeRecords.isEmpty
                        ? logicalRecords.first(where: { $0.id == command.recordID })
                        : nil
                    let existingRecord = activeRecords.first
                        ?? reusableStableRecord
                    if let activeWinner = activeRecords.first,
                       activeWinner.updatedAt > command.occurredAt {
                        throw RecordMealError.staleRevision
                    }
                    if existingRecord == nil,
                       try fetchRecord(id: command.recordID, in: context) != nil {
                        throw RecordMealError.recordIdentityCollision
                    }
                    let actualRecordID = existingRecord?.id ?? command.recordID
                    let photoSourceRecords = activeRecords.isEmpty
                        ? existingRecord.map { [$0] } ?? []
                        : activeRecords
                    let existingPhotoIDs = try photoSourceRecords.flatMap {
                        try decodePhotoIDs($0.photoIDsJSON)
                    }
                    let mergedPhotoIDs = orderedUnique(
                        existingPhotoIDs + command.photoIDs
                    )
                    let encodedPhotoIDs = try encode(mergedPhotoIDs)
                    let preservedParentShare = existingRecord?.parentShareEnabled
                        ?? command.parentShareEnabled
                    if let existingRecord,
                       existingRecord.updatedAt == command.occurredAt,
                       try !isExactReplay(
                           existingRecord,
                           command: command,
                           normalizedMenuName: normalizedMenuName
                       ) {
                        throw RecordMealError.conflictingRevision
                    }
                    let logicalEvents = try fetchLogicalMealEvents(
                        date: command.date,
                        normalizedMenuName: normalizedMenuName,
                        resolvedRecordIDs: Set(logicalRecords.map(\.id)),
                        in: context
                    )
                    let awardAlreadyRecorded = !logicalRecords.isEmpty
                        || !logicalEvents.isEmpty
                    let dailyBaseXP = try sumXP(
                        date: command.date,
                        eventPrefix: "meal:",
                        in: context
                    )
                    let dailyTotalXP = try sumXP(
                        date: command.date,
                        eventPrefix: nil,
                        in: context
                    )
                    let xpGranted = try grantedXP(
                        command: command,
                        awardAlreadyRecorded: awardAlreadyRecorded,
                        dailyBaseXP: dailyBaseXP,
                        dailyTotalXP: dailyTotalXP
                    )

                    let installedNutrition = try installNutritionSnapshotIfPresent(
                        command: command,
                        normalizedMenuName: normalizedMenuName,
                        actualRecordID: actualRecordID
                    )

                    let record = try existingRecord
                        ?? insert(
                            RebuildMealRecordManagedObject.self,
                            entityName: RebuildEntityName.mealRecord,
                            in: context
                        )
                    if existingRecord == nil {
                        record.id = command.recordID
                    }

                    record.date = command.date
                    record.menuName = command.menuName
                    record.normalizedMenuName = normalizedMenuName
                    record.status = command.status.rawValue
                    record.difficultyReasonsJSON = encodedDifficultyReasons
                    record.allergyCodesJSON = encodedAllergyCodes
                    record.photoIDsJSON = encodedPhotoIDs
                    record.parentShareEnabled = preservedParentShare
                    record.updatedAt = command.occurredAt
                    record.deletedAt = nil

                    for duplicate in activeRecords where duplicate != record {
                        duplicate.deletedAt = command.occurredAt
                    }

                    if logicalEvents.isEmpty {
                        let event = try insert(
                            RebuildProgressEventManagedObject.self,
                            entityName: RebuildEntityName.progressEvent,
                            in: context
                        )
                        event.id = "meal:\(record.id)"
                        event.amount = Int64(xpGranted)
                        event.occurredAt = command.occurredAt
                        event.sourceRecordID = record.id
                    }

                    let totalXP = try sumAllXP(in: context)
                    try context.save()
                    let nutritionGuidance = nutritionGuidanceAfterSave(
                        installedNutrition
                    )
                    return RecordMealResult(
                        xpGranted: xpGranted,
                        totalXP: totalXP,
                        motion: command.status == .difficultToday ? .comfort : .mealSuccess,
                        nutritionGuidance: nutritionGuidance
                    )
                } catch {
                    context.rollback()
                    throw error
                }
            }
        }
    }

    private func validate(_ command: RecordMealCommand) throws -> String {
        guard policy.activeStatuses.contains(command.status.rawValue) else {
            throw RecordMealError.inactiveStatus(command.status.rawValue)
        }
        let childAllergies = Set(command.childAllergyCodes)
        let itemAllergies = Set(command.itemAllergyCodes)
        guard command.allergyCodes
                == Array(childAllergies.intersection(itemAllergies)).sorted()
        else {
            throw RecordMealError.allergyContextMismatch
        }
        try MealSafetyPolicy.validate(
            childAllergyCodes: childAllergies,
            itemAllergyCodes: itemAllergies,
            status: command.status
        )

        let normalizedMenuName = MealRecordIdentityNormalizer.normalizedMenuName(
            command.menuName
        )
        guard isCanonicalDate(command.date),
              !normalizedMenuName.isEmpty,
              !normalizedMenuName.contains("|"),
              command.recordID
                == "\(command.date)|\(normalizedMenuName)" else {
            throw RecordMealError.invalidRecordIdentity
        }
        return normalizedMenuName
    }

    private func grantedXP(
        command: RecordMealCommand,
        awardAlreadyRecorded: Bool,
        dailyBaseXP: Int,
        dailyTotalXP: Int
    ) throws -> Int {
        guard !awardAlreadyRecorded else {
            return 0
        }
        guard let requested = policy.statusXP[command.status.rawValue] else {
            throw RecordMealError.inactiveStatus(command.status.rawValue)
        }
        let baseRoom = max(0, policy.caps.base - max(0, dailyBaseXP))
        let totalRoom = max(0, policy.caps.total - max(0, dailyTotalXP))
        return min(requested, baseRoom, totalRoom)
    }

    private func fetchLogicalRecords(
        date: String,
        normalizedMenuName: String,
        in context: NSManagedObjectContext
    ) throws -> [RebuildMealRecordManagedObject] {
        let request = NSFetchRequest<RebuildMealRecordManagedObject>(
            entityName: RebuildEntityName.mealRecord
        )
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date == %@", date),
            NSPredicate(
                format: "normalizedMenuName == %@",
                normalizedMenuName
            ),
        ])
        return try context.fetch(request)
    }

    private func fetchRecord(
        id: String,
        in context: NSManagedObjectContext
    ) throws -> RebuildMealRecordManagedObject? {
        let request = NSFetchRequest<RebuildMealRecordManagedObject>(
            entityName: RebuildEntityName.mealRecord
        )
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id)
        return try context.fetch(request).first
    }

    private func fetchLogicalMealEvents(
        date: String,
        normalizedMenuName: String,
        resolvedRecordIDs: Set<String>,
        in context: NSManagedObjectContext
    ) throws -> [RebuildProgressEventManagedObject] {
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        request.predicate = NSPredicate(format: "id BEGINSWITH %@", "meal:")
        return try context.fetch(request).filter { event in
            let eventRecordID = String(event.id.dropFirst("meal:".count))
            return resolvedRecordIDs.contains(eventRecordID)
                || resolvedRecordIDs.contains(event.sourceRecordID ?? "")
                || isLogicalRecordIdentity(
                    eventRecordID,
                    date: date,
                    normalizedMenuName: normalizedMenuName
                ) || isLogicalRecordIdentity(
                    event.sourceRecordID,
                    date: date,
                    normalizedMenuName: normalizedMenuName
                )
        }
    }

    private func isLogicalRecordIdentity(
        _ candidate: String?,
        date: String,
        normalizedMenuName: String
    ) -> Bool {
        guard let candidate else { return false }
        let parts = candidate.split(
            separator: "|",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count == 2 || parts.count == 3,
              parts[0] == date,
              parts[1] == normalizedMenuName else {
            return false
        }
        return parts.count == 2
            || RebuildEatingStatus(rawValue: parts[2]) != nil
    }

    private func recordWinnerComesFirst(
        _ lhs: RebuildMealRecordManagedObject,
        _ rhs: RebuildMealRecordManagedObject
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
    }

    private func decodePhotoIDs(_ value: String) throws -> [String] {
        try decode([String].self, from: value)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from value: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data(value.utf8))
        } catch {
            throw RebuildContractLoadError.invalid("meal-record.json")
        }
    }

    private func isExactReplay(
        _ record: RebuildMealRecordManagedObject,
        command: RecordMealCommand,
        normalizedMenuName: String
    ) throws -> Bool {
        let storedReasons = try decode(
            [RebuildDifficultyReason].self,
            from: record.difficultyReasonsJSON
        )
        let storedAllergies = try decode(
            [Int].self,
            from: record.allergyCodesJSON
        )
        let storedPhotos = try decodePhotoIDs(record.photoIDsJSON)
        let replayPhotos = orderedUnique(storedPhotos + command.photoIDs)
        return record.date == command.date
            && record.menuName == command.menuName
            && record.normalizedMenuName == normalizedMenuName
            && record.status == command.status.rawValue
            && storedReasons == command.difficultyReasons
            && storedAllergies == command.allergyCodes
            && storedPhotos == replayPhotos
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func installNutritionSnapshotIfPresent(
        command: RecordMealCommand,
        normalizedMenuName: String,
        actualRecordID: String
    ) throws -> InstalledNutritionRevision? {
        guard let incoming = command.nutritionSnapshot else { return nil }
        guard incoming.schemaVersion
                == NutrientImpactSnapshot.supportedSchemaVersion,
              NutrientImpactSnapshot.supportedRuleVersions.contains(
                  incoming.ruleVersion
              ),
              incoming.recordID == command.recordID,
              incoming.date == command.date,
              incoming.normalizedMenuName == normalizedMenuName,
              incoming.status == command.status,
              incoming.recordUpdatedAt == command.occurredAt,
              NutrientImpactCopyCatalog.validatedCanonicalNutrientIDs(
                  incoming.nutrients
              ) == incoming.nutrients,
              NutrientImpactCopyCatalog.isCanonical(
                  status: incoming.status,
                  nutrientIDs: incoming.nutrients,
                  headline: incoming.headline,
                  explanation: incoming.explanation,
                  disclaimer: incoming.disclaimer,
                  hasAlternatives: !incoming.alternatives.isEmpty
              ),
              NutrientImpactCopyCatalog.validateMenuLabels(
                  incoming.alternatives
              ),
              incoming.status == .difficultToday
                || incoming.alternatives.isEmpty else {
            throw NutrientImpactSidecarError.invalidSnapshot
        }

        let rebound = NutrientImpactSnapshot(
            schemaVersion: incoming.schemaVersion,
            ruleVersion: incoming.ruleVersion,
            recordID: actualRecordID,
            date: command.date,
            normalizedMenuName: normalizedMenuName,
            status: command.status,
            recordUpdatedAt: command.occurredAt,
            nutrients: incoming.nutrients,
            headline: incoming.headline,
            explanation: incoming.explanation,
            alternatives: incoming.alternatives,
            disclaimer: incoming.disclaimer
        )
        let revision = RebuildMealRecordRevision(
            recordID: actualRecordID,
            date: command.date,
            normalizedMenuName: normalizedMenuName,
            status: command.status,
            updatedAt: command.occurredAt
        )
        try nutrientImpactSidecar.install(rebound)
        guard try nutrientImpactSidecar.load(matching: revision) == rebound else {
            throw NutrientImpactSidecarError.readBackFailed
        }
        return InstalledNutritionRevision(
            snapshot: rebound,
            revision: revision
        )
    }

    private func nutritionGuidanceAfterSave(
        _ installed: InstalledNutritionRevision?
    ) -> NutrientImpactGuidance? {
        guard let installed else { return nil }
        do {
            if try nutrientImpactSidecar.load(matching: installed.revision)
                == installed.snapshot {
                return NutrientImpactGuidance(
                    snapshot: installed.snapshot,
                    source: .recordedRevision
                )
            }
        } catch {
            // The Core Data transaction is already durable. A damaged or
            // unavailable sidecar changes only the guidance provenance.
        }
        return NutrientImpactGuidance(
            snapshot: installed.snapshot,
            source: .currentGuidance
        )
    }

    private func sumXP(
        date: String,
        eventPrefix: String?,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let dayInterval = try seoulDayInterval(for: date)
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        if let eventPrefix {
            request.predicate = NSPredicate(
                format: "id BEGINSWITH %@",
                eventPrefix
            )
        }
        let amounts = try context.fetch(request).compactMap { event in
            if let sourceDate = canonicalSourceDate(event.sourceRecordID) {
                return sourceDate == date ? event.amount : nil
            }
            return event.occurredAt >= dayInterval.start
                && event.occurredAt < dayInterval.end
                ? event.amount
                : nil
        }
        return try checkedSum(amounts)
    }

    private func sumAllXP(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        return max(0, try checkedSum(try context.fetch(request).map(\.amount)))
    }

    private func checkedSum(_ amounts: [Int64]) throws -> Int {
        var result = Int64(0)
        for amount in amounts {
            let addition = result.addingReportingOverflow(max(amount, 0))
            guard !addition.overflow else {
                throw RecordMealError.xpOverflow
            }
            result = addition.partialValue
        }
        guard let exact = Int(exactly: result) else {
            throw RecordMealError.xpOverflow
        }
        return exact
    }

    private func seoulDayInterval(for date: String) throws -> DateInterval {
        let components = date.split(separator: "-").compactMap {
            Int($0)
        }
        guard components.count == 3,
              let timeZone = TimeZone(identifier: "Asia/Seoul") else {
            throw RecordMealError.invalidRecordIdentity
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startComponents = DateComponents(
            timeZone: timeZone,
            year: components[0],
            month: components[1],
            day: components[2]
        )
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw RecordMealError.invalidRecordIdentity
        }
        return DateInterval(start: start, end: end)
    }

    private func canonicalSourceDate(_ sourceRecordID: String?) -> String? {
        guard let sourceRecordID,
              sourceRecordID.count > 11 else {
            return nil
        }
        let separator = sourceRecordID.index(
            sourceRecordID.startIndex,
            offsetBy: 10
        )
        guard sourceRecordID[separator] == "|" else {
            return nil
        }
        let date = String(sourceRecordID.prefix(10))
        return date.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) == nil ? nil : date
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw RebuildContractLoadError.invalid("meal-record.json")
        }
        return result
    }

    private func isCanonicalDate(_ value: String) -> Bool {
        guard value.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else {
            return false
        }
        return formatter.string(from: date) == value
    }

    private static func decodePolicy(_ data: Data) throws -> XPPolicyDocument {
        guard hasStrictPolicyNumbers(data),
              let policy = try? JSONDecoder().decode(
            XPPolicyDocument.self,
            from: data
        ), policy.isValid else {
            throw RebuildContractLoadError.invalid("xp-policy.json")
        }
        return policy
    }

    private static func hasStrictPolicyNumbers(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
              Set(root.keys) == Set([
                "version",
                "activeStatuses",
                "legacyReadCompatibleStatuses",
                "awardIdentityComponents",
                "awardIdentity",
                "statusTransitionsGrantAdditionalXP",
                "statusXP",
                "caps",
              ]),
              isJSONInteger(root["version"]),
              let statusXP = root["statusXP"] as? [String: Any],
              statusXP.values.allSatisfy(isJSONInteger),
              let caps = root["caps"] as? [String: Any],
              Set(caps.keys) == Set(["base", "challengeBonus", "total"]),
              caps.values.allSatisfy(isJSONInteger) else {
            return false
        }
        return true
    }

    private static func isJSONInteger(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return false
        }
        let type = String(cString: number.objCType)
        return type != "f" && type != "d"
    }
}

private struct XPPolicyDocument: Decodable {
    struct Caps: Decodable {
        let base: Int
        let challengeBonus: Int
        let total: Int
    }

    let version: Int
    let activeStatuses: [String]
    let legacyReadCompatibleStatuses: [String]
    let awardIdentityComponents: [String]
    let awardIdentity: String
    let statusTransitionsGrantAdditionalXP: Bool
    let statusXP: [String: Int]
    let caps: Caps

    var isValid: Bool {
        let active = Set(activeStatuses)
        let legacy = Set(legacyReadCompatibleStatuses)
        let knownStatuses = Set(RebuildEatingStatus.allCases.map(\.rawValue))
        return version == 1
            && !active.isEmpty
            && active.count == activeStatuses.count
            && legacy.count == legacyReadCompatibleStatuses.count
            && active.isDisjoint(with: legacy)
            && legacy.isEmpty
            && active.union(legacy) == knownStatuses
            && awardIdentityComponents == ["date", "normalizedMenuName"]
            && awardIdentity == "{date}|{normalizedMenuName}"
            && !statusTransitionsGrantAdditionalXP
            && Set(statusXP.keys) == active.union(legacy)
            && statusXP.values.allSatisfy { $0 >= 0 }
            && caps.base >= 0
            && caps.challengeBonus >= 0
            && caps.total >= 0
            && caps.base <= caps.total
            && caps.challengeBonus <= caps.total
    }
}

private func insert<Object: NSManagedObject>(
    _ type: Object.Type,
    entityName: String,
    in context: NSManagedObjectContext
) throws -> Object {
    let object = NSEntityDescription.insertNewObject(
        forEntityName: entityName,
        into: context
    )
    guard let typed = object as? Object else {
        context.delete(object)
        throw RebuildRepositoryError.unexpectedManagedObjectType(
            entityName: entityName
        )
    }
    return typed
}
