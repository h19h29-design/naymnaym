import SwiftUI

struct MealLossDetailView: View {
    var item: MealItem
    var isChallengeLocked: Bool = false
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

                    if isChallengeLocked {
                        RoundedCard {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(Color.red)
                                Text("알레르기/주의 메뉴는 한 입 도전보다 안전 확인이 먼저예요. 먹지 않아도 안전 XP로 기록돼요.")
                                    .font(AppTypography.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    PrimaryButton("한 입 도전하기", systemImage: "checkmark.seal.fill", isDisabled: isChallengeLocked) {
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
                            Text(outcomeTitle)
                                .font(.system(.title, design: .rounded).weight(.heavy))
                                .foregroundStyle(AppColors.primaryGreen)
                                .multilineTextAlignment(.center)
                            Text("총 XP +\(outcome.gainedExp)")
                                .font(AppTypography.headline)
                            if !outcome.xpBreakdown.summaryText.isEmpty {
                                Text(outcome.xpBreakdown.summaryText)
                                    .font(AppTypography.body.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if outcome.bonusExp > 0 {
                                Text("다시 시도 보너스 +\(outcome.bonusExp)")
                                    .font(AppTypography.caption.weight(.bold))
                                    .foregroundStyle(AppColors.orange)
                            }
                            Text("\(outcome.badgeName) 뱃지 획득!")
                                .font(AppTypography.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if !outcome.xpNotes.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(outcome.xpNotes.prefix(3), id: \.self) { note in
                                        Label(note, systemImage: "sparkle")
                                            .font(AppTypography.caption)
                                            .foregroundStyle(AppColors.graySecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
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

    private var outcomeTitle: String {
        if outcome.xpBreakdown.safety > 0, outcome.xpBreakdown.challenge == 0 {
            return "안전 기록 완료!"
        }
        if outcome.xpBreakdown.balance > 0, outcome.xpBreakdown.challenge == 0 {
            return "균형 기록 완료!"
        }
        return "한 입 도전 성공!"
    }
}
