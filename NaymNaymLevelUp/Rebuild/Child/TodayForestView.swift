import SwiftUI

struct TodayForestView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: TodayForestViewModel
    let growthPolicy: GrowthPolicy
    let isTabActive: Bool
    let isAppActive: Bool
    @State private var isShowingRecorder = false

    var body: some View {
        NavigationStack {
            ForestSceneView(
                reduceMotion: reduceMotion,
                activity: ForestSceneActivity(
                    isSheetPresented: isShowingRecorder,
                    isTabActive: isTabActive,
                    isAppActive: isAppActive
                )
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                        heading
                        characterStage
                        mealSummary
                        primaryAction
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, RebuildDesignTokens.spacing[4])
                    .padding(.vertical, RebuildDesignTokens.spacing[3])
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $isShowingRecorder) {
            MealRecordingSheet(viewModel: viewModel)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[1]) {
            Text(viewModel.title)
                .font(.largeTitle.bold())
                .foregroundStyle(RebuildDesignTokens.ink900)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today_title")
            Text(viewModel.dateText)
                .font(RebuildDesignTokens.bodyFont)
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("날짜 \(viewModel.dateText)")
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RebuildDesignTokens.cream50)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
    }

    private var characterStage: some View {
        HStack(alignment: .center, spacing: RebuildDesignTokens.spacing[3]) {
            GeometryReader { proxy in
                MascotRigView(
                    level: min(currentLevel, 7),
                    state: viewModel.motion,
                    reduceMotion: reduceMotion,
                    playbackRevision: viewModel.motionRevision
                )
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .center
                )
                .clipped()
            }
            .frame(width: 132, height: 152)

            VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[1]) {
                Text("레벨 \(currentLevel) · \(growthPolicy.title(for: currentLevel))")
                    .font(RebuildDesignTokens.headlineFont)
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .fixedSize(horizontal: false, vertical: true)
                Text(characterMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                Text("총 \(viewModel.totalXP) XP")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
                ProgressView(value: growthPolicy.progress(totalXP: viewModel.totalXP))
                    .tint(RebuildDesignTokens.forest500)
                    .accessibilityLabel("다음 레벨까지 성장 진행도")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityIdentifier("today_character_hub")
    }

    private var mealSummary: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            VStack(
                alignment: .leading,
                spacing: RebuildDesignTokens.spacing[1]
            ) {
                Text("오늘의 점심")
                    .font(RebuildDesignTokens.titleFont.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.sourceLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let meal = viewModel.meal {
                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[1]) {
                    ForEach(Array(meal.menuItems.enumerated()), id: \.offset) {
                        _, item in
                        HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
                            Circle()
                                .fill(
                                    viewModel.isAllergyRisk(item)
                                        ? RebuildDesignTokens.danger700
                                        : RebuildDesignTokens.forest500
                                )
                                .frame(width: 7, height: 7)
                                .padding(.top, 7)
                                .accessibilityHidden(true)
                            Text(item.name)
                                .font(RebuildDesignTokens.bodyFont)
                                .foregroundStyle(RebuildDesignTokens.ink900)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(
                                    viewModel.isAllergyRisk(item)
                                        ? "\(item.name), 알레르기 주의 메뉴"
                                        : item.name
                                )
                        }
                    }
                }
                Text(meal.calorie)
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.muted600)
            } else if viewModel.isLoading {
                ProgressView("급식을 확인하고 있어요.")
                    .frame(minHeight: RebuildDesignTokens.minimumActionSize)
            } else {
                Text(viewModel.message ?? "오늘 급식 정보가 아직 없어요.")
                    .font(RebuildDesignTokens.bodyFont)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RebuildDesignTokens.cream50)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
            .stroke(RebuildDesignTokens.cream100, lineWidth: 1)
        }
        .accessibilityIdentifier("today_meal_summary")
    }

    private var primaryAction: some View {
        Button {
            isShowingRecorder = true
        } label: {
            Text(viewModel.primaryActionTitle)
                .font(RebuildDesignTokens.headlineFont)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: RebuildDesignTokens.minimumActionSize
                )
                .padding(.horizontal, RebuildDesignTokens.spacing[3])
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .background(
            viewModel.isPrimaryActionEnabled
                ? RebuildDesignTokens.forest700
                : RebuildDesignTokens.muted600
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
        )
        .disabled(!viewModel.isPrimaryActionEnabled)
        .accessibilityLabel(viewModel.primaryActionTitle)
        .accessibilityHint("메뉴별로 먹은 상태를 기록합니다")
        .accessibilityIdentifier("today_primary_action")
    }

    private var currentLevel: Int {
        growthPolicy.level(totalXP: viewModel.totalXP)
    }

    private var characterMessage: String {
        if let message = viewModel.message {
            return message
        }
        return "오늘 급식도 함께 만나 볼까요?"
    }
}
