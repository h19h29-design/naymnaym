import SwiftUI

struct MascotNeutralFallbackView: View {
    static let pendingArtText = MascotArtAccessibility.pendingArtText

    static func accessibilityLabel(stageID: Int) -> String {
        MascotArtAccessibility.pendingLabel(stageID: stageID)
    }

    let stageID: Int

    var body: some View {
        VStack(spacing: RebuildDesignTokens.spacing[1]) {
            Image(systemName: "photo")
                .font(.title2)
                .accessibilityHidden(true)
            Text(Self.pendingArtText)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(RebuildDesignTokens.muted600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(stageID: stageID))
        .accessibilityIdentifier("mascot_pending_art_stage_\(stageID)")
    }
}

struct MascotRigView: View {
    let level: Int
    let state: RebuildMotionState
    let reduceMotion: Bool
    let playbackRevision: Int
    let isSpeaking: Bool

    @StateObject private var controller: MascotMotionController
    @StateObject private var loader = MascotRigLoader()

    private static let productionSpec =
        (try? MascotMotionSpec.bundled()) ?? .fixture

    init(
        level: Int,
        state: RebuildMotionState,
        reduceMotion: Bool,
        playbackRevision: Int = 0,
        isSpeaking: Bool = false
    ) {
        self.level = level
        self.state = state
        self.reduceMotion = reduceMotion
        self.playbackRevision = playbackRevision
        self.isSpeaking = isSpeaking
        _controller = StateObject(
            wrappedValue: MascotMotionController(
                spec: Self.productionSpec
            )
        )
    }

    var body: some View {
        Group {
            if usesNeutralFallback || loader.canRetry(for: level) {
                MascotNeutralFallbackView(stageID: level)
            } else {
                ZStack {
                    Color.clear

                    if loader.loadedLevel != level {
                        ProgressView()
                            .accessibilityHidden(true)
                    } else if shouldAnimateContinuously {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) {
                            context in
                            rig(
                                pose: renderedPose(at: context.date)
                            )
                        }
                    } else {
                        rig(pose: controller.pose)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    isSpeaking
                        ? "레벨 \(level) 냠냠 다람쥐가 말하는 중"
                        : "레벨 \(level) 냠냠 다람쥐"
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: level) {
            guard !usesNeutralFallback else { return }
            await loader.load(level: level)
        }
        .onAppear {
            guard !usesNeutralFallback else { return }
            controller.play(state, reduceMotion: reduceMotion)
        }
        .onChange(of: state) { newState in
            guard !usesNeutralFallback else { return }
            controller.play(newState, reduceMotion: reduceMotion)
        }
        .onChange(of: playbackRevision) { _ in
            guard !usesNeutralFallback else { return }
            controller.play(state, reduceMotion: reduceMotion)
        }
        .onChange(of: reduceMotion) { isReduced in
            guard !usesNeutralFallback else { return }
            controller.play(state, reduceMotion: isReduced)
        }
    }

    private var usesNeutralFallback: Bool {
        GrowthStageArtResolver.resolve(stageID: level).usesNeutralFallback
    }

    private var shouldAnimateContinuously: Bool {
        controller.isPlaybackActive || (isSpeaking && !reduceMotion)
    }

    private func renderedPose(at date: Date) -> MascotPose {
        let basePose = controller.isPlaybackActive
            ? controller.sampledPose()
            : controller.pose
        guard isSpeaking, !reduceMotion else { return basePose }

        let time = date.timeIntervalSinceReferenceDate
        let speechWave = CGFloat(sin(time * 11.0))
        let tailWave = CGFloat(sin((time * 8.0) + 0.8))
        var pose = basePose
        pose.bodyOffsetY += -1.8 * speechWave
        pose.bodyScaleX *= 1 + (0.008 * speechWave)
        pose.bodyScaleY *= 1 - (0.008 * speechWave)
        pose.headRotation = .degrees(
            pose.headRotation.degrees + (1.6 * Double(speechWave))
        )
        pose.leftArmRotation = .degrees(
            pose.leftArmRotation.degrees + (1.2 * Double(speechWave))
        )
        pose.rightArmRotation = .degrees(
            pose.rightArmRotation.degrees - (1.2 * Double(speechWave))
        )
        pose.tailRotation = .degrees(
            pose.tailRotation.degrees + (2.6 * Double(tailWave))
        )
        pose.smiling = true
        return pose
    }

    @ViewBuilder
    private func rig(pose: MascotPose) -> some View {
        let projection = MascotRenderProjection(
            state: controller.activeState,
            pose: pose
        )

        if let images = loader.renderedImages(for: level) {
            let celebrationBlend = projection.celebrationBlend
            let expressionBlend: CGFloat = projection.eyesClosed ? 1 : 0

            ZStack {
                rigImage(images.rest)
                    .opacity(
                        Double((1 - celebrationBlend) * (1 - expressionBlend))
                    )
                rigImage(images.blink)
                    .opacity(
                        Double((1 - celebrationBlend) * expressionBlend)
                    )
                rigImage(images.celebrate)
                    .opacity(Double(celebrationBlend))
            }
            .scaleEffect(
                x: projection.bodyScaleX,
                y: projection.bodyScaleY,
                anchor: .bottom
            )
            .rotationEffect(
                projection.wholeCharacterRotation,
                anchor: UnitPoint(x: 0.5, y: 0.62)
            )
            .offset(y: projection.bodyOffsetY)
            .animation(
                reduceMotion
                    ? MascotReducedMotionPolicy.animation
                    : .easeInOut(duration: 0.08),
                value: projection.eyesClosed
            )
        } else if let fallbackLayers =
            loader.renderedFallbackLayers(for: level) {
            ZStack {
                ForEach(fallbackLayers, id: \.part) { layer in
                    if isVisible(layer.part, in: projection) {
                        rigImage(layer.image)
                    }
                }
            }
            .scaleEffect(
                x: projection.bodyScaleX,
                y: projection.bodyScaleY,
                anchor: .bottom
            )
            .rotationEffect(
                projection.wholeCharacterRotation,
                anchor: UnitPoint(x: 0.5, y: 0.62)
            )
            .offset(y: projection.bodyOffsetY)
            .animation(
                reduceMotion
                    ? MascotReducedMotionPolicy.animation
                    : .easeInOut(duration: 0.08),
                value: projection.eyesClosed
            )
        }
    }

    private func rigImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private func isVisible(
        _ part: MascotRigSemanticPart,
        in projection: MascotRenderProjection
    ) -> Bool {
        switch part {
        case .eyesOpen:
            return !projection.eyesClosed
        case .eyesClosed:
            return projection.eyesClosed
        case .mouthNeutral:
            return !projection.smiling
        case .mouthSmile:
            return projection.smiling
        case .tailBack, .body, .scarf, .head, .armLeft, .armRight, .sprout:
            return true
        }
    }
}