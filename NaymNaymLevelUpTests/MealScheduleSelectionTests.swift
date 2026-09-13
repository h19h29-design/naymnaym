import Foundation
import XCTest
@testable import NaymNaymLevelUp

@MainActor
final class MealScheduleSelectionTests: XCTestCase {
    func testWeekContainsMondayThroughSundaySevenDays() {
        let wednesday = seoulDate(year: 2026, month: 8, day: 26)

        let dates = MealScheduleCalendar.weekDates(containing: wednesday)

        XCTAssertEqual(
            dates.map(MealScheduleCalendar.key(for:)),
            [
                "2026-08-24",
                "2026-08-25",
                "2026-08-26",
                "2026-08-27",
                "2026-08-28",
                "2026-08-29",
                "2026-08-30",
            ]
        )
    }

    func testMonthGridIncludesWeekendAndCompleteRows() {
        let august = seoulDate(year: 2026, month: 8, day: 12)

        let dates = MealScheduleCalendar.monthGridDates(containing: august)

        XCTAssertEqual(dates.count % 7, 0)
        XCTAssertEqual(dates.map(MealScheduleCalendar.key(for:)).first, "2026-07-27")
        XCTAssertEqual(dates.map(MealScheduleCalendar.key(for:)).last, "2026-09-06")
        XCTAssertTrue(dates.contains { MealScheduleCalendar.key(for: $0) == "2026-08-29" })
        XCTAssertTrue(dates.contains { MealScheduleCalendar.key(for: $0) == "2026-08-30" })
    }

