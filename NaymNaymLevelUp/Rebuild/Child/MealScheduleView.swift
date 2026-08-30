import SwiftUI
import UIKit

enum MealScheduleMode: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "일간"
        case .weekly: return "주간"
        case .monthly: return "월간"
        }
    }
}

struct MealScheduleSelectionState: Equatable {
    var route: MealDayRoute?

    init(route: MealDayRoute? = nil) {
        self.route = route
    }

    mutating func select(dateKey: String) {
        route = MealDayRoute(dateKey: dateKey)
    }
}

enum MealScheduleRow: String, CaseIterable, Identifiable {
    case grain
    case soup
    case side1
    case side2
    case kimchi
    case beverage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grain: return "밥/면"
        case .soup: return "국/탕"
        case .side1: return "반찬 1"
        case .side2: return "반찬 2"
        case .kimchi: return "김치"
        case .beverage: return "음료"
        }
    }

    var compactTitle: String {
        switch self {
        case .grain: return "밥"
        case .soup: return "국"
        case .side1: return "찬1"
        case .side2: return "찬2"
        case .kimchi: return "김치"
        case .beverage: return "음료"
        }
    }
}

struct MealScheduleMenuSlots: Equatable {
    var grain: [String] = []
    var soup: [String] = []
    var side1: [String] = []
    var side2: [String] = []
    var kimchi: [String] = []
    var beverage: [String] = []

    init(items: [RebuildMealItem]) {
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            switch Self.classify(name: name) {
            case .grain:
                grain.append(name)
            case .soup:
                soup.append(name)
            case .kimchi:
                kimchi.append(name)
            case .beverage:
                beverage.append(name)
            case .side1, .side2:
                if side1.isEmpty {
                    side1.append(name)
                } else {
                    side2.append(name)
                }
            }
        }
    }

    static func classify(name: String) -> MealScheduleRow {
        let normalized = name.replacingOccurrences(of: " ", with: "")
        if contains(
            normalized,
            anyOf: ["우유", "요구르트", "요거트", "주스", "쥬스", "음료"]
        ) {
            return .beverage
        }
        if contains(
            normalized,
            anyOf: ["김치", "깍두기", "석박지", "겉절이"]
        ) {
            return .kimchi
        }
        if contains(
            normalized,
            anyOf: ["국", "탕", "찌개", "스프", "전골"]
        ) {
            return .soup
        }
        if contains(
            normalized,
            anyOf: [
                "밥", "면", "라이스", "국수", "우동", "죽", "떡국",
                "수제비", "카레",
            ]
        ) {
            return .grain
        }
        return .side1
    }

    func value(for row: MealScheduleRow) -> String {
        let values: [String]
        switch row {
        case .grain:
            values = grain
        case .soup:
            values = soup
        case .side1:
            values = side1
        case .side2:
            values = side2
        case .kimchi:
            values = kimchi
        case .beverage:
            values = beverage
        }
        return values.isEmpty ? "—" : values.joined(separator: " · ")
    }

    var dailyRows: [MealScheduleDisplayRow] {
        [
            MealScheduleDisplayRow(
                row: .grain,
                value: value(for: .grain)
            ),
            MealScheduleDisplayRow(
                row: .soup,
                value: value(for: .soup)
            ),
            MealScheduleDisplayRow(
                row: .side1,
                value: value(for: .side1)
            ),
            MealScheduleDisplayRow(
                row: .side2,
                value: (side2 + kimchi).isEmpty
                    ? "—"
                    : (side2 + kimchi).joined(separator: " · ")
            ),
            MealScheduleDisplayRow(
                row: .beverage,
                value: value(for: .beverage)
            ),
        ]
    }

    private static func contains(
        _ value: String,
        anyOf candidates: [String]
    ) -> Bool {
        candidates.contains(where: value.contains)
    }
}

struct MealScheduleDisplayRow: Identifiable, Equatable {
    var id: MealScheduleRow { row }
    let row: MealScheduleRow
    let value: String
}

