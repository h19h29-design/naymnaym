import SwiftUI

struct GrowthProgressPresentation {
    let totalXP: Int
    let currentLevel: Int
    let nextLevel: Int?
    let remainingXP: Int
    let progressFraction: Double

    init(progress: PlayerProgress) {
        let totalXP = max(0, progress.exp)
        let currentLevel = PlayerProgress.level(forExp: totalXP)
        let currentThreshold = PlayerProgress.levelThresholds[currentLevel - 1]
        let nextThreshold = currentLevel < PlayerProgress.levelThresholds.count
            ? PlayerProgress.levelThresholds[currentLevel]
            : nil

        self.totalXP = totalXP
        self.currentLevel = currentLevel
        nextLevel = nextThreshold == nil ? nil : currentLevel + 1
        remainingXP = max(0, (nextThreshold ?? totalXP) - totalXP)

        if let nextThreshold {
            let interval = max(1, nextThreshold - currentThreshold)
            progressFraction = min(1, max(0, Double(totalXP - currentThreshold) / Double(interval)))
        } else {
            progressFraction = 1
        }
    }

    func isStageUnlocked(_ level: Int) -> Bool {
        level <= currentLevel
    }
}

struct GrowthLevelMarkPresentation {
    let level: Int
    let diameter: CGFloat = 54
    let glyphPointSize: CGFloat = 17

    var glyph: String {
        "L\(GrowthCharacterAssets.atlasCell(for: level) + 1)"
    }
}

