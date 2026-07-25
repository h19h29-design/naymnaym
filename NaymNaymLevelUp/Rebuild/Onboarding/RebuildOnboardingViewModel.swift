import Foundation

@MainActor
final class RebuildOnboardingViewModel: ObservableObject {
    typealias Sleep = (UInt64) async throws -> Void

    static let searchDebounceNanoseconds: UInt64 = 300_000_000

    @Published private(set) var step: RebuildOnboardingStep = .role
    @Published private(set) var draft = OnboardingDraft()
    @Published private(set) var validationMessage: String?
    @Published private(set) var schoolSearchState: RebuildSchoolSearchState = .idle
    @Published private(set) var completedProfile: RebuildUserProfile?

    private let profileStore: RebuildOnboardingProfileStore
    private let schoolSearchClient: RebuildSchoolSearchClient
    private let demoMode: Bool
    private let demoSchools: [RebuildOnboardingSchool]
    private let sleep: Sleep
    private var searchGeneration = 0

    init(
        profileStore: RebuildOnboardingProfileStore,
        schoolSearchClient: RebuildSchoolSearchClient,
        demoMode: Bool = false,
        demoSchools: [RebuildOnboardingSchool] = [],
        sleep: @escaping Sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.profileStore = profileStore
        self.schoolSearchClient = schoolSearchClient
        self.demoMode = demoMode
        self.demoSchools = demoSchools
        self.sleep = sleep
    }

    var progressText: String {
        let steps = visibleSteps
        let index = (steps.firstIndex(of: step) ?? 0) + 1
        return "\(index)/\(steps.count)"
    }

    func selectRole(_ role: RebuildOnboardingRole) {
        draft.role = role
        if role == .parent {
            draft.school = nil
            draft.allergyCodes = []
        }
        validationMessage = nil
        step = .nickname
    }

    func setNickname(_ nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...12).contains(trimmed.count) else {
            validationMessage = "별명을 1~12자로 입력해 주세요."
            return
        }
        draft.nickname = trimmed
        validationMessage = nil
        step = draft.role == .parent ? .confirmation : .school
    }

    func selectSchool(_ school: RebuildOnboardingSchool) {
        draft.school = school
        validationMessage = nil
        step = .allergies
    }

    func setAllergies(_ allergyCodes: [Int]) {
        draft.allergyCodes = Array(Set(allergyCodes)).sorted()
        validationMessage = nil
        step = .confirmation
    }

    func complete() async throws -> RebuildUserProfile {
        guard step == .confirmation else {
            throw RebuildOnboardingError.wrongStep
        }
        guard let role = draft.role else {
            throw RebuildOnboardingError.missingRole
        }
        guard (1...12).contains(draft.nickname.count) else {
            throw RebuildOnboardingError.invalidNickname
        }
        if role == .child {
            guard
                let school = draft.school,
                !school.officeCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !school.schoolCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw RebuildOnboardingError.missingSchoolIdentifiers
            }
        }

        let profile = RebuildUserProfile(
            id: "current",
            role: role,
            nickname: draft.nickname,
            school: role == .child ? draft.school : nil,
            allergyCodes: role == .child ? draft.allergyCodes : [],
            destination: role == .child ? .today : .parentConnection
        )
        try profileStore.save(profile)
        completedProfile = profile
        return profile
    }

    func cancel() {
        searchGeneration += 1
        draft = OnboardingDraft()
        step = .role
        validationMessage = nil
        schoolSearchState = .idle
        completedProfile = nil
    }

    func searchSchools(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        guard !trimmed.isEmpty else {
            schoolSearchState = .idle
            return
        }
        schoolSearchState = .loading
        do {
            try await sleep(Self.searchDebounceNanoseconds)
            guard generation == searchGeneration else { return }
            if demoMode {
                let matches = demoSchools.filter {
                    $0.name.localizedCaseInsensitiveContains(trimmed)
                }
                schoolSearchState = .demoResults(
                    matches.isEmpty ? demoSchools : matches
                )
                return
            }
            let schools = try await schoolSearchClient.search(query: trimmed)
            guard generation == searchGeneration else { return }
            schoolSearchState = schools.isEmpty ? .empty : .results(schools)
        } catch is CancellationError {
            return
        } catch {
            guard generation == searchGeneration else { return }
            schoolSearchState = .failed(
                "학교 검색에 실패했어요. 네트워크 상태를 확인해 주세요."
            )
        }
    }

    private var visibleSteps: [RebuildOnboardingStep] {
        if draft.role == .parent {
            return [.role, .nickname, .confirmation]
        }
        return RebuildOnboardingStep.allCases
    }
}
