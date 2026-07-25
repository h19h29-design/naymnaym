import XCTest
@testable import NaymNaymLevelUp

@MainActor
final class TodayForestViewModelTests: XCTestCase {
    func testCachedMealKeepsPrimaryActionAvailableOffline() async {
        let meal = RebuildMealDay.todayFixture()
        let repository = TodayMealRepositoryStub(
            states: [.cached(meal, refreshedAt: nil)]
        )
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.title, "오늘 급식")
        XCTAssertEqual(viewModel.primaryActionTitle, "오늘 급식 기록하기")
        XCTAssertTrue(viewModel.isPrimaryActionEnabled)
        XCTAssertEqual(viewModel.sourceLabel, "저장된 급식")
        XCTAssertEqual(viewModel.meal, meal)
    }

    func testLiveAndUnavailableStatesExposeTruthfulSourceAndAction() async {
        let live = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [.live(.todayFixture())]
            )
        )
        await live.load()
        XCTAssertEqual(live.sourceLabel, "학교 급식")
        XCTAssertTrue(live.isPrimaryActionEnabled)

        let empty = makeViewModel(
            repository: TodayMealRepositoryStub(states: [.empty])
        )
        await empty.load()
        XCTAssertEqual(empty.sourceLabel, "급식 정보 없음")
        XCTAssertFalse(empty.isPrimaryActionEnabled)

        let failed = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [.failed(message: "offline", cached: nil)]
            )
        )
        await failed.load()
        XCTAssertEqual(failed.sourceLabel, "급식을 불러오지 못했어요")
        XCTAssertFalse(failed.isPrimaryActionEnabled)
    }

    func testLoadRefreshesSchoolAndKeepsRepositoryResult() async {
        let repository = TodayMealRepositoryStub(
            states: [
                .empty,
                .cached(.todayFixture(), refreshedAt: nil),
            ]
        )
        let school = RebuildSchool(
            name: "냠냠초등학교",
            officeCode: "B10",
            schoolCode: "7010111"
        )
        let viewModel = makeViewModel(
            repository: repository,
            school: school
        )

        await viewModel.load()

        let refreshRequests = await repository.refreshRequests
        XCTAssertEqual(refreshRequests.count, 1)
        XCTAssertEqual(refreshRequests.first?.0, "2026-07-25")
        XCTAssertEqual(refreshRequests.first?.1, school)
        XCTAssertEqual(viewModel.sourceLabel, "저장된 급식")
        XCTAssertTrue(viewModel.isPrimaryActionEnabled)
    }

    func testAllergyRiskDisablesOneBiteAndPrioritizesSafetyActions() {
        let viewModel = makeViewModel(allergyCodes: [1, 5])
        let item = RebuildMealItem.todayFixture(allergyCodes: [5, 6])

        XCTAssertTrue(viewModel.isAllergyRisk(item))
        XCTAssertFalse(viewModel.isStatusEnabled(.oneBite, for: item))
        XCTAssertEqual(
            viewModel.prioritizedSafetyActions(for: item),
            [.allergyAvoided, .guardianCheck]
        )
    }

    func testDifficultyReasonsAreUniqueInCanonicalDisplayOrder() {
        XCTAssertEqual(
            TodayForestViewModel.orderedDifficultyReasons(
                [.other, .smell, .texture, .smell, .appearance, .taste]
            ),
            [.smell, .texture, .taste, .appearance, .other]
        )
    }

    func testRecordingPreservesMigratedPhotoMetadataAndUsesStableIdentity() async throws {
        let recorder = TodayMealRecorderSpy()
        let metadata = TodayMealPhotoMetadataStoreStub(
            photoIDs: ["legacy-photo", "new-photo"]
        )
        let item = RebuildMealItem.todayFixture()
        let viewModel = makeViewModel(
            recorder: recorder,
            metadataStore: metadata
        )
        await viewModel.load()

        let result = try await viewModel.record(
            item: item,
            status: .difficultToday,
            difficultyReasons: [
                .other, .smell, .smell, .appearance, .taste,
            ],
            parentShareEnabled: false
        )

        XCTAssertEqual(result.xpGranted, 3)
        XCTAssertEqual(recorder.commands.count, 1)
        let command = try XCTUnwrap(recorder.commands.first)
        XCTAssertEqual(
            command.recordID,
            "2026-07-25|시금치 나물|difficultToday"
        )
        XCTAssertEqual(
            command.difficultyReasons,
            [.smell, .taste, .appearance, .other]
        )
        XCTAssertEqual(command.photoIDs, ["legacy-photo", "new-photo"])
        XCTAssertEqual(command.allergyCodes, [])
    }

    func testAllergyAvoidedRecordsOnlyIntersectingAllergyCodes() async throws {
        let recorder = TodayMealRecorderSpy()
        let item = RebuildMealItem.todayFixture(allergyCodes: [2, 5, 6])
        let viewModel = makeViewModel(
            recorder: recorder,
            allergyCodes: [1, 5]
        )
        await viewModel.load()

        _ = try await viewModel.record(
            item: item,
            status: .allergyAvoided
        )

        XCTAssertEqual(recorder.commands.first?.allergyCodes, [5])
    }

    func testSmellAndAllergyAvoidedCanRecordWithoutDifficultyReasons() async throws {
        let recorder = TodayMealRecorderSpy()
        let safe = RebuildMealItem.todayFixture()
        let risk = RebuildMealItem.todayFixture(allergyCodes: [5])
        let viewModel = makeViewModel(
            recorder: recorder,
            allergyCodes: [5]
        )
        await viewModel.load()

        _ = try await viewModel.record(item: safe, status: .smelledOnly)
        _ = try await viewModel.record(item: risk, status: .allergyAvoided)

        XCTAssertEqual(
            recorder.commands.map(\.difficultyReasons),
            [[], []]
        )
    }

    private func makeViewModel(
        repository: TodayMealRepositoryStub = TodayMealRepositoryStub(
            states: [.cached(.todayFixture(), refreshedAt: nil)]
        ),
        recorder: TodayMealRecorderSpy = TodayMealRecorderSpy(),
        metadataStore: TodayMealPhotoMetadataStoreStub =
            TodayMealPhotoMetadataStoreStub(),
        school: RebuildSchool? = nil,
        allergyCodes: [Int] = []
    ) -> TodayForestViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return TodayForestViewModel(
            repository: repository,
            recorder: recorder,
            photoMetadataStore: metadataStore,
            school: school,
            allergyCodes: allergyCodes,
            date: calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 25,
                    hour: 12
                )
            )!,
            calendar: calendar
        )
    }
}

