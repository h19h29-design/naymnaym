import SwiftUI
import UIKit

enum IntroExperienceKind {
    case firstLaunch
    case daily
}

struct IntroMission: Equatable {
    var title: String
    var message: String
    var iconName: String
    var tintHex: String
    var primaryTitle: String?
    var primarySubtitle: String?
    var showsDemoBadge: Bool
    var mascotState: MascotAnimationState

    init(
        title: String,
        message: String,
        iconName: String,
        tintHex: String,
        primaryTitle: String? = nil,
        primarySubtitle: String? = nil,
        showsDemoBadge: Bool = false,
        mascotState: MascotAnimationState = .idle
    ) {
        self.title = title
        self.message = message
        self.iconName = iconName
        self.tintHex = tintHex
        self.primaryTitle = primaryTitle
        self.primarySubtitle = primarySubtitle
        self.showsDemoBadge = showsDemoBadge
        self.mascotState = mascotState
    }
}

enum IntroMissionTextFactory {
    static func make(
        todayMeal: MealDay?,
        mealStatus: MealDataState,
        mealMessage: String?,
        isLoading: Bool,
        hasRegisteredSchool: Bool,
        isDemoMode: Bool,
        isAllergyRisk: (MealItem) -> Bool
    ) -> IntroMission {
        if !hasRegisteredSchool {
            return IntroMission(
                title: "학교를 등록하면 시작할 수 있어요",
                message: "학교를 선택하면 오늘 급식과 한 입 미션을 확인할 수 있어요.",
                iconName: "building.columns.fill",
                tintHex: "#7BC96F",
                primaryTitle: "오늘 급식 보러가기",
                primarySubtitle: "학교 등록하고 시작",
                mascotState: .wave
            )
        }

        if isLoading {
            return IntroMission(
                title: "급식 확인 중",
                message: "냠냠이가 오늘 급식을 살펴보고 있어요.",
                iconName: "fork.knife",
                tintHex: "#7BC96F"
            )
        }

        if isDemoMode || mealStatus == .demo {
            return IntroMission(
                title: "체험 모드예요",
                message: "실제 학교 급식이 아니라 샘플 데이터로 앱을 둘러보는 중이에요.",
                iconName: "sparkles",
                tintHex: "#8B5CF6",
                showsDemoBadge: true,
                mascotState: .wave
            )
        }

        if let meal = todayMeal {
            if meal.menuItems.contains(where: isAllergyRisk) {
                return IntroMission(
                    title: "먼저 안전 확인",
                    message: "오늘 급식에 주의가 필요한 메뉴가 있어요. 한 입 도전보다 먼저 확인해요!",
                    iconName: "shield.lefthalf.filled",
                    tintHex: "#EF4444",
                    mascotState: .allergyWarning
                )
            }

            if let candidate = meal.menuItems.first(where: { !isAllergyRisk($0) }) {
                return IntroMission(
                    title: "오늘의 한 입 미션",
                    message: "오늘은 \(candidate.name) 한 입 도전이 추천돼요!",
                    iconName: "star.fill",
                    tintHex: "#FF9F43",
                    mascotState: .wave
                )
            }
        }

        switch mealStatus {
        case .missingAPIKey:
            return IntroMission(
                title: "급식 정보를 불러오지 못했어요",
                message: "API 키, 학교 설정, 네트워크 상태를 확인해 주세요.",
                iconName: "key.fill",
                tintHex: "#EF4444",
                primaryTitle: "설정 확인하기",
                primarySubtitle: "API 키와 학교 설정 확인"
            )
        case .error:
            return IntroMission(
                title: "급식 정보를 불러오지 못했어요",
                message: "API 키, 학교 설정, 네트워크 상태를 확인해 주세요.",
                iconName: "exclamationmark.triangle.fill",
                tintHex: "#EF4444",
                primaryTitle: "설정 확인하기",
                primarySubtitle: "API 키와 학교 설정 확인"
            )
        case .sampleSchool:
            return IntroMission(
                title: "급식 정보를 불러오지 못했어요",
                message: "API 키, 학교 설정, 네트워크 상태를 확인해 주세요.",
                iconName: "building.columns.fill",
                tintHex: "#EF4444",
                primaryTitle: "설정 확인하기",
                primarySubtitle: "실제 학교 설정 확인"
            )
        case .demo:
            return IntroMission(
                title: "체험 모드예요",
                message: "실제 학교 급식이 아니라 샘플 데이터로 앱을 둘러보는 중이에요.",
                iconName: "sparkles",
                tintHex: "#8B5CF6",
                showsDemoBadge: true,
                mascotState: .wave
            )
        case .noMeal:
            return IntroMission(
                title: "오늘은 급식 정보가 없어요",
                message: "방학, 재량휴업일, 급식 미운영일일 수 있어요.",
                iconName: "calendar.badge.exclamationmark",
                tintHex: "#7BC96F"
            )
        case .live:
            return IntroMission(
                title: "오늘도 천천히",
                message: "어려운 음식이 있어도 괜찮아요. 한 단계씩 해봐요!",
                iconName: "leaf.fill",
                tintHex: "#7BC96F"
            )
        }
    }
}

