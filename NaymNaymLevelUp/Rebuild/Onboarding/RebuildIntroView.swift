import SwiftUI

struct RebuildIntroView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var controller = RebuildIntroMotionController()
    @StateObject private var completionController =
        RebuildIntroCompletionController()

    let onCompleted: @MainActor () async -> Bool

    var body: some View {
        ZStack {
            RebuildDesignTokens.cream50
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    RebuildDesignTokens.cream50,
                    RebuildDesignTokens.cream100.opacity(0.72),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RebuildIntroLogoView(
                frame: RebuildIntroMotionSpec.frame(
                    at: controller.elapsed,
                    reduceMotion: controller.effectiveReduceMotion
                        ?? reduceMotion
                )
            )
            .padding(.horizontal, RebuildDesignTokens.spacing[3])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("급식레벨업")

            if completionController.completionFailed {
                Button("저장 다시 시도") {
                    completionController.attempt(onCompleted)
                }
                .buttonStyle(.borderedProminent)
                .tint(RebuildDesignTokens.forest700)
                .disabled(completionController.isAttemptInFlight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, RebuildDesignTokens.spacing[6])
            }
        }
        .onAppear {
            controller.start(
                reduceMotion: reduceMotion,
                onCompleted: {
                    completionController.attempt(onCompleted)
                }
            )
        }
        .onDisappear {
            controller.cancel()
        }
    }
}

private struct RebuildIntroLogoView: View {
    let frame: RebuildIntroLogoFrame

    var body: some View {
        RebuildIntroLogoCanvas(frame: frame)
            .aspectRatio(
                RebuildIntroMotionSpec.sourceAspectRatio,
                contentMode: .fit
            )
            .padding(8)
            .frame(maxWidth: RebuildIntroMotionSpec.sourceWidth + 16)
    }
}

struct RebuildIntroLogoCanvas: View {
    let frame: RebuildIntroLogoFrame

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let splitWidth = width * RebuildIntroMotionSpec.splitFraction

            ZStack {
                if frame.rendersWholeLogo {
                    logo
                        .opacity(frame.wholeLogoOpacity)
                } else {
                    HStack(spacing: 0) {
                        clippedWord(
                            frame.leftWord,
                            width: width,
                            height: height,
                            clipWidth: splitWidth,
                            alignment: .leading
                        )
                        clippedWord(
                            frame.rightWord,
                            width: width,
                            height: height,
                            clipWidth: width - splitWidth,
                            alignment: .trailing
                        )
                    }

                    if let shineProgress = frame.shineProgress {
                        RebuildIntroShine(
                            progress: shineProgress,
                            logoWidth: width
                        )
                    }
                }
            }
            .frame(width: width, height: height)
        }
    }

    private var logo: some View {
        Image("logo_naym_levelup")
            .resizable()
            .interpolation(.high)
            .aspectRatio(
                RebuildIntroMotionSpec.sourceAspectRatio,
                contentMode: .fit
            )
    }

    private func clippedWord(
        _ word: RebuildIntroWordFrame,
        width: CGFloat,
        height: CGFloat,
        clipWidth: CGFloat,
        alignment: Alignment
    ) -> some View {
        ZStack(alignment: alignment) {
            logo
                .frame(width: width, height: height)
                .scaleEffect(word.scale)
                .offset(y: word.translationY)
                .opacity(word.opacity)
        }
        .frame(width: clipWidth, height: height, alignment: alignment)
        .clipped()
    }
}

private struct RebuildIntroShine: View {
    let progress: CGFloat
    let logoWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.9), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(
                    width: logoWidth * 0.34,
                    height: geometry.size.height
                )
                .offset(
                    x: logoWidth * (-0.80 + (1.60 * progress))
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .mask {
                    Image("logo_naym_levelup")
                        .resizable()
                        .interpolation(.high)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