struct ProgressAndBadgesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedTab: GrowthTab = .evolution

    private let allBadges = ["한 입 도전자", "초록 용사", "단백질 파워", "칼슘 방패", "비타민 스타", "균형 기록", "안전 확인"]

    private var adaptiveColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 128), spacing: 8)]
    }

    private var presentation: GrowthProgressPresentation {
        GrowthProgressPresentation(progress: appState.progress)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    levelSummary
                    evolutionPath
                    tabPicker
                    selectedTabContent
                    xpBreakdown
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(GrowthPalette.cream.ignoresSafeArea())
            .navigationTitle("캐릭터 성장")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var levelSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    levelMark
                    levelIdentity
                    totalXPLabel(alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    levelMark
                    levelIdentity
                    Spacer(minLength: 8)
                    totalXPLabel(alignment: .trailing)
                }
            }

            ProgressView(value: presentation.progressFraction)
                .tint(GrowthPalette.forest)
                .scaleEffect(x: 1, y: 1.7, anchor: .center)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    progressCaptionLabel
                    remainingCaptionLabel
                        .multilineTextAlignment(.leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    progressCaptionLabel
                    Spacer(minLength: 8)
                    remainingCaptionLabel
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .growthSurface(background: Color.white)
        .accessibilityElement(children: .combine)
    }

    private var levelMark: some View {
        let mark = GrowthLevelMarkPresentation(level: presentation.currentLevel)

        return ZStack {
            Circle()
                .fill(GrowthPalette.forest)
                .frame(width: mark.diameter, height: mark.diameter)
            Text(mark.glyph)
                .font(.system(size: mark.glyphPointSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .frame(width: mark.diameter, height: mark.diameter)
        }
        .accessibilityHidden(true)
    }

    private var levelIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("현재 레벨 \(presentation.currentLevel)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(GrowthPalette.teal)
            Text(GrowthCharacterAssets.stageTitle(for: presentation.currentLevel))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(GrowthPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func totalXPLabel(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("총 XP")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(GrowthPalette.muted)
            Text("\(presentation.totalXP) XP")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(GrowthPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var progressCaptionLabel: some View {
        Text(progressCaption)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(GrowthPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var remainingCaptionLabel: some View {
        Text(remainingCaption)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(GrowthPalette.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progressCaption: String {
        guard let nextLevel = presentation.nextLevel else { return "7단계 진화를 모두 완료했어요" }
        return "레벨 \(nextLevel) 진행률 \(Int((presentation.progressFraction * 100).rounded()))%"
    }

    private var remainingCaption: String {
        presentation.nextLevel == nil ? "최고 단계" : "다음 진화까지 \(presentation.remainingXP) XP"
    }

    private var evolutionPath: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(title: "7단계 진화", detail: "지금까지의 성장과 다음 단계를 확인해요")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(1...7, id: \.self) { level in
                        evolutionStage(level: level)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .growthSurface(background: GrowthPalette.softForest)
    }

    private func evolutionStage(level: Int) -> some View {
        let isCurrent = level == presentation.currentLevel
        let isUnlocked = presentation.isStageUnlocked(level)
        let stageWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 180 : 76
        let characterSize: CGFloat = dynamicTypeSize.isAccessibilitySize ? 96 : 66

        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                GrowthCharacterView(level: level, size: characterSize)
                    .saturation(isUnlocked ? 1 : 0)
                    .opacity(isUnlocked ? 1 : 0.42)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isCurrent ? GrowthPalette.orange : Color.clear, lineWidth: 3)
                    )

                Image(systemName: stageIcon(isCurrent: isCurrent, isUnlocked: isUnlocked))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 22)
                    .background(stageColor(isCurrent: isCurrent, isUnlocked: isUnlocked))
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
            }

            Text("Lv.\(level)")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(isCurrent ? GrowthPalette.orange : GrowthPalette.text)
            Text(GrowthCharacterAssets.stageTitle(for: level))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(isUnlocked ? GrowthPalette.text : GrowthPalette.muted)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: stageWidth - 4)
                .frame(minHeight: 32, alignment: .top)
            Text(stageStatus(isCurrent: isCurrent, isUnlocked: isUnlocked))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(stageColor(isCurrent: isCurrent, isUnlocked: isUnlocked))
        }
        .frame(width: stageWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("레벨 \(level), \(GrowthCharacterAssets.stageTitle(for: level)), \(stageStatus(isCurrent: isCurrent, isUnlocked: isUnlocked))")
    }

    private var tabPicker: some View {
        Picker("성장 정보", selection: $selectedTab) {
            ForEach(GrowthTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("진화, 의상, 뱃지, 스토리 중 표시할 내용을 선택합니다")
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .evolution:
            evolutionContent
        case .outfits:
            outfitsContent
        case .badges:
            badgesContent
        case .story:
            storyContent
        }
    }

    private var evolutionContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("나의 현재 다람쥐")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(GrowthPalette.forest)
                Text("Lv.\(presentation.currentLevel) · \(GrowthCharacterAssets.stageTitle(for: presentation.currentLevel))")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(GrowthPalette.text)

                GeometryReader { proxy in
                    let characterSize = min(proxy.size.width, 150)
                    GrowthCharacterView(level: presentation.currentLevel, size: characterSize, pose: .celebrate)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 150)
            }
            .growthSurface(background: GrowthPalette.cream)

            nextEvolutionPreview
        }
    }

    @ViewBuilder
    private var nextEvolutionPreview: some View {
        if let nextLevel = presentation.nextLevel {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    nextCharacter(level: nextLevel)
                    nextEvolutionCopy(level: nextLevel)
                    Spacer(minLength: 0)
                }

                VStack(spacing: 12) {
                    nextCharacter(level: nextLevel)
                    nextEvolutionCopy(level: nextLevel)
                }
            }
            .growthSurface(background: GrowthPalette.softOrange)
        } else {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(GrowthPalette.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("모든 진화를 완료했어요")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(GrowthPalette.text)
                    Text("레전드 냠냠러로 쌓아 온 기록과 뱃지를 계속 모아 보세요.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(GrowthPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .growthSurface(background: GrowthPalette.softOrange)
        }
    }

    private func nextCharacter(level: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            GrowthCharacterView(level: level, size: 116)
                .saturation(0.25)
                .opacity(0.72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Image(systemName: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(GrowthPalette.orange)
                .clipShape(Circle())
                .offset(x: 5, y: -5)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("다음 진화 레벨 \(level), \(GrowthCharacterAssets.stageTitle(for: level)), 잠김")
    }

    private func nextEvolutionCopy(level: Int) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .center : .leading, spacing: 5) {
            Text("다음 진화")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(GrowthPalette.teal)
            Text("Lv.\(level) \(GrowthCharacterAssets.stageTitle(for: level))")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(GrowthPalette.text)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(presentation.remainingXP) XP를 더 모으면 새로운 모습과 성장 칭호가 열려요.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(GrowthPalette.muted)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var outfitsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(title: "성장 의상", detail: "현재 모드에서 레벨과 함께 열리는 의상이에요")

            LazyVGrid(columns: adaptiveColumns, spacing: 8) {
                ForEach(CharacterSkin.skins(for: appState.currentMode)) { skin in
                    outfitCell(skin)
                }
            }
        }
    }

    private func outfitCell(_ skin: CharacterSkin) -> some View {
        let isUnlocked = skin.isUnlocked(at: presentation.currentLevel)
        let isCurrent = skin.id == appState.currentSkin.id

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                GrowthCharacterView(level: skin.levelRequired, size: 96)
                    .saturation(isUnlocked ? 1 : 0)
                    .opacity(isUnlocked ? 1 : 0.4)
                    .frame(maxWidth: .infinity)
                Image(systemName: isCurrent ? "checkmark.circle.fill" : (isUnlocked ? "checkmark.seal.fill" : "lock.fill"))
                    .foregroundStyle(isCurrent ? GrowthPalette.orange : (isUnlocked ? GrowthPalette.forest : GrowthPalette.muted))
                    .accessibilityHidden(true)
            }
            Text(skin.name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(GrowthPalette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(skin.description)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(GrowthPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Label(isCurrent ? "현재 의상" : (isUnlocked ? "사용 가능" : "Lv.\(skin.levelRequired)에 열림"), systemImage: isUnlocked ? "checkmark" : "lock.fill")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(isCurrent ? GrowthPalette.orange : (isUnlocked ? GrowthPalette.forest : GrowthPalette.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .growthSurface(background: isCurrent ? GrowthPalette.softOrange : Color.white)
        .accessibilityElement(children: .combine)
    }

    private var badgesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                title: "뱃지 컬렉션",
                detail: "\(appState.progress.badges.filter(allBadges.contains).count)/\(allBadges.count)개 획득"
            )

            LazyVGrid(columns: adaptiveColumns, spacing: 8) {
                ForEach(Array(allBadges.enumerated()), id: \.offset) { index, badge in
                    badgeCell(name: badge, index: index)
                }
            }
        }
    }

    private func badgeCell(name: String, index: Int) -> some View {
        let isUnlocked = appState.progress.badges.contains(name)
        let tint = badgeTint(index: index)

        return VStack(spacing: 8) {
            Image(systemName: isUnlocked ? badgeIcon(name: name) : "lock.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(isUnlocked ? tint : GrowthPalette.muted)
                .frame(width: 52, height: 52)
                .background(isUnlocked ? tint.opacity(0.14) : GrowthPalette.muted.opacity(0.10))
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(isUnlocked ? GrowthPalette.text : GrowthPalette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(isUnlocked ? "획득 완료" : "아직 잠김")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(isUnlocked ? tint : GrowthPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .growthSurface(background: Color.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(isUnlocked ? "획득 완료" : "아직 잠김")")
    }

    private var storyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(title: "최근 성장 스토리", detail: "급식 기록이 다람쥐의 성장 이야기로 이어져요")

            if appState.records.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .font(.title3)
                        .foregroundStyle(GrowthPalette.teal)
                        .accessibilityHidden(true)
                    Text("아직 기록이 없어요. 오늘 급식에서 한 입 도전을 시작해 보세요.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(GrowthPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .growthSurface(background: GrowthPalette.softTeal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.records.prefix(6).enumerated()), id: \.element.id) { index, record in
                        recordRow(record)
                        if index < min(appState.records.count, 6) - 1 {
                            Divider()
                        }
                    }
                }
                .growthSurface(background: Color.white)
            }
        }
    }

    private func recordRow(_ record: ChallengeRecord) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: record.action.iconName)
                .font(.body.weight(.bold))
                .foregroundStyle(recordColor(for: record.action))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.menuName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(GrowthPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recordDetail(record))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(GrowthPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var xpBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(title: "XP 상세", detail: "네 가지 활동에서 모은 성장 경험치예요")
            LazyVGrid(columns: adaptiveColumns, spacing: 8) {
                xpCategory(title: "기록 XP", value: appState.progress.recordExp, icon: "square.and.pencil", tint: GrowthPalette.forest)
                xpCategory(title: "도전 XP", value: appState.progress.challengeExp, icon: "flag.fill", tint: GrowthPalette.orange)
                xpCategory(title: "균형 XP", value: appState.progress.balanceExp, icon: "scale.3d", tint: GrowthPalette.teal)
                xpCategory(title: "안전 XP", value: appState.progress.safetyExp, icon: "shield.checkered", tint: GrowthPalette.safety)
            }
        }
    }

    private func xpCategory(title: String, value: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(GrowthPalette.muted)
                Text("\(value) XP")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(GrowthPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .growthSurface(background: tint.opacity(0.10))
        .accessibilityElement(children: .combine)
    }

    private func sectionHeading(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(GrowthPalette.text)
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(GrowthPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stageIcon(isCurrent: Bool, isUnlocked: Bool) -> String {
        if isCurrent { return "location.fill" }
        return isUnlocked ? "checkmark" : "lock.fill"
    }

    private func stageColor(isCurrent: Bool, isUnlocked: Bool) -> Color {
        if isCurrent { return GrowthPalette.orange }
        return isUnlocked ? GrowthPalette.forest : GrowthPalette.muted
    }

    private func stageStatus(isCurrent: Bool, isUnlocked: Bool) -> String {
        if isCurrent { return "현재" }
        return isUnlocked ? "완료" : "잠김"
    }

    private func badgeIcon(name: String) -> String {
        if name.contains("초록") { return "leaf.fill" }
        if name.contains("단백질") { return "bolt.heart.fill" }
        if name.contains("칼슘") { return "shield.fill" }
        if name.contains("비타민") { return "star.fill" }
        if name.contains("균형") { return "scale.3d" }
        if name.contains("안전") { return "checkmark.shield.fill" }
        return "fork.knife.circle.fill"
    }

    private func badgeTint(index: Int) -> Color {
        switch index % 3 {
        case 0: return GrowthPalette.forest
        case 1: return GrowthPalette.orange
        default: return GrowthPalette.teal
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

    private func recordColor(for action: ChallengeRecord.Action) -> Color {
        switch action {
        case .oneBite:
            return GrowthPalette.forest
        case .skipped:
            return GrowthPalette.orange
        case .alreadyEats:
            return GrowthPalette.teal
        }
    }
}

private enum GrowthTab: String, CaseIterable, Identifiable {
    case evolution
    case outfits
    case badges
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .evolution: return "진화"
        case .outfits: return "의상"
        case .badges: return "뱃지"
        case .story: return "스토리"
        }
    }
}

private enum GrowthPalette {
    static let cream = Color(hex: "#FFF9EE")
    static let forest = Color(hex: "#527A2D")
    static let orange = Color(hex: "#E58A2E")
    static let teal = Color(hex: "#1FA6A7")
    static let text = Color(hex: "#3B3024")
    static let muted = Color(hex: "#746B60")
    static let safety = Color(hex: "#C84C4C")
    static let softForest = Color(hex: "#EDF4E7")
    static let softOrange = Color(hex: "#FFF0DF")
    static let softTeal = Color(hex: "#E5F5F3")
}

private extension View {
    func growthSurface(background: Color) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}
