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
    private var loadGeneration = 0

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

        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
                hasLoaded = true
            }
        }

        let initialState = await repository.currentState(date: route.dateKey)
        guard generation == loadGeneration else { return }
        apply(initialState)
        if let school {
            state = .refreshing(meal)
            await repository.refresh(date: route.dateKey, school: school)
            guard generation == loadGeneration else { return }
            let refreshedState = await repository.currentState(date: route.dateKey)
            guard generation == loadGeneration else { return }
            apply(refreshedState)
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
            if !viewModel.hasLoaded || viewModel.isLoading {
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
        if !viewModel.hasLoaded {
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(meal.menuItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(RebuildDesignTokens.forest500)
                        .frame(width: 7, height: 7)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                    Text(item.name)
                        .font(RebuildDesignTokens.bodyFont)
                        .foregroundStyle(RebuildDesignTokens.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(meal.calorie)
                .font(.footnote)
                .foregroundStyle(RebuildDesignTokens.muted600)
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
        return recordingViewModel.dateKey == route.dateKey && viewModel.meal != nil
    }

    private var recordButton: some View {
        Button {
            guard let recordingViewModel else { return }
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