enum MealScheduleCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "ko_KR")
        value.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        value.firstWeekday = 2
        return value
    }

    static func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func weekDates(containing date: Date) -> [Date] {
        let start = startOfSchoolWeek(for: date)
        return (0..<7).compactMap {
            dateByAddingDays($0, to: start)
        }
    }

    static func startOfSchoolWeek(for date: Date) -> Date {
        let localNoon = noon(on: date)
        let weekday = calendar.component(.weekday, from: localNoon)
        let offsetFromMonday = (weekday + 5) % 7
        return dateByAddingDays(-offsetFromMonday, to: localNoon)
    }

    static func endOfSchoolWeek(for date: Date) -> Date {
        dateByAddingDays(6, to: startOfSchoolWeek(for: date))
    }

    static func shiftedSchoolWeek(_ date: Date, by offset: Int) -> Date {
        dateByAddingDays(offset * 7, to: noon(on: date))
    }

    static func monthGridDates(containing date: Date) -> [Date] {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard
            let monthStart = noon(from: components),
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
            let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth)
        else {
            return []
        }

        let start = startOfSchoolWeek(for: monthStart)
        let end = endOfSchoolWeek(for: monthEnd)
        let dayCount = calendar.dateComponents(
            [.day],
            from: start,
            to: end
        ).day ?? 0

        return (0...dayCount).compactMap { offset -> Date? in
            dateByAddingDays(offset, to: start)
        }
    }

    static func shifted(
        _ date: Date,
        mode: MealScheduleMode,
        direction: Int
    ) -> Date {
        let component: Calendar.Component
        let value: Int
        switch mode {
        case .daily:
            component = .day
            value = direction
        case .weekly:
            return shiftedSchoolWeek(date, by: direction)
        case .monthly:
            component = .month
            value = direction
        }
        return noon(on: calendar.date(byAdding: component, value: value, to: noon(on: date)) ?? date)
    }

    static func sameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private static func noon(on date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return noon(from: components) ?? date
    }

    private static func noon(from components: DateComponents) -> Date? {
        var value = components
        value.hour = 12
        value.minute = 0
        value.second = 0
        return calendar.date(from: value)
    }

    private static func dateByAddingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}

protocol MealScheduleRepository: Sendable {
    func currentState(date: String) async -> MealLoadState
    func refresh(date: String, school: RebuildSchool) async
}

struct LiveMealScheduleRepository: MealScheduleRepository {
    let repository: RebuildMealRepository

    func currentState(date: String) async -> MealLoadState {
        await repository.currentState(date: date)
    }

    func refresh(date: String, school: RebuildSchool) async {
        await repository.refresh(date: date, school: school)
    }
}

struct UnavailableMealScheduleRepository: MealScheduleRepository {
    func currentState(date: String) async -> MealLoadState {
        .failed(message: "persistence unavailable", cached: nil)
    }

    func refresh(date: String, school: RebuildSchool) async {}
}

private struct MealScheduleLoadResult: Sendable {
    let key: String
    let meal: RebuildMealDay?
    let failed: Bool
}

@MainActor
final class MealScheduleViewModel: ObservableObject {
    @Published private(set) var meals: [String: RebuildMealDay] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    let schoolName: String

    let repository: any MealScheduleRepository
    let school: RebuildSchool?

    init(
        repository: any MealScheduleRepository,
        school: RebuildSchool?
    ) {
        self.repository = repository
        self.school = school
        schoolName = school?.name ?? "학교 등록 전"
    }

    func meal(for date: Date) -> RebuildMealDay? {
        meals[MealScheduleCalendar.key(for: date)]
    }

