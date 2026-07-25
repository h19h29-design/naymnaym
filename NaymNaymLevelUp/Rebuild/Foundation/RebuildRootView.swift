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
        RebuildBridgedDestinationView(profile: profile)
    }
}

enum RebuildLegacyProfileBridgeState: Equatable {
    case pending
    case ready(RebuildUserProfile)
}

@MainActor
final class RebuildLegacyProfileBridge: ObservableObject {
    @Published private(set) var state: RebuildLegacyProfileBridgeState = .pending

    func prepare(_ profile: RebuildUserProfile, appState: AppState) {
        appState.applyRebuildProfile(profile)
        guard isApplied(profile, to: appState) else { return }
        state = .ready(profile)
    }

    private func isApplied(
        _ profile: RebuildUserProfile,
        to appState: AppState
    ) -> Bool {
        switch profile.role {
        case .child:
            guard let school = profile.school else { return false }
            return appState.currentMode == .elementary
                && appState.profile?.officeCode == school.officeCode
                && appState.profile?.schoolCode == school.schoolCode
                && appState.profile?.selectedAllergyCodes
                    == profile.allergyCodes.sorted()
        case .parent:
            return appState.currentMode == .parent
                && appState.profile?.nickname == profile.nickname
        }
    }
}

private struct RebuildBridgedDestinationView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var bridge = RebuildLegacyProfileBridge()
    let profile: RebuildUserProfile

    var body: some View {
        Group {
            switch bridge.state {
            case .pending:
                ProgressView("프로필을 준비하고 있어요.")
            case let .ready(readyProfile):
                switch readyProfile.destination {
                case .today:
                    ChildNavigationView(
                        profile: readyProfile,
                        container: RebuildOnboardingAppStore.shared?.container
                    )
                case .parentConnection:
                    ParentSummaryView()
                }
            }
        }
        .task(id: profile.id) {
            bridge.prepare(profile, appState: appState)
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
