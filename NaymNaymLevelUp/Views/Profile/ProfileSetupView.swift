import SwiftUI

struct ProfileSetupView: View {
    @Binding var nickname: String
    @State private var showValidation = false
    var onNext: () -> Void

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        (2...12).contains(trimmedNickname.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("별명을 입력해 주세요")
                            .font(AppTypography.title)
                        Text("이름은 필요 없어요.\n별명만 입력하면 시작할 수 있어요.\n기록은 내 아이폰에만 저장돼요.")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("예: 냠냠이", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.cardStroke))
                            .accessibilityIdentifier("nicknameField")

                        if showValidation && !isValid {
                            Text(trimmedNickname.isEmpty ? "별명을 입력해 주세요." : "별명은 2~12자 정도를 권장해요.")
                                .font(AppTypography.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                PrimaryButton("다음", systemImage: "arrow.right", isDisabled: false) {
                    showValidation = true
                    if isValid {
                        onNext()
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(20)
        }
    }
}

