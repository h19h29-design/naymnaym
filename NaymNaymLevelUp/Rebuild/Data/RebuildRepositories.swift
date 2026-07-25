import CoreData

struct RebuildProfile: Equatable, Sendable {
    let id: String
    let role: String
    let nickname: String
    let officeCode: String?
    let schoolCode: String?
    let allergyCodesJSON: String
}

struct RebuildProgressEvent: Equatable, Sendable {
    let id: String
    let amount: Int64
    let occurredAt: Date
    let sourceRecordID: String?

    init(
        id: String,
        amount: Int64,
        occurredAt: Date,
        sourceRecordID: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.occurredAt = occurredAt
        self.sourceRecordID = sourceRecordID
    }
}

struct RebuildMigrationState: Equatable, Sendable {
    let id: String
    let version: Int
    let completedAt: Date
    let sourceDigest: String?
}

enum RebuildRepositoryError: Error {
    case unexpectedManagedObjectType(entityName: String)
    case totalXPOverflow
}

typealias RebuildProgressAppendSerializer = (
    _ operation: () throws -> Bool
) throws -> Bool

final class RebuildProgressLedgerSerializer: @unchecked Sendable {
    static let shared = RebuildProgressLedgerSerializer()

    private let lock = NSRecursiveLock()
    private let didEnter: (() -> Void)?

    init(didEnter: (() -> Void)? = nil) {
        self.didEnter = didEnter
    }

    func serialize<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        didEnter?()
        return try operation()
    }
}

final class RebuildProfileRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func save(_ profile: RebuildProfile) throws {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildProfileManagedObject>(
                entityName: RebuildEntityName.profile
            )
            request.predicate = NSPredicate(format: "id == %@", profile.id)
            request.fetchLimit = 1

            let object: RebuildProfileManagedObject
            if let existing = try context.fetch(request).first {
                object = existing
            } else {
                object = try insertManagedObject(
                    RebuildProfileManagedObject.self,
                    entityName: RebuildEntityName.profile,
                    in: context
                )
            }

            object.id = profile.id
            object.role = profile.role
            object.nickname = profile.nickname
            object.officeCode = profile.officeCode
            object.schoolCode = profile.schoolCode
            object.allergyCodesJSON = profile.allergyCodesJSON
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func load() throws -> RebuildProfile? {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildProfileManagedObject>(
                entityName: RebuildEntityName.profile
            )
            request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = 1
            return try context.fetch(request).first.map {
                RebuildProfile(
                    id: $0.id,
                    role: $0.role,
                    nickname: $0.nickname,
                    officeCode: $0.officeCode,
                    schoolCode: $0.schoolCode,
                    allergyCodesJSON: $0.allergyCodesJSON
                )
            }
        }
    }
}

final class RebuildProgressRepository {
    private let context: NSManagedObjectContext
    private let ledgerSerializer: RebuildProgressLedgerSerializer?
    private let injectedSerializeAppend: RebuildProgressAppendSerializer?

    init(context: NSManagedObjectContext) {
        self.context = context
        ledgerSerializer = .shared
        injectedSerializeAppend = nil
    }

    init(
        context: NSManagedObjectContext,
        ledgerSerializer: RebuildProgressLedgerSerializer
    ) {
        self.context = context
        self.ledgerSerializer = ledgerSerializer
        injectedSerializeAppend = nil
    }

    init(
        context: NSManagedObjectContext,
        serializeAppend: @escaping RebuildProgressAppendSerializer
    ) {
        self.context = context
        ledgerSerializer = nil
        injectedSerializeAppend = serializeAppend
    }

    func appendIfAbsent(_ event: RebuildProgressEvent) throws -> Bool {
        try context.performAndWait {
            if let ledgerSerializer {
                return try ledgerSerializer.serialize {
                    try appendInContext(event)
                }
            }
            guard let injectedSerializeAppend else {
                preconditionFailure("Missing progress append serializer")
            }
            return try injectedSerializeAppend {
                try appendInContext(event)
            }
        }
    }

    func totalXP() throws -> Int64 {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildProgressEventManagedObject>(
                entityName: RebuildEntityName.progressEvent
            )
            var total = Int64(0)
            for event in try context.fetch(request) {
                let (nextTotal, overflow) = total.addingReportingOverflow(
                    max(event.amount, 0)
                )
                guard !overflow else {
                    throw RebuildRepositoryError.totalXPOverflow
                }
                total = nextTotal
            }
            return total
        }
    }

    func load(id: String) throws -> RebuildProgressEvent? {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildProgressEventManagedObject>(
                entityName: RebuildEntityName.progressEvent
            )
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            return try context.fetch(request).first.map {
                RebuildProgressEvent(
                    id: $0.id,
                    amount: $0.amount,
                    occurredAt: $0.occurredAt,
                    sourceRecordID: $0.sourceRecordID
                )
            }
        }
    }

    private func requestForEvent(
        id: String
    ) -> NSFetchRequest<NSFetchRequestResult> {
        let request = NSFetchRequest<NSFetchRequestResult>(
            entityName: RebuildEntityName.progressEvent
        )
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return request
    }

    private func appendInContext(
        _ event: RebuildProgressEvent
    ) throws -> Bool {
        let request = requestForEvent(id: event.id)
        guard try context.count(for: request) == 0 else {
            return false
        }

        let object = try insertManagedObject(
            RebuildProgressEventManagedObject.self,
            entityName: RebuildEntityName.progressEvent,
            in: context
        )
        object.id = event.id
        object.amount = event.amount
        object.occurredAt = event.occurredAt
        object.sourceRecordID = event.sourceRecordID
        try context.save()
        return true
    }
}

final class RebuildMigrationStateRepository {
    static let stateID = "rebuild-migration"

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    var currentVersion: Int {
        get throws {
            try context.performAndWait {
                try fetchState().map { Int($0.version) } ?? 0
            }
        }
    }

    func markCompleted(
        version: Int,
        sourceDigest: String? = nil,
        completedAt: Date = Date()
    ) throws {
        try context.performAndWait {
            let object: RebuildMigrationStateManagedObject
            if let existing = try fetchState() {
                object = existing
            } else {
                object = try insertManagedObject(
                    RebuildMigrationStateManagedObject.self,
                    entityName: RebuildEntityName.migrationState,
                    in: context
                )
                object.id = Self.stateID
            }

            object.version = Int64(version)
            object.completedAt = completedAt
            object.sourceDigest = sourceDigest
            try context.save()
        }
    }

    func load() throws -> RebuildMigrationState? {
        try context.performAndWait {
            try fetchState().map {
                RebuildMigrationState(
                    id: $0.id,
                    version: Int($0.version),
                    completedAt: $0.completedAt,
                    sourceDigest: $0.sourceDigest
                )
            }
        }
    }

    private func fetchState() throws -> RebuildMigrationStateManagedObject? {
        let request = NSFetchRequest<RebuildMigrationStateManagedObject>(
            entityName: RebuildEntityName.migrationState
        )
        request.predicate = NSPredicate(format: "id == %@", Self.stateID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

private func insertManagedObject<Object: NSManagedObject>(
    _ type: Object.Type,
    entityName: String,
    in context: NSManagedObjectContext
) throws -> Object {
    let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    guard let typedObject = object as? Object else {
        context.delete(object)
        throw RebuildRepositoryError.unexpectedManagedObjectType(entityName: entityName)
    }
    return typedObject
}
