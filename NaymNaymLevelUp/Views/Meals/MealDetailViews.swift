import SwiftUI

struct MealLossDetailView: View {
    var item: MealItem
    var onChallenge: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.name)
                                .font(AppTypography.title)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(NutritionEstimator.makeStudentExplanation(for: item))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textDark)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    RoundedCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("게임 스탯 변화")
                                .font(AppTypography.headline)
                            ForEach(NutritionEstimator.makeGameStats(for: item)) { stat in
                                StatBar(title: stat.name, value: stat.value, color: AppColors.primaryGreen)
                            }
                        }
                    }

                    PrimaryButton("한 입 도전하기", systemImage: "checkmark.seal.fill") {
                        onChallenge()
                        dismiss()
                    }
                    SecondaryButton("오늘은 안 먹어요", systemImage: "moon") {
                        dismiss()
                    }
                }
                .padding(20)
            }
            .navigationTitle("영양소 안내")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
        }
    }
}

struct LevelUpResultView: View {
    var outcome: ChallengeOutcome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    CharacterAvatar(skin: outcome.skin, size: 150)
                    RoundedCard {
                        VStack(spacing: 14) {
                            Text("한 입 도전 성공!")
                                .font(.system(.title, design: .rounded).weight(.heavy))
                                .foregroundStyle(AppColors.primaryGreen)
                                .multilineTextAlignment(.center)
                            Text("장 건강 경험치 +\(outcome.gainedExp)")
                                .font(AppTypography.headline)
                            Text("편식 몬스터에게 \(outcome.damage) 데미지!")
                                .font(AppTypography.headline)
                                .foregroundStyle(AppColors.orange)
                            Text("\(outcome.badgeName) 뱃지 획득!")
                                .font(AppTypography.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if outcome.didLevelUp {
                                Text("Lv.\(outcome.newLevel) \(PlayerProgress.title(for: outcome.newLevel))로 레벨업!")
                                    .font(AppTypography.headline)
                                    .foregroundStyle(AppColors.primaryGreen)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    PrimaryButton("좋아요", systemImage: "hand.thumbsup.fill") {
                        dismiss()
                    }
                }
                .padding(20)
            }
            .navigationTitle("레벨업")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
        }
    }
}
