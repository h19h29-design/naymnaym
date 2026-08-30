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
