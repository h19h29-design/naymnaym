import SwiftUI

struct MonthlyMealCalendarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var displayedMonth = DateUtils.startOfMonth(for: Date())
    @State private var selectedMeal: MealDay?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    monthControls
                    weekdayHeader
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(calendarCells.indices, id: \.self) { index in
                            if let date = calendarCells[index] {
                                let meal = meal(for: date)
                                Button {
                                    selectedMeal = meal ?? MealDay(
                                        date: DateUtils.apiString(from: date),
                                        menuItems: [],
                                        calorie: "정보 없음",
                                        nutrition: .empty,
                                        isSample: false,
                                        notice: appState.mealStatus == .demo ? "체험 모드 데이터가 없는 날이에요." : "실제 급식 정보가 없는 날이에요."
                                    )
                                } label: {
                                    CalendarDayCell(date: date, meal: meal, isToday: DateUtils.isSameDay(date, Date()))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear.frame(minHeight: 82)
                            }
                        }
                    }
                    RoundedCard {
                        Text("긴 메뉴명은 칸 안에서 줄바꿈되며, 급식 정보가 없는 날은 정보 없음으로 표시돼요.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
            }
            .navigationTitle("월간 식단")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .task(id: displayedMonth) {
                await appState.loadMeals(for: displayedMonth)
            }
            .sheet(item: $selectedMeal) { meal in
                DailyMealSheet(meal: meal)
            }
        }
    }

    private var monthControls: some View {
        HStack {
            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 42, height: 42)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Spacer()
            Text(DateUtils.monthTitleFormatter.string(from: displayedMonth))
                .font(AppTypography.title)
                .minimumScaleFactor(0.8)
            Spacer()
            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 42, height: 42)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.graySecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarCells: [Date?] {
        let days = DateUtils.daysInMonth(for: displayedMonth)
        guard let first = days.first else { return [] }
        let leading = Calendar.current.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: leading) + days.map(Optional.some)
    }

    private func meal(for date: Date) -> MealDay? {
        let key = DateUtils.apiString(from: date)
        return appState.monthlyMeals.first(where: { $0.date == key })
    }
}

private struct DailyMealSheet: View {
    var meal: MealDay
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(DateUtils.displayString(fromAPIString: meal.date)) {
                    if meal.menuItems.isEmpty {
                        Text("정보 없음")
                    } else {
                        ForEach(meal.menuItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                Text(item.tags.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.graySecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("식단 상세")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
