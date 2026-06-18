import SwiftUI

private enum OnboardingStep {
    case intro
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
            IntroView {
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
        case .profile: return "별명 입력"
        case .school: return "학교 검색"
        case .allergy: return "알레르기 선택"
        }
    }
}

private struct IntroView: View {
    var onStart: () -> Void

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

