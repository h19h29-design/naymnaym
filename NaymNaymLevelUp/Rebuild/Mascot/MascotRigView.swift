import SwiftUI

struct MascotRigView: View {
    let level: Int
    let state: RebuildMotionState
    let reduceMotion: Bool

    @StateObject private var controller: MascotMotionController
    @StateObject private var loader = MascotRigLoader()

    private static let productionSpec =
        (try? MascotMotionSpec.bundled()) ?? .fixture

    init(
        level: Int,
        state: RebuildMotionState,
        reduceMotion: Bool
    ) {
        self.level = level
        self.state = state
        self.reduceMotion = reduceMotion
        _controller = StateObject(
            wrappedValue: MascotMotionController(
                spec: Self.productionSpec
            )
        )
    }

    var body: some View {
        Group {
            if loader.canRetry(for: level) {
                Button {
                    Task {
                        await loader.load(level: level)
                    }
                } label: {
                    VStack(spacing: RebuildDesignTokens.spacing[1]) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                        Text("캐릭터 다시 불러오기")
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(RebuildDesignTokens.forest700)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel(
                    "레벨 \(level) 캐릭터를 불러오지 못했습니다. 다시 시도"
                )
                .accessibilityIdentifier("mascot_rig_retry_level_\(level)")
            } else {
                ZStack {
                    Color.clear

                    if loader.loadedLevel != level {
                        ProgressView()
                            .accessibilityHidden(true)
                    } else if !controller.isPlaybackActive {
                        rig(pose: controller.pose)
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) {
                            context in
                            rig(
                                pose: controller.sampledPose(
                                    at: context.date
                                )
                            )
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("레벨 \(level) 냠냠 다람쥐")
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: level) {
            await loader.load(level: level)
        }
        .onAppear {
            controller.play(state, reduceMotion: reduceMotion)
        }
        .onChange(of: state) { newState in
            controller.play(newState, reduceMotion: reduceMotion)
        }
        .onChange(of: reduceMotion) { isReduced in
            controller.play(state, reduceMotion: isReduced)
        }
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
                .easeInOut(duration: reduceMotion ? 0.125 : 0.08),
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
                .easeInOut(duration: reduceMotion ? 0.125 : 0.08),
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
