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

struct OnboardingDraft: Equatable, Sendable {
    var role: RebuildOnboardingRole?
    var nickname = ""
    var school: RebuildOnboardingSchool?
    var allergyCodes: [Int] = []
}

struct RebuildUserProfile: Equatable, Sendable {
    let id: String
    let role: RebuildOnboardingRole
    let nickname: String
    let school: RebuildOnboardingSchool?
    let allergyCodes: [Int]
    let destination: RebuildOnboardingDestination
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
    struct Snapshot {
        let profileKey: String
        let profileValue: String?
        let schoolKey: String?
        let schoolValue: String?
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
        defaults.string(forKey: profileKey(profileID))
            ?? defaults.string(forKey: schoolKey(officeCode, schoolCode))
    }

    func write(_ profile: RebuildUserProfile) -> Snapshot {
        let idKey = profileKey(profile.id)
        guard let school = profile.school else {
            let snapshot = Snapshot(
                profileKey: idKey,
                profileValue: defaults.string(forKey: idKey),
                schoolKey: nil,
                schoolValue: nil
            )
            defaults.removeObject(forKey: idKey)
            return snapshot
        }
        let codeKey = schoolKey(school.officeCode, school.schoolCode)
        let snapshot = Snapshot(
            profileKey: idKey,
            profileValue: defaults.string(forKey: idKey),
            schoolKey: codeKey,
            schoolValue: defaults.string(forKey: codeKey)
        )
        defaults.set(school.name, forKey: idKey)
        defaults.set(school.name, forKey: codeKey)
        return snapshot
    }

    func restore(_ snapshot: Snapshot) {
        restore(snapshot.profileValue, forKey: snapshot.profileKey)
        if let schoolKey = snapshot.schoolKey {
            restore(snapshot.schoolValue, forKey: schoolKey)
        }
    }

    func removeProfile(id: String) {
        defaults.removeObject(forKey: profileKey(id))
    }

    private func restore(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func profileKey(_ id: String) -> String {
        "rebuild.school-name.profile.\(id)"
    }

    private func schoolKey(_ officeCode: String, _ schoolCode: String) -> String {
        "rebuild.school-name.codes.\(officeCode).\(schoolCode)"
    }
}

actor RebuildOnboardingProfileTransactionCoordinator {
    private let context: NSManagedObjectContext
    private let metadataStore: RebuildSchoolNameMetadataStore
    private let beforeRemove: (() -> Void)?

    init(
        container: NSPersistentContainer,
        metadataStore: RebuildSchoolNameMetadataStore = .init(),
        beforeRemove: (() -> Void)? = nil
    ) {
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.metadataStore = metadataStore
        self.beforeRemove = beforeRemove
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
                destination: role == .child ? .today : .parentConnection
            )
        }
    }

    func save(_ profile: RebuildUserProfile) throws {
        try context.performAndWait {
            let metadataSnapshot = metadataStore.write(profile)
            do {
                let request = NSFetchRequest<RebuildProfileManagedObject>(
                    entityName: RebuildEntityName.profile
                )
                request.sortDescriptors = [
                    NSSortDescriptor(key: "id", ascending: true)
                ]
                let existingProfiles = try context.fetch(request)
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
                try context.save()
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
            guard !objects.isEmpty else { return }
            for object in objects {
                context.delete(object)
            }
            do {
                try context.save()
                metadataStore.removeProfile(id: id)
            } catch {
                context.rollback()
                throw error
            }
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