    func load(dates: [Date]) async {
        var seenKeys = Set<String>()
        let requests = dates.compactMap { date -> (String, Date)? in
            let key = MealScheduleCalendar.key(for: date)
            guard seenKeys.insert(key).inserted else { return nil }
            return (key, date)
        }
        guard !requests.isEmpty else { return }

        isLoading = true
        message = school == nil
            ? "학교를 등록하면 최신 급식을 확인할 수 있어요."
            : nil

        let repository = self.repository
        let school = self.school
        var results: [MealScheduleLoadResult] = []
        for batchStart in stride(from: 0, to: requests.count, by: 5) {
            let batchEnd = min(batchStart + 5, requests.count)
            let batch = requests[batchStart..<batchEnd]
            let batchResults = await withTaskGroup(
                of: MealScheduleLoadResult.self,
                returning: [MealScheduleLoadResult].self
            ) { group in
                for (key, _) in batch {
                    group.addTask {
                        var state = await repository.currentState(date: key)
                        if let school {
                            await repository.refresh(date: key, school: school)
                            state = await repository.currentState(date: key)
                        }
                        return MealScheduleLoadResult(
                            key: key,
                            meal: Self.meal(from: state, expectedDate: key),
                            failed: Self.isFailed(state, expectedDate: key)
                        )
                    }
                }

                var values: [MealScheduleLoadResult] = []
                for await result in group {
                    values.append(result)
                }
                return values
            }
            results.append(contentsOf: batchResults)
        }

        for result in results {
            meals[result.key] = result.meal
        }
        if school != nil, results.allSatisfy(\.failed) {
            message = "급식을 불러오지 못했어요. 네트워크 연결을 확인해 주세요."
        }
        isLoading = false
    }

    private nonisolated static func meal(
        from state: MealLoadState,
        expectedDate: String
    ) -> RebuildMealDay? {
        let candidate: RebuildMealDay?
        switch state {
        case let .cached(meal, _), let .live(meal):
            candidate = meal
        case let .refreshing(cached), let .failed(_, cached):
            candidate = cached
        case .empty:
            candidate = nil
        }
        guard candidate?.date == expectedDate else { return nil }
        return candidate
    }

    private nonisolated static func isFailed(
        _ state: MealLoadState,
        expectedDate: String
    ) -> Bool {
        switch state {
        case .failed:
            return true
        case let .cached(meal, _), let .live(meal):
            return meal.date != expectedDate
        case let .refreshing(cached):
            return cached?.date != nil && cached?.date != expectedDate
        case .empty:
            return false
        }
    }
}

struct MealScheduleView: View {
    @ObservedObject var viewModel: MealScheduleViewModel
    @State private var mode: MealScheduleMode = .daily
    @State private var anchorDate = Date()
    @State private var selectedDate = Date()
    @State private var selection = MealScheduleSelectionState()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id("meal_schedule_top")
                        header
                        modeSelector
                        periodNavigation

