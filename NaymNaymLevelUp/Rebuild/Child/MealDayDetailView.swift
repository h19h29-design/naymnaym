import SwiftUI

@MainActor
final class MealDayDetailViewModel: ObservableObject {
    let route: MealDayRoute

    @Published private(set) var meal: RebuildMealDay?
    @Published private(set) var state: MealLoadState = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private let repository: any MealScheduleRepository
    private let school: RebuildSchool?

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

    var isMealSettledForRecording: Bool {
        guard hasLoaded, !isLoading, meal != nil else { return false }
        switch state {
        case .cached, .live, .failed:
            return true
        case .refreshing, .empty:
            return false
        }
    }

    init(
        route: MealDayRoute,
        repository: any MealScheduleRepository,
        school: RebuildSchool?
    ) {
        self.route = route
        self.repository = repository
        self.school = school
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
}

struct MealDayDetailView: View {
    let route: MealDayRoute

    @StateObject private var viewModel: MealDayDetailViewModel
    private let recordingViewModel: TodayForestViewModel?
    @State private var isShowingRecorder = false

    init(
        route: MealDayRoute,
        repository: any MealScheduleRepository,
        school: RebuildSchool?,
        recordingViewModel: TodayForestViewModel? = nil
    ) {
        self.route = route
        self.recordingViewModel = recordingViewModel
        _viewModel = StateObject(
            wrappedValue: MealDayDetailViewModel(
                route: route,
                repository: repository,
                school: school
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    stateContent
                    if canRecord {
                        recordButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(RebuildDesignTokens.cream50)
            .navigationTitle("급식 상세")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: route.id) {
            await viewModel.load()
        }
        .sheet(isPresented: $isShowingRecorder) {
            if let recordingViewModel {
                MealRecordingSheet(viewModel: recordingViewModel)
            }
        }
        .accessibilityIdentifier("meal_day_detail_\(route.dateKey)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(route.dateKey)
                .font(.title2.bold())
                .foregroundStyle(RebuildDesignTokens.ink900)
                .accessibilityAddTraits(.isHeader)
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
        Group {
            if viewModel.isRefreshingCachedMeal {
                Label("저장된 급식 · 업데이트 중", systemImage: "arrow.triangle.2.circlepath")
            } else if viewModel.shouldShowLoadingPlaceholder || viewModel.isLoading {
                Label("급식을 확인하고 있어요", systemImage: "arrow.triangle.2.circlepath")
            } else {
                switch viewModel.state {
                case .cached:
                    Label("저장된 급식", systemImage: "internaldrive")
                case .refreshing:
                    Label(
                        viewModel.meal == nil ? "급식을 확인하고 있어요" : "저장된 급식 · 업데이트 중",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                case .live:
                    Label("학교 급식", systemImage: "checkmark.circle.fill")
                case .empty:
                    Label("급식 정보 없음", systemImage: "calendar.badge.exclamationmark")
                case .failed:
                    Label("급식을 불러오지 못했어요", systemImage: "exclamationmark.triangle.fill")
                }
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(RebuildDesignTokens.forest700)
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
        .disabled(viewModel.isLoading)
    }

    private func mealContent(_ meal: RebuildMealDay) -> some View {
        let totals = MealWholeMealTotals(meal: meal)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(meal.menuItems.enumerated()), id: \.offset) { _, item in
                let visual = MealVisualResolver.resolve(item: item)
                let accessibility = MealAccessibilityDescriptor(
                    item: item,
                    visual: visual
                )
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        MealVisualIcon(iconKey: visual.iconKey)
                        .font(.headline)
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .frame(width: 26, height: 26)

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

                    if !item.allergyLabels.isEmpty {
                        Text("알레르기: \(item.allergyLabels.joined(separator: " · "))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibility.spokenLabel)
                .padding(12)
                .background(RebuildDesignTokens.cream50.opacity(0.72))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: RebuildDesignTokens.radii[0],
                        style: .continuous
                    )
                )
            }

            Text(totals.sourceLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RebuildDesignTokens.forest700)
            Text(totals.calorie)
                .font(.footnote)
                .foregroundStyle(RebuildDesignTokens.muted600)
            Text(totals.nutritionSummary)
                .font(.caption2)
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
        .accessibilityIdentifier("meal_day_detail_menu_\(route.dateKey)")
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
        Button {
            guard let recordingViewModel,
                  viewModel.isMealSettledForRecording else { return }
            recordingViewModel.synchronizeMeal(viewModel.meal, for: route)
            isShowingRecorder = true
        } label: {
            Text("급식 기록하기")
                .font(RebuildDesignTokens.headlineFont)
                .frame(maxWidth: .infinity, minHeight: RebuildDesignTokens.minimumActionSize)
        }
        .buttonStyle(.borderedProminent)
        .tint(RebuildDesignTokens.forest700)
        .accessibilityIdentifier("meal_day_detail_record_\(route.dateKey)")
    }
}
