import SwiftUI

struct ParentSummaryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("이번 주 요약")
                                .font(AppTypography.title)
                            Text(NutritionEstimator.makeParentSummary(records: recentRecords))
                                .font(AppTypography.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("가정에서 이렇게 도와주세요")
                                .font(AppTypography.headline)
                            helperRow("과일을 함께 먹어요")
                            helperRow("김밥 속 채소를 늘려요")
                            helperRow("나물 반찬을 조금씩 도전해요")
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("주의 문구")
                                .font(AppTypography.headline)
                            Text("놓칠 수 있어요, 도움이 될 수 있어요, 참고해 주세요처럼 부드럽게 안내합니다. 영양소 안내는 의학 진단이 아니라 교육용 참고 정보입니다.")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.graySecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("보호자 요약")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
        }
    }

    private var recentRecords: [ChallengeRecord] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return appState.records.filter { $0.createdAt >= weekAgo }
    }

    private func helperRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "leaf.circle.fill")
                .foregroundStyle(AppColors.primaryGreen)
            Text(text)
                .font(AppTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

