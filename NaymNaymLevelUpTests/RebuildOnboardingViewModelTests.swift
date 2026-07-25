import XCTest
import Foundation
import CoreData
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

    func testNicknameCountsExtendedGraphemeClustersOnBothSidesOfLimit() {
        let viewModel = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.child)

        viewModel.setNickname(String(repeating: "👨‍👩‍👧‍👦", count: 12))
        XCTAssertEqual(viewModel.step, .school)

        viewModel.cancel()
        viewModel.selectRole(.child)
        viewModel.setNickname(String(repeating: "👨‍👩‍👧‍👦", count: 13))
        XCTAssertEqual(viewModel.step, .nickname)

        viewModel.setNickname("🇰🇷e\u{301}")
        XCTAssertEqual(viewModel.step, .school)
        XCTAssertEqual(viewModel.draft.nickname.count, 2)
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

    func testDuplicateCompletionTapStartsOnlyOneSave() async throws {
        let store = ControlledOnboardingProfileStore()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.parent)
        viewModel.setNickname("보호자")

        let first = Task { try await viewModel.complete() }
        await store.waitUntilSaveStarts()
        XCTAssertTrue(viewModel.isCompleting)

        await XCTAssertThrowsErrorAsync(try await viewModel.complete()) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .completionInProgress
            )
        }
        XCTAssertEqual(store.saveCount, 1)

        store.finishSave()
        _ = try await first.value
        XCTAssertFalse(viewModel.isCompleting)
    }

    func testCancelDuringSaveNeverPublishesCompletion() async {
        let store = ControlledOnboardingProfileStore()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.parent)
        viewModel.setNickname("보호자")

        let completion = Task { try await viewModel.complete() }
        await store.waitUntilSaveStarts()
        viewModel.cancel()
        store.finishSave()

        await XCTAssertThrowsErrorAsync(try await completion.value) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .completionCancelled
            )
        }
        XCTAssertNil(viewModel.completedProfile)
        XCTAssertEqual(viewModel.step, .role)

        let restoredProfile = try? await store.load()
        XCTAssertNil(restoredProfile)
        let recreatedRoot = RebuildOnboardingBootstrapViewModel(
            profileStore: store
        )
        await recreatedRoot.load()
        XCTAssertEqual(recreatedRoot.state, .onboarding)
    }

    func testCancelledSaveCleanupNeverDeletesLaterProfile() async throws {
        let store = RacingOnboardingProfileStore()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.parent)
        viewModel.setNickname("취소할 보호자")

        let cancelled = Task { try await viewModel.complete() }
        await store.waitUntilFirstSaveStarts()
        viewModel.cancel()
        store.finishFirstSave()
        await store.waitUntilRemovalStarts()

        viewModel.selectRole(.parent)
        viewModel.setNickname("최종 보호자")
        let latest = try await viewModel.complete()
        store.finishRemoval()

        await XCTAssertThrowsErrorAsync(try await cancelled.value) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .completionCancelled
            )
        }
        let restoredProfile = try await store.load()
        XCTAssertEqual(restoredProfile, latest)
    }

    func testBootstrapLoadsPersistedProfilesAndRoutesWithoutOnboarding() async {
        let child = RebuildUserProfile.fixture(role: .child)
        let childStore = OnboardingProfileStoreSpy(loadedProfile: child)
        let firstLaunch = RebuildOnboardingBootstrapViewModel(
            profileStore: childStore
        )
        await firstLaunch.load()
        XCTAssertEqual(firstLaunch.state, .destination(child))

        let recreatedRoot = RebuildOnboardingBootstrapViewModel(
            profileStore: childStore
        )
        await recreatedRoot.load()
        XCTAssertEqual(recreatedRoot.state, .destination(child))

        let parent = RebuildUserProfile.fixture(role: .parent)
        let parentRoot = RebuildOnboardingBootstrapViewModel(
            profileStore: OnboardingProfileStoreSpy(loadedProfile: parent)
        )
        await parentRoot.load()
        XCTAssertEqual(parentRoot.state, .destination(parent))
        XCTAssertEqual(parent.destination, .parentConnection)
    }

    func testBootstrapShowsOnboardingOnlyWhenNoProfileExists() async {
        let bootstrap = RebuildOnboardingBootstrapViewModel(
            profileStore: OnboardingProfileStoreSpy()
        )

        await bootstrap.load()

        XCTAssertEqual(bootstrap.state, .onboarding)
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

    func testSchoolSearchTreatsInfo200AsEmptyAndRejectsErrorOrMalformedRows() async throws {
        let noData = makeSchoolClient(
            #"{"RESULT":{"CODE":"INFO-200","MESSAGE":"no data"}}"#
        )
        let noDataResults = try await noData.search(query: "없는학교")
        XCTAssertEqual(noDataResults, [])

        let serverError = makeSchoolClient(
            #"{"RESULT":{"CODE":"ERROR-300","MESSAGE":"auth failed"}}"#
        )
        await XCTAssertThrowsErrorAsync(
            try await serverError.search(query: "냠냠초")
        ) { error in
            XCTAssertEqual(
                error as? RebuildSchoolSearchError,
                .result(code: "ERROR-300", message: "auth failed")
            )
        }

        let malformed = makeSchoolClient(
            #"{"schoolInfo":[{"row":[{"SCHUL_NM":"코드 없는 학교"}]}]}"#
        )
        await XCTAssertThrowsErrorAsync(
            try await malformed.search(query: "코드 없는 학교")
        ) { error in
            XCTAssertEqual(
                error as? RebuildSchoolSearchError,
                .malformedResponse
            )
        }

        let missingRowsWithoutResult = [
            #"{"schoolInfo":[]}"#,
            #"{"schoolInfo":[{"head":[{"list_total_count":1}]}]}"#,
            #"{"schoolInfo":[{"head":[{"list_total_count":1}]},{"row":[]}]}"#,
            #"{"schoolInfo":[{"head":[{"list_total_count":1}]},{"other":[]}]}"#
        ]
        for payload in missingRowsWithoutResult {
            let client = makeSchoolClient(payload)
            await XCTAssertThrowsErrorAsync(
                try await client.search(query: "행 없는 학교")
            ) { error in
                XCTAssertEqual(
                    error as? RebuildSchoolSearchError,
                    .malformedResponse
                )
            }
        }
    }

    func testRebuildProfileBridgeMakesLegacyDestinationsUseStoredRoleAndSchool() {
        let suiteName = "RebuildProfileBridge-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults)
        )

        appState.applyRebuildProfile(.fixture(role: .child))

        XCTAssertEqual(appState.currentMode, .elementary)
        XCTAssertEqual(appState.profile?.nickname, "냠냠이")
        XCTAssertEqual(appState.profile?.schoolName, "서울 냠냠초")
        XCTAssertEqual(appState.profile?.officeCode, "B10")
        XCTAssertEqual(appState.profile?.schoolCode, "7010111")
        XCTAssertEqual(appState.profile?.selectedAllergyCodes, [1, 5])

        appState.applyRebuildProfile(.fixture(role: .parent))

        XCTAssertEqual(appState.currentMode, .parent)
        XCTAssertEqual(appState.profile?.nickname, "보호자")
        XCTAssertEqual(
            UserProfileStore(defaults: defaults).load()?.effectiveMode,
            .parent
        )
    }

    func testRealCoreDataStoreSerializesCancelledCleanupBeforeLaterSave() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataRace-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let removalStarted = expectation(description: "remove started")
        let allowRemoval = DispatchSemaphore(value: 0)
        let coordinator = RebuildOnboardingProfileTransactionCoordinator(
            container: container,
            metadataStore: RebuildSchoolNameMetadataStore(defaults: defaults),
            beforeRemove: {
                removalStarted.fulfill()
                allowRemoval.wait()
            }
        )
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: coordinator
        )
        let cancelled = RebuildUserProfile(
            id: "cancelled",
            role: .child,
            nickname: "취소",
            school: .fixture,
            allergyCodes: [1],
            destination: .today
        )
        let later = RebuildUserProfile(
            id: "later",
            role: .child,
            nickname: "최종",
            school: RebuildOnboardingSchool(
                name: "정확한 학교명",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [5],
            destination: .today
        )
        try await store.save(cancelled)

        let cleanup = Task {
            try await store.removeIfCurrent(id: cancelled.id)
        }
        await fulfillment(of: [removalStarted], timeout: 2)
        let laterSave = Task {
            try await store.save(later)
        }
        allowRemoval.signal()
        try await cleanup.value
        try await laterSave.value

        let loaded = try await store.load()
        XCTAssertEqual(loaded, later)
    }

    func testConcurrentRealCoreDataSavesLeaveExactlyOneCurrentProfile() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataConcurrent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: RebuildSchoolNameMetadataStore(defaults: defaults)
            )
        )
        let first = RebuildUserProfile.fixture(role: .child, id: "first")
        let second = RebuildUserProfile.fixture(role: .child, id: "second")

        async let firstSave: Void = store.save(first)
        async let secondSave: Void = store.save(second)
        _ = try await (firstSave, secondSave)

        let count = try container.viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(
                entityName: RebuildEntityName.profile
            )
            return try container.viewContext.count(for: request)
        }
        XCTAssertEqual(count, 1)
        let loaded = try await store.load()
        XCTAssertTrue([first, second].contains(loaded))
    }

    func testRealStoreReloadPreservesExactSchoolDisplayNameWithoutSchemaChange() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataReload-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadataStore = RebuildSchoolNameMetadataStore(defaults: defaults)
        let profile = RebuildUserProfile(
            id: "named-profile",
            role: .child,
            nickname: "냠냠이",
            school: RebuildOnboardingSchool(
                name: "서울 냠냠초등학교",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [1, 5],
            destination: .today
        )
        let firstStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadataStore
            )
        )
        try await firstStore.save(profile)

        let relaunchedStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadataStore
            )
        )

        let reloaded = try await relaunchedStore.load()
        XCTAssertEqual(reloaded?.school?.name, "서울 냠냠초등학교")
    }

    func testRealStoreWithoutSchoolNameMetadataUsesBackwardsFallback() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataFallback-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try container.viewContext.performAndWait {
            guard let entity = NSEntityDescription.entity(
                forEntityName: RebuildEntityName.profile,
                in: container.viewContext
            ) else {
                throw RebuildOnboardingError.persistenceUnavailable
            }
            let object = RebuildProfileManagedObject(
                entity: entity,
                insertInto: container.viewContext
            )
            object.id = "legacy-profile"
            object.role = RebuildOnboardingRole.child.rawValue
            object.nickname = "냠냠이"
            object.officeCode = "B10"
            object.schoolCode = "7010111"
            object.allergyCodesJSON = "[1,5]"
            try container.viewContext.save()
        }
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: RebuildSchoolNameMetadataStore(defaults: defaults)
            )
        )

        let loaded = try await store.load()

        XCTAssertEqual(loaded?.school?.name, "등록한 학교")
    }

    func testRootBridgeBecomesReadyOnlyAfterLegacyStateIsApplied() {
        let suiteName = "RebuildBridgeOrder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults)
        )
        let bridge = RebuildLegacyProfileBridge()
        let profile = RebuildUserProfile.fixture(role: .child)

        XCTAssertEqual(bridge.state, .pending)
        bridge.prepare(profile, appState: appState)

        XCTAssertEqual(bridge.state, .ready(profile))
        XCTAssertEqual(appState.profile?.officeCode, "B10")
        XCTAssertEqual(appState.profile?.schoolCode, "7010111")
        XCTAssertEqual(appState.profile?.selectedAllergyCodes, [1, 5])
        XCTAssertEqual(appState.currentMode, .elementary)
    }
}

