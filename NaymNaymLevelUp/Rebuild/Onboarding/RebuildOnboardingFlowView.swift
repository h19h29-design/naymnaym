import SwiftUI

struct RebuildOnboardingFlowView: View {
    @StateObject private var viewModel: RebuildOnboardingViewModel
    @State private var nickname = ""
    @State private var saveMessage: String?
    private let onCompleted: (RebuildUserProfile) -> Void

    init(
        viewModel: RebuildOnboardingViewModel? = nil,
        onCompleted: @escaping (RebuildUserProfile) -> Void = { _ in }
    ) {
        self.onCompleted = onCompleted
        if let viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else {
            _viewModel = StateObject(
                wrappedValue: Self.makeLiveViewModel()
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                    Text(viewModel.progressText)
                        .font(RebuildDesignTokens.headlineFont)
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .accessibilityLabel("온보딩 진행 \(viewModel.progressText)")
                    stepContent
                    Spacer(minLength: 0)
                    Button("처음부터 다시") {
                        nickname = ""
                        viewModel.cancel()
                    }
                    .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                    .accessibilityLabel("온보딩 처음부터 다시 시작")
        }
        .padding(RebuildDesignTokens.spacing[4])
        .background(RebuildDesignTokens.cream50)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .role:
            question("누가 사용하나요?") {
                action("아이로 시작") { viewModel.selectRole(.child) }
                action("보호자로 시작") { viewModel.selectRole(.parent) }
            }
        case .nickname:
            question("어떤 별명으로 부를까요?") {
                TextField("별명 1~12자", text: $nickname)
                    .textFieldStyle(.roundedBorder)
                    .font(RebuildDesignTokens.bodyFont)
                    .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                    .accessibilityLabel("별명")
                action("다음") { viewModel.setNickname(nickname) }
                validationMessage
            }
        case .school:
            RebuildSchoolSearchView(viewModel: viewModel)
        case .allergies:
            RebuildAllergySelectionView(viewModel: viewModel)
        case .confirmation:
            question("이대로 시작할까요?") {
                Text("별명: \(viewModel.draft.nickname)")
                    .font(RebuildDesignTokens.bodyFont)
                Text("학교: \(viewModel.draft.school?.name ?? "해당 없음")")
                    .font(RebuildDesignTokens.bodyFont)
                Text("알레르기: \(allergySummary)")
                    .font(RebuildDesignTokens.bodyFont)
                action("완료") {
                    Task {
                        do {
                            let profile = try await viewModel.complete()
                            onCompleted(profile)
                        } catch {
                            if error as? RebuildOnboardingError
                                != .completionCancelled {
                                saveMessage = "저장하지 못했어요. 다시 시도해 주세요."
                            }
                        }
                    }
                }
                .disabled(viewModel.isCompleting)
                .opacity(viewModel.isCompleting ? 0.55 : 1)
                if viewModel.isCompleting {
                    ProgressView("프로필을 저장하고 있어요.")
                }
                if let saveMessage {
                    Text(saveMessage)
                        .font(RebuildDesignTokens.bodyFont)
                        .foregroundStyle(RebuildDesignTokens.danger700)
                }
            }
        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        if let message = viewModel.validationMessage {
            Text(message)
                .font(RebuildDesignTokens.bodyFont)
                .foregroundStyle(RebuildDesignTokens.danger700)
        }
    }

    private var allergySummary: String {
        viewModel.draft.allergyCodes.isEmpty
            ? "선택 안 함"
            : viewModel.draft.allergyCodes.map(String.init).joined(separator: ", ")
    }

    private func question<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            Text(title)
                .font(RebuildDesignTokens.titleFont)
                .foregroundStyle(RebuildDesignTokens.ink900)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(RebuildDesignTokens.headlineFont)
                .frame(maxWidth: .infinity, minHeight: RebuildDesignTokens.minimumActionSize)
        }
        .foregroundStyle(RebuildDesignTokens.cream50)
        .background(RebuildDesignTokens.forest700)
        .clipShape(RoundedRectangle(cornerRadius: RebuildDesignTokens.radii[0]))
    }

    @MainActor
    private static func makeLiveViewModel() -> RebuildOnboardingViewModel {
        do {
            guard let appStore = RebuildOnboardingAppStore.shared else {
                throw RebuildOnboardingError.persistenceUnavailable
            }
            return RebuildOnboardingViewModel(
                profileStore: appStore.profileStore,
                schoolSearchClient: RebuildLiveSchoolSearchClient()
            )
        } catch {
            return RebuildOnboardingViewModel(
                profileStore: RebuildUnavailableOnboardingProfileStore(),
                schoolSearchClient: RebuildLiveSchoolSearchClient()
            )
        }
    }
}

private struct RebuildUnavailableOnboardingProfileStore:
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
