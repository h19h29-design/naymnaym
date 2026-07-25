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
    func save(_ profile: RebuildUserProfile) throws
}

protocol RebuildSchoolSearchClient {
    func search(query: String) async throws -> [RebuildOnboardingSchool]
}

final class RebuildCoreDataOnboardingProfileStore: RebuildOnboardingProfileStore {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func save(_ profile: RebuildUserProfile) throws {
        let context = container.newBackgroundContext()
        try context.performAndWait {
            do {
                let request = NSFetchRequest<RebuildProfileManagedObject>(
                    entityName: RebuildEntityName.profile
                )
                request.predicate = NSPredicate(format: "id == %@", profile.id)
                request.fetchLimit = 1
                let object = try context.fetch(request).first
                    ?? RebuildProfileManagedObject(
                        entity: try profileEntity(in: context),
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

    private func profileEntity(
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
        let data = try await client.request(
            path: "schoolInfo",
            query: ["SCHUL_NM": query]
        )
        let response = try JSONDecoder().decode(
            RebuildSchoolInfoResponse.self,
            from: data
        )
        return response.schoolInfo?
            .flatMap { $0.row ?? [] }
            .map {
                RebuildOnboardingSchool(
                    name: $0.SCHUL_NM,
                    officeCode: $0.ATPT_OFCDC_SC_CODE,
                    schoolCode: $0.SD_SCHUL_CODE
                )
            } ?? []
    }
}

private struct RebuildSchoolInfoResponse: Decodable {
    let schoolInfo: [RebuildSchoolInfoSection]?
}

private struct RebuildSchoolInfoSection: Decodable {
    let row: [RebuildSchoolInfoRow]?
}

private struct RebuildSchoolInfoRow: Decodable {
    let ATPT_OFCDC_SC_CODE: String
    let SD_SCHUL_CODE: String
    let SCHUL_NM: String
}
