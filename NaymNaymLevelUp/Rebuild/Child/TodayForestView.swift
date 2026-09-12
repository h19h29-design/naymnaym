import SwiftUI

struct TodayForestView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: TodayForestViewModel
    let growthPolicy: GrowthPolicy
    let isTabActive: Bool
    let isAppActive: Bool
    @State private var presentedMealDetail: TodayMealDetailPresentation?
    @StateObject private var speechSynthesizer = MascotSpeechSynthesizer()
    @AppStorage("mascotSpeechEnabled") private var isMascotSpeechEnabled = true

    var body: some View {
        NavigationStack {
            ForestSceneView(
                reduceMotion: reduceMotion,
                activity: ForestSceneActivity(
                    isSheetPresented: isShowingMealDetail,
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
        .task(id: isCurrentDayRefreshActive) {
            guard isCurrentDayRefreshActive else { return }
            await viewModel.loadCurrentDayAndReconcileDate()

            while !Task.isCancelled {
                let delay = viewModel.nanosecondsUntilNextCalendarDay()
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                _ = await viewModel.refreshCurrentDayIfNeeded()
            }
        }
        .onChange(of: viewModel.motionRevision) { _ in
            speakLatestMascotFeedback()
        }
        .onChange(of: isMascotSpeechEnabled) { enabled in
            if enabled {
                speakLatestMascotFeedback()
            } else {
                speechSynthesizer.stop()
            }
        }
        .sheet(item: $presentedMealDetail) { presentation in
            MealDayDetailView(
                route: presentation.route,
                repository: viewModel.mealScheduleRepository,
                school: viewModel.detailSchool,
                isDemoMode: viewModel.isDemoMode,
                recordingViewModel: presentation.recordingViewModel
            )
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            HStack(alignment: .center, spacing: RebuildDesignTokens.spacing[2]) {
                Text("오늘의 냠냠 모험")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RebuildDesignTokens.indigo600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RebuildDesignTokens.lavender200)
                    .clipShape(Capsule())
                Spacer(minLength: 0)
                Circle()
                    .fill(RebuildDesignTokens.sunny400)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(RebuildDesignTokens.coral400)
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(RebuildDesignTokens.sky400)
                    .frame(width: 8, height: 8)
            }

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
        .background(
            LinearGradient(
                colors: [
                    RebuildDesignTokens.cream50,
                    RebuildDesignTokens.lavender200.opacity(0.58),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
    }

    private var characterStage: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[3]) {
            HStack(alignment: .center, spacing: RebuildDesignTokens.spacing[2]) {
                Label("급식이", systemImage: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(RebuildDesignTokens.indigo600)

                Text("Lv. \(currentLevel)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RebuildDesignTokens.mint100)
                    .clipShape(Capsule())

                Spacer(minLength: 0)

                Button {
                    isMascotSpeechEnabled.toggle()
                } label: {
                    Image(systemName: isMascotSpeechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            isMascotSpeechEnabled
                                ? RebuildDesignTokens.indigo600
                                : RebuildDesignTokens.muted600
                        )
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.88))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMascotSpeechEnabled ? "급식이 음성 끄기" : "급식이 음성 켜기")
                .accessibilityHint("급식이의 기록 반응 음성을 설정합니다")
                .accessibilityIdentifier("today_mascot_speech_toggle")
            }

            mascotSpeechBubble

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(
                        alignment: .leading,
                        spacing: RebuildDesignTokens.spacing[3]
                    ) {
                        characterMascot
                            .frame(maxWidth: .infinity, alignment: .center)
                        characterDetails
                    }
                } else {
                    HStack(
                        alignment: .center,
                        spacing: RebuildDesignTokens.spacing[3]
                    ) {
                        characterMascot
                        characterDetails
                    }
                }
            }
        }
        .padding(RebuildDesignTokens.spacing[3])
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    RebuildDesignTokens.cream50,
                    RebuildDesignTokens.mint100,
                    RebuildDesignTokens.lavender200.opacity(0.72),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
            .stroke(RebuildDesignTokens.sky400.opacity(0.32), lineWidth: 1)
        }
        .accessibilityIdentifier("today_character_hub")
    }

    private var mascotSpeechBubble: some View {
        HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
            Image(systemName: speechSynthesizer.isSpeaking ? "waveform" : "quote.bubble.fill")
                .font(.headline)
                .foregroundStyle(
                    speechSynthesizer.isSpeaking
                        ? RebuildDesignTokens.coral400
                        : RebuildDesignTokens.indigo600
                )
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(speechSynthesizer.isSpeaking ? "급식이가 말하고 있어요" : "급식이의 한마디")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RebuildDesignTokens.muted600)
                Text(characterMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isMascotSpeechEnabled {
                Button {
                    speechSynthesizer.speak(spokenCharacterMessage)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RebuildDesignTokens.indigo600)
                        .frame(width: 36, height: 36)
                        .background(RebuildDesignTokens.lavender200)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("급식이 한마디 다시 듣기")
            }
        }
        .padding(RebuildDesignTokens.spacing[2])
        .background(.white.opacity(0.92))
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
            .stroke(RebuildDesignTokens.lavender200, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today_mascot_speech_bubble")
    }

    private var characterMascot: some View {
        GeometryReader { proxy in
            MascotRigView(
                level: currentLevel,
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
        .frame(width: 156, height: 174)
    }

    private var characterDetails: some View {
        let growth = RebuildDesignTokens.semanticPalette(.growth)
        return VStack(
            alignment: .leading,
            spacing: RebuildDesignTokens.spacing[2]
        ) {
            Text(growthPolicy.title(for: currentLevel))
                .font(RebuildDesignTokens.headlineFont)
                .foregroundStyle(growth.surface)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Label("도전 중", systemImage: "flag.fill")
                    .foregroundStyle(RebuildDesignTokens.indigo600)
                Label("성장 중", systemImage: "leaf.fill")
                    .foregroundStyle(RebuildDesignTokens.forest700)
            }
            .font(.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)

            Text("총 \(viewModel.totalXP) XP")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(RebuildDesignTokens.muted600)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: growthPolicy.progress(totalXP: viewModel.totalXP))
                .tint(growth.surface)
                .accessibilityLabel("다음 레벨까지 성장 진행도")

            if viewModel.lastGrantedXP > 0 {
                Text("+\(viewModel.lastGrantedXP) XP")
                    .font(.caption.bold())
                    .foregroundStyle(RebuildDesignTokens.ink900)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RebuildDesignTokens.sunny400.opacity(0.72))
                    .clipShape(Capsule())
                    .accessibilityLabel("이번 기록에서 \(viewModel.lastGrantedXP) 경험치 획득")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mealSummary: some View {
        VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[2]) {
            HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
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
                        .foregroundStyle(RebuildDesignTokens.indigo600)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "fork.knife.circle.fill")
                    .font(.title2)
                    .foregroundStyle(RebuildDesignTokens.coral400)
                    .padding(8)
                    .background(RebuildDesignTokens.coral400.opacity(0.12))
                    .clipShape(Circle())
            }

            if let meal = viewModel.meal {
                let totals = MealWholeMealTotals(
                    meal: meal,
                    isDemoMode: viewModel.isDemoMode
                )
                VStack(alignment: .leading, spacing: RebuildDesignTokens.spacing[1]) {
                    ForEach(Array(meal.menuItems.enumerated()), id: \.offset) {
                        _, item in
                        let visual = MealVisualResolver.resolve(item: item)
                        let accessibility = MealAccessibilityDescriptor(
                            item: item,
                            visual: visual
                        )
                        HStack(alignment: .top, spacing: RebuildDesignTokens.spacing[2]) {
                            MealVisualIcon(iconKey: visual.iconKey)
                            .font(.headline)
                            .foregroundStyle(
                                viewModel.isAllergyRisk(item)
                                    ? RebuildDesignTokens.danger700
                                    : RebuildDesignTokens.indigo600
                            )
                            .frame(width: 26, height: 26)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(RebuildDesignTokens.bodyFont.weight(.semibold))
                                    .foregroundStyle(RebuildDesignTokens.ink900)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    Text(visual.categoryLabel)
                                    Text(visual.confidenceLabel)
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(RebuildDesignTokens.indigo600)
                                MealNutrientChips(
                                    nutrientIDs: visual.representativeNutrientIDs
                                )
                                Text(visual.representativeCopy)
                                    .font(.caption)
                                    .foregroundStyle(RebuildDesignTokens.muted600)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !item.allergyLabels.isEmpty {
                                    allergySignal(item)
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibility.spokenLabel)
                    }
                }
                Text(totals.sourceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RebuildDesignTokens.indigo600)
                Text(totals.calorie)
                    .font(.footnote)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                Text(totals.nutritionSummary)
                    .font(.caption2)
                    .foregroundStyle(RebuildDesignTokens.muted600)
                    .fixedSize(horizontal: false, vertical: true)
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
        .background(.white.opacity(0.94))
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
            .stroke(RebuildDesignTokens.sky400.opacity(0.28), lineWidth: 1)
        }
        .accessibilityIdentifier("today_meal_summary")
    }

    private func allergySignal(_ item: RebuildMealItem) -> some View {
        let safety = RebuildDesignTokens.semanticPalette(.safety)
        let style = MealAllergyVisualStyle.resolve(for: item)
        return Label(
            style.title,
            systemImage: style.systemImage
        )
        .font(.footnote.weight(.semibold))
        .foregroundStyle(safety.foreground)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, RebuildDesignTokens.spacing[2])
        .padding(.vertical, RebuildDesignTokens.spacing[1])
        .background(safety.surface)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[0],
                style: .continuous
            )
            .stroke(safety.foreground, lineWidth: 2)
        }
    }

    private var primaryAction: some View {
        Button {
            presentedMealDetail = viewModel.makeMealDetailPresentation()
        } label: {
            HStack(spacing: RebuildDesignTokens.spacing[2]) {
                Image(systemName: "fork.knife")
                Text(viewModel.primaryActionTitle)
            }
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
            Group {
                if viewModel.isMealDetailActionEnabled {
                    LinearGradient(
                        colors: [
                            RebuildDesignTokens.indigo600,
                            RebuildDesignTokens.forest700,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    RebuildDesignTokens.muted600
                }
            }
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: RebuildDesignTokens.radii[1],
                style: .continuous
            )
        )
        .disabled(!viewModel.isMealDetailActionEnabled)
        .accessibilityLabel(viewModel.primaryActionTitle)
        .accessibilityHint("메뉴별로 먹은 상태를 기록합니다")
        .accessibilityIdentifier("today_primary_action")
    }

    private var currentLevel: Int {
        growthPolicy.level(totalXP: viewModel.totalXP)
    }

    private var isShowingMealDetail: Bool {
        presentedMealDetail != nil
    }

    private var isCurrentDayRefreshActive: Bool {
        isTabActive && isAppActive
    }

    private var characterMessage: String {
        switch viewModel.motion {
        case .comfort:
            return "오늘은 여기까지 해도 괜찮아. 다음에 다시 만나보자!"
        case .mealSuccess:
            if viewModel.lastGrantedXP > 0 {
                return "좋아! 오늘의 도전 기록 완료. \(viewModel.lastGrantedXP) XP를 얻었어!"
            }
            return "좋아! 오늘의 도전을 잘 기록했어."
        case .levelUp:
            return "레벨 업! 우리 함께 한입씩 성장하고 있어!"
        case .tapReaction:
            return "안녕! 오늘 급식도 함께 만나볼까?"
        case .idle, .reducedMotion:
            if let message = viewModel.message {
                return message
            }
            return "오늘 급식도 함께 만나 볼까요?"
        }
    }

    private var spokenCharacterMessage: String {
        characterMessage
    }

    private func speakLatestMascotFeedback() {
        guard isMascotSpeechEnabled,
              viewModel.motionRevision > 0 else {
            return
        }
        speechSynthesizer.speak(spokenCharacterMessage)
    }
}