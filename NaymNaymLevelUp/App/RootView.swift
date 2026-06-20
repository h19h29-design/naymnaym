import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("last-intro-date") private var lastIntroDate = ""
    @State private var introDismissed = false

    private var todayKey: String {
        DateUtils.apiString(from: Date())
    }

    var body: some View {
        Group {
            if appState.hasProfile {
                if shouldShowIntro {
                    DailyIntroView {
                        lastIntroDate = todayKey
                        introDismissed = true
                    } onDemo: {
                        appState.startDemoMode()
                        lastIntroDate = todayKey
                        introDismissed = true
                        Task { await appState.loadMeals() }
                    } onParent: {
                        appState.updateUserMode(.parent)
                        lastIntroDate = todayKey
                        introDismissed = true
                    }
                    .task {
                        await appState.loadMeals()
                    }
                } else {
                    MainTabView()
                        .task {
                            await appState.loadMeals()
                        }
                }
            } else {
                OnboardingFlowView()
                    .onAppear {
                        appState.startDraft()
                    }
            }
        }
        .tint(Color(hex: appState.currentTheme.primaryColorHex))
    }

    private var shouldShowIntro: Bool {
        !introDismissed && lastIntroDate != todayKey
    }
}

private struct DailyIntroView: View {
    @EnvironmentObject private var appState: AppState

    var onMeal: () -> Void
    var onDemo: () -> Void
    var onParent: () -> Void

    @State private var bounce = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 10)
                Text("냠냠레벨업")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: appState.currentTheme.primaryColorHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                CharacterAvatar(skin: appState.currentSkin, size: 150)
                    .scaleEffect(bounce ? 1.04 : 0.98)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bounce)

                RoundedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("오늘의 한 입 미션", systemImage: "sparkles")
                            .font(AppTypography.headline)
                            .foregroundStyle(Color(hex: appState.currentTheme.primaryColorHex))
                        Text(missionText)
                            .font(AppTypography.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        ProgressView(value: appState.progress.expProgress)
                            .tint(Color(hex: appState.currentTheme.primaryColorHex))
                        Text(appState.progress.nextLevelText)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                    }
                }

                if hasAllergyWarning {
                    RoundedCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundStyle(Color.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("알레르기 안전 안내")
                                    .font(AppTypography.headline)
                                Text("오늘 급식에 선택한 알레르기와 관련된 메뉴가 있을 수 있어요. 한 입 도전보다 보호자와 학교 안내 확인이 먼저예요.")
                                    .font(AppTypography.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                PrimaryButton("오늘 급식 보러가기", systemImage: "fork.knife", action: onMeal)
                SecondaryButton("체험 모드", systemImage: "sparkles", action: onDemo)
                SecondaryButton("보호자 모드", systemImage: "person.2.fill", action: onParent)
            }
            .padding(20)
        }
        .pageBackground()
        .onAppear {
            bounce = true
        }
    }

    private var missionText: String {
        if let meal = appState.todayMeal,
           let candidate = meal.menuItems.first(where: { !appState.isAllergyRisk($0) }) {
            return "냠냠이가 오늘 급식을 확인했어요. \(candidate.name) 한 입 도전이 추천돼요."
        }
        if appState.mealStatus == .noMeal {
            return "오늘은 급식 정보가 없어요. 월간 식단에서 다른 날짜를 확인해 볼 수 있어요."
        }
        if appState.mealStatus == .demo {
            return "체험 모드입니다. 실제 학교 급식이 아닌 샘플로 흐름을 살펴봐요."
        }
        return "냠냠이가 오늘 급식을 확인하고 있어요."
    }

    private var hasAllergyWarning: Bool {
        guard let meal = appState.todayMeal else { return false }
        return meal.menuItems.contains { appState.isAllergyRisk($0) }
    }
}
