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

private struct MealScheduleDateStatePresentation {
    let label: String
    let systemImage: String
    let color: Color
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
    let state: MealLoadState
}

@MainActor
final class MealScheduleViewModel: ObservableObject {
    @Published private(set) var states: [String: MealLoadState] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    let schoolName: String
    let isDemoMode: Bool

    let repository: any MealScheduleRepository
    let school: RebuildSchool?

    init(
        repository: any MealScheduleRepository,
        school: RebuildSchool?,
        isDemoMode: Bool = false
    ) {
        self.repository = repository
        self.school = school
        self.isDemoMode = isDemoMode
        schoolName = school?.name ?? "학교 등록 전"
    }

    func meal(for date: Date) -> RebuildMealDay? {
        guard let state = loadState(for: date) else { return nil }
        return Self.meal(
            from: state,
            expectedDate: MealScheduleCalendar.key(for: date)
        )
    }

    func loadState(for date: Date) -> MealLoadState? {
        states[MealScheduleCalendar.key(for: date)]
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
                            state: Self.sanitized(state, expectedDate: key)
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
            states[result.key] = result.state
        }
        if school != nil, results.allSatisfy({ result in
            if case .failed = result.state { return true }
            return false
        }) {
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

    private nonisolated static func sanitized(
        _ state: MealLoadState,
        expectedDate: String
    ) -> MealLoadState {
        switch state {
        case let .cached(meal, refreshedAt):
            guard meal.date == expectedDate else {
                return .failed(message: "selected date mismatch", cached: nil)
            }
            return .cached(meal, refreshedAt: refreshedAt)
        case let .live(meal):
            guard meal.date == expectedDate else {
                return .failed(message: "selected date mismatch", cached: nil)
            }
            return .live(meal)
        case let .refreshing(cached):
            guard cached?.date == nil || cached?.date == expectedDate else {
                return .failed(message: "selected date mismatch", cached: nil)
            }
            return .refreshing(cached)
        case let .failed(message, cached):
            guard cached?.date == nil || cached?.date == expectedDate else {
                return .failed(message: "selected date mismatch", cached: nil)
            }
            return .failed(message: message, cached: cached)
        case .empty:
            return .empty
        }
    }
}

struct MealScheduleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: MealScheduleViewModel
    private let recordingViewModelFactory: (MealDayRoute) -> TodayForestViewModel?
    @State private var mode: MealScheduleMode = .daily
    @State private var anchorDate = Date()
    @State private var selectedDate = Date()
    @State private var selection = MealScheduleSelectionState()

