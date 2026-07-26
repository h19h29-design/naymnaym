import SwiftUI

struct GrowthView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let provider: any GrowthSnapshotProviding
    let policy: GrowthPolicy
    let isActive: Bool

    @State private var snapshot: GrowthSnapshot?
    @State private var loadFailed = false

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
        let level = policy.level(totalXP: snapshot.totalXP)
        let nextThreshold = policy.nextThreshold(totalXP: snapshot.totalXP)

        return ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[3]
            ) {
                currentCharacter(level: level)
                progressCard(
                    snapshot: snapshot,
                    level: level,
                    nextThreshold: nextThreshold
                )
                nextUnlock(
                    level: level,
                    nextThreshold: nextThreshold
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
        VStack(spacing: RebuildDesignTokens.spacing[2]) {
            MascotRigView(
                level: level,
                state: .idle,
                reduceMotion: reduceMotion
            )
            .frame(width: 188, height: 188)

            Text(policy.title(for: level))
                .font(RebuildDesignTokens.titleFont.bold())
                .foregroundStyle(RebuildDesignTokens.forest700)
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "현재 캐릭터, 레벨 \(level), \(policy.title(for: level))"
        )
        .accessibilityIdentifier("growth_current_character")
    }

    private func progressCard(
        snapshot: GrowthSnapshot,
        level: Int,
        nextThreshold: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            HStack {
                Text("레벨 \(level)")
                    .font(RebuildDesignTokens.headlineFont)
                    .foregroundStyle(RebuildDesignTokens.ink900)
                Spacer()
                Text("\(snapshot.totalXP) XP")
                    .font(RebuildDesignTokens.bodyFont.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
            }

            ProgressView(value: policy.progress(totalXP: snapshot.totalXP))
                .tint(RebuildDesignTokens.forest500)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)

            Text(
                nextThreshold.map {
                    "다음 성장까지 \(max($0 - snapshot.totalXP, 0)) XP"
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
            HStack(spacing: RebuildDesignTokens.spacing[3]) {
                MascotRestArtView(
                    level: nextLevel,
                    silhouetteColor: warmLockedMascotColor
                )
                .frame(width: 92, height: 92)

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
                        .foregroundStyle(warmLockedMascotColor)
                }
                Spacer(minLength: 0)
            }
            .padding(RebuildDesignTokens.spacing[3])
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RebuildDesignTokens.cream100)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: RebuildDesignTokens.radii[1],
                    style: .continuous
                )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "다음 해금, 레벨 \(nextLevel), \(policy.title(for: nextLevel)), \(nextThreshold) XP"
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
            snapshot = try await provider.load(limit: 20)
        } catch {
            loadFailed = true
        }
    }
}

let warmLockedMascotColor = Color(
    .sRGB,
    red: 184.0 / 255.0,
    green: 117.0 / 255.0,
    blue: 72.0 / 255.0,
    opacity: 1
)

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
            wrappedValue: MascotRestArtLoader(level: level)
        )
    }

    var body: some View {
        Group {
            if let image = loader.image {
                loadedArt(image)
            } else if loader.loadError != nil {
                Button {
                    loader.load()
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
            } else {
                ProgressView()
                    .accessibilityLabel(
                        "레벨 \(level) 캐릭터를 불러오는 중"
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: level) {
            loader.load()
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
