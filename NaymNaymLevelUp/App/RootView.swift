import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("last-intro-date") private var lastIntroDate = ""
    @State private var introDismissed = false
    @State private var selectedTab: MainTab = .today

    private var todayKey: String {
        DateUtils.apiString(from: Date())
    }

    var body: some View {
        Group {
            if appState.hasProfile {
                if appState.currentMode == .parent {
                    MainTabView(selection: $selectedTab)
                } else if shouldShowIntro {
                    IntroExperienceView(
                        kind: .daily,
                        primaryTitle: "오늘 급식 보러가기",
                        primarySubtitle: "실제 급식과 한 입 미션 확인",
                        onPrimary: {
                            selectedTab = appState.mealStatus.needsSettingsCheck ? .settings : .today
                            lastIntroDate = todayKey
                            introDismissed = true
                        },
                        onDemo: {
                            appState.startDemoMode()
                            selectedTab = .today
                            lastIntroDate = todayKey
                            introDismissed = true
                            Task { await appState.loadMeals() }
                        },
                        onParent: {
                            appState.updateUserMode(.parent)
                            selectedTab = .parent
                            lastIntroDate = todayKey
                            introDismissed = true
                        }
                    )
                    .task {
                        await appState.loadMeals()
                    }
                } else {
                    MainTabView(selection: $selectedTab)
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

private extension MealDataState {
    var needsSettingsCheck: Bool {
        switch self {
        case .error, .missingAPIKey, .sampleSchool:
            return true
        case .live, .noMeal, .demo:
            return false
        }
    }
}
