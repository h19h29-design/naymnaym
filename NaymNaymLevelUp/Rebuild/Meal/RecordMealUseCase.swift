import CoreData
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
    private static let transactionLock = NSRecursiveLock()

    private let container: NSPersistentContainer
    private let policy: XPPolicyDocument

    init(
        container: NSPersistentContainer,
        bundle: Bundle = .main
    ) throws {
        self.container = container
        policy = try Self.decodePolicy(
            try loadRebuildContractData(named: "xp-policy.json", bundle: bundle)
        )
    }

    init(
        container: NSPersistentContainer,
        policyData: Data
    ) throws {
        self.container = container
        policy = try Self.decodePolicy(policyData)
    }

    func execute(_ command: RecordMealCommand) throws -> RecordMealResult {
        let normalizedMenuName = try validate(command)
        let encodedDifficultyReasons = try encode(command.difficultyReasons)
        let encodedAllergyCodes = try encode(command.allergyCodes)
        let encodedPhotoIDs = try encode(command.photoIDs)
        let eventID = "meal:\(command.recordID)"

        Self.transactionLock.lock()
        defer { Self.transactionLock.unlock() }

        let context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        return try context.performAndWait {
            do {
                let existingRecord = try fetchRecord(
                    id: command.recordID,
                    in: context
                )
                let existingEvent = try fetchEvent(id: eventID, in: context)
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
                    existingRecord: existingRecord,
                    existingEvent: existingEvent,
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

                try context.save()
                let totalXP = try sumAllXP(in: context)
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
        existingRecord: RebuildMealRecordManagedObject?,
        existingEvent: RebuildProgressEventManagedObject?,
        dailyBaseXP: Int,
        dailyTotalXP: Int
    ) throws -> Int {
        guard existingRecord == nil, existingEvent == nil else {
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

    private func sumXP(
        date: String,
        eventPrefix: String?,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<RebuildProgressEventManagedObject>(
            entityName: RebuildEntityName.progressEvent
        )
        let datePredicate = NSPredicate(
            format: "sourceRecordID BEGINSWITH %@",
            "\(date)|"
        )
        if let eventPrefix {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                datePredicate,
                NSPredicate(format: "id BEGINSWITH %@", eventPrefix),
            ])
        } else {
            request.predicate = datePredicate
        }
        return try checkedSum(try context.fetch(request).map(\.amount))
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
            let addition = result.addingReportingOverflow(amount)
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
        guard let policy = try? JSONDecoder().decode(
            XPPolicyDocument.self,
            from: data
        ), policy.isValid else {
            throw RebuildContractLoadError.invalid("xp-policy.json")
        }
        return policy
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
