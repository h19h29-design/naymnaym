import SwiftUI

struct GrowthView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let provider: any GrowthSnapshotProviding
    let policy: GrowthPolicy
    let isActive: Bool
    private let legacyRights: LegacyGrowthRights
    private let stateStore: any GrowthStageStateStore

    @State private var snapshot: GrowthSnapshot?
    @State private var entitlement: GrowthEntitlement?
    @State private var loadFailed = false

    init(
        provider: any GrowthSnapshotProviding,
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
                if let snapshot {
                    content(snapshot)
                } else {
                    loadingState
                }
            }
            .background(RebuildDesignTokens.cream50)
            .navigationTitle("나의 성장")
        }
        .task(id: isActive) {
            guard isActive else { return }
            await reload()
        }
        .accessibilityIdentifier("growth_screen")
    }

    private func content(_ snapshot: GrowthSnapshot) -> some View {
        let fallbackLevel = policy.level(totalXP: snapshot.totalXP)
        let highestUnlockedStageID = entitlement?.highestUnlockedStageID
            ?? fallbackLevel
        let selectedStageID = entitlement?.selectedStageID
            ?? highestUnlockedStageID
        let progressPresentation = GrowthEntitlementProgressPresentation.resolve(
            policy: policy,
            totalXP: snapshot.totalXP,
            highestUnlockedStageID: highestUnlockedStageID
        )

        return ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[3]
            ) {
                currentCharacter(level: selectedStageID)
                progressCard(
                    snapshot: snapshot,
                    presentation: progressPresentation
                )
                nextUnlock(
                    level: progressPresentation.level,
                    nextThreshold: progressPresentation.nextThreshold
                )
                recentEvents(snapshot.recentEvents)
                Text("성장은 천천히, 매일의 한 입으로")
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, RebuildDesignTokens.spacing[4])
            }
            .padding(.horizontal, RebuildDesignTokens.spacing[4])
            .padding(.top, RebuildDesignTokens.spacing[3])
        }
        .refreshable {
            await reload()
        }
    }

    private func currentCharacter(level: Int) -> some View {
        let art = GrowthStageArtResolver.resolve(stageID: level)
        return VStack(spacing: RebuildDesignTokens.spacing[2]) {
            if art.usesNeutralFallback {
                MascotRestArtView(
                    level: art.artStageID,
                    silhouetteColor: GrowthLockedPalette.silhouetteColor
                )
                .frame(width: 188, height: 188)
                .accessibilityHidden(true)
            } else {
                MascotRigView(
                    level: art.artStageID,
                    state: .idle,
                    reduceMotion: reduceMotion
                )
                .frame(width: 188, height: 188)
                .accessibilityHidden(true)
            }

            Text(policy.title(for: level))
                .font(RebuildDesignTokens.titleFont.bold())
                .foregroundStyle(RebuildDesignTokens.forest700)
                .fixedSize(horizontal: false, vertical: true)
            if art.usesNeutralFallback {
                Text("중립 미리보기")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity)
        .background(RebuildDesignTokens.cream50)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[2],
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[2],
                style: .continuous
            )
            .stroke(RebuildDesignTokens.cream100, lineWidth: 1)
        }
        .accessibilityIdentifier("growth_current_character")
    }

    private func progressCard(
        snapshot: GrowthSnapshot,
        presentation: GrowthEntitlementProgressPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            HStack {
                Text("레벨 \(presentation.level)")
                    .font(RebuildDesignTokens.headlineFont)
                    .foregroundStyle(RebuildDesignTokens.ink900)
                Spacer()
                Text("\(snapshot.totalXP) XP")
                    .font(RebuildDesignTokens.bodyFont.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
            }

            ProgressView(value: presentation.progress)
                .tint(RebuildDesignTokens.forest500)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            Text(
                presentation.nextThreshold.map { _ in
                    "다음 성장까지 \(presentation.remainingXP ?? 0) XP"
                } ?? "모든 성장 단계를 열었어요!"
            )
            .font(.footnote)
            .foregroundStyle(RebuildDesignTokens.muted600)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("growth_progress")
    }

    @ViewBuilder
    private func nextUnlock(
        level: Int,
        nextThreshold: Int?
    ) -> some View {
        if let nextThreshold {
            let nextLevel = level + 1
            let art = GrowthStageArtResolver.resolve(stageID: nextLevel)
            HStack(spacing: RebuildDesignTokens.spacing[3]) {
                MascotRestArtView(
                    level: art.artStageID,
                    silhouetteColor: GrowthLockedPalette.silhouetteColor
                )
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: RebuildDesignTokens.spacing[1]
                ) {
                    Text("다음 해금")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(RebuildDesignTokens.muted600)
                    Text(policy.title(for: nextLevel))
                        .font(RebuildDesignTokens.headlineFont)
                        .foregroundStyle(RebuildDesignTokens.ink900)
                    Text("\(nextThreshold) XP에 만나요")
                        .font(.footnote)
                        .foregroundStyle(GrowthLockedPalette.textColor)
                    if art.usesNeutralFallback {
                        Text("중립 미리보기")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RebuildDesignTokens.muted600)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(RebuildDesignTokens.spacing[3])
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GrowthLockedPalette.surfaceColor)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[1],
                    style: .continuous
                )
            )
            .accessibilityIdentifier("growth_next_unlock")
        } else {
            Text("최고 레벨 달성")
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(RebuildDesignTokens.forest700)
                .padding(RebuildDesignTokens.spacing[3])
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RebuildDesignTokens.cream100)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: RebuildDesignTokens.radii[1],
                        style: .continuous
                    )
                )
                .accessibilityIdentifier("growth_next_unlock")
        }
    }

    private func recentEvents(
        _ events: [RebuildProgressEvent]
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RebuildDesignTokens.spacing[2]
        ) {
            Text("최근 성장 기록")
                .font(RebuildDesignTokens.titleFont.bold())
                .foregroundStyle(RebuildDesignTokens.ink900)
                .accessibilityAddTraits(.isHeader)

            if events.isEmpty {
                Text("급식을 기록하면 성장 이야기가 여기에 쌓여요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(events, id: \.id) { event in
                    let presentation = GrowthEventPresentation(event: event)
                    HStack(
                        alignment: .center,
                        spacing: RebuildDesignTokens.spacing[2]
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: RebuildDesignTokens.spacing[0]
                        ) {
                            Text(presentation.title)
                                .font(RebuildDesignTokens.bodyFont.weight(.semibold))
                                .foregroundStyle(RebuildDesignTokens.ink900)
                            Text(presentation.dateText)
                                .font(.footnote)
                                .foregroundStyle(RebuildDesignTokens.muted600)
                        }
                        Spacer(minLength: RebuildDesignTokens.spacing[2])
                        Text(presentation.xpText)
                            .font(RebuildDesignTokens.bodyFont.bold())
                            .foregroundStyle(RebuildDesignTokens.forest700)
                    }
                    .padding(RebuildDesignTokens.spacing[3])
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: RebuildDesignTokens.radii[1],
                            style: .continuous
                        )
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("growth_recent_events")
    }

    private var loadingState: some View {
        VStack(spacing: RebuildDesignTokens.spacing[2]) {
            if loadFailed {
                Text("성장 기록을 불러오지 못했어요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            } else {
                ProgressView()
                Text("성장 기록을 불러오고 있어요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func reload() async {
        loadFailed = false
        do {
            let loadedSnapshot = try await provider.load(limit: 20)
            let resolved = GrowthEntitlementResolver.resolve(
                policy: policy,
                totalXP: loadedSnapshot.totalXP,
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
            entitlement = resolved
            snapshot = loadedSnapshot
        } catch {
            loadFailed = true
        }
    }
}

enum GrowthLockedPalette {
    static let silhouetteHex = "#B87548"
    static let textHex = "#1F5E43"
    static let surfaceHex = "#FFF0DF"

    static let silhouetteColor = Color(
        .sRGB,
        red: 184.0 / 255.0,
        green: 117.0 / 255.0,
        blue: 72.0 / 255.0,
        opacity: 1
    )
    static let textColor = RebuildDesignTokens.forest700
    static let surfaceColor = Color(
        .sRGB,
        red: 1,
        green: 240.0 / 255.0,
        blue: 223.0 / 255.0,
        opacity: 1
    )
}

struct MascotRestArtView: View {
    let level: Int
    let silhouetteColor: Color?
    @StateObject private var loader: MascotRestArtLoader

    init(
        level: Int,
        silhouetteColor: Color?
    ) {
        self.level = level
        self.silhouetteColor = silhouetteColor
        _loader = StateObject(
            wrappedValue: MascotRestArtLoader()
        )
    }

    var body: some View {
        Group {
            if let image = loader.renderedImage(for: level) {
                loadedArt(image)
            } else if loader.canRetry(for: level) {
                Button {
                    Task {
                        await loader.load(level: level)
                    }
                } label: {
                    VStack(spacing: RebuildDesignTokens.spacing[1]) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                        Text("다시 시도")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel(
                    "레벨 \(level) 캐릭터를 불러오지 못했습니다. 다시 시도"
                )
                .accessibilityIdentifier("mascot_rest_retry_level_\(level)")
            } else {
                ProgressView()
                    .accessibilityLabel(
                        "레벨 \(level) 캐릭터를 불러오는 중"
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: level) {
            await loader.load(level: level)
        }
    }

    @ViewBuilder
    private func loadedArt(_ image: UIImage) -> some View {
        if let silhouetteColor {
            silhouetteColor
                .mask(verifiedImage(image))
                .accessibilityLabel("레벨 \(level) 잠긴 캐릭터 실루엣")
        } else {
            verifiedImage(image)
                .accessibilityLabel("레벨 \(level) 해금 캐릭터")
        }
    }

    private func verifiedImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
