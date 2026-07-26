import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("last-intro-date") private var lastIntroDate = ""
    @StateObject private var rebuildIntroGate = RebuildIntroDailyGate()
    @State private var introDismissed = false
    @State private var selectedTab: MainTab = .today

    private var todayKey: String {
        RebuildIntroLocalDay.key(for: Date())
    }

    var body: some View {
        Group {
            if RebuildFeatureGate.isEnabled() {
                if rebuildIntroGate.shouldPresent {
                    RebuildIntroView {
                        rebuildIntroGate.markCompleted()
                    }
                } else {
                    RebuildRootView()
                }
            } else if appState.hasProfile {
                if appState.currentMode == .parent {
                    MainTabView(selection: $selectedTab)
                } else if shouldShowIntro {
                    IntroExperienceView(
                        kind: .daily,
                        characterLevel: appState.progress.level,
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
        .tint(AppColors.primaryGreen)
        .onOpenURL { url in
            Task {
                await handleOpenURL(url)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            rebuildIntroGate.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
        ) { _ in
            rebuildIntroGate.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSSystemTimeZoneDidChange
            )
        ) { _ in
            rebuildIntroGate.refresh()
        }
    }

    private var shouldShowIntro: Bool {
        !introDismissed && lastIntroDate != todayKey
    }

    @MainActor
    private func handleOpenURL(_ url: URL) async {
        guard let route = await RebuildIntroDeepLinkCoordinator.resolve(
            url: url,
            resolver: appState.handleDeepLink,
            markIntroCompleted: {
                rebuildIntroGate.markCompleted()
                introDismissed = true
                lastIntroDate = todayKey
            }
        ) else {
            return
        }

        switch route {
        case .parentSummary:
            selectedTab = .parent
        case .childInvite:
            selectedTab = .parent
        case .onboarding:
            break
        }
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
