import CoreData

enum RebuildEntityName {
    static let dailyMealReview = "RebuildDailyMealReview"
    static let profile = "RebuildProfile"
    static let mealDay = "RebuildMealDay"
    static let mealRecord = "RebuildMealRecord"
    static let mealPhoto = "RebuildMealPhoto"
    static let progressEvent = "RebuildProgressEvent"
    static let syncEnvelope = "RebuildSyncEnvelope"
    static let parentLink = "RebuildParentLink"
    static let migrationState = "RebuildMigrationState"
}

enum RebuildManagedModel {
    static func make(includeDailyReview: Bool = true) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            entity(
                name: RebuildEntityName.profile,
                managedObjectClass: RebuildProfileManagedObject.self,
                attributes: [
                    attribute("id", type: .stringAttributeType),
                    attribute("role", type: .stringAttributeType),
                    attribute("nickname", type: .stringAttributeType),
                    attribute("officeCode", type: .stringAttributeType, isOptional: true),
                    attribute("schoolCode", type: .stringAttributeType, isOptional: true),
                    attribute("allergyCodesJSON", type: .stringAttributeType),
                ],
                uniqueKey: "id"
            ),
            entity(
                name: RebuildEntityName.mealDay,
                managedObjectClass: RebuildMealDayManagedObject.self,
                attributes: [
                    attribute("date", type: .stringAttributeType),
                    attribute("payloadJSON", type: .stringAttributeType),
                    attribute("fetchedAt", type: .dateAttributeType),
                    attribute("source", type: .stringAttributeType),
                ],
                uniqueKey: "date"
            ),
            entity(
                name: RebuildEntityName.mealRecord,
                managedObjectClass: RebuildMealRecordManagedObject.self,
                attributes: [
                    attribute("id", type: .stringAttributeType),
                    attribute("date", type: .stringAttributeType),
                    attribute("menuName", type: .stringAttributeType),
                    attribute("normalizedMenuName", type: .stringAttributeType),
                    attribute("status", type: .stringAttributeType),
                    attribute("difficultyReasonsJSON", type: .stringAttributeType),
                    attribute("allergyCodesJSON", type: .stringAttributeType),
                    attribute("photoIDsJSON", type: .stringAttributeType),
                    attribute("parentShareEnabled", type: .booleanAttributeType, defaultValue: false),
                    attribute("updatedAt", type: .dateAttributeType),
                    attribute("deletedAt", type: .dateAttributeType, isOptional: true),
                ],
                uniqueKey: "id"
            ),
            entity(
                name: RebuildEntityName.mealPhoto,
                managedObjectClass: RebuildMealPhotoManagedObject.self,
                attributes: [
                    attribute("id", type: .stringAttributeType),
                    attribute("recordID", type: .stringAttributeType),
                    attribute("relativePath", type: .stringAttributeType),
                    attribute("createdAt", type: .dateAttributeType),
                ],
                uniqueKey: "id"
            ),
            entity(
                name: RebuildEntityName.progressEvent,
                managedObjectClass: RebuildProgressEventManagedObject.self,
                attributes: [
                    attribute("id", type: .stringAttributeType),
                    attribute("amount", type: .integer64AttributeType),
                    attribute("occurredAt", type: .dateAttributeType),
                    attribute("sourceRecordID", type: .stringAttributeType, isOptional: true),
                ],
                uniqueKey: "id"
            ),
            entity(
                name: RebuildEntityName.syncEnvelope,
                managedObjectClass: RebuildSyncEnvelopeManagedObject.self,
                attributes: [
                    attribute("id", type: .stringAttributeType),
                    attribute("recordType", type: .stringAttributeType),
                    attribute("recordID", type: .stringAttributeType),
                    attribute("state", type: .stringAttributeType),
                    attribute("retryCount", type: .integer64AttributeType),
                    attribute("updatedAt", type: .dateAttributeType),
                ],
                uniqueKey: "id"
            ),
            entity(
                name: RebuildEntityName.parentLink,
                managedObjectClass: RebuildParentLinkManagedObject.self,
                attributes: [
                    attribute("id", type: .stringAttributeType),
                    attribute("inviteCode", type: .stringAttributeType),
                    attribute("connectionState", type: .stringAttributeType),
                    attribute("connectedAt", type: .dateAttributeType, isOptional: true),
                ],
                uniqueKey: "id"
            ),
            entity(
                name: RebuildEntityName.migrationState,
                managedObjectClass: RebuildMigrationStateManagedObject.self,
                attributes: [
                    attribute("id", type: .stringAttributeType),
                    attribute("version", type: .integer64AttributeType),
                    attribute("completedAt", type: .dateAttributeType),
                    attribute("sourceDigest", type: .stringAttributeType, isOptional: true),
                ],
                uniqueKey: "id"
            ),
        ]
        if includeDailyReview {
            model.entities.append(entity(name: RebuildEntityName.dailyMealReview, managedObjectClass: NSManagedObject.self,
                attributes: [attribute("id", type: .stringAttributeType), attribute("contextKey", type: .stringAttributeType),
                             attribute("day", type: .stringAttributeType), attribute("payloadJSON", type: .stringAttributeType)], uniqueKey: "id"))
        }
        return model
    }

    private static func entity(
        name: String,
        managedObjectClass: NSManagedObject.Type,
        attributes: [NSAttributeDescription],
        uniqueKey: String
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(managedObjectClass)
        entity.properties = attributes
        entity.uniquenessConstraints = [[uniqueKey]]
        return entity
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        isOptional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        return attribute
    }
}