private actor TodayMealRepositoryStub: TodayMealRepository {
    private let states: [MealLoadState]
    private var currentIndex = 0
    private(set) var refreshRequests: [(String, RebuildSchool)] = []

    init(states: [MealLoadState]) {
        self.states = states
    }

    func currentState(date: String) async -> MealLoadState {
        states[min(currentIndex, states.count - 1)]
    }

    func refresh(date: String, school: RebuildSchool) async {
        refreshRequests.append((date, school))
        currentIndex = min(currentIndex + 1, states.count - 1)
    }
}

private final class TodayMealRecorderSpy: TodayMealRecorder, @unchecked Sendable {
    private(set) var commands: [RecordMealCommand] = []

    func execute(_ command: RecordMealCommand) async throws -> RecordMealResult {
        commands.append(command)
        return RecordMealResult(
            xpGranted: command.status == .difficultToday ? 3 : 8,
            totalXP: 23,
            motion: command.status == .difficultToday ? .comfort : .mealSuccess
        )
    }
}

private struct TodayMealPhotoMetadataStoreStub: TodayMealPhotoMetadataStore {
    var photoIDs: [String] = []

    func photoIDs(date: String, normalizedMenuName: String) async throws -> [String] {
        photoIDs
    }
}

private extension RebuildMealDay {
    static func todayFixture() -> RebuildMealDay {
        RebuildMealDay(
            date: "2026-07-25",
            menuItems: [.todayFixture()],
            calorie: "620 Kcal",
            nutrition: .empty
        )
    }
}

private extension RebuildMealItem {
    static func todayFixture(
        allergyCodes: [Int] = []
    ) -> RebuildMealItem {
        RebuildMealItem(
            name: "시금치 나물",
            allergyCodes: allergyCodes,
            nutrients: ["fiber", "vitamin"],
            tags: [],
            sourceRawText: "시금치 나물"
        )
    }
}
