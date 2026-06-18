import SwiftUI

struct ProgressAndBadgesView: View {
    @EnvironmentObject private var appState: AppState

    private let allBadges = ["한입 도전자", "초록 용사", "단백질 파워", "칼슘 방패", "비타민 스타", "편식 몬스터 헌터"]
    private let badgeColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    progressCard
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
                CharacterAvatar(skin: appState.progress.currentSkin, size: 132)
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
            }
            .frame(maxWidth: .infinity)
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
        switch record.action {
        case .oneBite:
            return "+\(record.gainedExp) EXP · \(record.badgeName ?? "뱃지 없음")"
        case .skipped:
            return "안 먹는 메뉴로 기록"
        case .alreadyEats:
            return "잘 먹는 메뉴로 기록"
        }
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
