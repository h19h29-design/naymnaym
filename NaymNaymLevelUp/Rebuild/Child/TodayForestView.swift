import SwiftUI

struct TodayForestView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: TodayForestViewModel
    let growthPolicy: GrowthPolicy
    let isTabActive: Bool
    let isAppActive: Bool
    @State private var presentedMealDetail: TodayMealDetailPresentation?
    @State private var shownMotionRevision = 0
    @State private var showsConversation = false
    @State private var dailyReviewMeal: DailyReviewPresentation?
    private struct DailyReviewPresentation: Identifiable { let meal: RebuildMealDay; var id:String{meal.date} }

    var body: some View {
        NavigationStack {
            ForestSceneView(
                reduceMotion: reduceMotion,
                activity: ForestSceneActivity(
                    isSheetPresented: isShowingMealDetail || showsConversation || dailyReviewMeal != nil,
                    isTabActive: isTabActive,
                    isAppActive: isAppActive
                )
            ) {
                ScrollViewReader { proxy in
                  ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        heading
                        characterStage.id("companion-stage")
                        dashboardStats
                        missionCard
                        mealSummary
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, RebuildDesignTokens.spacing[3])
                  }
                  .onChange(of: isShowingMealDetail) { isPresented in
                      guard !isPresented, viewModel.motionRevision > shownMotionRevision else { return }
                      proxy.scrollTo("companion-stage", anchor: .top)
                      shownMotionRevision = viewModel.motionRevision
                  }
                }
            }
            .navigationBarHidden(true)
        }
        .task(id: isCurrentDayRefreshActive) {
            guard isCurrentDayRefreshActive else { return }
            await viewModel.loadCurrentDayAndReconcileDate()

            while !Task.isCancelled {
                let delay = viewModel.nanosecondsUntilNextCalendarDay()
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                _ = await viewModel.refreshCurrentDayIfNeeded()
            }
        }
        .sheet(item: $presentedMealDetail) { presentation in
            MealDayDetailView(
                route: presentation.route,
                repository: viewModel.mealScheduleRepository,
                school: viewModel.detailSchool,
                isDemoMode: viewModel.isDemoMode,
                recordingViewModel: presentation.recordingViewModel
            )
        }
        .sheet(isPresented: $showsConversation) {
            CompanionConversationView(level: currentLevel)
        }
        .sheet(item:$dailyReviewMeal) {presentation in
            DailyReviewSheet(meal:presentation.meal,allergies:viewModel.allergyCodes)
        }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
            Text("급식레벨업")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(RebuildDesignTokens.ink900)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today_title")
            Text("한 입씩, 쑥쑥 자라는 하루")
                .font(.footnote.weight(.medium))
                .foregroundStyle(RebuildDesignTokens.forest700)
            }
            Spacer(minLength: 4)
            Text(viewModel.dateText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("날짜 \(viewModel.dateText)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RebuildDesignTokens.cream50)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
    }

    private var characterStage: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image("CompanionForestStage")
                    .resizable().scaledToFill()
                    .frame(height: 238).clipped()
                    .accessibilityHidden(true)
                characterMascot
                    .padding(.leading, 4)
                VStack(alignment: .trailing, spacing: 14) {
                    HStack {
                        Label(growthPolicy.title(for: currentLevel), systemImage: "leaf.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(RebuildDesignTokens.forest700)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.white.opacity(0.94), in: Capsule())
                        Spacer(minLength: 0)
                    }
                    Text(characterMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(RebuildDesignTokens.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(11)
                        .frame(width: 126)
                        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
            .frame(height: 238)
            characterDetails.padding(14).background(.white.opacity(0.97))
            Button { showsConversation = true } label: {
                Label("냠냠이와 이야기하기", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered).tint(RebuildDesignTokens.forest700)
            .padding(.horizontal, 12).padding(.bottom, 10)
            .accessibilityIdentifier("companion_open_conversation")
            if DailyMealReviewAvailability.isEnabled {
                Button {
                    let meal=viewModel.meal ?? RebuildMealDay(date:DailyMealReviewFactory.day(Date()),menuItems:[],calorie:"",nutrition:.empty)
                    dailyReviewMeal=DailyReviewPresentation(meal:meal)
                } label: {
                    Label("오늘 식단 AI 해설",systemImage:"sparkles").font(.subheadline.bold()).frame(maxWidth:.infinity,minHeight:48)
                }.buttonStyle(.borderedProminent).tint(RebuildDesignTokens.forest700)
                    .padding(.horizontal,12).padding(.bottom,12).accessibilityIdentifier("today_daily_review")
            }
        }
        .frame(maxWidth: .infinity)
        .background(RebuildDesignTokens.cream50)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[2],
                style: .continuous
            )
        )
        .overlay(RoundedRectangle(cornerRadius: RebuildDesignTokens.radii[2]).stroke(.white, lineWidth: 2))
        .shadow(color: Color.brown.opacity(0.09), radius: 8, y: 4)
        .accessibilityIdentifier("today_character_hub")
    }

    private var characterMascot: some View {
        GeometryReader { proxy in
            MascotRigView(
                level: currentLevel,
                state: viewModel.motion,
                reduceMotion: reduceMotion,
                playbackRevision: viewModel.motionRevision,
                isActive: isTabActive && isAppActive && !isShowingMealDetail && !showsConversation && dailyReviewMeal == nil
            )
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .center
            )
            .clipped()
        }
        .frame(width: 234, height: 234)
    }

    private var characterDetails: some View {
        let growth = RebuildDesignTokens.semanticPalette(.growth)
        return HStack(spacing: 12) {
            Text("Lv.\(currentLevel)")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(growth.surface)
            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: growthPolicy.progress(totalXP: viewModel.totalXP))
                    .tint(RebuildDesignTokens.forest500)
                    .scaleEffect(x: 1, y: 1.8)
                    .accessibilityLabel("다음 레벨까지 성장 진행도")
                Text(growthPolicy.nextThreshold(totalXP: viewModel.totalXP).map { "EXP \(viewModel.totalXP) / \($0)" } ?? "최고 레벨 달성 · \(viewModel.totalXP) XP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dashboardStats: some View {
        HStack(spacing: 8) {
            statCard("오늘 메뉴", value: "\(viewModel.meal?.menuItems.count ?? 0)가지", icon: "fork.knife", color: .orange)
            statCard("나의 주의", value: "\(viewModel.meal?.menuItems.filter(viewModel.isAllergyRisk).count ?? 0)개", icon: "shield.lefthalf.filled", color: RebuildDesignTokens.forest700)
            statCard("차곡차곡", value: "\(viewModel.totalXP) XP", icon: "star.fill", color: Color(red: 0.9, green: 0.54, blue: 0.12))
        }
    }

    private func statCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon).font(.caption2.weight(.medium)).foregroundStyle(color)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(RebuildDesignTokens.ink900)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 11)
        .background(Color.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.94, green: 0.87, blue: 0.79), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var missionCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("오늘의 한 입 미션").font(.headline.weight(.bold))
                    Text("한 입씩, 나만의 속도로!").font(.subheadline.weight(.semibold))
                    Text("먹은 만큼 솔직하게 기록해요.").font(.caption).foregroundStyle(RebuildDesignTokens.muted600)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image("CompanionLunchTray").resizable().scaledToFit().frame(width: 86, height: 82).accessibilityHidden(true)
            }
            primaryAction
        }
        .foregroundStyle(RebuildDesignTokens.ink900)
        .padding(14)
        .background(Color.white.opacity(0.98), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(red: 0.96, green: 0.86, blue: 0.8), lineWidth: 1))
    }

    private var mealSummary: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            VStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[1]
            ) {
                Text("오늘의 점심")
                    .font(RebuildDesignTokens.titleFont.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.sourceLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let meal = viewModel.meal {
                let totals = MealWholeMealTotals(
                    meal: meal,
                    isDemoMode: viewModel.isDemoMode
                )
                LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(Array(meal.menuItems.enumerated()), id: \.offset) {
                        _, item in
                        let visual = MealVisualResolver.resolve(item: item)
                        let accessibility = MealAccessibilityDescriptor(
                            item: item,
                            visual: visual
                        )
                        HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
                            MealVisualIcon(iconKey: visual.iconKey)
                            .font(.headline)
                            .foregroundStyle(
                                viewModel.isAllergyRisk(item)
                                    ? RebuildDesignTokens.danger700
                                    : RebuildDesignTokens.forest700
                            )
                            .frame(width: 24, height: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(RebuildDesignTokens.bodyFont.weight(.semibold))
                                    .foregroundStyle(RebuildDesignTokens.ink900)
                                    .fixedSize(horizontal: false, vertical: true)
                                MealNutrientChips(
                                    nutrientIDs: visual.representativeNutrientIDs
                                )
                                if viewModel.isAllergyRisk(item) {
                                    allergySignal(item)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                        .padding(10)
                        .background(viewModel.isAllergyRisk(item) ? Color(red: 1, green: 0.93, blue: 0.91) : Color(red: 0.98, green: 0.97, blue: 0.93), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibility.spokenLabel)
                    }
                }
                Text(totals.sourceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
                Text(totals.calorie)
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                Text("전체 영양·알레르기 정보는 급식 상세에서 확인해요.")
                    .font(.caption2).foregroundStyle(RebuildDesignTokens.muted600)
            } else if viewModel.isLoading {
                ProgressView("급식을 확인하고 있어요.")
                    .frame(minHeight: RebuildDesignTokens.minimumActionSize)
            } else {
                Text(viewModel.message ?? "오늘 급식 정보가 아직 없어요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RebuildDesignTokens.cream50)
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
            .stroke(RebuildDesignTokens.cream100, lineWidth: 1)
        }
        .accessibilityIdentifier("today_meal_summary")
    }

    private func allergySignal(_ item: RebuildMealItem) -> some View {
        let safety = RebuildDesignTokens.semanticPalette(.safety)
        let matches = Set(item.allergyCodes).intersection(viewModel.allergyCodes).sorted()
        let title = matches.map(AllergyMap.label(for:)).joined(separator: " · ") + " 주의"
        return Label(title, systemImage: "exclamationmark.shield.fill")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(safety.foreground)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 5)
        .padding(.vertical, RebuildDesignTokens.spacing[1])
        .background(safety.surface)
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
            .stroke(safety.foreground.opacity(0.5), lineWidth: 1)
        }
    }

    private var primaryAction: some View {
        Button {
            presentedMealDetail = viewModel.makeMealDetailPresentation()
        } label: {
            Label(viewModel.primaryActionTitle, systemImage: "fork.knife")
                .font(RebuildDesignTokens.headlineFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: RebuildDesignTokens.minimumActionSize
                )
                .padding(.horizontal, RebuildDesignTokens.spacing[3])
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .background(
            viewModel.isMealDetailActionEnabled
                ? Color(red: 0.96, green: 0.39, blue: 0.31)
                : RebuildDesignTokens.muted600
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
        )
        .disabled(!viewModel.isMealDetailActionEnabled)
        .accessibilityLabel(viewModel.primaryActionTitle)
        .accessibilityHint("메뉴별로 먹은 상태를 기록합니다")
        .accessibilityIdentifier("today_primary_action")
    }

    private var currentLevel: Int {
        growthPolicy.level(totalXP: viewModel.totalXP)
    }

    private var isShowingMealDetail: Bool {
        presentedMealDetail != nil
    }

    private var isCurrentDayRefreshActive: Bool {
        isTabActive && isAppActive
    }

    private var characterMessage: String {
        if let message = viewModel.message {
            return message
        }
        return "오늘 급식도 함께 만나 볼까요?"
    }
}