    func testSeoulMidnightProducesTheLocalDateKey() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let justBeforeSeoulMidnight = utc.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 11,
                hour: 14,
                minute: 59,
                second: 59
            )
        )!
        let justAfterSeoulMidnight = utc.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 11,
                hour: 15,
                minute: 0,
                second: 1
            )
        )!

        XCTAssertEqual(
            MealScheduleCalendar.key(for: justBeforeSeoulMidnight),
            "2026-08-11"
        )
        XCTAssertEqual(
            MealScheduleCalendar.key(for: justAfterSeoulMidnight),
            "2026-08-12"
        )
    }

    func testSelectedDateRequestsTheSameDateKey() async {
        let repository = RecordingMealScheduleRepository(states: ["2026-08-12": .empty])
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: "2026-08-12"),
            repository: repository,
            school: nil
        )

        await viewModel.load()

        let requestedDates = await repository.requestedDates
        XCTAssertEqual(requestedDates, ["2026-08-12"])
        XCTAssertNil(viewModel.meal)
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testDemoMealDetailDisclosesThatLiveStateIsSampleContent() async {
        let meal = RebuildMealDay.fixture(
            date: "2026-08-12",
            menuName: "체험 메뉴"
        )
        let repository = RecordingMealScheduleRepository(
            states: [meal.date: .live(meal)]
        )
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: meal.date),
            repository: repository,
            school: nil,
            isDemoMode: true
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.statePresentation.label, "체험 급식")
    }

    func testMissingSelectedDateDoesNotUseTodayFallback() async {
        let todayMeal = RebuildMealDay.fixture(date: "2026-08-30", menuName: "오늘 급식")
        let firstCachedMeal = RebuildMealDay.fixture(date: "2026-08-01", menuName: "첫 캐시")
        let repository = RecordingMealScheduleRepository(
            states: [
                "2026-08-30": .live(todayMeal),
                "2026-08-01": .cached(firstCachedMeal, refreshedAt: nil),
                "2026-08-12": .empty,
            ]
        )
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: "2026-08-12"),
            repository: repository,
            school: nil
        )

        await viewModel.load()

        let requestedDates = await repository.requestedDates
        XCTAssertEqual(requestedDates, ["2026-08-12"])
        XCTAssertNil(viewModel.meal)
        XCTAssertEqual(viewModel.state, .empty)
    }

    func testFailedSelectedDateRetainsItsOwnCachedState() async {
        let selectedCache = RebuildMealDay.fixture(date: "2026-08-12", menuName: "선택 날짜 캐시")
        let unrelatedMeal = RebuildMealDay.fixture(date: "2026-08-30", menuName: "오늘 급식")
        let selectedState = MealLoadState.failed(
            message: "network",
            cached: selectedCache
        )
        let repository = RecordingMealScheduleRepository(
            states: [
                "2026-08-12": selectedState,
                "2026-08-30": .live(unrelatedMeal),
            ]
        )
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: "2026-08-12"),
            repository: repository,
            school: nil
        )

        await viewModel.load()

        let requestedDates = await repository.requestedDates
        XCTAssertEqual(requestedDates, ["2026-08-12"])
        XCTAssertEqual(viewModel.meal, selectedCache)
        XCTAssertEqual(viewModel.state, selectedState)
    }

    func testRepositoryReturningDifferentDateCannotBeRenderedAsSelectedDateContent() async {
        let wrongDateMeal = RebuildMealDay.fixture(date: "2026-08-13", menuName: "다른 날짜 급식")
        let repository = RecordingMealScheduleRepository(
            states: ["2026-08-12": .live(wrongDateMeal)]
        )
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: "2026-08-12"),
            repository: repository,
            school: nil
        )

        await viewModel.load()

        let requestedDates = await repository.requestedDates
        XCTAssertEqual(requestedDates, ["2026-08-12"])
        XCTAssertNil(viewModel.meal)
        guard case let .failed(message, cached) = viewModel.state else {
            return XCTFail("Expected the mismatched response to fail")
        }
        XCTAssertEqual(message, "selected date mismatch")
        XCTAssertNil(cached)
    }

    func testCompactWeeklyAndMonthlyPresentationIsAvailableBeforeTap() async {
        let monday = seoulDate(year: 2026, month: 8, day: 24)
        let monthDate = seoulDate(year: 2026, month: 8, day: 12)
        let mondayMeal = RebuildMealDay.fixture(date: "2026-08-24", menuName: "월요일 메뉴")
        let monthMeal = RebuildMealDay.fixture(date: "2026-08-12", menuName: "수요일 메뉴")
        let repository = RecordingMealScheduleRepository(
            states: [
                "2026-08-24": .live(mondayMeal),
                "2026-08-12": .live(monthMeal),
            ]
        )
        let schedule = MealScheduleViewModel(repository: repository, school: nil)

        await schedule.load(dates: [monday, monthDate])

        XCTAssertEqual(schedule.meal(for: monday)?.menuItems.map(\.name), ["월요일 메뉴"])
        XCTAssertEqual(schedule.meal(for: monthDate)?.menuItems.map(\.name), ["수요일 메뉴"])
        let requestedDates = await repository.requestedDates
        XCTAssertEqual(Set(requestedDates), Set(["2026-08-24", "2026-08-12"]))
        XCTAssertEqual(requestedDates.count, 2)
    }

    func testCompactPreviewDoesNotSelectRouteBeforeTap() {
        var selection = MealScheduleSelectionState()

        XCTAssertNil(selection.route)

        selection.select(dateKey: "2026-08-12")

        XCTAssertEqual(selection.route, MealDayRoute(dateKey: "2026-08-12"))
    }

    func testDetailAccessibilityOrderIsDateStateMenuAllergyNutritionCTA() {
        let item = RebuildMealItem(
            name: "  시금치 나물  ",
            allergyCodes: [5],
            nutrients: ["fiber"],
            tags: [],
            sourceRawText: "시금치 나물(5)"
        )
        let meal = RebuildMealDay(
            date: "2026-08-12",
            menuItems: [item],
            calorie: "770 Kcal",
            nutrition: .empty
        )
        let elements = MealDayDetailAccessibility.make(
            dateKey: "2026-08-12",
            stateLabel: "학교 급식",
            meal: meal,
            canRecord: true
        )

        XCTAssertEqual(
            elements.map(\.section),
            [.date, .state, .menu, .allergy, .nutrition, .recordCTA]
        )
        XCTAssertEqual(
            elements.map(\.identifier),
            [
                "meal_day_date",
                "meal_day_status",
                "meal_day_menu_시금치 나물",
                "meal_day_allergy",
                "meal_day_nutrition",
                "meal_day_record_cta",
            ]
        )
        XCTAssertEqual(
            MealDayDetailAccessibility.rootID(dateKey: "2026-08-12"),
            "meal_day_detail_2026-08-12"
        )
        XCTAssertEqual(
            elements.map(\.sortPriority),
            elements.map(\.sortPriority).sorted(by: >)
        )
    }

    func testDetailAccessibilityMakesDuplicateMenuIdentifiersUniqueAndStable() {
        let item = RebuildMealItem(
            name: "우유",
            allergyCodes: [2],
            nutrients: [],
            tags: [],
            sourceRawText: "우유(2)"
        )
        let meal = RebuildMealDay(
            date: "2026-08-12",
            menuItems: [item, item],
            calorie: "",
            nutrition: .empty
        )

        let menuIdentifiers = MealDayDetailAccessibility.make(
            dateKey: meal.date,
            stateLabel: "학교 급식",
            meal: meal,
            canRecord: false
        )
        .filter { $0.section == .menu }
        .map(\.identifier)

        XCTAssertEqual(
            menuIdentifiers,
            ["meal_day_menu_우유", "meal_day_menu_우유_2"]
        )
        XCTAssertEqual(Set(menuIdentifiers).count, 2)
    }

    func testDetailAccessibilityAvoidsNaturalSuffixIdentifierCollision() {
        let milk = RebuildMealItem(
            name: "우유",
            allergyCodes: [2],
            nutrients: [],
            tags: [],
            sourceRawText: "우유(2)"
        )
        let naturallySuffixed = RebuildMealItem(
            name: "우유_2",
            allergyCodes: [],
            nutrients: [],
            tags: [],
            sourceRawText: "우유_2"
        )
        let meal = RebuildMealDay(
            date: "2026-08-12",
            menuItems: [milk, milk, naturallySuffixed],
            calorie: "",
            nutrition: .empty
        )

        let identifiers = MealDayDetailAccessibility.make(
            dateKey: meal.date,
            stateLabel: "최신 급식",
            meal: meal,
            canRecord: false
        )
        .filter { $0.section == .menu }
        .map(\.identifier)

        XCTAssertEqual(
            identifiers,
            [
                "meal_day_menu_우유",
                "meal_day_menu_우유_2",
                "meal_day_menu_우유_2_2",
            ]
        )
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testCachedDetailExposesSavedTimeAndRefreshAction() async {
        let cachedAt = Date(timeIntervalSince1970: 1_786_461_600)
        let meal = RebuildMealDay.fixture(
            date: "2026-08-12",
            menuName: "저장 메뉴"
        )
        let repository = RecordingMealScheduleRepository(
            states: [
                meal.date: .cached(meal, refreshedAt: cachedAt),
            ]
        )
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: meal.date),
            repository: repository,
            school: nil
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.showsCachedRefreshAction)
        XCTAssertTrue(viewModel.statePresentation.label.hasPrefix("저장된 급식 · "))
        XCTAssertNotEqual(viewModel.statePresentation.label, "저장된 급식")
    }

    func testSchedulePreservesEmptyAndFailedStatesPerDate() async {
        let emptyDate = seoulDate(year: 2026, month: 8, day: 29)
        let failedDate = seoulDate(year: 2026, month: 8, day: 30)
        let repository = RecordingMealScheduleRepository(
            states: [
                "2026-08-29": .empty,
                "2026-08-30": .failed(message: "offline", cached: nil),
            ]
        )
        let schedule = MealScheduleViewModel(repository: repository, school: nil)

        await schedule.load(dates: [emptyDate, failedDate])

        guard case .empty = schedule.loadState(for: emptyDate) else {
            return XCTFail("Expected the exact date to retain empty state")
        }
        guard case let .failed(message, cached) = schedule.loadState(for: failedDate) else {
            return XCTFail("Expected the exact date to retain failed state")
        }
        XCTAssertEqual(message, "offline")
        XCTAssertNil(cached)
    }

    func testAllergyStateUsesTextIconAndShape() {
        let riskyItem = RebuildMealItem(
            name: "두부조림",
            allergyCodes: [5],
            nutrients: [],
            tags: [],
            sourceRawText: "두부조림(5)"
        )
        let style = MealAllergyVisualStyle.resolve(for: riskyItem)

        XCTAssertEqual(style.title, "알레르기 정보 확인: 5. 대두")
        XCTAssertEqual(style.systemImage, "exclamationmark.shield.fill")
        XCTAssertGreaterThanOrEqual(style.borderWidth, 2)
        XCTAssertGreaterThan(style.cornerRadius, 0)
        XCTAssertEqual(style.channels, [.text, .icon, .shape])
    }

    func testPersonalAllergyHighlightContainsOnlyRegisteredMatches() {
        let item = RebuildMealItem(name: "닭갈비", allergyCodes: [5, 6, 15], nutrients: [], tags: [], sourceRawText: "닭갈비(5.6.15)")
        let style = MealAllergyVisualStyle.personalized(for: item, registeredCodes: [2, 6, 6])
        XCTAssertEqual(style?.title, "나의 알레르기 주의: 6. 밀")
        XCTAssertEqual(style?.isRisk, true)
        XCTAssertNil(MealAllergyVisualStyle.personalized(for: item, registeredCodes: []))
        XCTAssertNil(MealAllergyVisualStyle.personalized(for: item, registeredCodes: [2]))
        XCTAssertEqual(item.allergyCodes, [5, 6, 15], "전체 원본 정보는 상세 확인을 위해 보존")
    }

    func testMismatchedRefreshRetainsExactCachedMeal() async {
        let selectedCache = RebuildMealDay.fixture(
            date: "2026-08-12",
            menuName: "선택 날짜 캐시"
        )
        let wrongDateMeal = RebuildMealDay.fixture(
            date: "2026-08-13",
            menuName: "다른 날짜 급식"
        )
        let repository = RefreshingMealScheduleRepository(
            initial: .cached(selectedCache, refreshedAt: nil),
            refreshed: .live(wrongDateMeal)
        )
        let school = RebuildSchool(
            name: "냠냠초등학교",
            officeCode: "B10",
            schoolCode: "7010111"
        )
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: "2026-08-12"),
            repository: repository,
            school: school
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.meal, selectedCache)
        XCTAssertEqual(
            viewModel.state,
            .failed(message: "selected date mismatch", cached: selectedCache)
        )
    }

    func testDetailStartsUnloadedAndIgnoresOverlappingLoad() async {
        let repository = BlockingMealScheduleRepository()
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: "2026-08-12"),
            repository: repository,
            school: nil
        )

        XCTAssertFalse(viewModel.hasLoaded)
        let firstLoad = Task { await viewModel.load() }
        await repository.waitForCurrentState()
        XCTAssertTrue(viewModel.isLoading)

        let secondLoad = Task { await viewModel.load() }
        await Task.yield()
        await repository.release()
        await firstLoad.value
        await secondLoad.value

        XCTAssertTrue(viewModel.hasLoaded)
        let callCount = await repository.currentStateCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testExactCacheRemainsVisibleAndUnrecordableWhileRefreshIsInFlight() async {
        let cachedMeal = RebuildMealDay.fixture(
            date: "2026-08-12",
            menuName: "저장된 선택 날짜"
        )
        let refreshedMeal = RebuildMealDay.fixture(
            date: "2026-08-12",
            menuName: "최신 선택 날짜"
        )
        let repository = BlockingRefreshMealScheduleRepository(
            cached: cachedMeal,
            refreshed: refreshedMeal
        )
        let school = RebuildSchool(
            name: "냠냠초등학교",
            officeCode: "B10",
            schoolCode: "7010111"
        )
        let viewModel = MealDayDetailViewModel(
            route: MealDayRoute(dateKey: "2026-08-12"),
            repository: repository,
            school: school
        )

        XCTAssertTrue(viewModel.shouldShowLoadingPlaceholder)

        let loadTask = Task { await viewModel.load() }
        await repository.waitForRefresh()

        XCTAssertEqual(viewModel.meal, cachedMeal)
        XCTAssertEqual(viewModel.state, .refreshing(cachedMeal))
        XCTAssertFalse(viewModel.shouldShowLoadingPlaceholder)
        XCTAssertTrue(viewModel.isRefreshingCachedMeal)
        XCTAssertFalse(viewModel.isMealSettledForRecording)

        await repository.releaseRefresh()
        await loadTask.value

        XCTAssertEqual(viewModel.meal, refreshedMeal)
        XCTAssertEqual(viewModel.state, .live(refreshedMeal))
        XCTAssertTrue(viewModel.isMealSettledForRecording)
    }

    private func seoulDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )!
    }
}

