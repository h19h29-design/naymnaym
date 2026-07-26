import SwiftUI

struct CollectionView: View {
    let provider: any GrowthSnapshotProviding
    let policy: GrowthPolicy
    let isActive: Bool

    @State private var totalXP: Int?
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let totalXP {
                    content(totalXP: totalXP)
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

    private func content(totalXP: Int) -> some View {
        let unlockedLevel = policy.level(totalXP: totalXP)

        return ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[3]
            ) {
                Text("지금까지 만난 모습과 앞으로 만날 친구들이에요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(1...7, id: \.self) { level in
                    collectionCard(
                        level: level,
                        isUnlocked: level <= unlockedLevel
                    )
                }

                Text("총 \(totalXP) XP")
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .padding(.bottom, RebuildDesignTokens.spacing[4])
            }
            .padding(.horizontal, RebuildDesignTokens.spacing[4])
            .padding(.top, RebuildDesignTokens.spacing[3])
        }
        .refreshable {
            await reload()
        }
    }

    private func collectionCard(
        level: Int,
        isUnlocked: Bool
    ) -> some View {
        let threshold = policy.thresholds[level - 1]

        return HStack(spacing: RebuildDesignTokens.spacing[3]) {
            MascotRestArtView(
                level: level,
                silhouetteColor: isUnlocked
                    ? nil
                    : GrowthLockedPalette.silhouetteColor
            )
            .frame(width: 112, height: 112)

            VStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[1]
            ) {
                Text("레벨 \(level)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)

                Text(
                    isUnlocked
                        ? policy.title(for: level)
                        : "아직 잠겨 있어요"
                )
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(RebuildDesignTokens.ink900)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    isUnlocked
                        ? "해금 완료"
                        : "잠금 · \(threshold) XP에 해금"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    isUnlocked
                        ? RebuildDesignTokens.forest700
                        : GrowthLockedPalette.textColor
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isUnlocked
                ? Color.white
                : GrowthLockedPalette.surfaceColor
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .accessibilityIdentifier(
            isUnlocked
                ? "collection_level_\(level)_unlocked"
                : "collection_level_\(level)_locked_warm_silhouette"
        )
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
            totalXP = try await provider.load(limit: 0).totalXP
        } catch {
            loadFailed = true
        }
    }
}