struct IntroExperienceView: View {
    @EnvironmentObject private var appState: AppState

    var kind: IntroExperienceKind
    var primaryTitle: String
    var primarySubtitle: String
    var onPrimary: () -> Void
    var onDemo: () -> Void
    var onParent: () -> Void

    @State private var phase: MascotIntroPhase = .hidden
    @State private var mascotAnimationState: MascotAnimationState = .intro
    @State private var particlesAreMoving = false
    @State private var hasPlayedIntro = false
    @State private var introSequenceCompleted = false

    private var style: IntroStyle {
        IntroStyle(mode: appState.currentMode)
    }

    private var mission: IntroMission {
        IntroMissionTextFactory.make(
            todayMeal: appState.todayMeal,
            mealStatus: appState.mealStatus,
            mealMessage: appState.mealMessage,
            isLoading: appState.isLoadingMeals,
            hasRegisteredSchool: appState.profile?.schoolCode.isEmpty == false,
            isDemoMode: appState.profile?.isUsingDemoMode == true,
            isAllergyRisk: appState.isAllergyRisk
        )
    }

    private var buttonsReady: Bool {
        introSequenceCompleted
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: layoutSpacing(for: proxy.size.height)) {
                    LogoHeader(style: style, compact: isCompactHeight(proxy.size.height))
                        .padding(.top, isCompactHeight(proxy.size.height) ? 8 : 18)

                    Text("편식을 혼내지 않고, 한 입 도전으로 바꾸는 급식 코칭 앱")
                        .font(.system(isSmallHeight(proxy.size.height) ? .caption : .subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(style.text.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 8)

                    ZStack {
                        ParticleField(isMoving: particlesAreMoving, compact: isCompactHeight(proxy.size.height))
                        LottieMascotView(
                            state: mascotAnimationState,
                            onComplete: handleMascotAnimationComplete
                        ) {
                            AnimatedMascotView(
                                phase: phase,
                                size: mascotSize(for: proxy.size),
                                style: style
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: mascotStageHeight(for: proxy.size))
                    .padding(.top, isCompactHeight(proxy.size.height) ? -4 : 0)

                    MissionCard(
                        mission: mission,
                        kind: kind,
                        progressText: appState.progress.nextLevelText,
                        progressValue: appState.progress.expProgress,
                        style: style,
                        compact: isSmallHeight(proxy.size.height)
                    )

                    ActionButtonStack(
                        primaryTitle: mission.primaryTitle ?? primaryTitle,
                        primarySubtitle: mission.primarySubtitle ?? primarySubtitle,
                        style: style,
                        isReady: buttonsReady,
                        compact: isSmallHeight(proxy.size.height),
                        onPrimary: onPrimary,
                        onDemo: onDemo,
                        onParent: onParent
                    )

                    FeatureStrip(style: style, compact: isSmallHeight(proxy.size.height))
                        .padding(.bottom, isCompactHeight(proxy.size.height) ? 10 : 24)
                }
                .padding(.horizontal, proxy.size.width < 360 ? 15 : 22)
                .frame(width: min(proxy.size.width, 520))
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
            }
            .background(IntroBackground(style: style))
        }
        .task {
            guard !hasPlayedIntro else { return }
            hasPlayedIntro = true
            mascotAnimationState = .intro
            particlesAreMoving = true

            if LottieAnimationCatalog.isAnimationBundled(MascotAnimationState.intro.animationName) {
                phase = .settled
                await completeLottieIntroAfterTimeoutIfNeeded()
            } else {
                await playFallbackIntro()
            }
        }
        .onChange(of: mission) { newMission in
            guard introSequenceCompleted, mascotAnimationState != .intro else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                mascotAnimationState = newMission.mascotState
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func playFallbackIntro() async {
        let sequence: [(MascotIntroPhase, UInt64)] = [
            (.peek, 340_000_000),
            (.rise, 520_000_000),
            (.bounce, 420_000_000),
            (.wink, 410_000_000),
            (.wave, 530_000_000),
            (.jump, 500_000_000),
            (.land, 250_000_000),
            (.settled, 0)
        ]

        for (nextPhase, delay) in sequence {
            withAnimation(nextPhase.animation) {
                phase = nextPhase
            }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        completeIntroSequence()
    }

    private func completeLottieIntroAfterTimeoutIfNeeded() async {
        try? await Task.sleep(nanoseconds: 4_200_000_000)
        guard !Task.isCancelled, mascotAnimationState == .intro, !introSequenceCompleted else { return }
        completeIntroSequence()
    }

    private func handleMascotAnimationComplete() {
        if mascotAnimationState == .intro {
            completeIntroSequence()
            return
        }

        guard let nextState = mascotAnimationState.stateAfterCompletion else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            mascotAnimationState = nextState
        }
    }

    private func completeIntroSequence() {
        withAnimation(.easeOut(duration: 0.22)) {
            phase = .settled
            introSequenceCompleted = true
            mascotAnimationState = mission.mascotState
        }
    }

    private func isCompactHeight(_ height: CGFloat) -> Bool {
        height < 820
    }

    private func isSmallHeight(_ height: CGFloat) -> Bool {
        height < 720
    }

    private func mascotSize(for size: CGSize) -> CGFloat {
        if isSmallHeight(size.height) {
            return min(178, max(164, size.width * 0.52))
        }
        return min(isCompactHeight(size.height) ? 210 : 242, max(180, size.width * 0.62))
    }

    private func mascotStageHeight(for size: CGSize) -> CGFloat {
        if isSmallHeight(size.height) {
            return 184
        }
        return isCompactHeight(size.height) ? 222 : 270
    }

    private func layoutSpacing(for height: CGFloat) -> CGFloat {
        if isSmallHeight(height) {
            return 7
        }
        return isCompactHeight(height) ? 10 : 15
    }
}

private enum MascotIntroPhase {
    case hidden
    case peek
    case rise
    case bounce
    case wink
    case wave
    case jump
    case land
    case settled

    var animation: Animation {
        switch self {
        case .hidden:
            return .easeOut(duration: 0.01)
        case .peek:
            return .easeOut(duration: 0.18)
        case .rise:
            return .spring(response: 0.55, dampingFraction: 0.72)
        case .bounce:
            return .spring(response: 0.32, dampingFraction: 0.52)
        case .wink:
            return .easeInOut(duration: 0.24)
        case .wave:
            return .easeInOut(duration: 0.30)
        case .jump:
            return .spring(response: 0.34, dampingFraction: 0.56)
        case .land:
            return .spring(response: 0.26, dampingFraction: 0.54)
        case .settled:
            return .spring(response: 0.42, dampingFraction: 0.80)
        }
    }
}

private struct IntroStyle {
    var mode: UserMode

    var primary: Color {
        Color(hex: mode == .middle ? "#37D67A" : "#42B84B")
    }

    var orange: Color {
        Color(hex: "#FF8F22")
    }

    var purple: Color {
        Color(hex: mode == .middle ? "#6D5DFF" : "#8B5CF6")
    }

    var cream: Color {
        Color(hex: "#FFF8E7")
    }

    var mint: Color {
        Color(hex: "#DCF7EF")
    }

    var text: Color {
        Color(hex: mode == .middle ? "#172033" : "#162334")
    }

    var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [purple, Color(hex: "#B455FF")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct LogoHeader: View {
    var style: IntroStyle
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            if AssetCatalog.hasImage("logo_naym_levelup") {
                Image("logo_naym_levelup")
                    .resizable()
                    .scaledToFit()
                    .frame(height: compact ? 52 : 62)
                    .accessibilityLabel("냠냠레벨업")
            } else {
                RequiredAssetPlaceholder(
                    assetName: "logo_naym_levelup",
                    recommendedSize: "가로 760px 이상, 투명 PNG"
                )
                .frame(height: compact ? 54 : 64)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MissionCard: View {
    var mission: IntroMission
    var kind: IntroExperienceKind
    var progressText: String
    var progressValue: Double
    var style: IntroStyle
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 7 : 10) {
            if mission.showsDemoBadge {
                Text("체험 모드")
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: mission.tintHex))
                    .clipShape(Capsule())
                    .accessibilityLabel("체험 모드")
            }

            Label {
                Text(mission.title)
                    .font(.system(compact ? .subheadline : .headline, design: .rounded).weight(.heavy))
            } icon: {
                Image(systemName: mission.iconName)
                    .foregroundStyle(Color(hex: mission.tintHex))
            }
            .foregroundStyle(style.text)

            Text(mission.message)
                .font(.system(compact ? .headline : .title3, design: .rounded).weight(.heavy))
                .foregroundStyle(style.text)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)

            if kind == .daily {
                ProgressView(value: progressValue)
                    .tint(style.primary)
                    .padding(.top, 2)
                Text(progressText)
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(style.text.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 12 : 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.93))
                .shadow(color: Color(hex: mission.tintHex).opacity(0.14), radius: 18, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }
}

private struct ActionButtonStack: View {
    var primaryTitle: String
    var primarySubtitle: String
    var style: IntroStyle
    var isReady: Bool
    var compact: Bool
    var onPrimary: () -> Void
    var onDemo: () -> Void
    var onParent: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            IntroActionButton(
                title: primaryTitle,
                subtitle: primarySubtitle,
                systemImage: "fork.knife",
                style: style,
                prominence: .primary,
                compact: compact,
                isDisabled: !isReady,
                action: onPrimary
            )

            HStack(spacing: 10) {
                IntroActionButton(
                    title: "체험 모드",
                    subtitle: "샘플로 살펴보기",
                    systemImage: "sparkles",
                    style: style,
                    prominence: .secondary,
                    compact: compact,
                    isDisabled: !isReady,
                    action: onDemo
                )
                IntroActionButton(
                    title: "보호자 모드",
                    subtitle: "아이 연결하기",
                    systemImage: "person.2.fill",
                    style: style,
                    prominence: .secondary,
                    compact: compact,
                    isDisabled: !isReady,
                    action: onParent
                )
            }
        }
        .opacity(isReady ? 1 : 0.52)
        .animation(.easeOut(duration: 0.28), value: isReady)
    }
}

private enum IntroButtonProminence {
    case primary
    case secondary
}

private struct IntroActionButton: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var style: IntroStyle
    var prominence: IntroButtonProminence
    var compact: Bool
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: prominence == .primary ? 20 : 15, weight: .heavy))
                    .frame(width: prominence == .primary ? 28 : 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(prominence == .primary ? .headline : .subheadline, design: .rounded).weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .opacity(0.82)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(prominence == .primary ? Color.white : style.text)
            .padding(.horizontal, prominence == .primary ? 18 : 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: buttonHeight)
            .background(background)
            .overlay(overlay)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: shadowColor, radius: prominence == .primary ? 16 : 9, x: 0, y: prominence == .primary ? 9 : 4)
        }
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    @ViewBuilder
    private var background: some View {
        if prominence == .primary {
            style.buttonGradient
        } else {
            Color.white.opacity(0.93)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if prominence == .primary {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style.primary.opacity(0.18), lineWidth: 1)
        }
    }

    private var shadowColor: Color {
        prominence == .primary ? style.purple.opacity(0.28) : Color.black.opacity(0.06)
    }

    private var buttonHeight: CGFloat {
        if compact {
            return prominence == .primary ? 56 : 46
        }
        return prominence == .primary ? 62 : 52
    }
}

