import SwiftUI

struct ProgressAndBadgesView: View {
    @EnvironmentObject private var appState: AppState

    private let allBadges = ["한입 도전자", "초록 용사", "단백질 파워", "칼슘 방패", "비타민 스타", "균형 기록", "안전 확인"]
    private let badgeColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    progressCard
                    modeSkinCard
                    badgeCard
                    recentRecords
                }
                .padding(20)
            }
            .navigationTitle("레벨 & 뱃지")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
        }
    }

    private var progressCard: some View {
        RoundedCard {
            VStack(spacing: 14) {
                CharacterAvatar(skin: appState.currentSkin, size: 132)
                Text("Lv.\(appState.progress.level) \(appState.progress.title)")
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: appState.progress.expProgress)
                    .tint(AppColors.primaryGreen)
                Text(appState.progress.nextLevelText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.graySecondary)
                Text("총 한 입 도전 \(appState.progress.totalChallenges)회")
                    .font(AppTypography.body.weight(.semibold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    xpPill(title: "기록 XP", value: appState.progress.recordExp, color: AppColors.primaryGreen)
                    xpPill(title: "도전 XP", value: appState.progress.challengeExp, color: AppColors.orange)
                    xpPill(title: "균형 XP", value: appState.progress.balanceExp, color: Color.blue)
                    xpPill(title: "안전 XP", value: appState.progress.safetyExp, color: Color.red)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var modeSkinCard: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(appState.currentMode.title) 테마 캐릭터")
                    .font(AppTypography.headline)
                HStack(spacing: 10) {
                    ForEach(CharacterSkin.skins(for: appState.currentMode).prefix(4)) { skin in
                        VStack(spacing: 6) {
                            CharacterAvatar(skin: skin, size: 58)
                            Text("Lv.\(skin.levelRequired)")
                                .font(.caption2.weight(.bold))
                            Text(skin.name)
                                .font(.caption2)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var badgeCard: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("보유 뱃지")
                    .font(AppTypography.headline)
                LazyVGrid(columns: badgeColumns, spacing: 12) {
                    ForEach(allBadges, id: \.self) { badge in
                        BadgeView(name: badge, isLocked: !appState.progress.badges.contains(badge))
                    }
                }
            }
        }
    }

    private var recentRecords: some View {
        RoundedCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("최근 급식 기록")
                    .font(AppTypography.headline)
                if appState.records.isEmpty {
                    Text("아직 기록이 없어요. 오늘 급식에서 한 입 도전을 시작해 보세요.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.graySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(appState.records.prefix(6)) { record in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: record.action.iconName)
                                .foregroundStyle(recordColor(for: record.action))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.menuName)
                                    .font(AppTypography.body.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(recordDetail(record))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.graySecondary)
                            }
                            Spacer()
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private func recordDetail(_ record: ChallengeRecord) -> String {
        let xpText = record.xpBreakdown.summaryText.isEmpty ? "" : " · \(record.xpBreakdown.summaryText)"
        switch record.action {
        case .oneBite:
            return "+\(record.gainedExp) XP\(xpText) · \(record.badgeName ?? "뱃지 없음")"
        case .skipped:
            return record.gainedExp > 0 ? "+\(record.gainedExp) XP\(xpText)" : "안 먹는 메뉴로 기록"
        case .alreadyEats:
            return record.gainedExp > 0 ? "+\(record.gainedExp) XP\(xpText)" : "잘 먹는 메뉴로 기록"
        }
    }

    private func xpPill(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColors.graySecondary)
            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppColors.textDark)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func recordColor(for action: ChallengeRecord.Action) -> Color {
        switch action {
        case .oneBite:
            return AppColors.primaryGreen
        case .skipped:
            return AppColors.orange
        case .alreadyEats:
            return AppColors.graySecondary
        }
    }
}