@objc(RebuildProfileManagedObject)
final class RebuildProfileManagedObject: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var role: String
    @NSManaged var nickname: String
    @NSManaged var officeCode: String?
    @NSManaged var schoolCode: String?
    @NSManaged var allergyCodesJSON: String
}

@objc(RebuildMealDayManagedObject)
final class RebuildMealDayManagedObject: NSManagedObject {
    @NSManaged var date: String
    @NSManaged var payloadJSON: String
    @NSManaged var fetchedAt: Date
    @NSManaged var source: String
}

@objc(RebuildMealRecordManagedObject)
final class RebuildMealRecordManagedObject: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var date: String
    @NSManaged var menuName: String
    @NSManaged var normalizedMenuName: String
    @NSManaged var status: String
    @NSManaged var difficultyReasonsJSON: String
    @NSManaged var allergyCodesJSON: String
    @NSManaged var photoIDsJSON: String
    @NSManaged var parentShareEnabled: Bool
    @NSManaged var updatedAt: Date
    @NSManaged var deletedAt: Date?
}

@objc(RebuildMealPhotoManagedObject)
final class RebuildMealPhotoManagedObject: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var recordID: String
    @NSManaged var relativePath: String
    @NSManaged var createdAt: Date
}

@objc(RebuildProgressEventManagedObject)
final class RebuildProgressEventManagedObject: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var amount: Int64
    @NSManaged var occurredAt: Date
    @NSManaged var sourceRecordID: String?
}

@objc(RebuildSyncEnvelopeManagedObject)
final class RebuildSyncEnvelopeManagedObject: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var recordType: String
    @NSManaged var recordID: String
    @NSManaged var state: String
    @NSManaged var retryCount: Int64
    @NSManaged var updatedAt: Date
}

@objc(RebuildParentLinkManagedObject)
final class RebuildParentLinkManagedObject: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var inviteCode: String
    @NSManaged var connectionState: String
    @NSManaged var connectedAt: Date?
}

@objc(RebuildMigrationStateManagedObject)
final class RebuildMigrationStateManagedObject: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var version: Int64
    @NSManaged var completedAt: Date
    @NSManaged var sourceDigest: String?
}
