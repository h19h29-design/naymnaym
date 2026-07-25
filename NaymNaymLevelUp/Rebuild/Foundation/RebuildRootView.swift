import SwiftUI

struct RebuildRootView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var bootstrap: RebuildOnboardingBootstrapViewModel
    @StateObject private var onboarding: RebuildOnboardingViewModel

    init() {
        let profileStore: RebuildOnboardingProfileStore
        if let appStore = RebuildOnboardingAppStore.shared {
            profileStore = appStore.profileStore
        } else {
            profileStore = RebuildRootUnavailableProfileStore()
        }
        _bootstrap = StateObject(
            wrappedValue: RebuildOnboardingBootstrapViewModel(
                profileStore: profileStore
            )
        )
        _onboarding = StateObject(
            wrappedValue: RebuildOnboardingViewModel(
                profileStore: profileStore,
                schoolSearchClient: RebuildLiveSchoolSearchClient()
            )
        )
    }

    var body: some View {
        Group {
            switch bootstrap.state {
            case .loading:
                ProgressView("프로필을 확인하고 있어요.")
            case .onboarding:
                RebuildOnboardingFlowView(
                    viewModel: onboarding,
                    onCompleted: bootstrap.accept
                )
            case let .destination(profile):
                destination(for: profile)
            case .failed:
                VStack(spacing: RebuildDesignTokens.spacing[3]) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("프로필을 열 수 없어요")
                        .font(RebuildDesignTokens.titleFont)
                    Text("앱을 다시 시작해 주세요.")
                        .font(RebuildDesignTokens.bodyFont)
                }
            }
        }
        .task {
            await bootstrap.load()
        }
    }

    @ViewBuilder
    private func destination(for profile: RebuildUserProfile) -> some View {
        switch profile.destination {
        case .today:
            TodayMealView()
                .task(id: profile.id) {
                    appState.applyRebuildProfile(profile)
                    await appState.loadMeals()
                }
        case .parentConnection:
            ParentSummaryView()
                .task(id: profile.id) {
                    appState.applyRebuildProfile(profile)
                }
        }
    }
}

private struct RebuildRootUnavailableProfileStore:
    RebuildOnboardingProfileStore {
    func load() async throws -> RebuildUserProfile? {
        throw RebuildOnboardingError.persistenceUnavailable
    }

    func save(_ profile: RebuildUserProfile) async throws {
        throw RebuildOnboardingError.persistenceUnavailable
    }

    func removeIfCurrent(id: String) async throws {
        throw RebuildOnboardingError.persistenceUnavailable
    }
}