private final class OnboardingProfileStoreSpy: RebuildOnboardingProfileStore {
    private(set) var savedProfiles: [RebuildUserProfile] = []
    private let error: Error?
    private let loadedProfile: RebuildUserProfile?

    init(
        error: Error? = nil,
        loadedProfile: RebuildUserProfile? = nil
    ) {
        self.error = error
        self.loadedProfile = loadedProfile
    }

    func load() async throws -> RebuildUserProfile? {
        loadedProfile
    }

    func save(_ profile: RebuildUserProfile) async throws {
        if let error {
            throw error
        }
        savedProfiles.append(profile)
    }

    func removeIfCurrent(id: String) async throws {
        if savedProfiles.last?.id == id {
            savedProfiles.removeLast()
        }
    }
}

@MainActor
private final class ControlledOnboardingProfileStore:
    RebuildOnboardingProfileStore {
    private(set) var saveCount = 0
    private var persistedProfile: RebuildUserProfile?
    private var saveContinuation: CheckedContinuation<Void, Error>?

    func load() async throws -> RebuildUserProfile? {
        persistedProfile
    }

    func save(_ profile: RebuildUserProfile) async throws {
        saveCount += 1
        try await withCheckedThrowingContinuation { continuation in
            saveContinuation = continuation
        }
        persistedProfile = profile
    }

    func removeIfCurrent(id: String) async throws {
        if persistedProfile?.id == id {
            persistedProfile = nil
        }
    }

    func waitUntilSaveStarts() async {
        while saveContinuation == nil {
            await Task.yield()
        }
    }

    func finishSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

@MainActor
private final class RacingOnboardingProfileStore:
    RebuildOnboardingProfileStore {
    private var persistedProfile: RebuildUserProfile?
    private var saveCount = 0
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?
    private var removalContinuation: CheckedContinuation<Void, Never>?
    private var removalStarted = false

    func load() async throws -> RebuildUserProfile? {
        persistedProfile
    }

    func save(_ profile: RebuildUserProfile) async throws {
        saveCount += 1
        if saveCount == 1 {
            await withCheckedContinuation { continuation in
                firstSaveContinuation = continuation
            }
        }
        persistedProfile = profile
    }

    func removeIfCurrent(id: String) async throws {
        removalStarted = true
        await withCheckedContinuation { continuation in
            removalContinuation = continuation
        }
        if persistedProfile?.id == id {
            persistedProfile = nil
        }
    }

    func waitUntilFirstSaveStarts() async {
        while firstSaveContinuation == nil {
            await Task.yield()
        }
    }

    func finishFirstSave() {
        firstSaveContinuation?.resume()
        firstSaveContinuation = nil
    }

    func waitUntilRemovalStarts() async {
        while !removalStarted {
            await Task.yield()
        }
    }

    func finishRemoval() {
        removalContinuation?.resume()
        removalContinuation = nil
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

private final class OnboardingURLProtocol: URLProtocol {
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    override func startLoading() {
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func makeSchoolClient(
    _ json: String
) -> RebuildLiveSchoolSearchClient {
    OnboardingURLProtocol.responseData = Data(json.utf8)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OnboardingURLProtocol.self]
    return RebuildLiveSchoolSearchClient(
        client: NEISClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com")!,
            session: URLSession(configuration: configuration)
        )
    )
}

private extension RebuildOnboardingSchool {
    static let fixture = RebuildOnboardingSchool(
        name: "서울 냠냠초",
        officeCode: "B10",
        schoolCode: "7010111"
    )
}

private extension RebuildUserProfile {
    static func fixture(
        role: RebuildOnboardingRole,
        id: String = "current"
    ) -> RebuildUserProfile {
        RebuildUserProfile(
            id: id,
            role: role,
            nickname: role == .child ? "냠냠이" : "보호자",
            school: role == .child ? .fixture : nil,
            allergyCodes: role == .child ? [1, 5] : [],
            destination: role == .child ? .today : .parentConnection
        )
    }
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
