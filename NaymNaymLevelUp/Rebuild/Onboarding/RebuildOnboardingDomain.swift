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
}

protocol RebuildSchoolSearchClient {
    func search(query: String) async throws -> [RebuildOnboardingSchool]
}

final class RebuildCoreDataOnboardingProfileStore:
    RebuildOnboardingProfileStore,
    @unchecked Sendable {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func load() async throws -> RebuildUserProfile? {
        let context = container.newBackgroundContext()
        return try await context.perform {
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
                    name: "등록한 학교",
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

    func save(_ profile: RebuildUserProfile) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            do {
                let request = NSFetchRequest<RebuildProfileManagedObject>(
                    entityName: RebuildEntityName.profile
                )
                request.predicate = NSPredicate(format: "id == %@", profile.id)
                request.fetchLimit = 1
                let object = try context.fetch(request).first
                    ?? RebuildProfileManagedObject(
                        entity: try Self.profileEntity(in: context),
                        insertInto: context
                    )
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
            return sections
                .flatMap { $0.row ?? [] }
                .map {
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
        profileStore = RebuildCoreDataOnboardingProfileStore(
            container: container
        )
    }
}
