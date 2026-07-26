import SwiftUI
import UIKit

struct ForestSceneView<Content: View>: View {
    let reduceMotion: Bool
    let activity: ForestSceneActivity
    let content: () -> Content

    @State private var clock: ForestSceneMotionClock

    init(
        reduceMotion: Bool,
        activity: ForestSceneActivity,
        timeSource: RebuildMonotonicTimeSource = .system,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.reduceMotion = reduceMotion
        self.activity = activity
        self.content = content
        _clock = State(
            initialValue: ForestSceneMotionClock(timeSource: timeSource)
        )
    }

    init(
        reduceMotion: Bool,
        isPaused: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            reduceMotion: reduceMotion,
            activity: ForestSceneActivity(
                isSheetPresented: isPaused,
                isTabActive: true,
                isAppActive: true
            ),
            content: content
        )
    }

    var body: some View {
        ZStack {
            if ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion: reduceMotion,
                activity: activity
            ) {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) {
                    _ in
                    layers(
                        frame: ForestSceneMotionSpec.frame(
                            elapsed: clock.elapsed(),
                            reduceMotion: false
                        )
                    )
                }
            } else {
                layers(
                    frame: ForestSceneMotionSpec.frame(
                        elapsed: clock.elapsed(),
                        reduceMotion: reduceMotion
                    )
                )
            }

            content()
                .zIndex(ForestSceneLayer.contentZIndex)
        }
        .background(RebuildDesignTokens.cream50)
        .onAppear {
            clock.update(activity: activity)
        }
        .onChange(of: activity) { newActivity in
            clock.update(activity: newActivity)
        }
    }

    private func layers(frame: ForestSceneFrame) -> some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(ForestSceneLayer.allCases, id: \.self) { layer in
                    let transform = frame[layer]
                    Image(uiImage: ForestSceneAssets.image(for: layer))
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .scaleEffect(
                            layer == .foregroundLeaves ? 1.04 : 1,
                            anchor: .center
                        )
                        .offset(x: transform.x, y: transform.y)
                        .zIndex(layer.zIndex)
                        .accessibilityHidden(true)
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private enum ForestSceneAssets {
    static func image(for layer: ForestSceneLayer) -> UIImage {
        guard let image = images[layer] else {
            fatalError("Validated forest scene layer is missing: \(layer.rawValue)")
        }
        return image
    }

    private static let images: [ForestSceneLayer: UIImage] = {
        Dictionary(
            uniqueKeysWithValues: ForestSceneLayer.allCases.map { layer in
                let filename: String
                switch layer {
                case .sky:
                    filename = "forest_home_sky"
                case .distantTrees:
                    filename = "forest_home_distant_trees"
                case .midgroundTrees:
                    filename = "forest_home_midground_trees"
                case .foregroundLeaves:
                    filename = "forest_home_foreground_leaves"
                case .ground:
                    filename = "forest_home_ground"
                }
                guard let url = Bundle.main.url(
                    forResource: filename,
                    withExtension: "png",
                    subdirectory: "ForestScene/Home"
                ),
                      let image = UIImage(contentsOfFile: url.path)
                else {
                    fatalError("Validated forest scene asset is missing: \(filename)")
                }
                return (layer, image)
            }
        )
    }()
}
