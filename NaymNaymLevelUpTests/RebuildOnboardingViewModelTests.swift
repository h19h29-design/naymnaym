import XCTest
@testable import NaymNaymLevelUp

@MainActor
final class RebuildOnboardingViewModelTests: XCTestCase {
    func testChildFlowTrimsNicknameAndSavesCanonicalProfileOnce() async throws {
        let store = OnboardingProfileStoreSpy()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )

        XCTAssertEqual(viewModel.step, .role)
        viewModel.selectRole(.child)
        XCTAssertEqual(viewModel.step, .nickname)
        viewModel.setNickname(" 냠냠이 ")
        XCTAssertEqual(viewModel.step, .school)
        viewModel.selectSchool(.fixture)
        XCTAssertEqual(viewModel.step, .allergies)
        viewModel.setAllergies([5, 1, 5])
        XCTAssertEqual(viewModel.step, .confirmation)

        let profile = try await viewModel.complete()

        XCTAssertEqual(profile.nickname, "냠냠이")
        XCTAssertEqual(profile.school, .fixture)
        XCTAssertEqual(profile.allergyCodes, [1, 5])
        XCTAssertEqual(profile.destination, .today)
        XCTAssertEqual(store.savedProfiles, [profile])
    }

    func testParentSkipsSchoolAndAllergiesAndRoutesToConnection() async throws {
        let store = OnboardingProfileStoreSpy()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )

        viewModel.selectRole(.parent)
        viewModel.setNickname("보호자")

        XCTAssertEqual(viewModel.step, .confirmation)
        let profile = try await viewModel.complete()
        XCTAssertNil(profile.school)
        XCTAssertEqual(profile.allergyCodes, [])
        XCTAssertEqual(profile.destination, .parentConnection)
    }

    func testNicknameUsesTrimmedGraphemeClusterLimit() {
        let viewModel = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.child)

        viewModel.setNickname("   ")
        XCTAssertEqual(viewModel.step, .nickname)
        XCTAssertEqual(viewModel.validationMessage, "별명을 1~12자로 입력해 주세요.")

        viewModel.setNickname(String(repeating: "🍱", count: 13))
        XCTAssertEqual(viewModel.step, .nickname)
        XCTAssertEqual(viewModel.validationMessage, "별명을 1~12자로 입력해 주세요.")

        viewModel.setNickname(String(repeating: "🍱", count: 12))
        XCTAssertEqual(viewModel.step, .school)
        XCTAssertNil(viewModel.validationMessage)
    }

    func testChildCompletionRequiresBothSchoolIdentifiers() async {
        let store = OnboardingProfileStoreSpy()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.child)
        viewModel.setNickname("냠냠이")
        viewModel.selectSchool(
            RebuildOnboardingSchool(
                name: "잘못된 학교",
                officeCode: "",
                schoolCode: "7010111"
            )
        )
        viewModel.setAllergies([])

        await XCTAssertThrowsErrorAsync(try await viewModel.complete()) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .missingSchoolIdentifiers
            )
        }
        XCTAssertTrue(store.savedProfiles.isEmpty)
    }

    func testCancelLeavesNoPartialProfile() {
        let store = OnboardingProfileStoreSpy()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.child)
        viewModel.setNickname("냠냠이")
        viewModel.selectSchool(.fixture)

        viewModel.cancel()

        XCTAssertEqual(viewModel.step, .role)
        XCTAssertEqual(viewModel.draft, OnboardingDraft())
        XCTAssertTrue(store.savedProfiles.isEmpty)
    }

    func testCompletionFailureDoesNotPublishCompletedProfile() async {
        let store = OnboardingProfileStoreSpy(error: TestError.saveFailed)
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.parent)
        viewModel.setNickname("보호자")

        await XCTAssertThrowsErrorAsync(try await viewModel.complete())

        XCTAssertNil(viewModel.completedProfile)
        XCTAssertEqual(viewModel.step, .confirmation)
        XCTAssertTrue(store.savedProfiles.isEmpty)
    }

    func testSchoolSearchDebouncesAndDistinguishesResultsEmptyAndFailure() async {
        let delay = DelayRecorder()
        let results = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub(schools: [.fixture]),
            sleep: { nanoseconds in
                delay.values.append(nanoseconds)
            }
        )

        await results.searchSchools(query: " 냠냠초 ")

        XCTAssertEqual(delay.values, [300_000_000])
        XCTAssertEqual(results.schoolSearchState, .results([.fixture]))

        let empty = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub()
        )
        await empty.searchSchools(query: "없는학교")
        XCTAssertEqual(empty.schoolSearchState, .empty)

        let failed = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub(error: TestError.offline)
        )
        await failed.searchSchools(query: "냠냠초")
        XCTAssertEqual(failed.schoolSearchState, .failed("학교 검색에 실패했어요. 네트워크 상태를 확인해 주세요."))
    }

    func testSampleSchoolsAppearOnlyInExplicitDemoMode() async {
        let live = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub(error: TestError.offline),
            demoMode: false,
            demoSchools: [.fixture]
        )
        await live.searchSchools(query: "냠냠")
        XCTAssertEqual(live.schoolSearchState, .failed("학교 검색에 실패했어요. 네트워크 상태를 확인해 주세요."))

        let demo = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub(error: TestError.offline),
            demoMode: true,
            demoSchools: [.fixture]
        )
        await demo.searchSchools(query: "냠냠")
        XCTAssertEqual(demo.schoolSearchState, .demoResults([.fixture]))
    }
}

private final class OnboardingProfileStoreSpy: RebuildOnboardingProfileStore {
    private(set) var savedProfiles: [RebuildUserProfile] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func save(_ profile: RebuildUserProfile) throws {
        if let error {
            throw error
        }
        savedProfiles.append(profile)
    }
}

private struct SchoolSearchClientStub: RebuildSchoolSearchClient {
    var schools: [RebuildOnboardingSchool] = []
    var error: Error?

    func search(query: String) async throws -> [RebuildOnboardingSchool] {
        if let error {
            throw error
        }
        return schools
    }
}

private final class DelayRecorder {
    var values: [UInt64] = []
}

private enum TestError: Error {
    case offline
    case saveFailed
}

private extension RebuildOnboardingSchool {
    static let fixture = RebuildOnboardingSchool(
        name: "서울 냠냠초",
        officeCode: "B10",
        schoolCode: "7010111"
    )
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