                        if viewModel.isLoading {
                            ProgressView("급식을 업데이트하고 있어요.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(RebuildDesignTokens.forest700)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let message = viewModel.message {
                            notice(message)
                        }

                        switch mode {
                        case .daily:
                            dailyContent
                        case .weekly:
                            weeklyContent
                        case .monthly:
                            monthlyContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(RebuildDesignTokens.cream50)
                .onChange(of: mode) { _ in
                    selectedDate = anchorDate
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("meal_schedule_top", anchor: .top)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task(id: loadKey) {
            await viewModel.load(dates: visibleDates)
        }
        .sheet(item: $selection.route) { route in
            MealDayDetailView(
                route: route,
                repository: viewModel.repository,
                school: viewModel.school
            )
        }
        .accessibilityIdentifier("meal_schedule_screen")
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            MealScheduleHeaderBackground()
                .frame(height: 124)
                .clipped()
            LinearGradient(
                colors: [
                    RebuildDesignTokens.cream50.opacity(0.38),
                    RebuildDesignTokens.cream50.opacity(0.92),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .frame(height: 124)

            VStack(alignment: .leading, spacing: 6) {
                Text("급식표")
                    .font(.largeTitle.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Text(viewModel.schoolName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Label(
                        viewModel.isLoading ? "업데이트 중" : "업데이트됨",
                        systemImage: viewModel.isLoading
                            ? "arrow.triangle.2.circlepath"
                            : "checkmark.circle.fill"
                    )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RebuildDesignTokens.forest500)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.86))
                    .clipShape(Capsule())
                }
            }
            .padding(18)
        }
        .frame(height: 124)
        .clipped()
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[2],
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[2],
                style: .continuous
            )
            .stroke(RebuildDesignTokens.forest500.opacity(0.18), lineWidth: 1)
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(MealScheduleMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(
                            mode == item
                                ? Color.white
                                : RebuildDesignTokens.muted600
                        )
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            mode == item
                                ? RebuildDesignTokens.forest700
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal_schedule_mode_\(item.rawValue)")
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.9))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(RebuildDesignTokens.forest500.opacity(0.2), lineWidth: 1)
        }
    }

    private var periodNavigation: some View {
        HStack {
            periodButton(systemImage: "chevron.left", direction: -1)
            Text(periodTitle)
                .font(.headline.bold())
                .foregroundStyle(RebuildDesignTokens.ink900)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            periodButton(systemImage: "chevron.right", direction: 1)
        }
        .frame(minHeight: RebuildDesignTokens.minimumActionSize)
    }

    private func periodButton(
        systemImage: String,
        direction: Int
    ) -> some View {
        Button {
            let shifted = MealScheduleCalendar.shifted(
                anchorDate,
                mode: mode,
                direction: direction
            )
            anchorDate = shifted
            selectedDate = shifted
        } label: {
            Image(systemName: systemImage)
                .font(.headline.bold())
                .foregroundStyle(RebuildDesignTokens.forest700)
                .frame(
                    width: RebuildDesignTokens.minimumActionSize,
                    height: RebuildDesignTokens.minimumActionSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dailyContent: some View {
        let meal = viewModel.meal(for: anchorDate)
        let slots = MealScheduleMenuSlots(items: meal?.menuItems ?? [])
        return VStack(alignment: .leading, spacing: 14) {
            Text("오늘의 메뉴")
                .font(.headline.bold())
                .foregroundStyle(RebuildDesignTokens.forest500)

            VStack(spacing: 0) {
                ForEach(Array(slots.dailyRows.enumerated()), id: \.element.id) {
                    index,
                    display in
                    HStack(spacing: 12) {
                        Text(display.row.compactTitle)
                            .font(.caption.bold())
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .frame(width: 38, height: 38)
                            .background(
                                RebuildDesignTokens.leaf300.opacity(0.22)
                            )
                            .clipShape(Circle())

                        Text(display.row.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .frame(width: 58, alignment: .leading)

                        Text(display.value)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(
                                display.value == "—"
                                    ? RebuildDesignTokens.muted600
                                    : RebuildDesignTokens.ink900
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        index.isMultiple(of: 2)
                            ? RebuildDesignTokens.cream50.opacity(0.7)
                            : Color.white
                    )

                    if index < slots.dailyRows.count - 1 {
                        Divider()
                            .overlay(
                                RebuildDesignTokens.forest500.opacity(0.16)
                            )
                    }
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[0],
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[0],
                    style: .continuous
                )
                .stroke(
                    RebuildDesignTokens.forest500.opacity(0.2),
                    lineWidth: 1
                )
            }

            menuVisualSummary(meal: meal)

            Text("영양 정보")
                .font(.subheadline.bold())
                .foregroundStyle(RebuildDesignTokens.forest500)
            nutritionSummary(meals: meal.map { [$0] } ?? [])
            allergySummary(meal: meal)

            Button {
                select(date: anchorDate)
            } label: {
                Label("급식 상세 보기", systemImage: "arrow.up.right.square")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(RebuildDesignTokens.forest700)
            .accessibilityIdentifier(
                "meal_schedule_day_detail_\(MealScheduleCalendar.key(for: anchorDate))"
            )
        }
        .mealScheduleCard()
        .accessibilityIdentifier("meal_schedule_daily")
    }

    private var weeklyContent: some View {
        let dates = MealScheduleCalendar.weekDates(containing: anchorDate)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("이번 주 메뉴")
                    .font(.headline.bold())
                    .foregroundStyle(RebuildDesignTokens.forest500)
                Spacer()
                Text("요일별 메뉴를 한눈에 비교")
                    .font(.caption2)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 52, height: 50)
                    ForEach(dates, id: \.self) { date in
                        let selected = MealScheduleCalendar.sameDay(
                            date,
                            selectedDate
                        )
                        Button {
                            select(date: date)
                        } label: {
                            VStack(spacing: 2) {
                                Text(weekdayFormatter.string(from: date))
                                    .font(.caption.bold())
                                Text(shortDateFormatter.string(from: date))
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(
                                selected
                                    ? Color.white
                                    : RebuildDesignTokens.forest700
                            )
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                selected
                                    ? RebuildDesignTokens.forest700
                                    : Color.white
                            )
                            .mealScheduleCellBorder()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "meal_schedule_week_day_\(MealScheduleCalendar.key(for: date))"
                        )
                    }
                }

                ForEach(MealScheduleRow.allCases) { row in
                    HStack(spacing: 0) {
                        Text(row.compactTitle)
                            .font(.caption2.bold())
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .frame(width: 52)
                            .frame(minHeight: 58)
                            .background(
                                RebuildDesignTokens.cream50.opacity(0.72)
                            )
                            .mealScheduleCellBorder()

                        ForEach(dates, id: \.self) { date in
                            let selected = MealScheduleCalendar.sameDay(
                                date,
                                selectedDate
                            )
                            let slots = MealScheduleMenuSlots(
                                items: viewModel.meal(for: date)?.menuItems ?? []
                            )
                            Button {
                                select(date: date)
                            } label: {
                                Text(slots.value(for: row))
                                    .font(.caption2.weight(selected ? .bold : .medium))
                                    .foregroundStyle(
                                        selected
                                            ? RebuildDesignTokens.forest700
                                            : RebuildDesignTokens.ink900
                                    )
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.76)
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 58,
                                        alignment: .center
                                    )
                                    .padding(.horizontal, 2)
                                    .background(
                                        selected
                                            ? RebuildDesignTokens.leaf300.opacity(0.2)
                                            : Color.white
                                    )
                                    .mealScheduleCellBorder()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "meal_schedule_week_menu_\(MealScheduleCalendar.key(for: date))_\(row.rawValue)"
                            )
                        }
                    }
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[0],
                    style: .continuous
                )
            )

            selectedMealInformation
        }
        .mealScheduleCard()
        .accessibilityIdentifier("meal_schedule_weekly")
    }

    private var monthlyContent: some View {
        let dates = MealScheduleCalendar.monthGridDates(containing: anchorDate)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 0),
            count: 7
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(monthNumber)월 급식 달력")
                    .font(.headline.bold())
                    .foregroundStyle(RebuildDesignTokens.forest500)
                Spacer()
                Text("선택 전에도 대표 메뉴 표시")
                    .font(.caption2)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { day in
                    Text(day)
                        .font(.caption.bold())
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color.white)
                        .mealScheduleCellBorder()
                }

                ForEach(dates, id: \.self) { date in
                    let meal = viewModel.meal(for: date)
                    let visuals = meal?.menuItems.map {
                        MealVisualResolver.resolve(item: $0)
                    } ?? []
                    let summary = MealMonthCellSummary(
                        dateLabel: dayFormatter.string(from: date),
                        visuals: visuals
                    )
                    let selected = MealScheduleCalendar.sameDay(
                        date,
                        selectedDate
                    )
                    Button {
                        select(date: date)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary.dateLabel)
                                .font(.caption2.bold())
                                .foregroundStyle(
                                    selected
                                        ? RebuildDesignTokens.forest500
                                        : dateIsInDisplayedMonth(date)
                                            ? RebuildDesignTokens.forest700
                                            : RebuildDesignTokens.muted600.opacity(0.45)
                                )

                            if let representativeIconKey = summary.representativeIconKey {
                                HStack(spacing: 2) {
                                    MealVisualIcon(iconKey: representativeIconKey)
                                        .font(.caption2.weight(.semibold))
                                    if let additionalMenuLabel = summary.additionalMenuLabel {
                                        Text(additionalMenuLabel)
                                            .font(.caption2.weight(.bold))
                                    }
                                }
                                .foregroundStyle(
                                    selected
                                        ? RebuildDesignTokens.forest700
                                        : RebuildDesignTokens.ink900
                                )
                            } else {
                                Text("정보 없음")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(
                                        RebuildDesignTokens.muted600
                                    )
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 82,
                            alignment: .topLeading
                        )
                        .background(
                            selected
                                ? RebuildDesignTokens.leaf300.opacity(0.22)
                                : Color.white
                        )
                        .mealScheduleCellBorder()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(monthCellAccessibility(date: date, meal: meal))
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[0],
                    style: .continuous
                )
            )

            selectedMealInformation
        }
        .mealScheduleCard()
        .accessibilityIdentifier("meal_schedule_monthly")
    }

    private func nutritionSummary(
        meals: [RebuildMealDay]
    ) -> some View {
        let summary = MealScheduleNutritionSummary(meals: meals)
        return VStack(alignment: .leading, spacing: 8) {
            Text(
                meals.count > 1
                    ? "전체 급식 기준 · NEIS 제공 (기간 평균)"
                    : "전체 급식 기준 · NEIS 제공"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(RebuildDesignTokens.forest700)

            HStack(spacing: 6) {
                ForEach(summary.tiles) { tile in
                    VStack(spacing: 4) {
                        Text(tile.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(RebuildDesignTokens.muted600)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(tile.value)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(
                                tile.title == "열량"
                                    ? Color.orange
                                    : RebuildDesignTokens.ink900
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RebuildDesignTokens.cream50.opacity(0.9))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: RebuildDesignTokens.radii[0],
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: RebuildDesignTokens.radii[0],
                            style: .continuous
                        )
                        .stroke(
                            RebuildDesignTokens.forest500.opacity(0.18),
                            lineWidth: 1
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedMealInformation: some View {
        let selectedMeal = viewModel.meal(for: selectedDate)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("선택한 날짜의 영양 정보")
                    .font(.subheadline.bold())
                    .foregroundStyle(RebuildDesignTokens.forest500)
                Spacer()
                Text(fullDateFormatter.string(from: selectedDate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }
            if let selectedMeal {
                menuVisualSummary(meal: selectedMeal)
                nutritionSummary(meals: [selectedMeal])
                allergySummary(meal: selectedMeal)
            } else {
                Text("해당 날짜의 영양 정보가 없어요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: RebuildDesignTokens.minimumActionSize,
                        alignment: .leading
                    )
            }
        }
        .accessibilityIdentifier(
            "meal_schedule_selected_information_\(MealScheduleCalendar.key(for: selectedDate))"
        )
    }

    @ViewBuilder
    private func menuVisualSummary(meal: RebuildMealDay?) -> some View {
        if let meal {
            VStack(alignment: .leading, spacing: 8) {
                Text("메뉴별 안내")
                    .font(.subheadline.bold())
                    .foregroundStyle(RebuildDesignTokens.forest500)

                ForEach(Array(meal.menuItems.enumerated()), id: \.offset) { _, item in
                    let visual = MealVisualResolver.resolve(item: item)
                    let accessibility = MealAccessibilityDescriptor(
                        item: item,
                        visual: visual
                    )
                    HStack(alignment: .top, spacing: 8) {
                        MealVisualIcon(iconKey: visual.iconKey)
                        .font(.subheadline)
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RebuildDesignTokens.ink900)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                Text(visual.categoryLabel)
                                Text(visual.confidenceLabel)
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            MealNutrientChips(
                                nutrientIDs: visual.representativeNutrientIDs
                            )
                            Text(visual.representativeCopy)
                                .font(.caption2)
                                .foregroundStyle(RebuildDesignTokens.muted600)
                                .fixedSize(horizontal: false, vertical: true)
                            if !item.allergyLabels.isEmpty {
                                Text(
                                    "알레르기: "
                                        + item.allergyLabels.joined(separator: " · ")
                                )
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.orange.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibility.spokenLabel)
                    .padding(8)
                    .background(RebuildDesignTokens.cream50.opacity(0.72))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: RebuildDesignTokens.radii[0],
                            style: .continuous
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func allergySummary(meal: RebuildMealDay?) -> some View {
        let codes = Array(
            Set(meal?.menuItems.flatMap(\.allergyCodes) ?? [])
        ).sorted()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("알레르기 정보")
                    .font(.subheadline.bold())
                    .foregroundStyle(RebuildDesignTokens.forest700)
                Spacer()
                Text("번호와 이름을 함께 표시")
                    .font(.caption2)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }

            if codes.isEmpty {
                Text("표시된 알레르기 정보가 없어요.")
                    .font(.caption)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            Text(AllergyMap.label(for: code))
                                .font(.caption.bold())
                                .foregroundStyle(Color.orange.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RebuildDesignTokens.leaf300.opacity(0.2))
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
        )
    }

    private func notice(_ message: String) -> some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(RebuildDesignTokens.ink900)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RebuildDesignTokens.leaf300.opacity(0.22))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[0],
                    style: .continuous
                )
            )
    }

    private var visibleDates: [Date] {
        switch mode {
        case .daily:
            return [anchorDate]
        case .weekly:
            return MealScheduleCalendar.weekDates(containing: anchorDate)
        case .monthly:
            return MealScheduleCalendar.monthGridDates(containing: anchorDate)
        }
    }

    private var loadKey: String {
        "\(mode.rawValue)-\(MealScheduleCalendar.key(for: anchorDate))"
    }

    private var periodTitle: String {
        switch mode {
        case .daily:
            return fullDateFormatter.string(from: anchorDate)
        case .weekly:
            let dates = MealScheduleCalendar.weekDates(containing: anchorDate)
            guard !dates.isEmpty, let last = dates.last else {
                return ""
            }
            let first = dates[0]
            return "\(monthDayFormatter.string(from: first)) – \(monthDayFormatter.string(from: last))"
        case .monthly:
            return monthFormatter.string(from: anchorDate)
        }
    }

    private var monthNumber: Int {
        MealScheduleCalendar.calendar.component(.month, from: anchorDate)
    }

    private func dateIsInDisplayedMonth(_ date: Date) -> Bool {
        let calendar = MealScheduleCalendar.calendar
        return calendar.component(.year, from: date)
            == calendar.component(.year, from: anchorDate)
            && calendar.component(.month, from: date)
            == calendar.component(.month, from: anchorDate)
    }

    private func monthCellAccessibility(
        date: Date,
        meal: RebuildMealDay?
    ) -> String {
        guard let meal, let firstItem = meal.menuItems.first else {
            return "\(fullDateFormatter.string(from: date)), 급식 정보 없음"
        }
        let additionalCount = max(meal.menuItems.count - 1, 0)
        let suffix = additionalCount > 0
            ? ", 외 \(additionalCount)개 메뉴"
            : ""
        return "\(fullDateFormatter.string(from: date)), \(firstItem.name)\(suffix)"
    }

    private func select(date: Date) {
        selectedDate = date
        selection.select(dateKey: MealScheduleCalendar.key(for: date))
    }

    private var fullDateFormatter: DateFormatter {
        Self.formatter("yyyy년 M월 d일")
    }

    private var monthDayFormatter: DateFormatter {
        Self.formatter("M월 d일")
    }

    private var monthFormatter: DateFormatter {
        Self.formatter("yyyy년 M월")
    }

    private var weekdayFormatter: DateFormatter {
        Self.formatter("E")
    }

    private var shortDateFormatter: DateFormatter {
        Self.formatter("M/d")
    }

    private var dayFormatter: DateFormatter {
        Self.formatter("d")
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let value = DateFormatter()
        value.calendar = MealScheduleCalendar.calendar
        value.locale = Locale(identifier: "ko_KR")
        value.timeZone = MealScheduleCalendar.calendar.timeZone
        value.dateFormat = format
        return value
    }
}

private struct MealScheduleHeaderBackground: View {
    private static let image: UIImage? = {
        guard
            let url = Bundle.main.url(
                forResource: "forest_home_sky",
                withExtension: "png",
                subdirectory: "ForestScene/Home"
            )
        else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        RebuildDesignTokens.leaf300.opacity(0.36),
                        RebuildDesignTokens.cream50,
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
        }
        .accessibilityHidden(true)
    }
}

struct MealScheduleNutritionTile: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

struct MealScheduleNutritionSummary {
    let tiles: [MealScheduleNutritionTile]

    init(meals: [RebuildMealDay]) {
        var values: [MealScheduleNutritionTile] = []
        let calories = meals.compactMap(Self.calorieValue)
        if !calories.isEmpty {
            let average = calories.reduce(0, +) / Double(calories.count)
            values.append(
                MealScheduleNutritionTile(
                    title: "열량",
                    value: "\(String(average)) kcal"
                )
            )
        }

        let definitions: [
            (RebuildNutritionInfo.SourceField, String)
        ] = [
            (.protein, "단백질"),
            (.carbs, "탄수화물"),
            (.fat, "지방"),
            (.calcium, "칼슘"),
        ]
        for (field, title) in definitions {
            guard let average = Self.averageNutrition(field: field, meals: meals) else {
                continue
            }
            values.append(
                MealScheduleNutritionTile(
                    title: title,
                    value: Self.formatted(average.value, unit: average.unit)
                )
            )
        }
        tiles = values
    }

    private static func calorieValue(_ meal: RebuildMealDay) -> Double? {
        let value = meal.calorie
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .first
        return value.flatMap { Double($0) }
    }

    private static func averageNutrition(
        field: RebuildNutritionInfo.SourceField,
        meals: [RebuildMealDay]
    ) -> (value: Double, unit: String?)? {
        let sourceMeals = meals.filter {
            $0.nutrition.sourceFields.contains(field)
        }
        guard !sourceMeals.isEmpty else { return nil }
        let values = sourceMeals.map { value(for: field, in: $0.nutrition) }
        let average = values.reduce(0, +) / Double(values.count)
        let units = Set(
            sourceMeals.compactMap {
                $0.nutrition.sourceUnits[field]?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
        )
        return (average, units.count == 1 ? units.first : nil)
    }

    private static func value(
        for field: RebuildNutritionInfo.SourceField,
        in nutrition: RebuildNutritionInfo
    ) -> Double {
        switch field {
        case .carbs: return nutrition.carbs
        case .protein: return nutrition.protein
        case .fat: return nutrition.fat
        case .calcium: return nutrition.calcium
        case .iron: return nutrition.iron
        case .vitamin: return nutrition.vitamin
        }
    }

    private static func formatted(_ value: Double, unit: String?) -> String {
        let suffix = unit.map { " \($0)" } ?? ""
        return "\(String(value))\(suffix)"
    }
}

private extension View {
    func mealScheduleCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.94))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[1],
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[1],
                    style: .continuous
                )
                .stroke(
                    RebuildDesignTokens.forest500.opacity(0.2),
                    lineWidth: 1
                )
            }
            .shadow(
                color: RebuildDesignTokens.forest700.opacity(0.08),
                radius: 12,
                y: 6
            )
    }

    func mealScheduleCellBorder() -> some View {
        overlay {
            Rectangle()
                .stroke(
                    RebuildDesignTokens.forest500.opacity(0.16),
                    lineWidth: 0.5
                )
        }
    }
}
