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
    @State private var inspectedStageID: Int?
    @State private var loadFailed = false

    init(
        provider: any GrowthSnapshotProviding,
        policy: GrowthPolicy,
        isActive: Bool,
        defaults: UserDefaults = .standard,
        legacyDefaultsDomainName: String? = nil,
        stateStore: (any GrowthStageStateStore)? = nil,
        legacyRights: LegacyGrowthRights? = nil
    ) {
        self.provider = provider
        self.policy = policy
        self.isActive = isActive
        self.legacyRights = legacyRights
            ?? LegacyDefaultsReader.readGrowthRights(
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
            .background(CompanionPageBackdrop())
            .navigationBarHidden(true)
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
        let activeStageID = entitlement?.selectedStageID
            ?? highestUnlockedStageID
        let inspectionStageID = inspectedStageID ?? activeStageID
        let progressPresentation = GrowthEntitlementProgressPresentation.resolve(
            policy: policy,
            totalXP: snapshot.totalXP,
            highestUnlockedStageID: highestUnlockedStageID
        )
        let roadmap = GrowthStageRoadmapPresentation.items(
            policy: policy,
            selectedStageID: inspectionStageID,
            highestUnlockedStageID: highestUnlockedStageID
        )
        let inspectedDetail = GrowthStageRoadmapPresentation.detail(
            policy: policy,
            stageID: inspectionStageID,
            highestUnlockedStageID: highestUnlockedStageID,
            selectedStageID: inspectionStageID
        )

        return ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[3]
            ) {
                HStack {
                    Label("나의 성장", systemImage: "leaf.fill")
                        .font(.title2.weight(.heavy))
                    Spacer()
                    Text("한 입씩, 쑥쑥!").font(.caption.weight(.semibold))
                }
                .foregroundStyle(RebuildDesignTokens.forest700)
                .padding(.horizontal, 4)
                currentCharacter(level: activeStageID)
                progressCard(
                    snapshot: snapshot,
                    presentation: progressPresentation
                )
                nextUnlock(
                    level: progressPresentation.level,
                    nextThreshold: progressPresentation.nextThreshold
                )
                growthRoadmap(
                    items: roadmap,
                    detail: inspectedDetail
                )
                recentEvents(snapshot.recentEvents)
                Text("성장은 천천히, 매일의 한 입으로")
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, RebuildDesignTokens.spacing[4])
            }
            .padding(.horizontal, 16)
            .padding(.top, RebuildDesignTokens.spacing[3])
        }
        .refreshable {
            await reload()
        }
    }

    private func currentCharacter(level: Int) -> some View {
        let art = GrowthStageArtResolver.resolve(stageID: level)
        return VStack(spacing: 0) {
          ZStack(alignment: .topTrailing) {
            Image("CompanionForestStage").resizable().scaledToFill()
                .frame(height: 224).clipped().accessibilityHidden(true)
            if art.usesNeutralFallback {
                MascotNeutralFallbackView(stageID: art.stageID)
                .frame(width: 224, height: 224)
                .frame(maxWidth: .infinity)
            } else {
                MascotRigView(
                    level: art.artStageID,
                    state: .idle,
                    reduceMotion: reduceMotion,
                    isActive: isActive
                )
                .frame(width: 224, height: 224)
                .frame(maxWidth: .infinity)
            }
            Label("Lv.\(level)", systemImage: "sparkles")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(RebuildDesignTokens.forest700)
                .padding(10).background(.white.opacity(0.94), in: Capsule())
                .padding(12)
          }
          VStack(spacing: 5) {
            Text(policy.title(for: level))
                .font(RebuildDesignTokens.titleFont.bold())
                .foregroundStyle(RebuildDesignTokens.forest700)
                .fixedSize(horizontal: false, vertical: true)
            Text("너와 함께 조금씩 자라고 있어!")
                .font(.caption.weight(.medium))
                .foregroundStyle(RebuildDesignTokens.muted600)
          }
          .frame(maxWidth: .infinity).padding(12).background(.white)
        }
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
            .stroke(.white, lineWidth: 2)
        }
        .shadow(color: RebuildDesignTokens.forest700.opacity(0.08), radius: 8, y: 3)
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
                if art.usesNeutralFallback {
                    MascotNeutralFallbackView(stageID: art.stageID)
                        .frame(width: 92, height: 92)
                } else {
                    MascotRestArtView(
                        level: art.artStageID,
                        silhouetteColor: GrowthLockedPalette.silhouetteColor
                    )
                    .frame(width: 92, height: 92)
                }

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

    private func growthRoadmap(
        items: [GrowthStageRoadmapItem],
        detail: GrowthStageDetailPresentation
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RebuildDesignTokens.spacing[2]
        ) {
            Text("성장 단계")
                .font(RebuildDesignTokens.titleFont.bold())
                .foregroundStyle(RebuildDesignTokens.ink900)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: RebuildDesignTokens.spacing[2]) {
                    ForEach(items) { item in
                        GrowthRoadmapCard(item: item) {
                            inspectedStageID = item.stageID
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            growthStageDetail(detail)
        }
        .accessibilityIdentifier("growth_stage_roadmap")
    }

    private func growthStageDetail(
        _ detail: GrowthStageDetailPresentation
    ) -> some View {
        GrowthStageDetailView(detail: detail)
    }
}

