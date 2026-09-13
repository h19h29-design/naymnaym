import SwiftUI

struct MealDayDetailStatePresentation: Equatable {
    let label: String
    let systemImage: String
}

enum MealDayDetailAccessibilitySection: Equatable {
    case date
    case state
    case menu
    case allergy
    case nutrition
    case recordCTA
}

struct MealDayDetailAccessibilityElement: Equatable {
    let section: MealDayDetailAccessibilitySection
    let identifier: String
    let label: String
    let sortPriority: Double
}

enum MealDayDetailAccessibility {
    static let dateID = "meal_day_date"
    static let stateID = "meal_day_status"
    static let allergyID = "meal_day_allergy"
    static let nutritionID = "meal_day_nutrition"
    static let recordCTAID = "meal_day_record_cta"
    static let cachedRefreshID = "meal_day_cached_refresh"

    static func rootID(dateKey: String) -> String {
        "meal_day_detail_\(dateKey)"
    }

    static func menuID(
        item: RebuildMealItem,
        occurrence: Int = 1
    ) -> String {
        let name = MealRecordIdentityNormalizer.normalizedMenuName(item.name)
        let base = "meal_day_menu_\(name)"
        return occurrence > 1 ? "\(base)_\(occurrence)" : base
    }

    static func menuIDs(items: [RebuildMealItem]) -> [String] {
        var used = Set<String>()
        var nextSuffix: [String: Int] = [:]
        return items.map { item in
            let base = menuID(item: item)
            guard !used.contains(base) else {
                var suffix = nextSuffix[base, default: 2]
                var candidate = "\(base)_\(suffix)"
                while used.contains(candidate) {
                    suffix += 1
                    candidate = "\(base)_\(suffix)"
                }
                used.insert(candidate)
                nextSuffix[base] = suffix + 1
                return candidate
            }
            used.insert(base)
            nextSuffix[base] = 2
            return base
        }
    }

    static func make(
        dateKey: String,
        stateLabel: String,
        meal: RebuildMealDay?,
        canRecord: Bool,
        isDemoMode: Bool = false
    ) -> [MealDayDetailAccessibilityElement] {
        var values: [(
            MealDayDetailAccessibilitySection,
            String,
            String
        )] = [
            (.date, dateID, dateKey),
            (.state, stateID, stateLabel),
        ]

        if let meal {
            let identifiers = menuIDs(items: meal.menuItems)
            values.append(contentsOf: meal.menuItems.enumerated().map { index, item in
                (.menu, identifiers[index], item.name)
            })
            let allergySummary = meal.menuItems.flatMap(\.allergyLabels)
            values.append(
                (
                    .allergy,
                    allergyID,
                    allergySummary.isEmpty
                        ? "표시된 알레르기 정보 없음"
                        : "알레르기 정보 확인: \(allergySummary.joined(separator: " · "))"
                )
            )
            let totals = MealWholeMealTotals(
                meal: meal,
                isDemoMode: isDemoMode
            )
            values.append(
                (
                    .nutrition,
                    nutritionID,
                    "\(totals.sourceLabel), \(totals.calorie), \(totals.nutritionSummary)"
                )
            )
        }

        if canRecord {
            values.append((.recordCTA, recordCTAID, "급식 기록하기"))
        }

        let count = values.count
        return values.enumerated().map { index, value in
            MealDayDetailAccessibilityElement(
                section: value.0,
                identifier: value.1,
                label: value.2,
                sortPriority: Double(count - index)
            )
        }
    }
}

@MainActor
final class MealDayDetailViewModel: ObservableObject {
    let route: MealDayRoute

    @Published private(set) var meal: RebuildMealDay?
    @Published private(set) var state: MealLoadState = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private let repository: any MealScheduleRepository
    private let school: RebuildSchool?
    let isDemoMode: Bool

    var shouldShowLoadingPlaceholder: Bool {
        (!hasLoaded || isLoading) && meal == nil
    }

