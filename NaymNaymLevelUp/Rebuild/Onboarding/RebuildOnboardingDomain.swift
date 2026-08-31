import CoreData
import Foundation

enum RebuildOnboardingRole: String, Equatable, Sendable {
    case child
    case parent
}

enum RebuildOnboardingStep: String, CaseIterable, Equatable, Sendable {
    case role
    case nickname
    case school
    case allergies
    case confirmation
}

enum RebuildOnboardingDestination: Equatable, Sendable {
    case today
    case parentConnection
}

struct RebuildOnboardingSchool: Equatable, Identifiable, Sendable {
    var id: String { "\(officeCode)-\(schoolCode)" }
    let name: String
    let officeCode: String
    let schoolCode: String
}

extension RebuildOnboardingSchool {
    init(sampleSchool: School) {
        self.init(
            name: sampleSchool.name,
            officeCode: sampleSchool.officeCode,
            schoolCode: sampleSchool.schoolCode
        )
    }
}

struct OnboardingDraft: Equatable, Sendable {
    var role: RebuildOnboardingRole?
    var nickname = ""
    var school: RebuildOnboardingSchool?
    var allergyCodes: [Int] = []
    var isDemoMode = false
}

struct RebuildUserProfile: Equatable, Sendable {
    let id: String
    let role: RebuildOnboardingRole
    let nickname: String
    let school: RebuildOnboardingSchool?
    let allergyCodes: [Int]
    let destination: RebuildOnboardingDestination
    let isDemoMode: Bool

    init(
        id: String,
        role: RebuildOnboardingRole,
        nickname: String,
        school: RebuildOnboardingSchool?,
        allergyCodes: [Int],
        destination: RebuildOnboardingDestination,
        isDemoMode: Bool = false
    ) {
        self.id = id
        self.role = role
        self.nickname = nickname
        self.school = school
        self.allergyCodes = allergyCodes
        self.destination = destination
        self.isDemoMode = isDemoMode
    }
}

enum RebuildOnboardingError: Error, Equatable {
    case missingRole
    case invalidNickname
    case missingSchoolIdentifiers
    case wrongStep
    case persistenceUnavailable
    case completionInProgress
    case completionCancelled
}

enum RebuildSchoolSearchState: Equatable, Sendable {
    case idle
    case loading
    case results([RebuildOnboardingSchool])
    case demoResults([RebuildOnboardingSchool])
    case empty
    case failed(String)
}

protocol RebuildOnboardingProfileStore {
    func load() async throws -> RebuildUserProfile?
    func save(_ profile: RebuildUserProfile) async throws
    func removeIfCurrent(id: String) async throws
}

protocol RebuildSchoolSearchClient {
    func search(query: String) async throws -> [RebuildOnboardingSchool]
}

final class RebuildSchoolNameMetadataStore: @unchecked Sendable {
    struct Entry {
        let key: String
        let value: String?
    }

    struct Snapshot {
        let entries: [Entry]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func name(
        profileID: String,
        officeCode: String,
        schoolCode: String
    ) -> String? {
        defaults.string(forKey: profileNameKey(profileID))
            ?? defaults.string(forKey: legacyProfileNameKey(profileID))
            ?? defaults.string(
                forKey: schoolNameKey(officeCode, schoolCode)
            )
            ?? defaults.string(
                forKey: legacySchoolNameKey(officeCode, schoolCode)
            )
    }

    func isDemoMode(profileID: String) -> Bool {
        defaults.string(forKey: profileDemoModeKey(profileID)) == "true"
    }

