import SwiftUI

struct TodayForestView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: TodayForestViewModel
    @State private var isShowingRecorder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[4]) {
                    heading
                    characterStage
                    mealSummary
                    primaryAction
                    progressSummary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RebuildDesignTokens.spacing[4])
                .padding(.vertical, RebuildDesignTokens.spacing[3])
            }
            .background(
                LinearGradient(
                    colors: [
                        RebuildDesignTokens.cream50,
                        RebuildDesignTokens.leaf300.opacity(0.24),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
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
    }

    private var characterStage: some View {
        VStack(spacing: RebuildDesignTokens.spacing[2]) {
            GeometryReader { proxy in
                Group {
                    if reduceMotion {
                        GrowthCharacterView(
                            level: appState.progress.level,
                            size: 188,
                            pose: .idle,
                            blendsCreamBackground: true
                        )
                    } else {
                        LottieMascotView(state: mascotState) {
                            GrowthCharacterView(
                                level: appState.progress.level,
                                size: 188,
                                pose: characterPose,
                                blendsCreamBackground: true
                            )
                        }
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .center
                )
                .clipped()
            }
            .frame(height: 196)

            Text(characterMessage)
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(RebuildDesignTokens.forest700)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity)
        .background(RebuildDesignTokens.cream50.opacity(0.84))
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[2],
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("현재 캐릭터, \(characterMessage)")
    }

    private var mealSummary: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            HStack(alignment: .firstTextBaseline) {
                Text("오늘의 점심")
                    .font(RebuildDesignTokens.titleFont.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: RebuildDesignTokens.spacing[2])
                Text(viewModel.sourceLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .multilineTextAlignment(.trailing)
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
        .background(.white)
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
                : RebuildDesignTokens.muted600.opacity(0.45)
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

    private var progressSummary: some View {
        HStack(alignment: .center, spacing: RebuildDesignTokens.spacing[3]) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(RebuildDesignTokens.forest500)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[0]) {
                Text("현재 성장")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
                Text("레벨 \(appState.progress.level) · 총 \(viewModel.totalXP) XP")
                    .font(RebuildDesignTokens.headlineFont)
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RebuildDesignTokens.leaf300.opacity(0.28))
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }

    private var mascotState: MascotAnimationState {
        switch viewModel.motion {
        case .mealSuccess: return .success
        case .levelUp: return .levelup
        case .comfort: return .wave
        case .idle, .tapReaction, .reducedMotion: return .idle
        }
    }

    private var characterPose: GrowthCharacterPose {
        switch viewModel.motion {
        case .mealSuccess, .levelUp: return .celebrate
        case .comfort, .tapReaction: return .wave
        case .idle, .reducedMotion: return .idle
        }
    }

    private var characterMessage: String {
        if let message = viewModel.message {
            return message
        }
        return "오늘 급식도 함께 만나 볼까요?"
    }
}