private struct FeatureStrip: View {
    var style: IntroStyle
    var compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            FeaturePill(assetName: "icon_one_bite", title: "한 입 도전", message: "작은 한 입이 변화를 만들어요", compact: compact)
            Divider().frame(height: compact ? 34 : 42)
            FeaturePill(assetName: "icon_growth_report", title: "성장 리포트", message: "나만의 성장을 확인해요", compact: compact)
            Divider().frame(height: compact ? 34 : 42)
            FeaturePill(assetName: "icon_reward", title: "응원과 보상", message: "도전할수록 레벨업", compact: compact)
        }
        .padding(.vertical, compact ? 8 : 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.91))
                .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
        )
    }
}

private struct FeaturePill: View {
    var assetName: String
    var title: String
    var message: String
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            if AssetCatalog.hasImage(assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
            } else {
                RequiredAssetPlaceholder(assetName: assetName, recommendedSize: "256x256 PNG")
                    .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
            }

            Text(title)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(AppColors.textDark)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(message)
                .font(.system(size: compact ? 8.4 : 9.4, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.graySecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IntroBackground: View {
    var style: IntroStyle

    var body: some View {
        ZStack(alignment: .bottom) {
            if AssetCatalog.hasImage("bg_soft_mint") {
                Image("bg_soft_mint")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [style.mint, style.cream, Color(hex: "#E7F8C8")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            RadialGradient(
                colors: [Color.white.opacity(0.70), Color.white.opacity(0)],
                center: .top,
                startRadius: 12,
                endRadius: 320
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 130, style: .continuous)
                .fill(Color(hex: "#BFEF8D").opacity(0.45))
                .frame(height: 118)
                .offset(y: 58)
                .ignoresSafeArea()
        }
    }
}

private struct ParticleField: View {
    var isMoving: Bool
    var compact: Bool

    private let particles: [ParticleSpec] = [
        ParticleSpec(kind: .symbol("sparkles"), x: -122, y: -74, size: 18, color: Color.white.opacity(0.95), delay: 0.00),
        ParticleSpec(kind: .symbol("star.fill"), x: -104, y: 46, size: 22, color: Color(hex: "#FFD34D"), delay: 0.12),
        ParticleSpec(kind: .symbol("leaf.fill"), x: 104, y: -26, size: 17, color: Color(hex: "#49B84E"), delay: 0.20),
        ParticleSpec(kind: .symbol("heart.fill"), x: 128, y: 44, size: 17, color: Color(hex: "#FF8D75"), delay: 0.28),
        ParticleSpec(kind: .symbol("sparkle"), x: 70, y: -92, size: 14, color: Color.white.opacity(0.92), delay: 0.36),
        ParticleSpec(kind: .circle, x: -138, y: -6, size: 8, color: Color(hex: "#7BC96F").opacity(0.75), delay: 0.44),
        ParticleSpec(kind: .circle, x: 148, y: -58, size: 7, color: Color(hex: "#FFB84A").opacity(0.75), delay: 0.52),
        ParticleSpec(kind: .circle, x: -60, y: 94, size: 6, color: Color.white.opacity(0.95), delay: 0.62)
    ]

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                particleView(particle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func particleView(_ particle: ParticleSpec) -> some View {
        let verticalOffset = compact ? particle.y * 0.78 : particle.y
        Group {
            switch particle.kind {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: particle.size, weight: .bold))
            case .circle:
                Circle()
                    .frame(width: particle.size, height: particle.size)
            }
        }
        .foregroundStyle(particle.color)
        .scaleEffect(isMoving ? 1.10 : 0.82)
        .opacity(isMoving ? 1 : 0.48)
        .offset(x: particle.x, y: verticalOffset + (isMoving ? -5 : 5))
        .animation(.easeInOut(duration: 1.35).delay(particle.delay).repeatForever(autoreverses: true), value: isMoving)
    }
}

private struct ParticleSpec: Identifiable {
    enum Kind {
        case symbol(String)
        case circle
    }

    let id = UUID()
    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var delay: Double
}

private struct AnimatedMascotView: View {
    var phase: MascotIntroPhase
    var size: CGFloat
    var style: IntroStyle

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(phase == .jump ? 0.08 : 0.17))
                .frame(width: size * (phase == .jump ? 0.38 : 0.58), height: size * 0.085)
                .blur(radius: 3)
                .offset(y: size * 0.01)

            mascotImage
                .frame(width: size, height: size)
                .scaleEffect(x: phase == .land ? 1.05 : imageScale, y: phase == .land ? 0.94 : imageScale, anchor: .bottom)
                .rotationEffect(.degrees(rotation))
                .offset(y: verticalOffset)
                .opacity(imageOpacity)
        }
        .frame(width: size * 1.34, height: size * 1.18, alignment: .bottom)
        .clipped()
        .accessibilityLabel("냠냠이 캐릭터가 인사하고 있어요.")
    }

    @ViewBuilder
    private var mascotImage: some View {
        if AssetCatalog.hasImage(assetName) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .shadow(color: style.primary.opacity(0.22), radius: 14, x: 0, y: 10)
        } else {
            RequiredAssetPlaceholder(
                assetName: assetName,
                recommendedSize: "캐릭터 투명 PNG/WebP, 900x900px 권장"
            )
        }
    }

