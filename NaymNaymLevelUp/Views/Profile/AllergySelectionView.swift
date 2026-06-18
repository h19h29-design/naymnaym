import SwiftUI

struct AllergySelectionView: View {
    @Binding var selectedCodes: Set<Int>
    var onFinish: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("알레르기 정보는 선택 입력이에요.")
                            .font(AppTypography.title)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("중요한 알레르기는 반드시 보호자와 학교 안내를 함께 확인해 주세요.")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(AllergyMap.allCodes, id: \.self) { code in
                        Button {
                            if selectedCodes.contains(code) {
                                selectedCodes.remove(code)
                            } else {
                                selectedCodes.insert(code)
                            }
                        } label: {
                            AllergyChip(code: code, isSelected: selectedCodes.contains(code))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                PrimaryButton("오늘 급식 보러 가기", systemImage: "fork.knife", action: onFinish)
                SecondaryButton("건너뛰기", systemImage: "forward.fill") {
                    selectedCodes.removeAll()
                    onFinish()
                }
            }
            .padding(20)
        }
    }
}

