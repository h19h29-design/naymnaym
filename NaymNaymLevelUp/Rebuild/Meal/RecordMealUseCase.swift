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
    let photoIDs: [String]
    let parentShareEnabled: Bool
    let occurredAt: Date
}

struct RecordMealResult: Equatable, Sendable {
    let xpGranted: Int
    let totalXP: Int
    let motion: RebuildMotionState
}

enum RecordMealError: Error, Equatable {
    case invalidRecordIdentity
    case inactiveStatus(String)
    case allergySafetyRequired
    case xpOverflow
}

final class RecordMealUseCase: @unchecked Sendable {
    private let container: NSPersistentContainer
    private let ledgerSerializer: RebuildProgressLedgerSerializer
    private let policy: XPPolicyDocument

    init(
        container: NSPersistentContainer,
        bundle: Bundle = .main
    ) throws {
        self.container = container
        ledgerSerializer = .shared
        policy = try Self.decodePolicy(
            try loadRebuildContractData(named: "xp-policy.json", bundle: bundle)
        )
    }

    init(
        container: NSPersistentContainer,
        policyData: Data,
        ledgerSerializer: RebuildProgressLedgerSerializer = .shared
    ) throws {
        self.container = container
        self.ledgerSerializer = ledgerSerializer
        policy = try Self.decodePolicy(policyData)
    }

    func execute(_ command: RecordMealCommand) throws -> RecordMealResult {
        let normalizedMenuName = try validate(command)
        let encodedDifficultyReasons = try encode(command.difficultyReasons)
        let encodedAllergyCodes = try encode(command.allergyCodes)
        let encodedPhotoIDs = try encode(command.photoIDs)
        let eventID = "meal:\(command.recordID)"

        let context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        return try context.performAndWait {
            try ledgerSerializer.serialize {
                do {
                    let existingRecord = try fetchRecord(
                        id: command.recordID,
                        in: context
                    )
                    let existingEvent = try fetchEvent(id: eventID, in: context)
                    let awardAlreadyRecorded =
                        try hasAwardRecord(
                            date: command.date,
                            normalizedMenuName: normalizedMenuName,
                            in: context
                        )
                        || hasAwardEvent(
                            date: command.date,
                            normalizedMenuName: normalizedMenuName,
                            in: context
                        )
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

                    let record = try existingRecord ?? insert(
                        RebuildMealRecordManagedObject.self,
                        entityName: RebuildEntityName.mealRecord,
                        in: context
                    )
                    record.id = command.recordID
                    record.date = command.date
                    record.menuName = command.menuName
                    record.normalizedMenuName = normalizedMenuName
                    record.status = command.status.rawValue
                    record.difficultyReasonsJSON = encodedDifficultyReasons
                    record.allergyCodesJSON = encodedAllergyCodes
                    record.photoIDsJSON = encodedPhotoIDs
                    record.parentShareEnabled = command.parentShareEnabled
                    record.updatedAt = command.occurredAt
                    record.deletedAt = nil

                    if existingEvent == nil {
                        let event = try insert(
                            RebuildProgressEventManagedObject.self,
                            entityName: RebuildEntityName.progressEvent,
                            in: context
                        )
                        event.id = eventID
                        event.amount = Int64(xpGranted)
                        event.occurredAt = command.occurredAt
                        event.sourceRecordID = command.recordID
                    }

                    let totalXP = try sumAllXP(in: context)
                    try context.save()
                    return RecordMealResult(
                        xpGranted: xpGranted,
                        totalXP: totalXP,
                        motion: command.status == .difficultToday ? .comfort : .mealSuccess
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
        if !command.allergyCodes.isEmpty, command.status != .allergyAvoided {
            throw RecordMealError.allergySafetyRequired
        }

        let normalizedMenuName = command.menuName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard isCanonicalDate(command.date),
              !normalizedMenuName.isEmpty,
              !normalizedMenuName.contains("|"),
              command.recordID
                == "\(command.date)|\(normalizedMenuName)|\(command.status.rawValue)" else {
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

    private func fetchRecord(
        id: String,
        in context: NSManagedObjectContext
    ) throws -> RebuildMealRecordManagedObject? {
        let request = NSFetchRequest<RebuildMealRecordManagedObject>(
            entityName: RebuildEntityName.mealRecord
        )
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchEvent(
        id: String,
        in context: NSManagedObjectContext
    ) throws -> RebuildProgressEventManagedObject? {
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func hasAwardRecord(
        date: String,
        normalizedMenuName: String,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let request = NSFetchRequest<NSFetchRequestResult>(
            entityName: RebuildEntityName.mealRecord
        )
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date == %@", date),
            NSPredicate(
                format: "normalizedMenuName == %@",
                normalizedMenuName
            ),
        ])
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    private func hasAwardEvent(
        date: String,
        normalizedMenuName: String,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let awardPrefix = "\(date)|\(normalizedMenuName)|"
        let request = NSFetchRequest<NSFetchRequestResult>(
            entityName: RebuildEntityName.progressEvent
        )
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id BEGINSWITH %@", "meal:"),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(
                    format: "id BEGINSWITH %@",
                    "meal:\(awardPrefix)"
                ),
                NSPredicate(
                    format: "sourceRecordID BEGINSWITH %@",
                    awardPrefix
                ),
            ]),
        ])
        request.fetchLimit = 1
        return try context.count(for: request) > 0
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
            && legacy == Set([RebuildEatingStatus.half.rawValue])
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