    /// Writes current metadata and retires metadata belonging to profiles
    /// replaced by the singleton Core Data profile row.
    ///
    /// The snapshot includes both current and retired keys so a failed Core
    /// Data save can restore the complete prior state.
    func write(
        _ profile: RebuildUserProfile,
        replacingProfileIDs: [String] = []
    ) -> Snapshot {
        let idNameKey = profileNameKey(profile.id)
        let idOfficeKey = profileOfficeKey(profile.id)
        let idSchoolKey = profileSchoolKey(profile.id)
        let idDemoModeKey = profileDemoModeKey(profile.id)
        let legacyIDKey = legacyProfileNameKey(profile.id)
        let previousOfficeCode = defaults.string(forKey: idOfficeKey)
        let previousSchoolCode = defaults.string(forKey: idSchoolKey)
        let retiredProfileIDs = Set(replacingProfileIDs).subtracting([profile.id])
        var affectedKeys = [
            idNameKey,
            idOfficeKey,
            idSchoolKey,
            idDemoModeKey,
            legacyIDKey
        ]
        if let previousOfficeCode, let previousSchoolCode {
            affectedKeys += [
                schoolNameKey(previousOfficeCode, previousSchoolCode),
                schoolOwnerKey(previousOfficeCode, previousSchoolCode),
                legacySchoolNameKey(previousOfficeCode, previousSchoolCode)
            ]
        }
        for retiredProfileID in retiredProfileIDs {
            affectedKeys += [
                profileNameKey(retiredProfileID),
                profileOfficeKey(retiredProfileID),
                profileSchoolKey(retiredProfileID),
                profileDemoModeKey(retiredProfileID),
                legacyProfileNameKey(retiredProfileID)
            ]
            if let officeCode = defaults.string(
                forKey: profileOfficeKey(retiredProfileID)
            ), let schoolCode = defaults.string(
                forKey: profileSchoolKey(retiredProfileID)
            ) {
                affectedKeys += [
                    schoolNameKey(officeCode, schoolCode),
                    schoolOwnerKey(officeCode, schoolCode),
                    legacySchoolNameKey(officeCode, schoolCode)
                ]
            }
        }
        if let school = profile.school {
            affectedKeys += [
                schoolNameKey(school.officeCode, school.schoolCode),
                schoolOwnerKey(school.officeCode, school.schoolCode),
                legacySchoolNameKey(school.officeCode, school.schoolCode)
            ]
        }
        let snapshot = Snapshot(
            entries: Array(Set(affectedKeys)).map {
                Entry(key: $0, value: defaults.string(forKey: $0))
            }
        )
        for retiredProfileID in retiredProfileIDs {
            removeIfOwned(profileID: retiredProfileID)
        }
        removeOwnedSchoolMetadata(
            profileID: profile.id,
            profileName: defaults.string(forKey: idNameKey)
                ?? defaults.string(forKey: legacyIDKey),
            officeCode: previousOfficeCode,
            schoolCode: previousSchoolCode
        )
        defaults.removeObject(forKey: legacyIDKey)
        if profile.isDemoMode {
            defaults.set("true", forKey: idDemoModeKey)
        } else {
            defaults.removeObject(forKey: idDemoModeKey)
        }
        guard let school = profile.school else {
            defaults.removeObject(forKey: idNameKey)
            defaults.removeObject(forKey: idOfficeKey)
            defaults.removeObject(forKey: idSchoolKey)
            return snapshot
        }
        defaults.set(school.name, forKey: idNameKey)
        defaults.set(school.officeCode, forKey: idOfficeKey)
        defaults.set(school.schoolCode, forKey: idSchoolKey)
        defaults.set(
            school.name,
            forKey: schoolNameKey(school.officeCode, school.schoolCode)
        )
        defaults.set(
            profile.id,
            forKey: schoolOwnerKey(school.officeCode, school.schoolCode)
        )
        return snapshot
    }

    func restore(_ snapshot: Snapshot) {
        for entry in snapshot.entries {
            restore(entry.value, forKey: entry.key)
        }
    }

