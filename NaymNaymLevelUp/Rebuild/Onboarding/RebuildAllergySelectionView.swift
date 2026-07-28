import SwiftUI

struct RebuildAllergySelectionView: View {
    @ObservedObject var viewModel: RebuildOnboardingViewModel
    @State private var selectedCodes: Set<Int> = []

    private let codes = AllergyMap.allCodes

    var body: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[1]) {
                Text("확인이 필요한 알레르기가 있나요?")
                    .font(RebuildDesignTokens.titleFont)
                    .accessibilityAddTraits(.isHeader)
                Text("급식표에 표시되는 번호와 식품명을 함께 확인해 주세요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.ink900.opacity(0.72))
            }
            ScrollView {
                LazyVStack(spacing: RebuildDesignTokens.spacing[1]) {
                    ForEach(codes, id: \.self) { code in
                        Button {
                            if selectedCodes.contains(code) {
                                selectedCodes.remove(code)
                            } else {
                                selectedCodes.insert(code)
                            }
                        } label: {
                            HStack {
                                Text(AllergyMap.label(for: code))
                                    .font(RebuildDesignTokens.bodyFont)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(
                                    systemName: selectedCodes.contains(code)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                            .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                        }
                        .accessibilityLabel(AllergyMap.label(for: code))
                        .accessibilityValue(
                            selectedCodes.contains(code) ? "선택됨" : "선택 안 됨"
                        )
                    }
                }
            }
            Button {
                viewModel.setAllergies(Array(selectedCodes))
            } label: {
                Text("다음")
                    .font(RebuildDesignTokens.headlineFont)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: RebuildDesignTokens.minimumActionSize
                    )
            }
            .foregroundStyle(RebuildDesignTokens.cream50)
            .background(RebuildDesignTokens.forest700)
            .clipShape(RoundedRectangle(cornerRadius: RebuildDesignTokens.radii[0]))
        }
    }
}
