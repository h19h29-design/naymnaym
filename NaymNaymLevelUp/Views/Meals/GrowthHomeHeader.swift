import SwiftUI

struct GrowthHomeMission: Equatable {
    let title: String
    let detail: String
    let progressText: String
    let completedCount: Int
    let totalCount: Int
}

enum GrowthHomePresentation {
    static func activityStreak(
        challengeRecords: [ChallengeRecord],
        mealRecords: [MealRecord],
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let recordedDates = Set(challengeRecords.map(\.date) + mealRecords.map(\.date))
        guard !recordedDates.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: date)
        if !recordedDates.contains(DateUtils.apiString(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  recordedDates.contains(DateUtils.apiString(from: yesterday)) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while recordedDates.contains(DateUtils.apiString(from: cursor)) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return streak
    }

    static func mission(
        meal: MealDay?,
        challengeRecords: [ChallengeRecord],
        mealRecords: [MealRecord],
        allergyRiskItemIDs: Set<UUID>
    ) -> GrowthHomeMission {
        guard let meal, !meal.menuItems.isEmpty else {
            return GrowthHomeMission(
                title: "오늘 급식을 기다리고 있어요",
                detail: "급식 정보가 준비되면 한 입 미션을 알려드릴게요.",
                progressText: "오늘 기록 0/0",
                completedCount: 0,
                totalCount: 0
            )
        }

        let mealNames = Set(meal.menuItems.map { normalized($0.name) })
        let recordedNames = Set(
            challengeRecords
                .filter { $0.date == meal.date }
                .map { normalized($0.menuName) }
            + mealRecords
                .filter { $0.date == meal.date }
                .map { normalized($0.menuName) }
        ).intersection(mealNames)
        let completedCount = recordedNames.count
        let totalCount = meal.menuItems.count
        let progressText = "오늘 기록 \(completedCount)/\(totalCount)"
        let safeItems = meal.menuItems.filter { !allergyRiskItemIDs.contains($0.id) }

        if let nextItem = safeItems.first(where: { !recordedNames.contains(normalized($0.name)) }) {
            return GrowthHomeMission(
                title: "\(nextItem.name) 한 입 도전",
                detail: "작은 한 입을 기록하면 기본 18 XP를 얻어요.",
                progressText: progressText,
                completedCount: completedCount,
                totalCount: totalCount
            )
        }

        if !safeItems.isEmpty {
            return GrowthHomeMission(
                title: "오늘 급식 기록을 모두 남겼어요",
                detail: "기록이 쌓일수록 다람쥐가 다음 단계로 성장해요.",
                progressText: progressText,
                completedCount: completedCount,
                totalCount: totalCount
            )
        }

        return GrowthHomeMission(
            title: "알레르기 주의 메뉴를 먼저 확인해요",
            detail: "한 입 도전보다 보호자와 학교의 안전 안내가 먼저예요.",
            progressText: progressText,
            completedCount: completedCount,
            totalCount: totalCount
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct GrowthHomeHeader: View {
    let progress: PlayerProgress
    let nickname: String
    let activityStreak: Int
    let mission: GrowthHomeMission

    var body: some View {
        VStack(spacing: 0) {
            profileRow

            Divider()
                .overlay(Palette.forest.opacity(0.16))

            hero

            Divider()
                .overlay(Palette.forest.opacity(0.16))

            missionRow
        }
        .background(Palette.cream)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.forest.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var profileRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nickname)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("Lv.\(progress.level) · \(GrowthCharacterAssets.stageTitle(for: progress.level))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.forest)
            }
            Spacer(minLength: 8)
            Label("\(progress.exp) XP", systemImage: "leaf.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.teal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 10) {
            GrowthCharacterView(level: progress.level, size: 126)
                .frame(width: 126, height: 126)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GrowthCharacterAssets.stageTitle(for: progress.level))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: progress.expProgress)
                        .tint(Palette.orange)
                    Text(progress.nextLevelText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.forest)
                }

                HStack(spacing: 12) {
                    metric(value: "\(activityStreak)일", label: "연속 기록", color: Palette.teal)
                    metric(value: "\(progress.totalChallenges)회", label: "한 입 도전", color: Palette.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var missionRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "target")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.orange)
                .frame(width: 30, height: 30)
                .background(Palette.orange.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("오늘의 한 입 미션")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.teal)
                Text(mission.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(mission.progressText) · \(mission.detail)")
                    .font(.caption2)
                    .foregroundStyle(Palette.forest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.teal.opacity(0.07))
    }

    private func metric(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Palette.text.opacity(0.72))
        }
    }
}

private enum Palette {
    static let cream = Color(hex: "#FFF9EE")
    static let forest = Color(hex: "#527A2D")
    static let orange = Color(hex: "#E58A2E")
    static let teal = Color(hex: "#1FA6A7")
    static let text = Color(hex: "#3B3024")
}
