import SwiftUI

struct TodayMealView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedItem: MealItem?
    @State private var challengeOutcome: ChallengeOutcome?
    @State private var recordNotice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if appState.isLoadingMeals {
                        ProgressView("급식 정보를 불러오는 중")
                            .frame(maxWidth: .infinity)
                    }

                    if let message = appState.mealMessage {
                        fallbackBanner(message)
                    }

                    if let recordNotice {
                        recordBanner(recordNotice)
                    }

                    if let meal = appState.todayMeal {
                        nutritionSummary(meal)

                        ForEach(meal.menuItems) { item in
                            MealCard(item: item) {
                                recordNotice = nil
                                appState.recordSkipped(item, date: meal.date)
                                selectedItem = item
                            } onChallenge: {
                                recordNotice = nil
                                challengeOutcome = appState.completeChallenge(for: item, date: meal.date)
                            } onAlreadyEats: {
                                appState.recordAlreadyEats(item, date: meal.date)
                                recordNotice = "\(item.name)은 잘 먹는 메뉴로 기록했어요."
                            }
                        }
                    } else {
                        emptyState
                    }

                    cautionCard
                }
                .padding(20)
            }
            .navigationTitle("오늘 급식")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .refreshable {
                await appState.loadMeals()
            }
            .sheet(item: $selectedItem) { item in
                MealLossDetailView(item: item) {
                    selectedItem = nil
                    challengeOutcome = appState.completeChallenge(for: item, date: appState.todayMeal?.date)
                }
            }
            .sheet(item: $challengeOutcome) { outcome in
                LevelUpResultView(outcome: outcome)
            }
        }
    }

    private var header: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    CharacterAvatar(skin: appState.progress.currentSkin, size: 70)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DateUtils.displayDateFormatter.string(from: Date()))
                            .font(AppTypography.headline)
                        Text(appState.profile?.schoolName ?? "학교 선택 전")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.graySecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                Text("안 먹고 싶은 반찬을 누르면 놓칠 수 있는 영양소를 쉽게 알려줘요.")
                    .font(AppTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nutritionSummary(_ meal: MealDay) -> some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("전체 영양 정보")
                        .font(AppTypography.headline)
                    Spacer()
                    Text(meal.calorie)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.orange)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                    ForEach(meal.nutrition.summaryRows, id: \.0) { row in
                        VStack(spacing: 4) {
                            Text(row.0)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColors.graySecondary)
                            Text(row.1)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.textDark)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppColors.primaryGreen.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func fallbackBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppColors.orange)
            Text(message)
                .font(AppTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(AppColors.softYellow.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func recordBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.primaryGreen)
            Text(message)
                .font(AppTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(AppColors.primaryGreen.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyState: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("급식 정보가 아직 없어요")
                    .font(AppTypography.headline)
                Text("잠시 후 다시 시도하거나 설정에서 학교를 확인해 주세요. API가 실패해도 샘플 데이터로 앱을 체험할 수 있어요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton("샘플 다시 불러오기", systemImage: "arrow.clockwise") {
                    Task { await appState.loadMeals() }
                }
            }
        }
    }

    private var cautionCard: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("안내")
                    .font(AppTypography.headline)
                Text("영양소 안내는 의학 진단이 아니라 교육용 참고 안내예요.\n알레르기 정보는 반드시 보호자와 학교 안내를 함께 확인해 주세요.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