    var isRefreshingCachedMeal: Bool {
        guard isLoading, meal != nil else { return false }
        if case .refreshing = state {
            return true
        }
        return false
    }

    var showsCachedRefreshAction: Bool {
        guard !isLoading else { return false }
        if case .cached = state {
            return true
        }
        return false
    }

    var isMealSettledForRecording: Bool {
        guard hasLoaded, !isLoading, meal != nil else { return false }
        switch state {
        case .cached, .live, .failed:
            return true
        case .refreshing, .empty:
            return false
        }
    }

    var schoolName: String {
        school?.name ?? "학교 등록 전"
    }

    var statePresentation: MealDayDetailStatePresentation {
        if isRefreshingCachedMeal {
            return MealDayDetailStatePresentation(
                label: isDemoMode
                    ? "체험 급식 · 업데이트 중"
                    : "저장된 급식 · 업데이트 중",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        if shouldShowLoadingPlaceholder || isLoading {
            return MealDayDetailStatePresentation(
                label: "급식을 확인하고 있어요",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }

        switch state {
        case let .cached(_, refreshedAt):
            return MealDayDetailStatePresentation(
                label: isDemoMode
                    ? "체험 급식 · 저장됨 · \(Self.cachedTimeLabel(refreshedAt))"
                    : "저장된 급식 · \(Self.cachedTimeLabel(refreshedAt))",
                systemImage: "internaldrive"
            )
        case .refreshing:
            return MealDayDetailStatePresentation(
                label: meal == nil
                    ? "급식을 확인하고 있어요"
                    : (isDemoMode
                        ? "체험 급식 · 업데이트 중"
                        : "저장된 급식 · 업데이트 중"),
                systemImage: "arrow.triangle.2.circlepath"
            )
        case .live:
            return MealDayDetailStatePresentation(
                label: isDemoMode ? "체험 급식" : "최신 급식",
                systemImage: "checkmark.circle.fill"
            )
        case .empty:
            return MealDayDetailStatePresentation(
                label: "급식 정보 없음",
                systemImage: "calendar.badge.exclamationmark"
            )
        case .failed:
            return MealDayDetailStatePresentation(
                label: "급식을 불러오지 못했어요",
                systemImage: "exclamationmark.triangle.fill"
            )
        }
    }

    init(
        route: MealDayRoute,
        repository: any MealScheduleRepository,
        school: RebuildSchool?,
        isDemoMode: Bool = false
    ) {
        self.route = route
        self.repository = repository
        self.school = school
        self.isDemoMode = isDemoMode
    }

    func load() async {
        guard !isLoading else { return }

        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        apply(await repository.currentState(date: route.dateKey))
        if let school {
            state = .refreshing(meal)
            await repository.refresh(date: route.dateKey, school: school)
            apply(await repository.currentState(date: route.dateKey))
        }
    }

    private func apply(_ candidate: MealLoadState) {
        switch candidate {
        case let .cached(candidateMeal, refreshedAt):
            guard candidateMeal.date == route.dateKey else {
                applyDateMismatch()
                return
            }
            meal = candidateMeal
            state = .cached(candidateMeal, refreshedAt: refreshedAt)
        case let .refreshing(candidateMeal):
            guard candidateMeal?.date == nil || candidateMeal?.date == route.dateKey else {
                applyDateMismatch()
                return
            }
            meal = candidateMeal
            state = .refreshing(candidateMeal)
        case let .live(candidateMeal):
            guard candidateMeal.date == route.dateKey else {
                applyDateMismatch()
                return
            }
            meal = candidateMeal
            state = .live(candidateMeal)
        case .empty:
            meal = nil
            state = .empty
        case let .failed(message, cached):
            guard cached?.date == nil || cached?.date == route.dateKey else {
                applyDateMismatch()
                return
            }
            meal = cached
            state = .failed(message: message, cached: cached)
        }
    }

    private func applyDateMismatch() {
        state = .failed(message: "selected date mismatch", cached: meal)
    }

    private static func cachedTimeLabel(_ refreshedAt: Date?) -> String {
        guard let refreshedAt else { return "저장 시각 미확인" }
        let formatter = DateFormatter()
        formatter.calendar = MealScheduleCalendar.calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = MealScheduleCalendar.calendar.timeZone
        formatter.dateFormat = "M월 d일 HH:mm 저장"
        return formatter.string(from: refreshedAt)
    }
}

struct MealDayDetailView: View {
    private enum PresentedSheet: String, Identifiable {
        case recorder

        var id: String { rawValue }
    }

    let route: MealDayRoute

    @StateObject private var viewModel: MealDayDetailViewModel
    private let recordingViewModel: TodayForestViewModel?
    @EnvironmentObject private var appState: AppState
    @State private var presentedSheet: PresentedSheet?

    init(
        route: MealDayRoute,
        repository: any MealScheduleRepository,
        school: RebuildSchool?,
        isDemoMode: Bool = false,
        recordingViewModel: TodayForestViewModel? = nil
    ) {
        self.route = route
        self.recordingViewModel = recordingViewModel
        _viewModel = StateObject(
            wrappedValue: MealDayDetailViewModel(
                route: route,
                repository: repository,
                school: school,
                isDemoMode: isDemoMode
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    stateContent
                    if DailyMealReviewAvailability.isEnabled {
                        DailyMealReviewView(
                            meal: viewModel.meal ?? RebuildMealDay(date: route.dateKey, menuItems: [], calorie: "", nutrition: .empty),
                            registeredAllergyCodes: appState.profile?.selectedAllergyCodes ?? recordingViewModel?.allergyCodes ?? [],
                            showsSourceNutrition: viewModel.meal == nil
                        )
                    }
                    if canRecord {
                        recordButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(
                RebuildDesignTokens.semanticPalette(.background).surface
            )
            .navigationTitle("급식 상세")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: route.id) {
            await viewModel.load()
        }
        .sheet(item: $presentedSheet) { _ in
            if let recordingViewModel {
                MealRecordingSheet(viewModel: recordingViewModel)
            }
        }
        .accessibilityIdentifier(
            MealDayDetailAccessibility.rootID(dateKey: route.dateKey)
        )
    }

    private var accessibilityElements: [MealDayDetailAccessibilityElement] {
        MealDayDetailAccessibility.make(
            dateKey: route.dateKey,
            stateLabel: viewModel.statePresentation.label,
            meal: viewModel.meal,
            canRecord: canRecord,
            isDemoMode: viewModel.isDemoMode
        )
    }

    private func accessibilityElement(
        identifier: String
    ) -> MealDayDetailAccessibilityElement? {
        accessibilityElements.first { $0.identifier == identifier }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDateTitle)
                    .font(.title2.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                Text(viewModel.schoolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(MealDayDetailAccessibility.dateID)
            .accessibilitySortPriority(
                accessibilityElement(
                    identifier: MealDayDetailAccessibility.dateID
                )?.sortPriority ?? 0
            )
            stateBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var stateBadge: some View {
        let statePriority = accessibilityElement(
            identifier: MealDayDetailAccessibility.stateID
        )?.sortPriority ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Label(
                viewModel.statePresentation.label,
                systemImage: viewModel.statePresentation.systemImage
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(RebuildDesignTokens.forest700)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(MealDayDetailAccessibility.stateID)
            .accessibilitySortPriority(statePriority)

            if viewModel.showsCachedRefreshAction {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                        .font(.footnote.bold())
                        .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(RebuildDesignTokens.forest700)
                .accessibilityIdentifier(MealDayDetailAccessibility.cachedRefreshID)
                .accessibilitySortPriority(statePriority - 0.5)
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.shouldShowLoadingPlaceholder {
            ProgressView("급식을 확인하고 있어요.")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            switch viewModel.state {
            case .cached, .refreshing, .live:
                if let meal = viewModel.meal {
                    mealContent(meal)
                } else {
                    ProgressView("급식을 확인하고 있어요.")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            case .empty:
                VStack(alignment: .leading, spacing: 12) {
                    messageCard(
                        title: "이 날짜에는 등록된 급식이 없어요",
                        message: "주말·방학·휴업일에는 급식이 없을 수 있어요."
                    )
                    retryButton
                }
            case let .failed(message, cached):
                VStack(alignment: .leading, spacing: 12) {
                    if let cached {
                        mealContent(cached)
                    } else {
                        messageCard(
                            title: "급식을 불러오지 못했어요",
                            message: message == "selected date mismatch"
                                ? "선택한 날짜와 응답 날짜가 달라 표시하지 않았어요."
                                : "인터넷 연결을 확인하고 다시 시도해 주세요."
                        )
                    }
                    retryButton
                }
            }
        }
    }

    private var retryButton: some View {
        Button("다시 시도") {
            Task { await viewModel.load() }
        }
        .buttonStyle(.borderedProminent)
        .tint(RebuildDesignTokens.forest700)
        .frame(minWidth: 48, minHeight: 48)
        .disabled(viewModel.isLoading)
    }

    private func mealContent(_ meal: RebuildMealDay) -> some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            menuSection(meal)
            allergySection(meal)
            nutritionSection(meal)
        }
    }

    private func menuSection(_ meal: RebuildMealDay) -> some View {
        let menuIdentifiers = MealDayDetailAccessibility.menuIDs(
            items: meal.menuItems
        )
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            Label("메뉴", systemImage: "fork.knife")
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(
                    RebuildDesignTokens.semanticPalette(.appetite).foreground
                )
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(true)

            ForEach(Array(meal.menuItems.enumerated()), id: \.offset) { index, item in
                let visual = MealVisualResolver.resolve(item: item)
                let menuIdentifier = menuIdentifiers[index]
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        MealVisualIcon(iconKey: visual.iconKey)
                            .font(.title2)
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .frame(width: 56, height: 56)
                            .background(
                                RebuildDesignTokens.semanticPalette(.appetite).surface
                            )
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(RebuildDesignTokens.bodyFont.weight(.semibold))
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
                        }
                    }

                    Text(visual.representativeCopy)
                        .font(.caption)
                        .foregroundStyle(RebuildDesignTokens.muted600)
                        .fixedSize(horizontal: false, vertical: true)

                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(item.name), \(visual.categoryLabel), "
                        + visual.representativeCopy
                )
                .accessibilityIdentifier(
                    menuIdentifier
                )
                .accessibilitySortPriority(
                    accessibilityElement(
                        identifier: menuIdentifier
                    )?.sortPriority ?? 0
                )
                .padding(12)
                .background(
                    RebuildDesignTokens.semanticPalette(.appetite).surface.opacity(0.55)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: RebuildDesignTokens.radii[0],
                        style: .continuous
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
    }

    private func allergySection(_ meal: RebuildMealDay) -> some View {
        let riskyItems = meal.menuItems.filter { !$0.allergyLabels.isEmpty }
        let registeredCodes = recordingViewModel?.allergyCodes ?? appState.profile?.selectedAllergyCodes ?? []
        let hasPersonalRisk = riskyItems.contains {
            MealAllergyVisualStyle.personalized(for: $0, registeredCodes: registeredCodes) != nil
        }
        let safety = RebuildDesignTokens.semanticPalette(.safety)
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            if riskyItems.isEmpty {
                let style = MealAllergyVisualStyle.resolve(
                    for: RebuildMealItem(
                        name: "급식",
                        allergyCodes: [],
                        nutrients: [],
                        tags: [],
                        sourceRawText: ""
                    )
                )
                Label(style.title, systemImage: style.systemImage)
                    .foregroundStyle(RebuildDesignTokens.forest700)
            } else {
                ForEach(Array(riskyItems.enumerated()), id: \.offset) { _, item in
                    let style = MealAllergyVisualStyle.personalized(
                        for: item,
                        registeredCodes: recordingViewModel?.allergyCodes ?? appState.profile?.selectedAllergyCodes ?? []
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        if let style {
                            Label(style.title, systemImage: style.systemImage)
                                .font(RebuildDesignTokens.headlineFont)
                                .foregroundStyle(safety.foreground)
                        }
                        Text(item.name)
                            .font(RebuildDesignTokens.bodyFont)
                        Text("전체 정보: \(item.allergyLabels.joined(separator: " · "))")
                            .font(.footnote)
                            .foregroundStyle(RebuildDesignTokens.muted600)
                    }
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RebuildDesignTokens.spacing[3])
        .background(Color.white)
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
                hasPersonalRisk ? safety.foreground : RebuildDesignTokens.cream100,
                lineWidth: hasPersonalRisk ? 2 : 1
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(MealDayDetailAccessibility.allergyID)
        .accessibilitySortPriority(
            accessibilityElement(
                identifier: MealDayDetailAccessibility.allergyID
            )?.sortPriority ?? 0
        )
    }

    private func nutritionSection(_ meal: RebuildMealDay) -> some View {
        let totals = MealWholeMealTotals(
            meal: meal,
            isDemoMode: viewModel.isDemoMode
        )
        let palette = RebuildDesignTokens.semanticPalette(.nutrition)
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            Label("급식 전체 영양", systemImage: "leaf.fill")
                .font(RebuildDesignTokens.headlineFont)
                .accessibilityAddTraits(.isHeader)
            Text(totals.sourceLabel)
                .font(.caption.weight(.semibold))
            Text(totals.calorie)
                .font(RebuildDesignTokens.bodyFont.weight(.semibold))
            Text(totals.nutritionSummary)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(palette.foreground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RebuildDesignTokens.spacing[3])
        .background(palette.surface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(MealDayDetailAccessibility.nutritionID)
        .accessibilitySortPriority(
            accessibilityElement(
                identifier: MealDayDetailAccessibility.nutritionID
            )?.sortPriority ?? 0
        )
    }

    private func messageCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(RebuildDesignTokens.ink900)
            Text(message)
                .font(RebuildDesignTokens.bodyFont)
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
    }

    private var canRecord: Bool {
        guard let recordingViewModel else { return false }
        return recordingViewModel.dateKey == route.dateKey
            && viewModel.isMealSettledForRecording
    }

    private var recordButton: some View {
        let palette = RebuildDesignTokens.semanticPalette(.mission)
        return Button {
            guard let recordingViewModel,
                  viewModel.isMealSettledForRecording else { return }
            recordingViewModel.synchronizeMeal(viewModel.meal, for: route)
            presentedSheet = .recorder
        } label: {
            Text("급식 기록하기")
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(palette.foreground)
                .frame(maxWidth: .infinity, minHeight: RebuildDesignTokens.minimumActionSize)
                .background(palette.surface)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: RebuildDesignTokens.radii[1],
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(MealDayDetailAccessibility.recordCTAID)
        .accessibilitySortPriority(
            accessibilityElement(
                identifier: MealDayDetailAccessibility.recordCTAID
            )?.sortPriority ?? 0
        )
    }

    private var formattedDateTitle: String {
        let input = DateFormatter()
        input.calendar = MealScheduleCalendar.calendar
        input.locale = Locale(identifier: "ko_KR")
        input.timeZone = MealScheduleCalendar.calendar.timeZone
        input.dateFormat = "yyyy-MM-dd"

        guard let date = input.date(from: route.dateKey) else {
            return route.dateKey
        }
        let output = DateFormatter()
        output.calendar = MealScheduleCalendar.calendar
        output.locale = Locale(identifier: "ko_KR")
        output.timeZone = MealScheduleCalendar.calendar.timeZone
        output.dateFormat = "yyyy년 M월 d일 EEEE"
        return output.string(from: date)
    }
}
