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
        let saveStarted = expectation(description: "first save started")
        store.onSaveStarted = { saveStarted.fulfill() }
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.parent)
        viewModel.setNickname("보호자")

        let first = Task { try await viewModel.complete() }
        await fulfillment(of: [saveStarted], timeout: 2)
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
        let saveStarted = expectation(description: "save started")
        store.onSaveStarted = { saveStarted.fulfill() }
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.parent)
        viewModel.setNickname("보호자")

        let completion = Task { try await viewModel.complete() }
        await fulfillment(of: [saveStarted], timeout: 2)
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

    func testTwoRapidCancelledCompletionsRestoreSeededProfileAfterEachCleanup() async throws {
        let previous = RebuildUserProfile.fixture(
            role: .child,
            id: "rapid-cancellation-seed",
            isDemoMode: true
        )
        let store = RapidCancellationProfileStore(seed: previous)
        let firstSaveStarted = expectation(description: "first rapid save started")
        let firstRemovalStarted = expectation(description: "first rapid removal started")
        let secondSaveStarted = expectation(description: "second rapid save started")
        let secondRemovalStarted = expectation(description: "second rapid removal started")
        store.onSaveStarted = { count in
            switch count {
            case 1:
                firstSaveStarted.fulfill()
            case 2:
                secondSaveStarted.fulfill()
            default:
                XCTFail("Unexpected save count: \(count)")
            }
        }
        store.onRemovalStarted = { count in
            switch count {
            case 1:
                firstRemovalStarted.fulfill()
            case 2:
                secondRemovalStarted.fulfill()
            default:
                XCTFail("Unexpected removal count: \(count)")
            }
        }
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )

        viewModel.selectRole(.parent)
        viewModel.setNickname("첫 번째")
        let first = Task { try await viewModel.complete() }
        await fulfillment(of: [firstSaveStarted], timeout: 2)
        viewModel.cancel()
        XCTAssertTrue(viewModel.isCompleting)
        store.finishSave()
        await fulfillment(of: [firstRemovalStarted], timeout: 2)

        viewModel.selectRole(.parent)
        viewModel.setNickname("두 번째")
        await XCTAssertThrowsErrorAsync(try await viewModel.complete()) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .completionInProgress
            )
        }
        store.finishRemoval()
        await XCTAssertThrowsErrorAsync(try await first.value) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .completionCancelled
            )
        }
        XCTAssertFalse(viewModel.isCompleting)
        let restoredAfterFirst = try await store.load()
        XCTAssertEqual(restoredAfterFirst, previous)

        let second = Task { try await viewModel.complete() }
        await fulfillment(of: [secondSaveStarted], timeout: 2)
        viewModel.cancel()
        XCTAssertTrue(viewModel.isCompleting)
        store.finishSave()
        await fulfillment(of: [secondRemovalStarted], timeout: 2)
        XCTAssertTrue(viewModel.isCompleting)
        store.finishRemoval()

        await XCTAssertThrowsErrorAsync(try await second.value) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .completionCancelled
            )
        }
        XCTAssertFalse(viewModel.isCompleting)
        let restoredAfterSecond = try await store.load()
        XCTAssertEqual(restoredAfterSecond, previous)
    }

    func testCancelledReplacementRestoresSeededExistingProfileAndMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildSeededCancellation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let seedStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        let previous = RebuildUserProfile.fixture(
            role: .child,
            id: "seeded-demo",
            isDemoMode: true
        )
        try await seedStore.save(previous)

        let saveStarted = expectation(description: "replacement save started")
        let allowSave = DispatchSemaphore(value: 0)
        var didSignalSaveStart = false
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata,
                saveContext: { context in
                    if !didSignalSaveStart {
                        didSignalSaveStart = true
                        saveStarted.fulfill()
                        allowSave.wait()
                    }
                    try context.save()
                }
            )
        )
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.child)
        viewModel.setNickname("새 사용자")
        viewModel.selectSchool(
            RebuildOnboardingSchool(
                name: "새 학교",
                officeCode: "C10",
                schoolCode: "1234567"
            )
        )
        viewModel.setAllergies([])

        let completion = Task { try await viewModel.complete() }
        await fulfillment(of: [saveStarted], timeout: 2)
        viewModel.cancel()
        allowSave.signal()

        await XCTAssertThrowsErrorAsync(try await completion.value) { error in
            XCTAssertEqual(
                error as? RebuildOnboardingError,
                .completionCancelled
            )
        }
        let restored = try await store.load()
        XCTAssertEqual(restored, previous)
        XCTAssertTrue(metadata.isDemoMode(profileID: previous.id))
        XCTAssertEqual(
            metadata.name(
                profileID: previous.id,
                officeCode: previous.school!.officeCode,
                schoolCode: previous.school!.schoolCode
            ),
            previous.school!.name
        )
    }

    func testCancelledSaveCleanupNeverDeletesLaterProfile() async throws {
        let store = RacingOnboardingProfileStore()
        let firstSaveStarted = expectation(description: "first save started")
        let removalStarted = expectation(description: "removal started")
        store.onFirstSaveStarted = { firstSaveStarted.fulfill() }
        store.onRemovalStarted = { removalStarted.fulfill() }
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )
        viewModel.selectRole(.parent)
        viewModel.setNickname("취소할 보호자")

        let cancelled = Task { try await viewModel.complete() }
        await fulfillment(of: [firstSaveStarted], timeout: 2)
        viewModel.cancel()
        store.finishFirstSave()
        await fulfillment(of: [removalStarted], timeout: 2)

        XCTAssertTrue(viewModel.isCompleting)
        let latest = RebuildUserProfile.fixture(role: .parent, id: "final-parent")
        try await store.save(latest)
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

    func testExplicitDemoSelectionUsesMappedSampleSchoolAndAdvances() {
        let viewModel = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub()
        )

        XCTAssertFalse(viewModel.isDemoSelection)

        viewModel.selectDemoExperience()

        let sample = SampleDataProvider().sampleSchools[0]
        XCTAssertTrue(viewModel.isDemoSelection)
        XCTAssertTrue(viewModel.draft.isDemoMode)
        XCTAssertEqual(viewModel.step, .allergies)
        XCTAssertEqual(
            viewModel.draft.school,
            RebuildOnboardingSchool(
                name: sample.name,
                officeCode: sample.officeCode,
                schoolCode: sample.schoolCode
            )
        )
    }

    func testLiveSchoolWithSampleIdentifiersDoesNotBecomeDemoSelection() {
        let sample = SampleDataProvider().sampleSchools[0]
        let viewModel = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub()
        )

        viewModel.selectSchool(
            RebuildOnboardingSchool(
                name: "실제 학교",
                officeCode: sample.officeCode,
                schoolCode: sample.schoolCode
            )
        )

        XCTAssertFalse(viewModel.draft.isDemoMode)
        XCTAssertFalse(viewModel.isDemoSelection)
    }

    func testExplicitDemoSelectionPersistsIntentOnCompletedProfile() async throws {
        let store = OnboardingProfileStoreSpy()
        let viewModel = RebuildOnboardingViewModel(
            profileStore: store,
            schoolSearchClient: SchoolSearchClientStub()
        )

        viewModel.selectRole(.child)
        viewModel.setNickname("체험이")
        viewModel.selectDemoExperience()
        viewModel.setAllergies([5, 1])

        let profile = try await viewModel.complete()

        XCTAssertTrue(profile.isDemoMode)
        XCTAssertEqual(store.savedProfiles, [profile])
    }

    func testLiveFailureDoesNotBecomeDemoUntilExplicitSelection() async {
        let viewModel = RebuildOnboardingViewModel(
            profileStore: OnboardingProfileStoreSpy(),
            schoolSearchClient: SchoolSearchClientStub(error: TestError.offline)
        )

        await viewModel.searchSchools(query: "냠냠")

        XCTAssertEqual(
            viewModel.schoolSearchState,
            .failed("학교 검색에 실패했어요. 네트워크 상태를 확인해 주세요.")
        )
        XCTAssertFalse(viewModel.isDemoSelection)
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

    func testSeparateProfileCoordinatorRollbackSkipsCompletedLaterRepositorySave() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildSeparateProfileWriterRace-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let coordinator = RebuildOnboardingProfileTransactionCoordinator(
            container: container,
            metadataStore: metadata
        )
        let store = RebuildCoreDataOnboardingProfileStore(coordinator: coordinator)
        let first = RebuildUserProfile.fixture(
            role: .child,
            id: "separate-writer-profile"
        )
        try await store.save(first)
        let capturedToken = try await store.saveAndCaptureRollback(first)
        let token = try XCTUnwrap(capturedToken)

        let repository = RebuildProfileRepository(
            context: container.newBackgroundContext()
        )
        let later = RebuildProfile(
            id: first.id,
            role: first.role.rawValue,
            nickname: "나중 저장",
            officeCode: first.school?.officeCode,
            schoolCode: first.school?.schoolCode,
            allergyCodesJSON: "[1,5]"
        )
        try repository.save(later)
        try await store.rollback(token)

        let loaded = try await store.load()
        XCTAssertEqual(loaded?.id, first.id)
        XCTAssertEqual(loaded?.nickname, later.nickname)
    }

    func testIdenticalLaterCoordinatorWriteInvalidatesRollbackMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildIdenticalMetadataWriter-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let firstStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        let previous = RebuildUserProfile(
            id: "identical-metadata-profile",
            role: .child,
            nickname: "같은 Core Data",
            school: RebuildOnboardingSchool(
                name: "이전 학교명",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [1, 5],
            destination: .today
        )
        let replacement = RebuildUserProfile(
            id: previous.id,
            role: previous.role,
            nickname: previous.nickname,
            school: RebuildOnboardingSchool(
                name: "교체 학교명",
                officeCode: previous.school!.officeCode,
                schoolCode: previous.school!.schoolCode
            ),
            allergyCodes: previous.allergyCodes,
            destination: previous.destination
        )
        let later = RebuildUserProfile(
            id: previous.id,
            role: previous.role,
            nickname: previous.nickname,
            school: RebuildOnboardingSchool(
                name: "나중 학교명",
                officeCode: previous.school!.officeCode,
                schoolCode: previous.school!.schoolCode
            ),
            allergyCodes: previous.allergyCodes,
            destination: previous.destination
        )

        try await firstStore.save(previous)
        let capturedToken = try await firstStore.saveAndCaptureRollback(replacement)
        let token = try XCTUnwrap(capturedToken)
        let secondStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        try await secondStore.save(later)

        try await firstStore.rollback(token)

        XCTAssertEqual(
            metadata.name(
                profileID: later.id,
                officeCode: later.school!.officeCode,
                schoolCode: later.school!.schoolCode
            ),
            later.school!.name
        )
        let loaded = try await firstStore.load()
        XCTAssertEqual(loaded, later)
    }

    func testProfileRollbackGenerationIsScopedToPersistentContainer() async throws {
        let firstContainer = try RebuildPersistentStore.makeInMemory()
        let secondContainer = try RebuildPersistentStore.makeInMemory()
        let firstSuite = "RebuildProfileGenerationFirst-\(UUID().uuidString)"
        let secondSuite = "RebuildProfileGenerationSecond-\(UUID().uuidString)"
        let firstDefaults = UserDefaults(suiteName: firstSuite)!
        let secondDefaults = UserDefaults(suiteName: secondSuite)!
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        let firstStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: firstContainer,
                metadataStore: RebuildSchoolNameMetadataStore(defaults: firstDefaults)
            )
        )
        let secondStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: secondContainer,
                metadataStore: RebuildSchoolNameMetadataStore(defaults: secondDefaults)
            )
        )
        let previous = RebuildUserProfile.fixture(
            role: .child,
            id: "container-scoped-profile"
        )
        let replacement = RebuildUserProfile(
            id: previous.id,
            role: previous.role,
            nickname: "교체 사용자",
            school: previous.school,
            allergyCodes: previous.allergyCodes,
            destination: previous.destination
        )

        try await firstStore.save(previous)
        let capturedToken = try await firstStore.saveAndCaptureRollback(replacement)
        let token = try XCTUnwrap(capturedToken)
        try await secondStore.save(
            RebuildUserProfile.fixture(role: .parent, id: "other-container")
        )

        try await firstStore.rollback(token)

        let loaded = try await firstStore.load()
        XCTAssertEqual(loaded, previous)
    }

    func testFailedReplacementRestoresDivergentProfileAndFallbackSchoolMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildDivergentSchoolMetadataFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let previous = RebuildUserProfile.fixture(
            role: .child,
            id: "divergent-metadata-profile"
        )
        let seedStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        try await seedStore.save(previous)

        let scopedOffice = "C10"
        let scopedSchool = "1234567"
        let fallbackOffice = previous.school!.officeCode
        let fallbackSchool = previous.school!.schoolCode
        defaults.set(
            scopedOffice,
            forKey: "rebuild.school-name.profile.\(previous.id).office"
        )
        defaults.set(
            scopedSchool,
            forKey: "rebuild.school-name.profile.\(previous.id).school"
        )
        let originalNames = [
            (scopedOffice, scopedSchool, "프로필 코드 학교"),
            (scopedOffice, fallbackSchool, "혼합 코드 학교"),
            (fallbackOffice, scopedSchool, "반대 혼합 코드 학교"),
            (fallbackOffice, fallbackSchool, "Core Data 코드 학교"),
        ]
        for (office, school, name) in originalNames {
            defaults.set(
                name,
                forKey: "rebuild.school-name.codes.\(office).\(school).name"
            )
            defaults.set(
                previous.id,
                forKey: "rebuild.school-name.codes.\(office).\(school).owner"
            )
            defaults.set(
                "legacy-\(name)",
                forKey: "rebuild.school-name.codes.\(office).\(school)"
            )
        }

        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata,
                saveContext: { _ in throw TestError.saveFailed }
            )
        )
        let replacement = RebuildUserProfile.fixture(
            role: .child,
            id: "replacement-after-divergent-metadata"
        )

        await XCTAssertThrowsErrorAsync(try await store.save(replacement)) { error in
            XCTAssertEqual(error as? TestError, .saveFailed)
        }

        for (office, school, name) in originalNames {
            XCTAssertEqual(
                defaults.string(
                    forKey: "rebuild.school-name.codes.\(office).\(school).name"
                ),
                name
            )
            XCTAssertEqual(
                defaults.string(
                    forKey: "rebuild.school-name.codes.\(office).\(school).owner"
                ),
                previous.id
            )
            XCTAssertEqual(
                defaults.string(
                    forKey: "rebuild.school-name.codes.\(office).\(school)"
                ),
                "legacy-\(name)"
            )
        }
    }

    func testRollbackRestoresDivergentProfileAndFallbackSchoolMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildDivergentSchoolMetadataRollback-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let previous = RebuildUserProfile.fixture(
            role: .child,
            id: "divergent-rollback-profile"
        )
        let seedStore = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        try await seedStore.save(previous)

        let scopedOffice = "C10"
        let scopedSchool = "1234567"
        let fallbackOffice = previous.school!.officeCode
        let fallbackSchool = previous.school!.schoolCode
        defaults.set(
            scopedOffice,
            forKey: "rebuild.school-name.profile.\(previous.id).office"
        )
        defaults.set(
            scopedSchool,
            forKey: "rebuild.school-name.profile.\(previous.id).school"
        )
        let originalNames = [
            (scopedOffice, scopedSchool, "프로필 코드 학교"),
            (scopedOffice, fallbackSchool, "혼합 코드 학교"),
            (fallbackOffice, scopedSchool, "반대 혼합 코드 학교"),
            (fallbackOffice, fallbackSchool, "Core Data 코드 학교"),
        ]
        for (office, school, name) in originalNames {
            defaults.set(
                name,
                forKey: "rebuild.school-name.codes.\(office).\(school).name"
            )
            defaults.set(
                previous.id,
                forKey: "rebuild.school-name.codes.\(office).\(school).owner"
            )
            defaults.set(
                "legacy-\(name)",
                forKey: "rebuild.school-name.codes.\(office).\(school)"
            )
        }

        let replacement = RebuildUserProfile.fixture(
            role: .child,
            id: "replacement-before-divergent-rollback"
        )
        let token = try await seedStore.saveAndCaptureRollback(replacement)
        try await seedStore.rollback(try XCTUnwrap(token))

        for (office, school, name) in originalNames {
            XCTAssertEqual(
                defaults.string(
                    forKey: "rebuild.school-name.codes.\(office).\(school).name"
                ),
                name
            )
            XCTAssertEqual(
                defaults.string(
                    forKey: "rebuild.school-name.codes.\(office).\(school).owner"
                ),
                previous.id
            )
            XCTAssertEqual(
                defaults.string(
                    forKey: "rebuild.school-name.codes.\(office).\(school)"
                ),
                "legacy-\(name)"
            )
        }
        let restored = try await seedStore.load()
        XCTAssertEqual(restored, previous)
    }

    func testCancelledCleanupCannotRemoveLaterWinnerThatReusesProfileID() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildRollbackCompareAndSwap-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        let cancelled = RebuildUserProfile(
            id: "reused-profile-id",
            role: .child,
            nickname: "취소될 저장",
            school: RebuildOnboardingSchool(
                name: "첫 번째 학교",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [1],
            destination: .today,
            isDemoMode: true
        )
        let later = RebuildUserProfile(
            id: cancelled.id,
            role: .child,
            nickname: "나중 저장",
            school: RebuildOnboardingSchool(
                name: "나중 학교",
                officeCode: "C10",
                schoolCode: "1234567"
            ),
            allergyCodes: [5],
            destination: .today,
            isDemoMode: false
        )

        let transaction = try await store.saveAndCaptureRollback(cancelled)
        XCTAssertNotNil(transaction)
        try await store.save(later)
        if let transaction {
            try await store.rollback(transaction)
        }

        let loaded = try await store.load()
        XCTAssertEqual(loaded, later)
        XCTAssertTrue(metadata.hasProfileMetadata(id: later.id))
        XCTAssertFalse(
            metadata.hasSchoolMetadata(
                officeCode: cancelled.school!.officeCode,
                schoolCode: cancelled.school!.schoolCode
            )
        )
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
            destination: .today,
            isDemoMode: true
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
        XCTAssertTrue(reloaded?.isDemoMode == true)

        let bootstrap = RebuildOnboardingBootstrapViewModel(
            profileStore: relaunchedStore
        )
        await bootstrap.load()
        XCTAssertEqual(bootstrap.state, .destination(reloaded!))
    }

    func testReplacingPersistedProfileRemovesPreviousDemoMetadataButKeepsCurrentMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataReplacement-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        let previous = RebuildUserProfile.fixture(
            role: .child,
            id: "profile-a",
            isDemoMode: true
        )
        let current = RebuildUserProfile(
            id: "profile-b",
            role: .child,
            nickname: "최종",
            school: RebuildOnboardingSchool(
                name: "새 학교",
                officeCode: "C10",
                schoolCode: "1234567"
            ),
            allergyCodes: [],
            destination: .today,
            isDemoMode: false
        )

        try await store.save(previous)
        XCTAssertTrue(metadata.isDemoMode(profileID: previous.id))

        try await store.save(current)

        XCTAssertFalse(metadata.hasProfileMetadata(id: previous.id))
        XCTAssertFalse(metadata.isDemoMode(profileID: previous.id))
        XCTAssertTrue(metadata.hasProfileMetadata(id: current.id))
        XCTAssertFalse(metadata.isDemoMode(profileID: current.id))
        let loaded = try await store.load()
        XCTAssertEqual(loaded, current)
    }

    func testReplacingLegacyCoreDataProfileRemovesLegacyCodeKeyedMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildLegacyReplacement-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let legacyOfficeCode = "B10"
        let legacySchoolCode = "7010111"
        let legacyKey =
            "rebuild.school-name.codes.\(legacyOfficeCode).\(legacySchoolCode)"
        defaults.set("이전 레거시 학교", forKey: legacyKey)
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
            object.id = "legacy-b901"
            object.role = RebuildOnboardingRole.child.rawValue
            object.nickname = "레거시"
            object.officeCode = legacyOfficeCode
            object.schoolCode = legacySchoolCode
            object.allergyCodesJSON = "[1]"
            try container.viewContext.save()
        }
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        let current = RebuildUserProfile(
            id: "current-after-legacy",
            role: .child,
            nickname: "현재",
            school: RebuildOnboardingSchool(
                name: "현재 학교",
                officeCode: "C10",
                schoolCode: "1234567"
            ),
            allergyCodes: [],
            destination: .today
        )

        try await store.save(current)

        XCTAssertNil(defaults.string(forKey: legacyKey))
        XCTAssertEqual(
            metadata.name(
                profileID: current.id,
                officeCode: current.school!.officeCode,
                schoolCode: current.school!.schoolCode
            ),
            current.school!.name
        )
    }

    func testFailedLegacyReplacementRestoresLegacyCodeKeyedMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildLegacyReplacementFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let legacyOfficeCode = "B10"
        let legacySchoolCode = "7010111"
        let legacyName = "이전 레거시 학교"
        let legacyKey =
            "rebuild.school-name.codes.\(legacyOfficeCode).\(legacySchoolCode)"
        defaults.set(legacyName, forKey: legacyKey)
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
            object.id = "legacy-b901-failure"
            object.role = RebuildOnboardingRole.child.rawValue
            object.nickname = "레거시"
            object.officeCode = legacyOfficeCode
            object.schoolCode = legacySchoolCode
            object.allergyCodesJSON = "[]"
            try container.viewContext.save()
        }
        var wasLegacyKeyRemovedDuringAttempt = false
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata,
                saveContext: { _ in
                    wasLegacyKeyRemovedDuringAttempt =
                        defaults.string(forKey: legacyKey) == nil
                    throw TestError.saveFailed
                }
            )
        )
        let current = RebuildUserProfile(
            id: "current-after-legacy-failure",
            role: .child,
            nickname: "현재",
            school: RebuildOnboardingSchool(
                name: "현재 학교",
                officeCode: "C10",
                schoolCode: "1234567"
            ),
            allergyCodes: [],
            destination: .today
        )

        await XCTAssertThrowsErrorAsync(try await store.save(current))

        XCTAssertTrue(wasLegacyKeyRemovedDuringAttempt)
        XCTAssertEqual(defaults.string(forKey: legacyKey), legacyName)
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.id, "legacy-b901-failure")
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

    func testCancelledRealStoreProfileRemovesOwnedSchoolMetadataAndCannotLeakName() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataCancel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        let cancelled = RebuildUserProfile(
            id: "cancelled-owned-metadata",
            role: .child,
            nickname: "취소",
            school: RebuildOnboardingSchool(
                name: "취소된 학교 이름",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [1],
            destination: .today,
            isDemoMode: true
        )
        try await store.save(cancelled)

        try await store.removeIfCurrent(id: cancelled.id)

        let removedProfile = try await store.load()
        XCTAssertNil(removedProfile)
        XCTAssertFalse(metadata.hasProfileMetadata(id: cancelled.id))
        XCTAssertFalse(
            metadata.hasSchoolMetadata(
                officeCode: "B10",
                schoolCode: "7010111"
            )
        )

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
            object.id = "legacy-after-cancel"
            object.role = RebuildOnboardingRole.child.rawValue
            object.nickname = "레거시"
            object.officeCode = "B10"
            object.schoolCode = "7010111"
            object.allergyCodesJSON = "[]"
            try container.viewContext.save()
        }

        let legacy = try await store.load()
        XCTAssertEqual(legacy?.school?.name, "등록한 학교")
    }

    func testStaleCleanupCannotRemoveLaterSameSchoolMetadataOwner() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataOwner-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata
            )
        )
        let cancelled = RebuildUserProfile(
            id: "cancelled-owner",
            role: .child,
            nickname: "취소",
            school: RebuildOnboardingSchool(
                name: "이전 학교 이름",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [],
            destination: .today
        )
        let later = RebuildUserProfile(
            id: "later-owner",
            role: .child,
            nickname: "최종",
            school: RebuildOnboardingSchool(
                name: "최종 학교 이름",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [5],
            destination: .today
        )
        try await store.save(cancelled)
        try await store.save(later)

        try await store.removeIfCurrent(id: cancelled.id)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, later)
        XCTAssertFalse(metadata.hasProfileMetadata(id: cancelled.id))
        XCTAssertTrue(metadata.hasProfileMetadata(id: later.id))
        XCTAssertEqual(
            metadata.schoolOwner(
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            later.id
        )
    }

    func testRealCoreDataPublicationFailureRollsBackAllSchoolMetadata() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let suiteName = "RebuildMetadataSaveFailure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let metadata = RebuildSchoolNameMetadataStore(defaults: defaults)
        let store = RebuildCoreDataOnboardingProfileStore(
            coordinator: RebuildOnboardingProfileTransactionCoordinator(
                container: container,
                metadataStore: metadata,
                saveContext: { context in
                    context.insertedObjects.first?.setValue(
                        nil,
                        forKey: "id"
                    )
                    try context.save()
                }
            )
        )
        let profile = RebuildUserProfile(
            id: "failed-publication",
            role: .child,
            nickname: "실패",
            school: RebuildOnboardingSchool(
                name: "실패 학교 이름",
                officeCode: "B10",
                schoolCode: "7010111"
            ),
            allergyCodes: [],
            destination: .today,
            isDemoMode: true
        )

        await XCTAssertThrowsErrorAsync(try await store.save(profile))

        let count = try container.viewContext.performAndWait {
            try container.viewContext.count(
                for: NSFetchRequest<NSManagedObject>(
                    entityName: RebuildEntityName.profile
                )
            )
        }
        XCTAssertEqual(count, 0)
        XCTAssertFalse(metadata.hasProfileMetadata(id: profile.id))
        XCTAssertFalse(metadata.isDemoMode(profileID: profile.id))
        XCTAssertFalse(
            metadata.hasSchoolMetadata(
                officeCode: "B10",
                schoolCode: "7010111"
            )
        )
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

    func testRootBridgeLeavesMatchingChildProfileBytesUnchanged() throws {
        let suiteName = "RebuildBridgeChildNoOp-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserProfileStore(defaults: defaults)
        let legacyProfile = UserProfile(
            id: try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            nickname: "냠냠이",
            schoolName: "서울 냠냠초",
            officeCode: "B10",
            schoolCode: "7010111",
            regionName: "서울특별시",
            selectedAllergyCodes: [1, 5],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            userMode: .elementary,
            themeId: "legacy-child-theme",
            isDemoMode: false
        )
        store.save(legacyProfile)
        let bytesBefore = try XCTUnwrap(defaults.data(forKey: "user-profile"))
        let appState = AppState(profileStore: store)
        let bridge = RebuildLegacyProfileBridge()
        let rebuildProfile = RebuildUserProfile.fixture(role: .child)

        bridge.prepare(rebuildProfile, appState: appState)

        XCTAssertEqual(bridge.state, .ready(rebuildProfile))
        XCTAssertEqual(defaults.data(forKey: "user-profile"), bytesBefore)
        XCTAssertEqual(appState.profile, legacyProfile)
    }

    func testRootBridgeLeavesMatchingParentProfileBytesUnchanged() throws {
        let suiteName = "RebuildBridgeParentNoOp-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserProfileStore(defaults: defaults)
        let legacyProfile = UserProfile(
            id: try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            nickname: "보호자",
            schoolName: "",
            officeCode: "",
            schoolCode: "",
            regionName: "legacy-parent-region",
            selectedAllergyCodes: [],
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            userMode: .parent,
            themeId: "legacy-parent-theme",
            isDemoMode: false
        )
        store.save(legacyProfile)
        let bytesBefore = try XCTUnwrap(defaults.data(forKey: "user-profile"))
        let appState = AppState(profileStore: store)
        let bridge = RebuildLegacyProfileBridge()
        let rebuildProfile = RebuildUserProfile.fixture(role: .parent)

        bridge.prepare(rebuildProfile, appState: appState)

        XCTAssertEqual(bridge.state, .ready(rebuildProfile))
        XCTAssertEqual(defaults.data(forKey: "user-profile"), bytesBefore)
        XCTAssertEqual(appState.profile, legacyProfile)
    }

    func testRootBridgeChildUpdatePreservesLegacyIdentityAndFields() throws {
        let suiteName = "RebuildBridgeChildPatch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserProfileStore(defaults: defaults)
        let legacyID = try XCTUnwrap(
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")
        )
        let legacyCreatedAt = Date(timeIntervalSince1970: 1_720_000_000)
        store.save(
            UserProfile(
                id: legacyID,
                nickname: "이전 별명",
                schoolName: "이전 학교",
                officeCode: "C10",
                schoolCode: "old-school",
                regionName: "보존할 지역",
                selectedAllergyCodes: [2],
                createdAt: legacyCreatedAt,
                userMode: .middle,
                themeId: "preserved-child-theme",
                isDemoMode: true
            )
        )
        let appState = AppState(profileStore: store)
        let bridge = RebuildLegacyProfileBridge()
        let rebuildProfile = RebuildUserProfile(
            id: "rebuild-child",
            role: .child,
            nickname: "새 별명",
            school: .fixture,
            allergyCodes: [5, 1, 5],
            destination: .today,
            isDemoMode: false
        )

        bridge.prepare(rebuildProfile, appState: appState)

        let persisted = try XCTUnwrap(store.load())
        XCTAssertEqual(bridge.state, .ready(rebuildProfile))
        XCTAssertEqual(persisted.id, legacyID)
        XCTAssertEqual(persisted.createdAt, legacyCreatedAt)
        XCTAssertEqual(persisted.regionName, "보존할 지역")
        XCTAssertEqual(persisted.themeId, "preserved-child-theme")
        XCTAssertEqual(persisted.nickname, "새 별명")
        XCTAssertEqual(persisted.schoolName, "서울 냠냠초")
        XCTAssertEqual(persisted.officeCode, "B10")
        XCTAssertEqual(persisted.schoolCode, "7010111")
        XCTAssertEqual(persisted.selectedAllergyCodes, [1, 5])
        XCTAssertEqual(persisted.effectiveMode, .elementary)
        XCTAssertFalse(persisted.isUsingDemoMode)
    }

    func testRootBridgeParentUpdatePreservesLegacyIdentityAndFields() throws {
        let suiteName = "RebuildBridgeParentPatch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserProfileStore(defaults: defaults)
        let legacyID = try XCTUnwrap(
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")
        )
        let legacyCreatedAt = Date(timeIntervalSince1970: 1_730_000_000)
        store.save(
            UserProfile(
                id: legacyID,
                nickname: "아이",
                schoolName: "이전 학교",
                officeCode: "B10",
                schoolCode: "7010111",
                regionName: "보존할 보호자 지역",
                selectedAllergyCodes: [1, 5],
                createdAt: legacyCreatedAt,
                userMode: .elementary,
                themeId: "preserved-parent-theme",
                isDemoMode: true
            )
        )
        let appState = AppState(profileStore: store)
        let bridge = RebuildLegacyProfileBridge()
        let rebuildProfile = RebuildUserProfile(
            id: "rebuild-parent",
            role: .parent,
            nickname: "새 보호자",
            school: nil,
            allergyCodes: [],
            destination: .parentConnection
        )

        bridge.prepare(rebuildProfile, appState: appState)

        let persisted = try XCTUnwrap(store.load())
        XCTAssertEqual(bridge.state, .ready(rebuildProfile))
        XCTAssertEqual(persisted.id, legacyID)
        XCTAssertEqual(persisted.createdAt, legacyCreatedAt)
        XCTAssertEqual(persisted.regionName, "보존할 보호자 지역")
        XCTAssertEqual(persisted.themeId, "preserved-parent-theme")
        XCTAssertEqual(persisted.nickname, "새 보호자")
        XCTAssertEqual(persisted.schoolName, "")
        XCTAssertEqual(persisted.officeCode, "")
        XCTAssertEqual(persisted.schoolCode, "")
        XCTAssertEqual(persisted.selectedAllergyCodes, [])
        XCTAssertEqual(persisted.effectiveMode, .parent)
        XCTAssertFalse(persisted.isUsingDemoMode)
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
    var onSaveStarted: (() -> Void)?
    private var persistedProfile: RebuildUserProfile?
    private var saveContinuation: CheckedContinuation<Void, Error>?

    func load() async throws -> RebuildUserProfile? {
        persistedProfile
    }

    func save(_ profile: RebuildUserProfile) async throws {
        saveCount += 1
        onSaveStarted?()
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

    func finishSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

@MainActor
private final class RapidCancellationProfileStore:
    RebuildOnboardingProfileStore {
    private var persistedProfile: RebuildUserProfile?
    private var previousProfiles: [String: RebuildUserProfile?] = [:]
    private var saveContinuations: [CheckedContinuation<Void, Never>] = []
    private var removalContinuation: CheckedContinuation<Void, Never>?
    var onSaveStarted: ((Int) -> Void)?
    var onRemovalStarted: ((Int) -> Void)?
    private(set) var saveCount = 0
    private(set) var removalCount = 0

    init(seed: RebuildUserProfile) {
        persistedProfile = seed
    }

    func load() async throws -> RebuildUserProfile? {
        persistedProfile
    }

    func save(_ profile: RebuildUserProfile) async throws {
        saveCount += 1
        onSaveStarted?(saveCount)
        await withCheckedContinuation { continuation in
            saveContinuations.append(continuation)
        }
        previousProfiles[profile.id] = persistedProfile
        persistedProfile = profile
    }

    func removeIfCurrent(id: String) async throws {
        removalCount += 1
        onRemovalStarted?(removalCount)
        await withCheckedContinuation { continuation in
            removalContinuation = continuation
        }
        if persistedProfile?.id == id {
            persistedProfile = previousProfiles[id] ?? nil
        }
    }

    func finishSave() {
        guard !saveContinuations.isEmpty else { return }
        saveContinuations.removeFirst().resume()
    }

    func finishRemoval() {
        removalContinuation?.resume()
        removalContinuation = nil
    }
}

@MainActor
private final class RacingOnboardingProfileStore:
    RebuildOnboardingProfileStore {
    private var persistedProfile: RebuildUserProfile?
    private var saveCount = 0
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?
    private var removalContinuation: CheckedContinuation<Void, Never>?
    var onFirstSaveStarted: (() -> Void)?
    var onRemovalStarted: (() -> Void)?

    func load() async throws -> RebuildUserProfile? {
        persistedProfile
    }

    func save(_ profile: RebuildUserProfile) async throws {
        saveCount += 1
        if saveCount == 1 {
            onFirstSaveStarted?()
            await withCheckedContinuation { continuation in
                firstSaveContinuation = continuation
            }
        }
        persistedProfile = profile
    }

    func removeIfCurrent(id: String) async throws {
        onRemovalStarted?()
        await withCheckedContinuation { continuation in
            removalContinuation = continuation
        }
        if persistedProfile?.id == id {
            persistedProfile = nil
        }
    }

    func finishFirstSave() {
        firstSaveContinuation?.resume()
        firstSaveContinuation = nil
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
        id: String = "current",
        isDemoMode: Bool = false
    ) -> RebuildUserProfile {
        RebuildUserProfile(
            id: id,
            role: role,
            nickname: role == .child ? "냠냠이" : "보호자",
            school: role == .child ? .fixture : nil,
            allergyCodes: role == .child ? [1, 5] : [],
            destination: role == .child ? .today : .parentConnection,
            isDemoMode: isDemoMode
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