private struct GrowthStageDetailArtState: Equatable {
    let stageID: Int
    let state: MascotArtAccessibilityState
}

struct GrowthStageDetailView: View {
    let detail: GrowthStageDetailPresentation
    private let restArtLoader: MascotRestArtLoader?
    private let onAccessibilityLabelChange: ((String) -> Void)?

    @State private var artState: GrowthStageDetailArtState

    init(
        detail: GrowthStageDetailPresentation,
        restArtLoader: MascotRestArtLoader? = nil,
        onAccessibilityLabelChange: ((String) -> Void)? = nil
    ) {
        self.detail = detail
        self.restArtLoader = restArtLoader
        self.onAccessibilityLabelChange = onAccessibilityLabelChange
        let initialArtState = Self.initialArtState(for: detail.stageID)
        _artState = State(
            initialValue: GrowthStageDetailArtState(
                stageID: detail.stageID,
                state: initialArtState
            )
        )
    }

    var body: some View {
        let art = GrowthStageArtResolver.resolve(stageID: detail.stageID)
        let effectiveArtState = artState.stageID == detail.stageID
            ? artState.state
            : Self.initialArtState(for: detail.stageID)
        let accessibility = GrowthStageDetailAccessibilitySemantics.make(
            detail: detail,
            artState: effectiveArtState
        )

        return HStack(
            alignment: .top,
            spacing: RebuildDesignTokens.spacing[3]
        ) {
            if art.usesNeutralFallback {
                MascotNeutralFallbackView(stageID: art.stageID)
                    .frame(width: 96, height: 96)
            } else {
                let stageID = art.stageID
                MascotRestArtView(
                    level: art.artStageID,
                    silhouetteColor: detail.isUnlocked
                        ? nil
                        : GrowthLockedPalette.silhouetteColor,
                    loader: restArtLoader,
                    onAccessibilityStateChange: { state in
                        artState = GrowthStageDetailArtState(
                            stageID: stageID,
                            state: state
                        )
                    }
                )
                .frame(width: 96, height: 96)
            }

            VStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[1]
            ) {
                Text(accessibility.selectionLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
                Text(accessibility.stageLabel)
                    .font(RebuildDesignTokens.headlineFont)
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .accessibilityHidden(true)
                Text(accessibility.titleLabel)
                    .font(RebuildDesignTokens.bodyFont.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .fixedSize(horizontal: false, vertical: true)
                Text(accessibility.thresholdStateLabel)
                    .font(.footnote)
                    .foregroundStyle(
                        detail.isUnlocked
                            ? RebuildDesignTokens.forest700
                            : GrowthLockedPalette.textColor
                    )
                Text(accessibility.storyLabel)
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                Text(accessibility.rewardLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .fixedSize(horizontal: false, vertical: true)
                if accessibility.childArtIsPending {
                    Text(MascotArtAccessibility.pendingArtText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(RebuildDesignTokens.muted600)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(
            cornerRadius: RebuildDesignTokens.radii[1],
            style: .continuous
        ))
        .modifier(
            GrowthStageDetailAccessibilityModifier(
                semantics: accessibility,
                onLabelChange: onAccessibilityLabelChange
            )
        )
        .onChange(of: detail.stageID) { _ in
            artState = GrowthStageDetailArtState(
                stageID: detail.stageID,
                state: Self.initialArtState(for: detail.stageID)
            )
        }
    }

    private static func initialArtState(
        for stageID: Int
    ) -> MascotArtAccessibilityState {
        GrowthStageArtResolver.resolve(stageID: stageID).usesNeutralFallback
            ? .pending
            : .loading
    }
}

/// Applies the selected-stage contract to the actual SwiftUI detail element.
///
/// The optional callback is an internal observation seam for the runtime
/// regression test. It is invoked by this modifier, alongside the real
/// accessibility modifiers, so the test cannot pass by exercising only the
/// pure semantic helper.
struct GrowthStageDetailAccessibilityModifier: ViewModifier {
    let semantics: GrowthStageDetailAccessibilitySemantics
    let onLabelChange: ((String) -> Void)?

    func body(content: Content) -> some View {
        let label = semantics.parentLabel ?? semantics.spokenLabel
        return content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier(semantics.identifier)
            .onAppear {
                onLabelChange?(label)
            }
            .onChange(of: label) { updatedLabel in
                onLabelChange?(updatedLabel)
            }
    }
}

extension GrowthView {
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
            if inspectedStageID == nil {
                inspectedStageID = resolved.selectedStageID
            }
            snapshot = loadedSnapshot
        } catch {
            loadFailed = true
        }
    }
}

private struct GrowthRoadmapCard: View {
    let item: GrowthStageRoadmapItem
    let action: () -> Void

    private var stageText: String {
        "레벨 \(item.stageID)"
    }

    private var stateText: String {
        item.isUnlocked ? "해금" : "\(item.threshold) XP"
    }

    private var stateIconName: String {
        item.isUnlocked ? "checkmark.circle.fill" : "lock.fill"
    }

    private var foregroundColor: Color {
        item.isSelected
            ? RebuildDesignTokens.forest700
            : RebuildDesignTokens.ink900
    }

    private var backgroundColor: Color {
        item.isUnlocked ? Color.white : GrowthLockedPalette.surfaceColor
    }

    private var borderColor: Color {
        item.isSelected
            ? RebuildDesignTokens.forest500
            : RebuildDesignTokens.cream100
    }

    private var borderWidth: CGFloat {
        item.isSelected ? 2 : 1
    }

    var body: some View {
        Button(action: action) {
            cardLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier(item.accessibilityIdentifier)
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var cardLabel: some View {
        VStack(
            alignment: .leading,
            spacing: RebuildDesignTokens.spacing[1]
        ) {
            Text(stageText)
                .font(.footnote.weight(.bold))
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: RebuildDesignTokens.spacing[1]) {
                Image(systemName: stateIconName)
                    .accessibilityHidden(true)
                Text(stateText)
            }
            .font(.caption2.weight(.semibold))
            if item.usesNeutralFallback {
                Text(MascotArtAccessibility.pendingArtText)
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(RebuildDesignTokens.spacing[2])
        .frame(width: 132, alignment: .topLeading)
        .frame(minHeight: 112, alignment: .topLeading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(
            cornerRadius: RebuildDesignTokens.radii[1],
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
            .stroke(borderColor, lineWidth: borderWidth)
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
    private let onAccessibilityStateChange:
        (MascotArtAccessibilityState) -> Void
    @StateObject private var loader: MascotRestArtLoader

    init(
        level: Int,
        silhouetteColor: Color?,
        loader: MascotRestArtLoader? = nil,
        onAccessibilityStateChange: @escaping (
            MascotArtAccessibilityState
        ) -> Void = { _ in }
    ) {
        self.level = level
        self.silhouetteColor = silhouetteColor
        self.onAccessibilityStateChange = onAccessibilityStateChange
        _loader = StateObject(
            wrappedValue: loader ?? MascotRestArtLoader()
        )
    }

    var body: some View {
        Group {
            if usesNeutralFallback {
                MascotNeutralFallbackView(stageID: level)
            } else if let image = loader.renderedImage(for: level) {
                loadedArt(image)
            } else if loader.canRetry(for: level) {
                MascotNeutralFallbackView(stageID: level)
            } else {
                ProgressView()
                    .accessibilityLabel(
                        "레벨 \(level) 캐릭터를 불러오는 중"
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MascotRestArtAccessibility.label(
                stageID: level,
                state: accessibilityState
            )
        )
        .onAppear {
            onAccessibilityStateChange(accessibilityState)
        }
        .onChange(of: accessibilityState) { state in
            onAccessibilityStateChange(state)
        }
        .task(id: level) {
            guard !usesNeutralFallback else { return }
            await loader.load(level: level)
        }
    }

    private var usesNeutralFallback: Bool {
        GrowthStageArtResolver.resolve(stageID: level).usesNeutralFallback
    }

    private var accessibilityState: MascotArtAccessibilityState {
        MascotRestArtAccessibility.state(
            usesNeutralFallback: usesNeutralFallback,
            hasRenderedImage: loader.renderedImage(for: level) != nil,
            canRetry: loader.canRetry(for: level),
            isLocked: silhouetteColor != nil
        )
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
