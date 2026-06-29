import SwiftUI

enum MealCalendarMode: String, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "주간"
        case .monthly: return "월간"
        }
    }
}

struct MealCalendarPeriod {
    static func weekDates(starting date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func shiftedWeekStart(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: value * 7, to: calendar.startOfDay(for: date)) ?? date
    }

    static func shiftedMonth(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: value, to: DateUtils.startOfMonth(for: date)) ?? date
    }

    static func weekTitle(starting date: Date, calendar: Calendar = .current) -> String {
        let dates = weekDates(starting: date, calendar: calendar)
        guard let first = dates.first, let last = dates.last else { return "" }
        return "\(compactDateFormatter.string(from: first)) ~ \(compactDateFormatter.string(from: last))"
    }

    static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}

struct MonthlyMealCalendarView: View {
    var body: some View {
        MealCalendarView()
    }
}

struct MealCalendarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: MealCalendarMode = .weekly
    @State private var displayedWeekStart = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth = DateUtils.startOfMonth(for: Date())
    @State private var selectedDay: CalendarSelectedMeal?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    modePicker
                    periodHeader
                    navigationControls

                    if appState.isLoadingMeals {
                        ProgressView("식단을 불러오는 중")
                            .frame(maxWidth: .infinity)
                    }

                    if let message = appState.mealMessage {
                        calendarNotice(message)
                    }

                    switch mode {
                    case .weekly:
                        weeklyView
                    case .monthly:
                        monthlyView
                    }
                }
                .padding(18)
            }
            .navigationTitle("식단")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground(theme: appState.currentTheme)
            .task(id: loadKey) {
                await loadVisibleMeals()
            }
            .sheet(item: $selectedDay) { day in
                MealCalendarDetailSheet(selectedDay: day, mealStatus: appState.mealStatus)
                    .environmentObject(appState)
            }
        }
    }

    private var modePicker: some View {
        Picker("식단 보기", selection: $mode) {
            ForEach(MealCalendarMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var periodHeader: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(AppColors.orange)
                        .frame(width: 32, height: 32)
                        .background(AppColors.yellow.opacity(0.28))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.profile?.schoolName ?? "학교 선택 전")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textDark)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(mode == .weekly ? "자주 보는 7일 식단을 먼저 보여줘요." : "한 달 식단 흐름을 확인해요.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                    Spacer()
                    MealDataStateBadge(status: appState.mealStatus)
                }
            }
        }
    }

    private var navigationControls: some View {
        RoundedCard(padding: 12) {
            HStack(spacing: 10) {
                Button {
                    movePeriod(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 40, height: 40)
                        .background(AppColors.lavender)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 3) {
                    Text(periodTitle)
                        .font(AppTypography.headline)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    Button("오늘") {
                        displayedWeekStart = Calendar.current.startOfDay(for: Date())
                        displayedMonth = DateUtils.startOfMonth(for: Date())
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.indigo)
                }
                .frame(maxWidth: .infinity)

                Button {
                    movePeriod(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 40, height: 40)
                        .background(AppColors.lavender)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weeklyView: some View {
        VStack(spacing: 10) {
            ForEach(weekDates, id: \.self) { date in
                let meal = meal(for: date)
                Button {
                    selectedDay = CalendarSelectedMeal(date: date, meal: meal)
                } label: {
                    MealDayPreviewCard(
                        date: date,
                        meal: meal,
                        mealStatus: appState.mealStatus,
                        isToday: DateUtils.isSameDay(date, Date())
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthlyView: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.graySecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(calendarCells.indices, id: \.self) { index in
                    if let date = calendarCells[index] {
                        let meal = meal(for: date)
                        Button {
                            selectedDay = CalendarSelectedMeal(date: date, meal: meal)
                        } label: {
                            MealMonthDayCell(date: date, meal: meal, isToday: DateUtils.isSameDay(date, Date()))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(minHeight: 86)
                    }
                }
            }
        }
    }

    private func calendarNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: appState.mealStatus.noticeIcon)
                .foregroundStyle(appState.mealStatus.noticeColor)
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textDark)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(appState.mealStatus.noticeColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var weekDates: [Date] {
        MealCalendarPeriod.weekDates(starting: displayedWeekStart)
    }

    private var calendarCells: [Date?] {
        let days = DateUtils.daysInMonth(for: displayedMonth)
        guard let first = days.first else { return [] }
        let leading = Calendar.current.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: leading) + days.map(Optional.some)
    }

    private var periodTitle: String {
        switch mode {
        case .weekly:
            return MealCalendarPeriod.weekTitle(starting: displayedWeekStart)
        case .monthly:
            return DateUtils.monthTitleFormatter.string(from: displayedMonth)
        }
    }

    private var loadKey: String {
        "\(mode.rawValue)-\(DateUtils.apiString(from: mode == .weekly ? displayedWeekStart : displayedMonth))"
    }

    private func movePeriod(_ value: Int) {
        switch mode {
        case .weekly:
            displayedWeekStart = MealCalendarPeriod.shiftedWeekStart(displayedWeekStart, by: value)
        case .monthly:
            displayedMonth = MealCalendarPeriod.shiftedMonth(displayedMonth, by: value)
        }
    }

    private func loadVisibleMeals() async {
        switch mode {
        case .weekly:
            await appState.loadMeals(for: displayedWeekStart)
        case .monthly:
            await appState.loadMeals(for: displayedMonth)
        }
    }

    private func meal(for date: Date) -> MealDay? {
        let key = DateUtils.apiString(from: date)
        return appState.monthlyMeals.first(where: { $0.date == key })
    }
}

private struct CalendarSelectedMeal: Identifiable {
    var id: String { DateUtils.apiString(from: date) }
    var date: Date
    var meal: MealDay?
}

private struct MealDayPreviewCard: View {
    var date: Date
    var meal: MealDay?
    var mealStatus: MealDataState
    var isToday: Bool

    var body: some View {
        RoundedCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text(dayText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isToday ? Color.white : AppColors.indigo)
                    Text(weekdayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? Color.white.opacity(0.9) : AppColors.graySecondary)
                }
                .frame(width: 50, height: 54)
                .background(isToday ? AppColors.purple : AppColors.lavender)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(meal?.menuItems.isEmpty == false ? "급식 메뉴" : "급식 정보 없음")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textDark)
                        Spacer()
                        if meal?.isSample == true {
                            Text("체험")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.orange)
                                .clipShape(Capsule())
                        }
                    }
                    if let meal, !meal.menuItems.isEmpty {
                        Text(meal.menuItems.prefix(3).map(\.name).joined(separator: " · "))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textDark)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(noMealText)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var dayText: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var weekdayText: String {
        DateUtils.displayDateFormatter.string(from: date).components(separatedBy: " ").last ?? ""
    }

    private var noMealText: String {
        switch mealStatus {
        case .demo:
            return "체험 모드 샘플에 없는 날이에요."
        case .error, .missingAPIKey, .sampleSchool:
            return "설정 확인이 필요해요."
        case .live, .noMeal:
            return "방학, 휴업일 또는 급식 미운영일일 수 있어요."
        }
    }
}

private struct MealMonthDayCell: View {
    var date: Date
    var meal: MealDay?
    var isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption.weight(.bold))
                .foregroundStyle(isToday ? Color.white : AppColors.textDark)
                .frame(width: 24, height: 24)
                .background(isToday ? AppColors.purple : Color.clear)
                .clipShape(Circle())
            if let meal, !meal.menuItems.isEmpty {
                ForEach(Array(meal.menuItems.prefix(2))) { item in
                    Text(item.name)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textDark)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                if meal.menuItems.count > 2 {
                    Text("+\(meal.menuItems.count - 2)개")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppColors.indigo)
                }
            } else {
                Text("정보 없음")
                    .font(.caption2)
                    .foregroundStyle(AppColors.graySecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(meal == nil ? Color.white.opacity(0.58) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isToday ? AppColors.purple : AppColors.cardStroke, lineWidth: isToday ? 2 : 1)
        )
    }
}

