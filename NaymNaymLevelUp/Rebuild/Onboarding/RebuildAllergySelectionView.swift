import SwiftUI

struct RebuildAllergySelectionView: View {
    @ObservedObject var viewModel: RebuildOnboardingViewModel
    @State private var selectedCodes: Set<Int> = []

    private let codes = Array(1...19)

    var body: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            Text("확인이 필요한 알레르기가 있나요?")
                .font(RebuildDesignTokens.titleFont)
                .accessibilityAddTraits(.isHeader)
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
                                Text("\(code)번 알레르기")
                                    .font(RebuildDesignTokens.bodyFont)
                                Spacer()
                                Image(
                                    systemName: selectedCodes.contains(code)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                            .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                        }
                        .accessibilityLabel("\(code)번 알레르기")
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