private actor RecordingMealScheduleRepository: MealScheduleRepository {
    private let states: [String: MealLoadState]
    private(set) var requestedDates: [String] = []

    init(states: [String: MealLoadState]) {
        self.states = states
    }

    func currentState(date: String) async -> MealLoadState {
        requestedDates.append(date)
        return states[date] ?? .empty
    }

    func refresh(date: String, school: RebuildSchool) async {}
}

private actor RefreshingMealScheduleRepository: MealScheduleRepository {
    private let initial: MealLoadState
    private let refreshed: MealLoadState
    private var currentStateCallCountStorage = 0

    init(initial: MealLoadState, refreshed: MealLoadState) {
        self.initial = initial
        self.refreshed = refreshed
    }

    var currentStateCallCount: Int {
        currentStateCallCountStorage
    }

    func currentState(date: String) async -> MealLoadState {
        currentStateCallCountStorage += 1
        return currentStateCallCountStorage == 1 ? initial : refreshed
    }

    func refresh(date: String, school: RebuildSchool) async {}
}

private actor BlockingMealScheduleRepository: MealScheduleRepository {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var currentStateCallCount = 0

    func currentState(date: String) async -> MealLoadState {
        currentStateCallCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return .empty
    }

    func refresh(date: String, school: RebuildSchool) async {}

    func waitForCurrentState() async {
        while currentStateCallCount == 0 {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor BlockingRefreshMealScheduleRepository: MealScheduleRepository {
    private let cached: RebuildMealDay
    private let refreshed: RebuildMealDay
    private var refreshContinuation: CheckedContinuation<Void, Never>?
    private var refreshStarted = false

    init(cached: RebuildMealDay, refreshed: RebuildMealDay) {
        self.cached = cached
        self.refreshed = refreshed
    }

    func currentState(date: String) async -> MealLoadState {
        refreshStarted ? .live(refreshed) : .cached(cached, refreshedAt: nil)
    }

    func refresh(date: String, school: RebuildSchool) async {
        refreshStarted = true
        await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
    }

    func waitForRefresh() async {
        while !refreshStarted {
            await Task.yield()
        }
    }

    func releaseRefresh() {
        refreshContinuation?.resume()
        refreshContinuation = nil
    }
}

private extension RebuildMealDay {
    static func fixture(date: String, menuName: String) -> RebuildMealDay {
        RebuildMealDay(
            date: date,
            menuItems: [
                RebuildMealItem(
                    name: menuName,
                    allergyCodes: [],
                    nutrients: [],
                    tags: [],
                    sourceRawText: menuName
                )
            ],
            calorie: "770 Kcal",
            nutrition: .empty
        )
    }
}
