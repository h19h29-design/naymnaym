import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.hasProfile {
                MainTabView()
                    .task {
                        await appState.loadMeals()
                    }
            } else {
                OnboardingFlowView()
                    .onAppear {
                        appState.startDraft()
                    }
            }
        }
        .tint(AppColors.primaryGreen)
    }
}