private struct MealCalendarDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var recordNotice: String?

    var selectedDay: CalendarSelectedMeal
    var mealStatus: MealDataState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    if let meal = selectedDay.meal, !meal.menuItems.isEmpty {
                        nutritionCard(meal)
                        ForEach(meal.menuItems) { item in
                            calendarMealActionCard(item: item, meal: meal)
                        }
                    } else {
                        emptyCard
                    }

                    if let recordNotice {
                        Text(recordNotice)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textDark)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.lavender.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(18)
            }
            .navigationTitle("식단 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .pageBackground()
        }
    }

    private var header: some View {
        RoundedCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(AppColors.indigo)
                    .frame(width: 42, height: 42)
                    .background(AppColors.lavender)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(DateUtils.displayDateFormatter.string(from: selectedDay.date))
                        .font(AppTypography.title)
                    MealDataStateBadge(status: mealStatus)
                }
                Spacer()
            }
        }
    }

    private func nutritionCard(_ meal: MealDay) -> some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("영양 정보")
                        .font(AppTypography.headline)
                    Spacer()
                    Text(meal.calorie)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.orange)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                    ForEach(meal.nutrition.summaryRows, id: \.0) { row in
                        VStack(spacing: 3) {
                            Text(row.0)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.graySecondary)
                            Text(row.1)
                                .font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(nutritionTint(row.0))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func calendarMealActionCard(item: MealItem, meal: MealDay) -> some View {
        let isRisk = appState.isAllergyRisk(item)
        return RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(AppTypography.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.tags.joined(separator: " · "))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                    Spacer()
                    Image(systemName: isRisk ? "exclamationmark.shield.fill" : "fork.knife.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isRisk ? AppColors.warningRed : AppColors.indigo)
                }

                if isRisk {
                    Label("선택한 알레르기와 관련된 메뉴예요. 한 입 도전은 잠겨요.", systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warningRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    PrimaryButton("한 입 도전", systemImage: "checkmark.seal.fill", isDisabled: isRisk) {
                        _ = appState.recordMealInteraction(item: item, date: meal.date, status: .oneBite)
                        recordNotice = "\(item.name) 한 입 도전을 기록했어요."
                    }
                    SecondaryButton(isRisk ? "안전하게 피했어요" : "먹은 정도 기록", systemImage: isRisk ? "shield.checkered" : "list.bullet.clipboard") {
                        _ = appState.recordMealInteraction(
                            item: item,
                            date: meal.date,
                            status: isRisk ? .allergyAvoided : .half
                        )
                        recordNotice = isRisk ? "\(item.name)은 알레르기/주의로 피한 기록을 남겼어요." : "\(item.name)을 반 정도 먹은 기록으로 남겼어요."
                    }
                    SecondaryButton("잘 먹어요", systemImage: "hand.thumbsup") {
                        _ = appState.recordMealInteraction(item: item, date: meal.date, status: .finished)
                        recordNotice = "\(item.name)은 잘 먹는 메뉴로 기록했어요."
                    }
                    SecondaryButton("사진 기록", systemImage: "camera") {
                        recordNotice = "사진은 오늘 급식 탭의 먹은 정도 기록에서 추가할 수 있어요."
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("급식 정보 없음")
                    .font(AppTypography.headline)
                Text(emptyMessage)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyMessage: String {
        switch mealStatus {
        case .demo:
            return "체험 모드 샘플에 없는 날이에요."
        case .error, .missingAPIKey, .sampleSchool:
            return "API 키, 학교 설정, 네트워크 상태를 확인해 주세요."
        case .live, .noMeal:
            return "방학, 재량휴업일, 급식 미운영일일 수 있어요."
        }
    }

    private func nutritionTint(_ title: String) -> Color {
        if title.contains("탄수") { return AppColors.yellow.opacity(0.22) }
        if title.contains("단백") { return AppColors.coral.opacity(0.14) }
        if title.contains("지방") { return AppColors.orange.opacity(0.14) }
        if title.contains("칼슘") { return AppColors.infoBlue.opacity(0.14) }
        if title.contains("철") { return AppColors.indigo.opacity(0.12) }
        return AppColors.lavender.opacity(0.75)
    }
}

private struct MealDataStateBadge: View {
    var status: MealDataState

    var body: some View {
        Label(status.calendarTitle, systemImage: status.noticeIcon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status.noticeColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(status.noticeColor.opacity(0.12))
            .clipShape(Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private extension MealDataState {
    var calendarTitle: String {
        switch self {
        case .live: return "실제 데이터"
        case .demo: return "체험 모드"
        case .noMeal: return "급식 없음"
        case .error, .missingAPIKey, .sampleSchool: return "설정 확인"
        }
    }

    var noticeIcon: String {
        switch self {
        case .live: return "checkmark.circle.fill"
        case .demo: return "sparkles"
        case .noMeal: return "calendar.badge.exclamationmark"
        case .missingAPIKey: return "key.fill"
        case .sampleSchool: return "building.columns.fill"
        case .error: return "wifi.exclamationmark"
        }
    }

    var noticeColor: Color {
        switch self {
        case .live: return AppColors.successGreen
        case .demo: return AppColors.orange
        case .noMeal: return AppColors.graySecondary
        case .error, .missingAPIKey, .sampleSchool: return AppColors.warningRed
        }
    }
}