    init(
        viewModel: MealScheduleViewModel,
        recordingViewModelFactory: @escaping (MealDayRoute) -> TodayForestViewModel? = { _ in nil }
    ) {
        self.viewModel = viewModel
        self.recordingViewModelFactory = recordingViewModelFactory
    }

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
                .background(
                    RebuildDesignTokens.semanticPalette(.background).surface
                )
                .onChange(of: mode) { _ in
                    selectedDate = anchorDate
                    if reduceMotion {
                        proxy.scrollTo("meal_schedule_top", anchor: .top)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("meal_schedule_top", anchor: .top)
                        }
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
                school: viewModel.school,
                isDemoMode: viewModel.isDemoMode,
                recordingViewModel: recordingViewModelFactory(route)
            )
        }
        .accessibilityIdentifier("meal_schedule_screen")
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            MealScheduleHeaderBackground()
                .frame(maxWidth: .infinity)
            LinearGradient(
                colors: [
                    RebuildDesignTokens.cream50.opacity(0.38),
                    RebuildDesignTokens.cream50.opacity(0.92),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("급식표")
                    .font(.largeTitle.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .accessibilityAddTraits(.isHeader)
                headerMetadata
            }
            .padding(18)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 124,
            maxHeight: 124,
            alignment: .bottomLeading
        )
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

    @ViewBuilder
    private var headerMetadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                schoolNameLabel
                updateStateLabel
            }
        } else {
            HStack(spacing: 8) {
                schoolNameLabel
                    .lineLimit(1)
                Spacer(minLength: 8)
                updateStateLabel
            }
        }
    }

    private var schoolNameLabel: some View {
        Text(viewModel.schoolName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(RebuildDesignTokens.forest700)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var updateStateLabel: some View {
        Label(
            viewModel.isLoading ? "업데이트 중" : "업데이트됨",
            systemImage: viewModel.isLoading
                ? "arrow.triangle.2.circlepath"
                : "checkmark.circle.fill"
        )
        .font(.caption.weight(.bold))
        .foregroundStyle(RebuildDesignTokens.forest700)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.9))
        .clipShape(Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }

    private var modeSelector: some View {
        let palette = RebuildDesignTokens.semanticPalette(.schedule)
        return HStack(spacing: 4) {
            ForEach(MealScheduleMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(
                            mode == item
                                ? palette.foreground
                                : RebuildDesignTokens.muted600
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: RebuildDesignTokens.minimumActionSize
                        )
                        .background(
                            mode == item
                                ? palette.surface
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal_schedule_mode_\(item.rawValue)")
                .accessibilityAddTraits(mode == item ? .isSelected : [])
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .fixedSize(horizontal: false, vertical: true)
            periodButton(systemImage: "chevron.right", direction: 1)
        }
        .frame(minHeight: RebuildDesignTokens.minimumActionSize)
    }

    private func periodButton(
        systemImage: String,
        direction: Int
    ) -> some View {
        let palette = RebuildDesignTokens.semanticPalette(.schedule)
        return Button {
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
                .foregroundStyle(palette.surface)
                .frame(
                    width: RebuildDesignTokens.minimumActionSize,
                    height: RebuildDesignTokens.minimumActionSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            direction < 0
                ? "\(mode.title) 이전 기간"
                : "\(mode.title) 다음 기간"
        )
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

            allergySummary(meal: meal)

            Text("영양 정보")
                .font(.subheadline.bold())
                .foregroundStyle(RebuildDesignTokens.forest500)
            nutritionSummary(meals: meal.map { [$0] } ?? [])

            Button {
                select(date: anchorDate)
            } label: {
                Label("급식 상세 보기", systemImage: "arrow.up.right.square")
                    .font(.subheadline.bold())
                    .frame(
                        maxWidth: .infinity,
                        minHeight: RebuildDesignTokens.minimumActionSize
                    )
            }
            .buttonStyle(.borderedProminent)
            .tint(RebuildDesignTokens.semanticPalette(.schedule).surface)
            .accessibilityIdentifier(
                "meal_schedule_day_detail_\(MealScheduleCalendar.key(for: anchorDate))"
            )
        }
        .mealScheduleCard()
        .accessibilityIdentifier("meal_schedule_daily")
    }

    @ViewBuilder
    private func scheduleSectionHeading(
        title: String,
        subtitle: String
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(RebuildDesignTokens.forest500)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(RebuildDesignTokens.forest500)
                Spacer(minLength: 8)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }
        }
    }

    private var weeklyContent: some View {
        let dates = MealScheduleCalendar.weekDates(containing: anchorDate)
        return VStack(alignment: .leading, spacing: 12) {
            scheduleSectionHeading(
                title: "이번 주 메뉴",
                subtitle: dynamicTypeSize.isAccessibilitySize
                    ? "요일별 대표 메뉴"
                    : "요일별 메뉴를 한눈에 비교"
            )

            if dynamicTypeSize.isAccessibilitySize {
                weeklyAccessiblePreview(dates: dates)
            } else {
                weeklyMenuTable(dates: dates)
            }

            selectedMealInformation
        }
        .mealScheduleCard()
        .accessibilityIdentifier("meal_schedule_weekly")
    }

    private func weeklyMenuTable(dates: [Date]) -> some View {
        let rowHeaderWidth: CGFloat = 52
        let dayColumnWidth: CGFloat = 84
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: rowHeaderWidth, height: 50)
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
                            .frame(width: dayColumnWidth)
                            .frame(
                                minHeight: RebuildDesignTokens.minimumActionSize
                            )
                            .background(
                                selected
                                    ? RebuildDesignTokens.forest700
                                    : Color.white
                            )
                            .contentShape(Rectangle())
                            .mealScheduleCellBorder()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "meal_schedule_week_day_\(MealScheduleCalendar.key(for: date))"
                        )
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                ForEach(MealScheduleRow.allCases) { row in
                    HStack(spacing: 0) {
                        Text(row.compactTitle)
                            .font(.caption2.bold())
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .frame(width: rowHeaderWidth)
                            .frame(minHeight: 64)
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
                                    .frame(width: dayColumnWidth)
                                    .frame(minHeight: 64, alignment: .center)
                                    .padding(.horizontal, 2)
                                    .background(
                                        selected
                                            ? RebuildDesignTokens.leaf300.opacity(0.2)
                                            : Color.white
                                    )
                                    .contentShape(Rectangle())
                                    .mealScheduleCellBorder()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "meal_schedule_week_menu_\(MealScheduleCalendar.key(for: date))_\(row.rawValue)"
                            )
                            .accessibilityAddTraits(selected ? .isSelected : [])
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
        }
    }

    private func weeklyAccessiblePreview(dates: [Date]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 8) {
                ForEach(dates.indices, id: \.self) { index in
                    let date: Date = dates[index]
                    let meal = viewModel.meal(for: date)
                    let statePresentation = dateStatePresentation(for: date)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text(weekdayFormatter.string(from: date))
                                .font(.headline.bold())
                            Text(shortDateFormatter.string(from: date))
                                .font(.body.weight(.semibold))

                            if let representativeMenu = meal?.menuItems.first?.name {
                                Text(representativeMenu)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let iconKey = summary.representativeIconKey {
                                HStack(spacing: 6) {
                                    MealVisualIcon(iconKey: iconKey)
                                        .font(.title3.weight(.semibold))
                                    if let count = summary.additionalMenuLabel {
                                        Text(count)
                                            .font(.body.bold())
                                    }
                                }
                            } else {
                                Label(
                                    statePresentation.label,
                                    systemImage: statePresentation.systemImage
                                )
                                    .font(.footnote.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .foregroundStyle(
                            selected
                                ? Color.white
                                : RebuildDesignTokens.ink900
                        )
                        .padding(12)
                        .frame(width: 132)
                        .frame(minHeight: 120, alignment: .topLeading)
                        .background(
                            selected
                                ? RebuildDesignTokens.forest700
                                : Color.white
                        )
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
                                selected
                                    ? RebuildDesignTokens.forest700
                                    : RebuildDesignTokens.forest500.opacity(0.24),
                                lineWidth: selected ? 2 : 1
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        monthCellAccessibility(
                            date: date,
                            meal: meal,
                            state: statePresentation
                        )
                    )
                    .accessibilityIdentifier(
                        "meal_schedule_week_day_\(MealScheduleCalendar.key(for: date))"
                    )
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var monthlyContent: some View {
        let dates = MealScheduleCalendar.monthGridDates(containing: anchorDate)
        let cellWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 60 : 48
        let columns = Array(
            repeating: GridItem(.fixed(cellWidth), spacing: 0),
            count: 7
        )
        return VStack(alignment: .leading, spacing: 12) {
            scheduleSectionHeading(
                title: "\(monthNumber)월 급식 달력",
                subtitle: "선택 전에도 대표 메뉴 표시"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { day in
                        Text(day)
                            .font(.caption.bold())
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .frame(width: cellWidth)
                            .frame(
                                minHeight: RebuildDesignTokens.minimumActionSize
                            )
                            .background(Color.white)
                            .mealScheduleCellBorder()
                    }

                    ForEach(dates, id: \.self) { date in
                        let meal = viewModel.meal(for: date)
                        let statePresentation = dateStatePresentation(for: date)
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
                        let dateStyle = MealMonthDateVisualStyle.resolve(
                            position: selected
                                ? .selected
                                : dateIsInDisplayedMonth(date)
                                    ? .currentMonth
                                    : .adjacentMonth
                        )
                        Button {
                            select(date: date)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(summary.dateLabel)
                                        .font(.caption2.bold())
                                        .foregroundStyle(dateStyle.foreground)
                                    Spacer(minLength: 0)
                                    Circle()
                                        .fill(statePresentation.color)
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                }

                                if let iconKey = summary.representativeIconKey {
                                    Group {
                                        if dynamicTypeSize.isAccessibilitySize {
                                            VStack(alignment: .leading, spacing: 2) {
                                                MealVisualIcon(iconKey: iconKey)
                                                    .font(.headline.weight(.semibold))
                                                if let count = summary.additionalMenuLabel {
                                                    Text(count)
                                                        .font(.caption.bold())
                                                }
                                            }
                                        } else {
                                            HStack(spacing: 2) {
                                                MealVisualIcon(iconKey: iconKey)
                                                    .font(.caption2.weight(.semibold))
                                                if let count = summary.additionalMenuLabel {
                                                    Text(count)
                                                        .font(.caption2.weight(.bold))
                                                }
                                            }
                                        }
                                    }
                                    .foregroundStyle(
                                        selected
                                            ? RebuildDesignTokens.forest700
                                            : RebuildDesignTokens.ink900
                                    )
                                } else if dynamicTypeSize.isAccessibilitySize {
                                    Image(systemName: statePresentation.systemImage)
                                        .font(.headline)
                                        .foregroundStyle(dateStyle.foreground)
                                        .accessibilityHidden(true)
                                } else {
                                    Text(statePresentation.label)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(dateStyle.foreground)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(6)
                            .frame(width: cellWidth)
                            .frame(
                                minHeight: dynamicTypeSize.isAccessibilitySize
                                    ? 112
                                    : 82,
                                alignment: .topLeading
                            )
                            .background(dateStyle.surface)
                            .contentShape(Rectangle())
                            .mealScheduleCellBorder()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            monthCellAccessibility(
                                date: date,
                                meal: meal,
                                state: statePresentation
                            )
                        )
                        .accessibilityIdentifier(
                            "meal_schedule_month_day_\(MealScheduleCalendar.key(for: date))"
                        )
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .frame(width: cellWidth * 7)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: RebuildDesignTokens.radii[0],
                        style: .continuous
                    )
                )
            }

            selectedMealInformation
        }
        .mealScheduleCard()
        .accessibilityIdentifier("meal_schedule_monthly")
    }

    private func nutritionSummary(
        meals: [RebuildMealDay]
    ) -> some View {
        let summary = MealScheduleNutritionSummary(meals: meals)
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 96), spacing: 6)]
        return VStack(alignment: .leading, spacing: 8) {
            Text(
                MealPresentationCopy.wholeMealSourceLabel(
                    isDemoMode: viewModel.isDemoMode,
                    isAveraged: meals.count > 1
                )
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(RebuildDesignTokens.forest700)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(summary.tiles) { tile in
                    nutritionTile(tile)
                }
            }
        }
    }

    private func nutritionTile(
        _ tile: MealScheduleNutritionTile
    ) -> some View {
        VStack(spacing: 4) {
            Text(tile.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(RebuildDesignTokens.muted600)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text(tile.value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(
                    tile.title == "열량"
                        ? RebuildDesignTokens.danger700
                        : RebuildDesignTokens.ink900
                )
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(
            maxWidth: .infinity,
            minHeight: RebuildDesignTokens.minimumActionSize
        )
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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var selectedMealInformation: some View {
        let selectedMeal = viewModel.meal(for: selectedDate)
        let statePresentation = dateStatePresentation(for: selectedDate)
        let emptyStateForeground = MealMonthDateVisualStyle.resolve(
            position: .selected
        ).foreground
        VStack(alignment: .leading, spacing: 10) {
            scheduleSectionHeading(
                title: "선택한 날짜의 영양 정보",
                subtitle: fullDateFormatter.string(from: selectedDate)
            )
            if let selectedMeal {
                menuVisualSummary(meal: selectedMeal)
                allergySummary(meal: selectedMeal)
                nutritionSummary(meals: [selectedMeal])
            } else {
                Label(
                    selectedDateEmptyMessage(),
                    systemImage: statePresentation.systemImage
                )
                    .font(RebuildDesignTokens.bodyFont.weight(.semibold))
                    .foregroundStyle(emptyStateForeground)
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
                                allergyBadge(
                                    item.allergyLabels.joined(separator: " · ")
                                )
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
            scheduleSectionHeading(
                title: "알레르기 정보",
                subtitle: "번호와 이름을 함께 표시"
            )

            if codes.isEmpty {
                Label(
                    MealAllergyVisualStyle.clear.title,
                    systemImage: MealAllergyVisualStyle.clear.systemImage
                )
                    .font(.caption)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            allergyBadge(AllergyMap.label(for: code))
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

    private func allergyBadge(_ title: String) -> some View {
        let style = MealAllergyVisualStyle.risk(labels: [title])
        let palette = RebuildDesignTokens.semanticPalette(.safety)
        return Label(style.title, systemImage: style.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(palette.surface)
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
                    palette.foreground,
                    lineWidth: style.borderWidth
                )
            }
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
        meal: RebuildMealDay?,
        state: MealScheduleDateStatePresentation
    ) -> String {
        guard let meal, let firstItem = meal.menuItems.first else {
            return "\(fullDateFormatter.string(from: date)), \(state.label)"
        }
        let additionalCount = max(meal.menuItems.count - 1, 0)
        let suffix = additionalCount > 0
            ? ", 외 \(additionalCount)개 메뉴"
            : ""
        return "\(fullDateFormatter.string(from: date)), \(state.label), \(firstItem.name)\(suffix)"
    }

    private func dateStatePresentation(
        for date: Date
    ) -> MealScheduleDateStatePresentation {
        guard let state = viewModel.loadState(for: date) else {
            return MealScheduleDateStatePresentation(
                label: viewModel.isLoading ? "확인 중" : "확인 전",
                systemImage: viewModel.isLoading
                    ? "arrow.triangle.2.circlepath"
                    : "clock",
                color: RebuildDesignTokens.muted600
            )
        }

        switch state {
        case .cached:
            return MealScheduleDateStatePresentation(
                label: viewModel.isDemoMode
                    ? "체험 급식 · 저장됨"
                    : "저장된 급식",
                systemImage: "internaldrive",
                color: RebuildDesignTokens.forest700
            )
        case .refreshing:
            return MealScheduleDateStatePresentation(
                label: viewModel.isDemoMode
                    ? "체험 급식 · 업데이트 중"
                    : "업데이트 중",
                systemImage: "arrow.triangle.2.circlepath",
                color: RebuildDesignTokens.semanticPalette(.schedule).surface
            )
        case .live:
            return MealScheduleDateStatePresentation(
                label: viewModel.isDemoMode ? "체험 급식" : "최신 급식",
                systemImage: "checkmark.circle.fill",
                color: RebuildDesignTokens.forest700
            )
        case .empty:
            return MealScheduleDateStatePresentation(
                label: "급식 없음",
                systemImage: "calendar.badge.minus",
                color: RebuildDesignTokens.muted600
            )
        case .failed:
            return MealScheduleDateStatePresentation(
                label: "불러오기 실패",
                systemImage: "exclamationmark.triangle.fill",
                color: RebuildDesignTokens.danger700
            )
        }
    }

    private func selectedDateEmptyMessage() -> String {
        switch viewModel.loadState(for: selectedDate) {
        case .failed:
            return "해당 날짜의 급식을 불러오지 못했어요."
        case .empty:
            return "해당 날짜에는 등록된 급식이 없어요."
        default:
            return "해당 날짜의 영양 정보를 아직 확인할 수 없어요."
        }
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
                    value: Self.formatted(average, unit: "kcal")
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
        let units = sourceMeals.compactMap {
            $0.nutrition.sourceUnits[field]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).nilIfEmpty
        }
        if units.isEmpty {
            return (average, nil)
        }
        guard units.count == sourceMeals.count, Set(units).count == 1 else {
            return nil
        }
        return (average, units.first)
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
        var number = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        while number.last == "0" {
            number.removeLast()
        }
        if number.last == "." {
            number.removeLast()
        }
        if number == "-0" {
            number = "0"
        }
        let suffix = unit.map { " \($0)" } ?? ""
        return "\(number)\(suffix)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
