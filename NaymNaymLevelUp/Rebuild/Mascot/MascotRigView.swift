import SwiftUI

struct MascotRigView: View {
    let level: Int
    let state: RebuildMotionState
    let reduceMotion: Bool

    @StateObject private var controller: MascotMotionController
    @State private var images: MascotRigImages?
    @State private var fallbackLayers: [MascotRigFallbackLayer]?

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
        ZStack {
            Color.clear

            if !controller.isPlaybackActive {
                rig(pose: controller.pose)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) {
                    context in
                    rig(pose: controller.sampledPose(at: context.date))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: level) {
            do {
                images = try MascotRigAssetStore.shared.images(
                    level: level,
                    bundle: .main
                )
                fallbackLayers = nil
            } catch {
                images = nil
                fallbackLayers = try? MascotRigAssetStore.shared
                    .fallbackLayers(level: level, bundle: .main)
            }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("레벨 \(level) 냠냠 다람쥐")
    }

    @ViewBuilder
    private func rig(pose: MascotPose) -> some View {
        let projection = MascotRenderProjection(
            state: controller.activeState,
            pose: pose
        )

        if let images {
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
        } else if let fallbackLayers {
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
        } else {
            Image(legacyAssetName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
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

    private var legacyAssetName: String {
        "Squirrel_Growth_Level_\(min(max(level, 1), 7))"
    }
}