    private var assetName: String {
        switch phase {
        case .hidden:
            return "mascot_onboarding"
        case .wink:
            return "mascot_wave_1"
        case .wave:
            return "mascot_wave_2"
        case .jump:
            return "mascot_jump"
        default:
            return "mascot_onboarding"
        }
    }

    private var verticalOffset: CGFloat {
        switch phase {
        case .hidden:
            return size * 0.70
        case .peek:
            return size * 0.62
        case .rise:
            return size * 0.08
        case .bounce:
            return -size * 0.04
        case .wink:
            return -size * 0.02
        case .wave:
            return -size * 0.02
        case .jump:
            return -size * 0.20
        case .land:
            return size * 0.03
        case .settled:
            return 0
        }
    }

    private var imageScale: CGFloat {
        switch phase {
        case .hidden, .peek:
            return 0.92
        case .bounce:
            return 1.04
        case .jump:
            return 1.05
        default:
            return 1
        }
    }

    private var imageOpacity: Double {
        phase == .hidden ? 0 : 1
    }

    private var rotation: Double {
        switch phase {
        case .wave:
            return -3.5
        case .jump:
            return 2.5
        case .land:
            return -1
        default:
            return 0
        }
    }
}

private enum AssetCatalog {
    static func hasImage(_ name: String) -> Bool {
        UIImage(named: name) != nil
    }
}

private struct RequiredAssetPlaceholder: View {
    var assetName: String
    var recommendedSize: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 22, weight: .semibold))
            Text(assetName)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(recommendedSize)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(Color(hex: "#7A805F"))
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                .foregroundStyle(Color(hex: "#B9DDA0"))
        )
    }
}
