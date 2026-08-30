import XCTest
@testable import NaymNaymLevelUp

@MainActor
final class TodayForestViewModelTests: XCTestCase {
    func testAllSixStatusesArePresented() {
        XCTAssertEqual(
            TodayForestViewModel.activeStatuses,
            [
                .finished,
                .half,
                .oneBite,
                .smelledOnly,
                .difficultToday,
                .allergyAvoided,
            ]
        )
        XCTAssertEqual(
            TodayForestViewModel.activeStatuses.map(\.childTitle),
            [
                "다 먹었어요",
                "반 정도 먹었어요",
                "한 입 도전",
                "냄새만 맡았어요",
                "오늘은 안 먹어요",
                "알레르기로 피했어요",
            ]
        )
    }

    func testDifficultTodayKeepsRawValueAndUsesUserFacingNoMealLabel() {
        XCTAssertEqual(RebuildEatingStatus.difficultToday.rawValue, "difficultToday")
        XCTAssertEqual(RebuildEatingStatus.difficultToday.childTitle, "오늘은 안 먹어요")
    }

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

    func testFreshViewModelLoadsPersistedProgressTotal() async {
        let progress = TodayProgressProviderStub(totalXP: 734)
        let viewModel = makeViewModel(progressProvider: progress)

        XCTAssertEqual(viewModel.totalXP, 0)

        await viewModel.load()

        XCTAssertEqual(viewModel.totalXP, 734)
        let requestCount = await progress.requestCount
        XCTAssertEqual(requestCount, 1)
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
        XCTAssertTrue(empty.isMealDetailActionEnabled)

        let failed = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [.failed(message: "offline", cached: nil)]
            )
        )
        await failed.load()
        XCTAssertEqual(failed.sourceLabel, "급식을 불러오지 못했어요")
        XCTAssertFalse(failed.isPrimaryActionEnabled)
        XCTAssertTrue(failed.isMealDetailActionEnabled)
    }

    func testDetailMealSynchronizationOnlyAcceptsExactDate() {
        let viewModel = makeViewModel()
        let exactMeal = RebuildMealDay.todayFixture()
        let wrongDateMeal = RebuildMealDay(
            date: "2026-07-26",
            menuItems: exactMeal.menuItems,
            calorie: exactMeal.calorie,
            nutrition: exactMeal.nutrition
        )

        viewModel.synchronizeMeal(
            exactMeal,
            for: MealDayRoute(dateKey: "2026-07-25")
        )
        XCTAssertEqual(viewModel.meal, exactMeal)

        viewModel.synchronizeMeal(
            wrongDateMeal,
            for: MealDayRoute(dateKey: "2026-07-25")
        )
        XCTAssertEqual(viewModel.meal, exactMeal)
    }

    func testScheduleRouteBuildsDateScopedRecordingViewModel() throws {
        let source = makeViewModel(allergyCodes: [2, 5])

        let scoped = try XCTUnwrap(
            source.recordingViewModel(
                for: MealDayRoute(dateKey: "2026-08-12")
            )
        )

        XCTAssertEqual(scoped.dateKey, "2026-08-12")
        XCTAssertEqual(scoped.allergyCodes, [2, 5])
        XCTAssertNil(
            source.recordingViewModel(
                for: MealDayRoute(dateKey: "not-a-date")
            )
        )
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

    func testAllergyRiskAllowsOnlyAllergyAvoidedAndGuardianCheck() {
        let viewModel = makeViewModel(allergyCodes: [1, 5])
        let item = RebuildMealItem.todayFixture(allergyCodes: [5, 6])

        XCTAssertTrue(viewModel.isAllergyRisk(item))
        XCTAssertEqual(
            TodayForestViewModel.activeStatuses.filter {
                viewModel.isStatusEnabled($0, for: item)
            },
            [.allergyAvoided]
        )
        XCTAssertEqual(
            viewModel.prioritizedSafetyActions(for: item),
            [.allergyAvoided, .guardianCheck]
        )
    }

    func testRiskRecordingLayoutUsesOneRecommendedStatusAndUniquePerMenuIDs() {
        let first = RebuildMealItem.todayFixture(name: "우유")
        let second = RebuildMealItem.todayFixture(name: "우유")

        XCTAssertEqual(
            MealRecordingActionLayout.gridStatuses(isAllergyRisk: true),
            TodayForestViewModel.activeStatuses.filter { $0 != .allergyAvoided }
        )
        XCTAssertEqual(
            MealRecordingActionLayout.recommendedStatuses(isAllergyRisk: true),
            [.allergyAvoided]
        )
        XCTAssertEqual(
            MealRecordingActionLayout.gridStatuses(isAllergyRisk: false),
            TodayForestViewModel.activeStatuses
        )

        let identifiers = [first, second].enumerated().flatMap { index, item in
            MealRecordingActionLayout.gridStatuses(isAllergyRisk: true).map {
                MealRecordingAccessibilityID.status(
                    menuIndex: index,
                    item: item,
                    status: $0
                )
            } + [
                MealRecordingAccessibilityID.allergyAvoidance(
                    menuIndex: index,
                    item: item
                ),
                MealRecordingAccessibilityID.guardianCheck(
                    menuIndex: index,
                    item: item
                ),
            ]
        }
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.contains("우유") })
    }

    func testAllergyRiskIsRejectedBeforeRecorder() async throws {
        let recorder = TodayMealRecorderSpy()
        let item = RebuildMealItem.todayFixture(allergyCodes: [5])
        let viewModel = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [.cached(.todayFixture(menuItems: [item]), refreshedAt: nil)]
            ),
            recorder: recorder,
            allergyCodes: [5]
        )
        await viewModel.load()

        for status in RebuildEatingStatus.allCases where status != .allergyAvoided {
            await XCTAssertThrowsErrorAsync(expected: .allergySafetyRequired) {
                _ = try await viewModel.prepareRecord(item: item, status: status)
            }
        }

        XCTAssertTrue(recorder.commands.isEmpty)
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

        let prepared = try await viewModel.prepareRecord(
            item: item,
            status: .difficultToday,
            difficultyReasons: [
                .other, .smell, .smell, .appearance, .taste,
            ],
            parentShareEnabled: false
        )
        let result = try await viewModel.record(prepared: prepared)

        XCTAssertEqual(result.xpGranted, 3)
        XCTAssertEqual(recorder.commands.count, 1)
        let command = try XCTUnwrap(recorder.commands.first)
        XCTAssertEqual(
            command.recordID,
            "2026-07-25|시금치 나물"
        )
        XCTAssertEqual(
            command.difficultyReasons,
            [.smell, .taste, .appearance, .other]
        )
        XCTAssertEqual(command.photoIDs, ["legacy-photo", "new-photo"])
        XCTAssertEqual(command.allergyCodes, [])
    }

    func testNutritionReviewCancelWritesNothing() async throws {
        let recorder = TodayMealRecorderSpy()
        let item = RebuildMealItem.todayFixture()
        let viewModel = makeViewModel(recorder: recorder)
        await viewModel.load()

        let prepared = try await viewModel.prepareRecord(
            item: item,
            status: .finished
        )
        var reviewState = MealRecordingReviewState()
        reviewState.present(
            MealRecordingReviewDraft(
                item: item,
                preparedRecord: prepared
            )
        )

        XCTAssertTrue(recorder.commands.isEmpty)
        XCTAssertNotNil(reviewState.draft)
        XCTAssertEqual(prepared.command.recordID, "2026-07-25|시금치 나물")
        XCTAssertEqual(prepared.command.status, .finished)
        XCTAssertEqual(prepared.command.allergyCodes, [])
        XCTAssertEqual(prepared.nutritionSnapshot.nutrients, ["fiber", "vitamin"])
        XCTAssertEqual(prepared.nutritionSnapshot, prepared.command.nutritionSnapshot)

        reviewState.cancel()

        XCTAssertNil(reviewState.draft)
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testRecordingReviewAppearsBeforeAnyWrite() async throws {
        let recorder = TodayMealRecorderSpy()
        let item = RebuildMealItem.todayFixture()
        let viewModel = makeViewModel(recorder: recorder)
        await viewModel.load()

        let prepared = try await viewModel.prepareRecord(
            item: item,
            status: .oneBite
        )
        var reviewState = MealRecordingReviewState()
        reviewState.present(
            MealRecordingReviewDraft(
                item: item,
                preparedRecord: prepared
            )
        )

        XCTAssertNotNil(reviewState.draft)
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testLargeContentSizeKeepsStatusActionsReachable() {
        let item = RebuildMealItem.todayFixture(name: "시금치 나물")
        let descriptor = MealRecordingActionLayout.descriptor(
            isAccessibilitySize: true,
            isAllergyRisk: false,
            menuIndex: 2,
            item: item
        )

        XCTAssertEqual(
            descriptor.columnCount,
            1
        )
        XCTAssertEqual(descriptor.statuses, TodayForestViewModel.activeStatuses)
        XCTAssertGreaterThanOrEqual(descriptor.minimumHitDimension, 48)
        XCTAssertEqual(
            descriptor.statusIdentifiers,
            TodayForestViewModel.activeStatuses.map {
                "meal_recording_status_2_시금치_나물_\($0.rawValue)"
            }
        )
        XCTAssertEqual(
            MealRecordingAccessibilityID.nutritionReview,
            "meal_recording_nutrition_review"
        )
        XCTAssertEqual(MealRecordingAccessibilityID.confirm, "meal_recording_confirm")
    }

    func testReduceMotionUsesStaticResult() async throws {
        XCTAssertEqual(MascotReducedMotionPolicy.renderMode, .staticFinal)
        XCTAssertEqual(MascotReducedMotionPolicy.transitionDuration, 0)
        XCTAssertFalse(MascotReducedMotionPolicy.schedulesCompletion)
        XCTAssertFalse(MascotReducedMotionPolicy.emitsHaptic)

        let controller = MascotMotionController(spec: .fixture)

        controller.play(
            .mealSuccess,
            reduceMotion: true,
            at: 1_000
        )

        XCTAssertEqual(controller.activeState, .reducedMotion)
        XCTAssertFalse(controller.isPlaybackActive)
        XCTAssertEqual(controller.pose.bodyOffsetY, 0)
        XCTAssertEqual(controller.pose.bodyScaleX, 1)
        XCTAssertEqual(controller.pose.bodyScaleY, 1)

        let staticPose = controller.pose
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(controller.activeState, .reducedMotion)
        XCTAssertEqual(controller.pose, staticPose)
    }

    func testNutritionReviewConfirmWritesPreparedCommandOnce() async throws {
        let recorder = TodayMealRecorderSpy()
        let item = RebuildMealItem.todayFixture()
        let viewModel = makeViewModel(recorder: recorder)
        await viewModel.load()
        let prepared = try await viewModel.prepareRecord(
            item: item,
            status: .half
        )

        XCTAssertTrue(recorder.commands.isEmpty)

        _ = try await viewModel.record(prepared: prepared)

        XCTAssertEqual(recorder.commands, [prepared.command])
        XCTAssertEqual(
            viewModel.lastNutritionGuidance?.snapshot,
            prepared.nutritionSnapshot
        )
        XCTAssertEqual(
            viewModel.lastNutritionGuidance?.source,
            .recordedRevision
        )
    }

    func testPreparedSafeMealRefreshThatBecomesRiskRejectsConfirmWithoutWrite() async throws {
        let recorder = TodayMealRecorderSpy()
        let safeItem = RebuildMealItem.todayFixture(allergyCodes: [])
        let viewModel = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [.cached(.todayFixture(menuItems: [safeItem]), refreshedAt: nil)]
            ),
            recorder: recorder,
            allergyCodes: [5]
        )
        await viewModel.load()
        let prepared = try await viewModel.prepareRecord(
            item: safeItem,
            status: .finished
        )
        let refreshedRisk = RebuildMealItem.todayFixture(allergyCodes: [5])
        viewModel.synchronizeMeal(
            .todayFixture(menuItems: [refreshedRisk]),
            for: MealDayRoute(dateKey: "2026-07-25")
        )

        await XCTAssertThrowsErrorAsync(expected: .allergySafetyRequired) {
            _ = try await viewModel.record(prepared: prepared)
        }

        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testPreparedRecordRejectsChangedMissingOrAmbiguousCurrentItem() async throws {
        let original = RebuildMealItem.todayFixture()
        let currentMeals: [RebuildMealDay] = [
            .todayFixture(menuItems: [
                .todayFixture(nutrients: ["protein"]),
            ]),
            .todayFixture(menuItems: []),
            .todayFixture(menuItems: [original, original]),
        ]

        for currentMeal in currentMeals {
            let recorder = TodayMealRecorderSpy()
            let viewModel = makeViewModel(
                repository: TodayMealRepositoryStub(
                    states: [.cached(.todayFixture(menuItems: [original]), refreshedAt: nil)]
                ),
                recorder: recorder
            )
            await viewModel.load()
            let prepared = try await viewModel.prepareRecord(
                item: original,
                status: .half
            )
            viewModel.synchronizeMeal(
                currentMeal,
                for: MealDayRoute(dateKey: "2026-07-25")
            )

            await XCTAssertThrowsErrorAsync(expected: .stalePreparedRecord) {
                _ = try await viewModel.record(prepared: prepared)
            }
            XCTAssertTrue(recorder.commands.isEmpty)
        }
    }

    func testDifficultPreparedRecordRejectsChangedMissingOrUnsafeAlternative() async throws {
        let current = RebuildMealItem.todayFixture()
        let alternative = RebuildMealItem.todayFixture(
            name: "브로콜리무침",
            nutrients: ["fiber", "vitamin"]
        )
        let refreshedMeals: [RebuildMealDay] = [
            .todayFixture(menuItems: [
                current,
                .todayFixture(
                    name: "브로콜리무침",
                    allergyCodes: [5],
                    nutrients: ["fiber", "vitamin"]
                ),
            ]),
            .todayFixture(menuItems: [current]),
            .todayFixture(menuItems: [
                current,
                .todayFixture(
                    name: "브로콜리무침",
                    nutrients: ["protein"]
                ),
            ]),
        ]

        for refreshedMeal in refreshedMeals {
            let recorder = TodayMealRecorderSpy()
            let viewModel = makeViewModel(
                repository: TodayMealRepositoryStub(
                    states: [
                        .cached(
                            .todayFixture(menuItems: [current, alternative]),
                            refreshedAt: nil
                        ),
                    ]
                ),
                recorder: recorder,
                allergyCodes: [5]
            )
            await viewModel.load()
            let prepared = try await viewModel.prepareRecord(
                item: current,
                status: .difficultToday
            )
            XCTAssertEqual(
                prepared.nutritionSnapshot.alternatives,
                ["브로콜리무침"]
            )
            viewModel.synchronizeMeal(
                refreshedMeal,
                for: MealDayRoute(dateKey: "2026-07-25")
            )

            await XCTAssertThrowsErrorAsync(expected: .stalePreparedRecord) {
                _ = try await viewModel.record(prepared: prepared)
            }
            XCTAssertTrue(recorder.commands.isEmpty)
        }
    }

    func testSameMealAlternativesAreOnlyPreparedForDifficultToday() async throws {
        let current = RebuildMealItem.todayFixture()
        let alternative = RebuildMealItem.todayFixture(
            name: "브로콜리무침",
            nutrients: ["fiber", "vitamin"]
        )
        let viewModel = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [
                    .cached(
                        .todayFixture(menuItems: [current, alternative]),
                        refreshedAt: nil
                    ),
                ]
            )
        )
        await viewModel.load()

        for status in RebuildEatingStatus.allCases {
            let prepared = try await viewModel.prepareRecord(
                item: current,
                status: status
            )
            if status == .difficultToday {
                XCTAssertEqual(
                    prepared.nutritionSnapshot.alternatives,
                    ["브로콜리무침"]
                )
            } else {
                XCTAssertTrue(
                    prepared.nutritionSnapshot.alternatives.isEmpty,
                    status.rawValue
                )
            }
        }
    }

    func testNonDifficultNutritionUsesCurrentVisualNutrients() {
        for status in RebuildEatingStatus.allCases where status != .difficultToday {
            XCTAssertEqual(
                TodayForestViewModel.nutrientIDsForSnapshot(
                    status: status,
                    representativeNutrientIDs: ["protein"],
                    alternativeTargetNutrientIDs: ["fiber", "vitamin"]
                ),
                ["protein"],
                status.rawValue
            )
        }
        XCTAssertEqual(
            TodayForestViewModel.nutrientIDsForSnapshot(
                status: .difficultToday,
                representativeNutrientIDs: ["protein"],
                alternativeTargetNutrientIDs: ["fiber", "vitamin"]
            ),
            ["fiber", "vitamin"]
        )
    }

    func testAllergyAvoidedRecordsOnlyIntersectingAllergyCodes() async throws {
        let recorder = TodayMealRecorderSpy()
        let item = RebuildMealItem.todayFixture(allergyCodes: [2, 5, 6])
        let viewModel = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [.cached(.todayFixture(menuItems: [item]), refreshedAt: nil)]
            ),
            recorder: recorder,
            allergyCodes: [1, 5]
        )
        await viewModel.load()

        let prepared = try await viewModel.prepareRecord(
            item: item,
            status: .allergyAvoided
        )
        _ = try await viewModel.record(prepared: prepared)

        XCTAssertEqual(recorder.commands.first?.allergyCodes, [5])
        XCTAssertEqual(recorder.commands.first?.childAllergyCodes, [1, 5])
        XCTAssertEqual(recorder.commands.first?.itemAllergyCodes, [2, 5, 6])
    }

    func testSmellAndAllergyAvoidedCanRecordWithoutDifficultyReasons() async throws {
        let recorder = TodayMealRecorderSpy()
        let safe = RebuildMealItem.todayFixture(name: "시금치 나물")
        let risk = RebuildMealItem.todayFixture(
            name: "우유",
            allergyCodes: [5]
        )
        let viewModel = makeViewModel(
            repository: TodayMealRepositoryStub(
                states: [
                    .cached(
                        .todayFixture(menuItems: [safe, risk]),
                        refreshedAt: nil
                    ),
                ]
            ),
            recorder: recorder,
            allergyCodes: [5]
        )
        await viewModel.load()

        let safePrepared = try await viewModel.prepareRecord(
            item: safe,
            status: .smelledOnly
        )
        _ = try await viewModel.record(prepared: safePrepared)
        let riskPrepared = try await viewModel.prepareRecord(
            item: risk,
            status: .allergyAvoided
        )
        _ = try await viewModel.record(prepared: riskPrepared)

        XCTAssertEqual(
            recorder.commands.map(\.difficultyReasons),
            [[], []]
        )
    }

    func testConsecutiveEqualSuccessMotionsAdvancePlaybackRevision() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        let item = try XCTUnwrap(viewModel.meal?.menuItems.first)

        let first = try await viewModel.prepareRecord(
            item: item,
            status: .finished
        )
        _ = try await viewModel.record(prepared: first)
        let firstRevision = viewModel.motionRevision
        let second = try await viewModel.prepareRecord(
            item: item,
            status: .finished
        )
        _ = try await viewModel.record(prepared: second)

        XCTAssertEqual(viewModel.motion, .mealSuccess)
        XCTAssertEqual(viewModel.motionRevision, firstRevision + 1)
    }

    private func makeViewModel(
        repository: TodayMealRepositoryStub = TodayMealRepositoryStub(
            states: [.cached(.todayFixture(), refreshedAt: nil)]
        ),
        recorder: TodayMealRecorderSpy = TodayMealRecorderSpy(),
        metadataStore: TodayMealPhotoMetadataStoreStub =
            TodayMealPhotoMetadataStoreStub(),
        progressProvider: TodayProgressProviderStub =
            TodayProgressProviderStub(totalXP: 0),
        school: RebuildSchool? = nil,
        allergyCodes: [Int] = []
    ) -> TodayForestViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return TodayForestViewModel(
            repository: repository,
            recorder: recorder,
            photoMetadataStore: metadataStore,
            progressProvider: progressProvider,
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

private actor TodayProgressProviderStub: TodayProgressProvider {
    let storedTotalXP: Int
    private(set) var requestCount = 0

    init(totalXP: Int) {
        storedTotalXP = totalXP
    }

    func totalXP() async throws -> Int {
        requestCount += 1
        return storedTotalXP
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
            motion: command.status == .difficultToday ? .comfort : .mealSuccess,
            nutritionGuidance: command.nutritionSnapshot.map {
                NutrientImpactGuidance(
                    snapshot: $0,
                    source: .recordedRevision
                )
            }
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
    static func todayFixture(
        menuItems: [RebuildMealItem] = [.todayFixture()]
    ) -> RebuildMealDay {
        RebuildMealDay(
            date: "2026-07-25",
            menuItems: menuItems,
            calorie: "620 Kcal",
            nutrition: .empty
        )
    }
}

private extension RebuildMealItem {
    static func todayFixture(
        name: String = "시금치 나물",
        allergyCodes: [Int] = [],
        nutrients: [String] = ["fiber", "vitamin"]
    ) -> RebuildMealItem {
        RebuildMealItem(
            name: name,
            allergyCodes: allergyCodes,
            nutrients: nutrients,
            tags: [],
            sourceRawText: name
        )
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    expected: TodayForestError,
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? TodayForestError, expected, file: file, line: line)
    }
}
