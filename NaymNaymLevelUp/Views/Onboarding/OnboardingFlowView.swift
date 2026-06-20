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
    @State private var step: OnboardingStep = .intro

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .pageBackground()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            IntroView(
                onStart: { step = .mode },
                onDemo: {
                    appState.startDemoMode(mode: .elementary)
                    Task { await appState.loadMeals() }
                },
                onParent: {
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
                step = .school
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

private struct IntroView: View {
    var onStart: () -> Void
    var onDemo: () -> Void
    var onParent: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 10)
                CharacterAvatar(skin: CharacterSkin.skin(for: 1), size: 148)
                VStack(spacing: 8) {
                    Text("냠냠레벨업")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.primaryGreen)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("편식 습관을 바꾸는 한 입의 힘!")
                        .font(AppTypography.headline)
                        .multilineTextAlignment(.center)
                }
                RoundedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("오늘 급식에서 안 먹는 반찬을 누르면,\n놓칠 수 있는 영양소를 알려줘요.\n한 입 도전으로 레벨업해요!")
                            .font(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        privacyRow("회원가입 없이 시작해요.")
                        privacyRow("이름 대신 별명만 사용해요.")
                        privacyRow("기록은 내 아이폰에만 저장돼요.")
                    }
                }
                PrimaryButton("시작하기", systemImage: "arrow.right.circle.fill", action: onStart)
                SecondaryButton("체험 모드", systemImage: "sparkles", action: onDemo)
                SecondaryButton("보호자 모드", systemImage: "person.2.fill", action: onParent)
            }
            .padding(20)
        }
    }

    private func privacyRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.primaryGreen)
            Text(text)
                .font(AppTypography.body)
                .fixedSize(horizontal: false, vertical: true)
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