    func removeIfOwned(
        profileID: String,
        fallbackOfficeCode: String? = nil,
        fallbackSchoolCode: String? = nil
    ) {
        let idNameKey = profileNameKey(profileID)
        let idOfficeKey = profileOfficeKey(profileID)
        let idSchoolKey = profileSchoolKey(profileID)
        let idDemoModeKey = profileDemoModeKey(profileID)
        let legacyIDKey = legacyProfileNameKey(profileID)
        let profileName = defaults.string(forKey: idNameKey)
            ?? defaults.string(forKey: legacyIDKey)
        let officeCode = defaults.string(forKey: idOfficeKey)
            ?? fallbackOfficeCode
        let schoolCode = defaults.string(forKey: idSchoolKey)
            ?? fallbackSchoolCode
        removeOwnedSchoolMetadata(
            profileID: profileID,
            profileName: profileName,
            officeCode: officeCode,
            schoolCode: schoolCode
        )
        defaults.removeObject(forKey: idNameKey)
        defaults.removeObject(forKey: idOfficeKey)
        defaults.removeObject(forKey: idSchoolKey)
        defaults.removeObject(forKey: idDemoModeKey)
        defaults.removeObject(forKey: legacyIDKey)
    }

    func hasProfileMetadata(id: String) -> Bool {
        defaults.object(forKey: profileNameKey(id)) != nil
            || defaults.object(forKey: profileOfficeKey(id)) != nil
            || defaults.object(forKey: profileSchoolKey(id)) != nil
            || defaults.object(forKey: profileDemoModeKey(id)) != nil
            || defaults.object(forKey: legacyProfileNameKey(id)) != nil
    }

    func hasSchoolMetadata(
        officeCode: String,
        schoolCode: String
    ) -> Bool {
        defaults.object(forKey: schoolNameKey(officeCode, schoolCode)) != nil
            || defaults.object(
                forKey: schoolOwnerKey(officeCode, schoolCode)
            ) != nil
            || defaults.object(
                forKey: legacySchoolNameKey(officeCode, schoolCode)
            ) != nil
    }

    func schoolOwner(
        officeCode: String,
        schoolCode: String
    ) -> String? {
        defaults.string(forKey: schoolOwnerKey(officeCode, schoolCode))
    }

    private func restore(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func removeOwnedSchoolMetadata(
        profileID: String,
        profileName: String?,
        officeCode: String?,
        schoolCode: String?
    ) {
        guard let officeCode, let schoolCode else { return }
        let nameKey = schoolNameKey(officeCode, schoolCode)
        let ownerKey = schoolOwnerKey(officeCode, schoolCode)
        let legacyNameKey = legacySchoolNameKey(officeCode, schoolCode)
        let owner = defaults.string(forKey: ownerKey)
        let isLegacyOwnership = owner == nil
            && profileName != nil
            && (
                defaults.string(forKey: nameKey) == profileName
                    || defaults.string(forKey: legacyNameKey) == profileName
            )
        guard owner == profileID || isLegacyOwnership else { return }
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: ownerKey)
        defaults.removeObject(forKey: legacyNameKey)
    }

    private func profileNameKey(_ id: String) -> String {
        "rebuild.school-name.profile.\(id).name"
    }

    private func legacyProfileNameKey(_ id: String) -> String {
        "rebuild.school-name.profile.\(id)"
    }

    private func profileOfficeKey(_ id: String) -> String {
        "rebuild.school-name.profile.\(id).office"
    }

    private func profileSchoolKey(_ id: String) -> String {
        "rebuild.school-name.profile.\(id).school"
    }

    private func profileDemoModeKey(_ id: String) -> String {
        "rebuild.profile.\(id).demo-mode"
    }

    private func schoolNameKey(
        _ officeCode: String,
        _ schoolCode: String
    ) -> String {
        "rebuild.school-name.codes.\(officeCode).\(schoolCode).name"
    }

    private func schoolOwnerKey(
        _ officeCode: String,
        _ schoolCode: String
    ) -> String {
        "rebuild.school-name.codes.\(officeCode).\(schoolCode).owner"
    }

