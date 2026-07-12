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
        mealState: MealDataState,
        isLoading: Bool,
        message: String?,
        challengeRecords: [ChallengeRecord],
        mealRecords: [MealRecord],
        allergyRiskItemIDs: Set<UUID>
    ) -> GrowthHomeMission {
        if isLoading {
            return unavailableMission(
                title: "오늘 급식을 불러오는 중이에요",
                detail: "학교 급식 정보를 확인하고 있어요."
            )
        }

        switch mealState {
        case .noMeal:
            return unavailableMission(
                title: "오늘은 등록된 급식이 없어요",
                detail: resolvedDetail(message, fallback: "확인된 급식이 없어 오늘의 한 입 미션은 쉬어가요.")
            )
        case .error:
            return unavailableMission(
                title: "급식 정보를 불러오지 못했어요",
                detail: resolvedDetail(message, fallback: "네트워크 상태를 확인한 뒤 다시 불러와 주세요.")
            )
        case .missingAPIKey:
            return unavailableMission(
                title: "급식 API 설정을 확인해 주세요",
                detail: resolvedDetail(message, fallback: "설정이 완료되기 전에는 오늘의 미션을 만들 수 없어요.")
            )
        case .sampleSchool:
            return unavailableMission(
                title: "실제 학교를 선택해 주세요",
                detail: resolvedDetail(message, fallback: "학교를 선택하면 실제 급식으로 미션을 만들어요.")
            )
        case .demo:
            guard let meal, !meal.menuItems.isEmpty else {
                return unavailableMission(
                    title: "체험 급식이 준비되지 않았어요",
                    detail: resolvedDetail(message, fallback: "체험 모드를 다시 시작해 주세요.")
                )
            }
            return mealMission(
                meal: meal,
                isDemo: true,
                challengeRecords: challengeRecords,
                mealRecords: mealRecords,
                allergyRiskItemIDs: allergyRiskItemIDs
            )
        case .live:
            guard let meal, !meal.menuItems.isEmpty else {
                return unavailableMission(
                    title: "오늘 급식 정보를 확인하지 못했어요",
                    detail: resolvedDetail(message, fallback: "실제 급식 응답에 메뉴가 없어 다시 불러와 주세요.")
                )
            }
            return mealMission(
                meal: meal,
                isDemo: false,
                challengeRecords: challengeRecords,
                mealRecords: mealRecords,
                allergyRiskItemIDs: allergyRiskItemIDs
            )
        }
    }

    private static func mealMission(
        meal: MealDay,
        isDemo: Bool,
        challengeRecords: [ChallengeRecord],
        mealRecords: [MealRecord],
        allergyRiskItemIDs: Set<UUID>
    ) -> GrowthHomeMission {
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
        let unrecordedRiskItems = meal.menuItems.filter {
            allergyRiskItemIDs.contains($0.id) && !recordedNames.contains(normalized($0.name))
        }

        if let riskItem = unrecordedRiskItems.first {
            return GrowthHomeMission(
                title: "알레르기 주의 메뉴를 먼저 확인해요",
                detail: modeDetail(
                    "\(riskItem.name)은 도전하지 말고 보호자와 학교 안내를 확인해요.",
                    isDemo: isDemo
                ),
                progressText: progressText,
                completedCount: completedCount,
                totalCount: totalCount
            )
        }

        if let nextItem = safeItems.first(where: { !recordedNames.contains(normalized($0.name)) }) {
            return GrowthHomeMission(
                title: "\(nextItem.name) 한 입 도전",
                detail: modeDetail("작은 한 입을 기록하면 기본 18 XP를 얻어요.", isDemo: isDemo),
                progressText: progressText,
                completedCount: completedCount,
                totalCount: totalCount
            )
        }

        if completedCount >= totalCount {
            return GrowthHomeMission(
                title: "오늘 급식 기록을 모두 남겼어요",
                detail: modeDetail("기록이 쌓일수록 다람쥐가 다음 단계로 성장해요.", isDemo: isDemo),
                progressText: progressText,
                completedCount: completedCount,
                totalCount: totalCount
            )
        }

        return GrowthHomeMission(
            title: "오늘 급식 기록을 확인해 주세요",
            detail: modeDetail("기록 상태를 확인한 뒤 다시 시도해 주세요.", isDemo: isDemo),
            progressText: progressText,
            completedCount: completedCount,
            totalCount: totalCount
        )
    }

    private static func unavailableMission(title: String, detail: String) -> GrowthHomeMission {
        GrowthHomeMission(
            title: title,
            detail: detail,
            progressText: "오늘 기록 0/0",
            completedCount: 0,
            totalCount: 0
        )
    }

    private static func resolvedDetail(_ message: String?, fallback: String) -> String {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return fallback
        }
        return message
    }

    private static func modeDetail(_ detail: String, isDemo: Bool) -> String {
        isDemo ? "체험 급식 미션이에요. \(detail)" : detail
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct GrowthHomeHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    @ViewBuilder
    private var profileRow: some View {
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 6) {
                    profileIdentity
                    xpLabel
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    profileIdentity
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    xpLabel
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var hero: some View {
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 10) {
                    heroCharacter(size: 196)
                        .frame(maxWidth: .infinity)
                        .frame(height: 198, alignment: .bottom)
                    growthDetails
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .background(Color.white.opacity(0.82))
                }
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    heroCharacter(size: 210)
                        .frame(width: 198, height: 208, alignment: .bottom)
                    growthDetails
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.82))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            Image("Squirrel_Home_Background")
                .resizable()
                .scaledToFill()
                .overlay(Color.white.opacity(0.10))
                .accessibilityHidden(true)
        }
        .clipped()
    }

    private func heroCharacter(size: CGFloat) -> some View {
        GrowthCharacterView(
            level: progress.level,
            size: size,
            pose: .wave,
            blendsCreamBackground: true
        )
        .shadow(color: Palette.forest.opacity(0.18), radius: 10, y: 7)
    }

    @ViewBuilder
    private var missionRow: some View {
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 8) {
                    missionIcon
                    missionContent
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    missionIcon
                    missionContent
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(Palette.teal.opacity(0.07))
    }

    private var profileIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nickname)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Lv.\(progress.level) · \(GrowthCharacterAssets.stageTitle(for: progress.level))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.forest)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var xpLabel: some View {
        Label("\(progress.exp) XP", systemImage: "leaf.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.teal)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var growthDetails: some View {
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            metrics
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: Color.white.opacity(0.9), radius: 2)
    }

    @ViewBuilder
    private var metrics: some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: 6) {
                combinedMetric(value: "\(activityStreak)일", label: "연속 기록", color: Palette.teal)
                combinedMetric(value: "\(progress.totalChallenges)회", label: "한 입 도전", color: Palette.orange)
            }
        } else {
            HStack(spacing: 12) {
                metric(value: "\(activityStreak)일", label: "연속 기록", color: Palette.teal)
                metric(value: "\(progress.totalChallenges)회", label: "한 입 도전", color: Palette.orange)
            }
        }
    }

    private var missionIcon: some View {
        Image(systemName: "target")
            .font(.headline.weight(.bold))
            .foregroundStyle(Palette.orange)
            .frame(width: 30, height: 30)
            .background(Palette.orange.opacity(0.12))
            .clipShape(Circle())
    }

    private var missionContent: some View {
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
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
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

    private func combinedMetric(value: String, label: String, color: Color) -> some View {
        Text("\(label) \(value)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum Palette {
    static let cream = Color(hex: "#FFF9EE")
    static let forest = Color(hex: "#527A2D")
    static let orange = Color(hex: "#E58A2E")
    static let teal = Color(hex: "#1FA6A7")
    static let text = Color(hex: "#3B3024")
}
