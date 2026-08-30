import SwiftUI

private enum CollectionSection: String, CaseIterable, Identifiable {
    case characters
    case nutrition
    case challenge
    case streak
    case legacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .characters: return "캐릭터"
        case .nutrition: return "영양 탐험 12"
        case .challenge: return "식사 도전 12"
        case .streak: return "꾸준함 12"
        case .legacy: return "이전 뱃지"
        }
    }

    var badgeCategory: CollectionBadgeCategory? {
        switch self {
        case .characters: return nil
        case .nutrition: return .nutrition
        case .challenge: return .challenge
        case .streak: return .streak
        case .legacy: return nil
        }
    }
}

struct CollectionView: View {
    let provider: any CollectionSnapshotProviding
    let policy: GrowthPolicy
    let isActive: Bool
    private let legacyRights: LegacyGrowthRights
    private let stateStore: any GrowthStageStateStore

    @State private var progress: CollectionProgress?
    @State private var entitlement: GrowthEntitlement?
    @State private var loadFailed = false
    @State private var selectedSection: CollectionSection = .characters

    init(
        provider: any CollectionSnapshotProviding,
        policy: GrowthPolicy,
        isActive: Bool,
        defaults: UserDefaults = .standard,
        legacyDefaultsDomainName: String? = nil,
        stateStore: (any GrowthStageStateStore)? = nil
    ) {
        self.provider = provider
        self.policy = policy
        self.isActive = isActive
        legacyRights = LegacyDefaultsReader.readGrowthRights(
            defaults: defaults,
            persistentDomainName: legacyDefaultsDomainName
        )
        self.stateStore = stateStore
            ?? UserDefaultsGrowthStageStateStore(defaults: defaults)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let progress {
                    content(progress: progress)
                } else {
                    loadingState
                }
            }
            .background(RebuildDesignTokens.cream50)
            .navigationTitle("성장 도감")
        }
        .task(id: isActive) {
            guard isActive else { return }
            await reload()
        }
        .accessibilityIdentifier("collection_screen")
    }

    private func content(progress: CollectionProgress) -> some View {
        let unlockedLevel = entitlement?.highestUnlockedStageID
            ?? policy.level(totalXP: progress.totalXP)
        let unlockedCharacters = min(unlockedLevel, policy.thresholds.count)
        let totalCollected = unlockedCharacters + progress.collectedCount

        return ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[3]
            ) {
                collectionHeader(
                    totalCollected: totalCollected,
                    progress: progress,
                    unlockedLevel: unlockedLevel
                )
                sectionSelector(progress: progress)
                if selectedSection == .characters {
                    characterGrid(unlockedLevel: unlockedLevel)
                } else if let category = selectedSection.badgeCategory {
                    badgeGrid(progress: progress, category: category)
                } else {
                    legacyBadgeGrid(progress: progress)
                }
            }
            .padding(.horizontal, RebuildDesignTokens.spacing[4])
            .padding(.vertical, RebuildDesignTokens.spacing[3])
        }
        .refreshable {
            await reload()
        }
    }

    private func collectionHeader(
        totalCollected: Int,
        progress: CollectionProgress,
        unlockedLevel: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            Text("성장 도감")
                .font(.largeTitle.bold())
                .foregroundStyle(RebuildDesignTokens.ink900)
                .accessibilityAddTraits(.isHeader)
            Text("먹어 본 한 입이 캐릭터와 배지를 채워요.")
                .font(RebuildDesignTokens.bodyFont)
                .foregroundStyle(RebuildDesignTokens.muted600)
            HStack(alignment: .center, spacing: RebuildDesignTokens.spacing[2]) {
                Image(systemName: "sparkles")
                    .foregroundStyle(RebuildDesignTokens.forest500)
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[0]) {
                    Text("전체 수집 \(totalCollected) / \(policy.thresholds.count + progress.badges.count)")
                        .font(RebuildDesignTokens.headlineFont)
                        .foregroundStyle(RebuildDesignTokens.ink900)
                    Text("레벨 \(unlockedLevel) · 배지 \(progress.collectedCount) / \(progress.badges.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(RebuildDesignTokens.muted600)
                    if !progress.legacyBadgeIDsForDisplay.isEmpty {
                        Text("\(progress.legacyBadgeGroupTitle) \(progress.legacyBadgeIDsForDisplay.count)개 보관")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RebuildDesignTokens.muted600)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(RebuildDesignTokens.spacing[2])
            .background(RebuildDesignTokens.cream100)
            .clipShape(RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            ))
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(
            cornerRadius: RebuildDesignTokens.radii[2],
            style: .continuous
        ))
    }

    private func sectionSelector(progress: CollectionProgress) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RebuildDesignTokens.spacing[2]) {
                ForEach(CollectionSection.allCases) { section in
                    let isSelected = selectedSection == section
                    Button {
                        selectedSection = section
                    } label: {
                        Text(section == .characters ? "캐릭터 \(policy.thresholds.count)" : section.title)
                            .font(.footnote.weight(.bold))
                            .lineLimit(1)
                            .padding(.horizontal, RebuildDesignTokens.spacing[3])
                            .frame(minHeight: RebuildDesignTokens.minimumActionSize)
                    }
                    .foregroundStyle(
                        isSelected ? Color.white : RebuildDesignTokens.forest700
                    )
                    .background(
                        isSelected ? RebuildDesignTokens.forest700 : RebuildDesignTokens.cream100
                    )
                    .clipShape(Capsule())
                    .accessibilityIdentifier("collection_section_\(section.rawValue)")
                    .accessibilityLabel(
                        section == .characters
                            ? "캐릭터 \(policy.thresholds.count)개"
                            : section == .legacy
                            ? "\(section.title), \(progress.legacyBadgeIDsForDisplay.count)개 보관"
                            : "\(section.title), \(section.badgeCategory.map { progress.earnedCount(for: $0) } ?? 0)개 획득"
                    )
                }
            }
        }
    }

    private func characterGrid(unlockedLevel: Int) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: RebuildDesignTokens.spacing[3]),
            GridItem(.flexible(), spacing: RebuildDesignTokens.spacing[3]),
        ]
        return LazyVGrid(columns: columns, spacing: RebuildDesignTokens.spacing[3]) {
            ForEach(Array(policy.thresholds.enumerated()), id: \.offset) { index, threshold in
                let level = index + 1
                characterTile(
                    level: level,
                    threshold: threshold,
                    isUnlocked: level <= unlockedLevel
                )
            }
        }
    }

    private func characterTile(
        level: Int,
        threshold: Int,
        isUnlocked: Bool
    ) -> some View {
        let art = GrowthStageArtResolver.resolve(stageID: level)
        return VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[1],
                    style: .continuous
                )
                .fill(isUnlocked ? RebuildDesignTokens.cream100 : GrowthLockedPalette.surfaceColor)
                MascotRestArtView(
                    level: art.artStageID,
                    silhouetteColor: isUnlocked && !art.usesNeutralFallback
                        ? nil
                        : GrowthLockedPalette.silhouetteColor
                )
                .padding(RebuildDesignTokens.spacing[2])
                .accessibilityHidden(true)
                if level >= 8 {
                    Image(systemName: stageSymbol(for: level))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isUnlocked ? Color.white : GrowthLockedPalette.textColor)
                        .padding(7)
                        .background(isUnlocked ? RebuildDesignTokens.forest700 : GrowthLockedPalette.surfaceColor)
                        .clipShape(Circle())
                        .padding(RebuildDesignTokens.spacing[1])
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 122)
            Text("레벨 \(level)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(RebuildDesignTokens.muted600)
            if art.usesNeutralFallback {
                Text("중립 미리보기")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }
            Text(isUnlocked ? policy.title(for: level) : "아직 잠겨 있어요")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RebuildDesignTokens.ink900)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(isUnlocked ? "해금 완료" : "\(threshold) XP에 해금")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isUnlocked ? RebuildDesignTokens.forest700 : GrowthLockedPalette.textColor)
        }
        .padding(RebuildDesignTokens.spacing[2])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUnlocked ? Color.white : GrowthLockedPalette.surfaceColor)
        .clipShape(RoundedRectangle(
            cornerRadius: RebuildDesignTokens.radii[1],
            style: .continuous
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isUnlocked
                ? "레벨 \(level) 해금, \(policy.title(for: level))\(art.usesNeutralFallback ? ", 중립 미리보기" : "")"
                : "레벨 \(level) 잠김, \(threshold) XP에 해금\(art.usesNeutralFallback ? ", 중립 미리보기" : "")"
        )
        .accessibilityIdentifier(
            isUnlocked
                ? "collection_level_\(level)_unlocked"
                : "collection_level_\(level)_locked_warm_silhouette"
        )
    }

    private func badgeGrid(
        progress: CollectionProgress,
        category: CollectionBadgeCategory
    ) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: RebuildDesignTokens.spacing[3]),
            GridItem(.flexible(), spacing: RebuildDesignTokens.spacing[3]),
            GridItem(.flexible(), spacing: RebuildDesignTokens.spacing[3]),
        ]
        return LazyVGrid(columns: columns, spacing: RebuildDesignTokens.spacing[3]) {
            ForEach(progress.badges(for: category), id: \.id) { badge in
                badgeTile(badge, isEarned: progress.earnedBadgeIDs.contains(badge.id))
            }
        }
    }

    private func badgeTile(_ badge: CollectionBadge, isEarned: Bool) -> some View {
        VStack(spacing: RebuildDesignTokens.spacing[1]) {
            Image(systemName: badgeSymbol(for: badge))
                .font(.title2)
                .foregroundStyle(isEarned ? RebuildDesignTokens.forest700 : GrowthLockedPalette.textColor)
                .frame(width: 48, height: 48)
                .background(isEarned ? RebuildDesignTokens.cream100 : GrowthLockedPalette.surfaceColor)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(isEarned ? badge.title : "잠긴 배지")
                .font(.caption.weight(.bold))
                .foregroundStyle(RebuildDesignTokens.ink900)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .padding(RebuildDesignTokens.spacing[2])
        .background(isEarned ? Color.white : GrowthLockedPalette.surfaceColor)
        .clipShape(RoundedRectangle(
            cornerRadius: RebuildDesignTokens.radii[1],
            style: .continuous
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isEarned ? "배지 획득, \(badge.title)" : "잠긴 배지, \(badge.threshold)회 기록하면 해금")
        .accessibilityIdentifier("collection_badge_\(badge.id)_\(isEarned ? "earned" : "locked")")
    }

    private func legacyBadgeGrid(progress: CollectionProgress) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: RebuildDesignTokens.spacing[3]),
            GridItem(.flexible(), spacing: RebuildDesignTokens.spacing[3]),
        ]
        return LazyVGrid(columns: columns, spacing: RebuildDesignTokens.spacing[3]) {
            ForEach(progress.legacyBadgeIDsForDisplay, id: \.self) { badgeID in
                VStack(spacing: RebuildDesignTokens.spacing[1]) {
                    Image(systemName: "seal.fill")
                        .font(.title2)
                        .foregroundStyle(RebuildDesignTokens.forest700)
                        .frame(width: 48, height: 48)
                        .background(RebuildDesignTokens.cream100)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    Text(badgeID)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RebuildDesignTokens.ink900)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 116)
                .padding(RebuildDesignTokens.spacing[2])
                .background(Color.white)
                .clipShape(RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[1],
                    style: .continuous
                ))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(progress.legacyBadgeGroupTitle), \(badgeID)")
                .accessibilityIdentifier("collection_legacy_badge_\(badgeID)")
            }
        }
    }

    private func stageSymbol(for level: Int) -> String {
        switch level {
        case 8...9: return "leaf.fill"
        case 10...11: return "medal.fill"
        case 12: return "crown.fill"
        default: return "sparkles"
        }
    }

    private func badgeSymbol(for badge: CollectionBadge) -> String {
        switch badge.category {
        case .nutrition: return "leaf.circle.fill"
        case .challenge: return "fork.knife.circle.fill"
        case .streak: return "flame.circle.fill"
        }
    }

    private var loadingState: some View {
        VStack(spacing: RebuildDesignTokens.spacing[2]) {
            if loadFailed {
                Text("도감을 불러오지 못했어요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func reload() async {
        loadFailed = false
        do {
            let snapshot = try await provider.loadCollection()
            let resolved = GrowthEntitlementResolver.resolve(
                policy: policy,
                totalXP: snapshot.totalXP,
                legacy: legacyRights,
                stored: stateStore.read()
            )
            stateStore.writeMonotonic(
                GrowthStageStateV2(
                    version: GrowthStageStateV2.currentVersion,
                    highestUnlockedStageID: resolved.highestUnlockedStageID,
                    selectedStageID: resolved.selectedStageID
                )
            )
            let policyData = try loadRebuildContractData(named: "collection-policy.json")
            progress = try CollectionProgress.evaluate(
                totalXP: snapshot.totalXP,
                records: snapshot.records,
                policyData: policyData,
                legacy: legacyRights
            )
            entitlement = resolved
        } catch {
            loadFailed = true
        }
    }
}