    private func legacySchoolNameKey(
        _ officeCode: String,
        _ schoolCode: String
    ) -> String {
        "rebuild.school-name.codes.\(officeCode).\(schoolCode)"
    }
}

actor RebuildOnboardingProfileTransactionCoordinator {
    private let context: NSManagedObjectContext
    private let metadataStore: RebuildSchoolNameMetadataStore
    private let beforeRemove: (() -> Void)?
    private let saveContext: (NSManagedObjectContext) throws -> Void

    init(
        container: NSPersistentContainer,
        metadataStore: RebuildSchoolNameMetadataStore = .init(),
        beforeRemove: (() -> Void)? = nil,
        saveContext: @escaping (NSManagedObjectContext) throws -> Void = {
            try $0.save()
        }
    ) {
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.metadataStore = metadataStore
        self.beforeRemove = beforeRemove
        self.saveContext = saveContext
    }

    func load() throws -> RebuildUserProfile? {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildProfileManagedObject>(
                entityName: RebuildEntityName.profile
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "id", ascending: true)
            ]
            request.fetchLimit = 1
            guard let object = try context.fetch(request).first else {
                return nil
            }
            guard let role = RebuildOnboardingRole(rawValue: object.role) else {
                throw RebuildOnboardingError.persistenceUnavailable
            }
            let allergyCodes = try JSONDecoder().decode(
                [Int].self,
                from: Data(object.allergyCodesJSON.utf8)
            )
            let school: RebuildOnboardingSchool?
            if
                role == .child,
                let officeCode = object.officeCode,
                let schoolCode = object.schoolCode,
                !officeCode.isEmpty,
                !schoolCode.isEmpty
            {
                school = RebuildOnboardingSchool(
                    name: metadataStore.name(
                        profileID: object.id,
                        officeCode: officeCode,
                        schoolCode: schoolCode
                    ) ?? "등록한 학교",
                    officeCode: officeCode,
                    schoolCode: schoolCode
                )
            } else {
                school = nil
            }
            return RebuildUserProfile(
                id: object.id,
                role: role,
                nickname: object.nickname,
                school: school,
                allergyCodes: Array(Set(allergyCodes)).sorted(),
                destination: role == .child ? .today : .parentConnection,
                isDemoMode: metadataStore.isDemoMode(profileID: object.id)
            )
        }
    }

    func save(_ profile: RebuildUserProfile) throws {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildProfileManagedObject>(
                entityName: RebuildEntityName.profile
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "id", ascending: true)
            ]
            let existingProfiles = try context.fetch(request)
            let metadataSnapshot = metadataStore.write(
                profile,
                replacingProfileIDs: existingProfiles.map(\.id)
            )
            do {
                let object: RebuildProfileManagedObject
                if let existing = existingProfiles.first {
                    object = existing
                } else {
                    object = RebuildProfileManagedObject(
                        entity: try Self.profileEntity(in: context),
                        insertInto: context
                    )
                }
                for duplicate in existingProfiles.dropFirst() {
                    context.delete(duplicate)
                }
                object.id = profile.id
                object.role = profile.role.rawValue
                object.nickname = profile.nickname
                object.officeCode = profile.school?.officeCode
                object.schoolCode = profile.school?.schoolCode
                object.allergyCodesJSON = try String(
                    data: JSONEncoder().encode(profile.allergyCodes),
                    encoding: .utf8
                ) ?? "[]"
                try saveContext(context)
            } catch {
                context.rollback()
                metadataStore.restore(metadataSnapshot)
                throw error
            }
        }
    }

    func removeIfCurrent(id: String) throws {
        beforeRemove?()
        try context.performAndWait {
            let request = NSFetchRequest<RebuildProfileManagedObject>(
                entityName: RebuildEntityName.profile
            )
            request.predicate = NSPredicate(format: "id == %@", id)
            let objects = try context.fetch(request)
            let fallbackOfficeCode = objects.first?.officeCode
            let fallbackSchoolCode = objects.first?.schoolCode
            for object in objects {
                context.delete(object)
            }
            if context.hasChanges {
                do {
                    try saveContext(context)
                } catch {
                    context.rollback()
                    throw error
                }
            }
            metadataStore.removeIfOwned(
                profileID: id,
                fallbackOfficeCode: fallbackOfficeCode,
                fallbackSchoolCode: fallbackSchoolCode
            )
        }
    }

    private static func profileEntity(
        in context: NSManagedObjectContext
    ) throws -> NSEntityDescription {
        guard let entity = NSEntityDescription.entity(
            forEntityName: RebuildEntityName.profile,
            in: context
        ) else {
            throw RebuildOnboardingError.persistenceUnavailable
        }
        return entity
    }
}

