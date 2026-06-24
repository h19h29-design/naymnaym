import SwiftUI

private enum OnboardingStep {
    case intro
    case mode
    case profile
    case school
    case allergy
}

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("last-intro-date") private var lastIntroDate = ""
    @State private var step: OnboardingStep = .intro

    private var todayKey: String {
        DateUtils.apiString(from: Date())
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(step == .intro ? .hidden : .visible, for: .navigationBar)
                .pageBackground()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            IntroExperienceView(
                kind: .firstLaunch,
                primaryTitle: "오늘 급식 보러가기",
                primarySubtitle: "학교 등록하고 시작",
                onPrimary: {
                    markIntroSeen()
                    step = .mode
                },
                onDemo: {
                    markIntroSeen()
                    appState.startDemoMode(mode: .elementary)
                    Task { await appState.loadMeals() }
                },
                onParent: {
                    markIntroSeen()
                    appState.draftUserMode = .parent
                    step = .profile
                }
            )
        case .mode:
            ModeSelectionView(selectedMode: $appState.draftUserMode) {
                step = .profile
            }
        case .profile:
            ProfileSetupView(nickname: $appState.draftNickname) {
                if appState.draftUserMode == .parent {
                    appState.saveParentProfile(nickname: appState.draftNickname)
                } else {
                    step = .school
                }
            }
        case .school:
            SchoolSearchView(mode: .onboarding) { school in
                appState.draftSchool = school
                step = .allergy
            }
        case .allergy:
            AllergySelectionView(selectedCodes: $appState.draftAllergyCodes) {
                if let school = appState.draftSchool {
                    appState.saveProfile(
                        nickname: appState.draftNickname,
                        school: school,
                        allergyCodes: appState.draftAllergyCodes
                    )
                }
            }
        }
    }

    private func markIntroSeen() {
        lastIntroDate = todayKey
    }

    private var title: String {
        switch step {
        case .intro: return "냠냠레벨업"
        case .mode: return "사용자 모드"
        case .profile: return "별명 입력"
        case .school: return "학교 검색"
        case .allergy: return "알레르기 선택"
        }
    }
}

private struct ModeSelectionView: View {
    @Binding var selectedMode: UserMode
    var onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(UserMode.allCases.filter { $0 != .parent }) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        ModeCard(mode: mode, isSelected: selectedMode == mode)
                    }
                    .buttonStyle(.plain)
                }
                PrimaryButton("이 모드로 시작", systemImage: "checkmark.circle.fill", action: onNext)
            }
            .padding(20)
        }
    }
}

private struct ModeCard: View {
    var mode: UserMode
    var isSelected: Bool

    private var theme: ThemeProfile {
        ThemeProfile.profile(id: mode.defaultThemeId, mode: mode)
    }

    var body: some View {
        RoundedCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: theme.primaryColorHex).opacity(mode == .middle ? 0.95 : 0.18))
                        .frame(width: 54, height: 54)
                    Image(systemName: mode.systemImage)
                        .foregroundStyle(mode == .middle ? Color.white : Color(hex: theme.primaryColorHex))
                        .font(.title3.weight(.bold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(mode.title) 모드")
                        .font(AppTypography.headline)
                    Text(description)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.graySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(hex: theme.primaryColorHex) : AppColors.graySecondary)
            }
        }
    }

    private var description: String {
        switch mode {
        case .elementary:
            return "큰 버튼과 쉬운 문장으로 한 입 도전을 도와줘요."
        case .middle:
            return "다크 게임형 미션, EXP, 뱃지를 중심으로 보여줘요."
        case .high:
            return "깔끔한 기록과 영양 밸런스 중심으로 보여줘요."
        case .parent:
            return "아이별 요약과 알레르기 주의, 사진 기록을 확인해요."
        }
    }
}