final class RebuildCoreDataOnboardingProfileStore:
    RebuildOnboardingProfileStore,
    @unchecked Sendable {
    private let coordinator: RebuildOnboardingProfileTransactionCoordinator

    init(container: NSPersistentContainer) {
        coordinator = RebuildOnboardingProfileTransactionCoordinator(
            container: container
        )
    }

    init(coordinator: RebuildOnboardingProfileTransactionCoordinator) {
        self.coordinator = coordinator
    }

    func load() async throws -> RebuildUserProfile? {
        try await coordinator.load()
    }

    func save(_ profile: RebuildUserProfile) async throws {
        try await coordinator.save(profile)
    }

    func removeIfCurrent(id: String) async throws {
        try await coordinator.removeIfCurrent(id: id)
    }
}

struct RebuildLiveSchoolSearchClient: RebuildSchoolSearchClient {
    private let client: NEISClient

    init(client: NEISClient = NEISClient()) {
        self.client = client
    }

    func search(query: String) async throws -> [RebuildOnboardingSchool] {
        do {
            let data = try await client.request(
                path: "schoolInfo",
                query: ["SCHUL_NM": query]
            )
            let response = try JSONDecoder().decode(
                RebuildSchoolInfoResponse.self,
                from: data
            )
            if let result = response.RESULT {
                if result.CODE == "INFO-200" {
                    return []
                }
                throw RebuildSchoolSearchError.result(
                    code: result.CODE,
                    message: result.MESSAGE
                )
            }
            guard let sections = response.schoolInfo else {
                throw RebuildSchoolSearchError.malformedResponse
            }
            let rowSections = sections.compactMap(\.row)
            let rows = rowSections.flatMap { $0 }
            guard
                !sections.isEmpty,
                !rowSections.isEmpty,
                !rows.isEmpty
            else {
                throw RebuildSchoolSearchError.malformedResponse
            }
            return rows.map {
                RebuildOnboardingSchool(
                    name: $0.SCHUL_NM,
                    officeCode: $0.ATPT_OFCDC_SC_CODE,
                    schoolCode: $0.SD_SCHUL_CODE
                )
            }
        } catch let error as RebuildSchoolSearchError {
            throw error
        } catch is DecodingError {
            throw RebuildSchoolSearchError.malformedResponse
        }
    }
}

enum RebuildSchoolSearchError: Error, Equatable {
    case malformedResponse
    case result(code: String, message: String?)
}

private struct RebuildSchoolInfoResponse: Decodable {
    let schoolInfo: [RebuildSchoolInfoSection]?
    let RESULT: RebuildSchoolInfoResult?
}

private struct RebuildSchoolInfoSection: Decodable {
    let row: [RebuildSchoolInfoRow]?
}

private struct RebuildSchoolInfoRow: Decodable {
    let ATPT_OFCDC_SC_CODE: String
    let SD_SCHUL_CODE: String
    let SCHUL_NM: String
}

private struct RebuildSchoolInfoResult: Decodable {
    let CODE: String
    let MESSAGE: String?
}

@MainActor
final class RebuildOnboardingAppStore {
    static let shared: RebuildOnboardingAppStore? = try? RebuildOnboardingAppStore()

    let container: NSPersistentContainer
    let profileStore: RebuildCoreDataOnboardingProfileStore

    private init() throws {
        let container = try RebuildPersistentStore.makePersistent()
        // Preserve legacy school, meal, and growth data before deciding whether
        // the user needs the rebuild onboarding flow.
        _ = try? RebuildMigrationCoordinator(
            container: container
        ).runIfNeeded()
        self.container = container
        let coordinator = RebuildOnboardingProfileTransactionCoordinator(
            container: container,
            metadataStore: RebuildSchoolNameMetadataStore()
        )
        profileStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: coordinator
        )
    }
}
