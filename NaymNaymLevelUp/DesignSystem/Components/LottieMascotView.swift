import SwiftUI
import UIKit

#if canImport(Lottie)
import Lottie
#endif

struct LottieMascotView<Fallback: View>: View {
    var animationName: String
    var loopMode: MascotAnimationLoopMode
    var contentMode: UIView.ContentMode
    var playOnAppear: Bool
    var fallbackAssetName: String
    var onComplete: (() -> Void)?
    @ViewBuilder var fallback: () -> Fallback

    init(
        animationName: String,
        loopMode: MascotAnimationLoopMode,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        playOnAppear: Bool = true,
        fallbackAssetName: String = "mascot_onboarding",
        onComplete: (() -> Void)? = nil,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.animationName = animationName
        self.loopMode = loopMode
        self.contentMode = contentMode
        self.playOnAppear = playOnAppear
        self.fallbackAssetName = fallbackAssetName
        self.onComplete = onComplete
        self.fallback = fallback
    }

    var body: some View {
        Group {
            if LottieAnimationCatalog.isAnimationBundled(animationName) {
                lottiePlayer
            } else {
                fallback()
                    .onAppear {
                        logMissingAnimation()
                    }
            }
        }
        .accessibilityLabel("냠냠이 캐릭터 애니메이션")
    }

    @ViewBuilder
    private var lottiePlayer: some View {
        #if canImport(Lottie)
        LottieMascotRepresentable(
            animationName: animationName,
            loopMode: loopMode,
            contentMode: contentMode,
            playOnAppear: playOnAppear,
            onComplete: onComplete
        )
        #else
        fallback()
            .onAppear {
                logMissingPackage()
            }
        #endif
    }

    private func logMissingAnimation() {
        print("[LottieMascotView] Missing bundled Lottie animation: \(animationName). Using \(fallbackAssetName) PNG fallback.")
    }

    private func logMissingPackage() {
        print("[LottieMascotView] lottie-ios is unavailable at compile time. Using \(fallbackAssetName) PNG fallback for \(animationName).")
    }
}

extension LottieMascotView where Fallback == EmptyView {
    init(
        animationName: String,
        loopMode: MascotAnimationLoopMode,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        playOnAppear: Bool = true,
        fallbackAssetName: String = "mascot_onboarding",
        onComplete: (() -> Void)? = nil
    ) {
        self.init(
            animationName: animationName,
            loopMode: loopMode,
            contentMode: contentMode,
            playOnAppear: playOnAppear,
            fallbackAssetName: fallbackAssetName,
            onComplete: onComplete,
            fallback: { EmptyView() }
        )
    }
}

extension LottieMascotView {
    init(
        state: MascotAnimationState,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        playOnAppear: Bool = true,
        onComplete: (() -> Void)? = nil,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.init(
            animationName: state.animationName,
            loopMode: state.loopMode,
            contentMode: contentMode,
            playOnAppear: playOnAppear,
            fallbackAssetName: state.fallbackAssetName,
            onComplete: onComplete,
            fallback: fallback
        )
    }
}

#if canImport(Lottie)
private struct LottieMascotRepresentable: UIViewRepresentable {
    var animationName: String
    var loopMode: MascotAnimationLoopMode
    var contentMode: UIView.ContentMode
    var playOnAppear: Bool
    var onComplete: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.backgroundBehavior = .pauseAndRestore
        view.contentMode = contentMode
        view.clipsToBounds = false
        configure(view, context: context)
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        uiView.contentMode = contentMode
        configure(uiView, context: context)
    }

    private func configure(_ view: LottieAnimationView, context: Context) {
        context.coordinator.onComplete = onComplete

        if context.coordinator.animationName != animationName {
            view.stop()
            view.animation = LottieAnimation.named(
                animationName,
                bundle: .main,
                subdirectory: LottieAnimationCatalog.resourceSubdirectory
            )
            context.coordinator.animationName = animationName
            context.coordinator.hasStarted = false
        }

        view.loopMode = loopMode.lottieLoopMode

        guard playOnAppear, !context.coordinator.hasStarted else { return }
        context.coordinator.hasStarted = true
        view.play { completed in
            guard completed else { return }
            DispatchQueue.main.async {
                context.coordinator.onComplete?()
            }
        }
    }

    final class Coordinator {
        var animationName: String?
        var hasStarted = false
        var onComplete: (() -> Void)?
    }
}

private extension MascotAnimationLoopMode {
    var lottieLoopMode: LottieLoopMode {
        switch self {
        case .playOnce:
            return .playOnce
        case .loop:
            return .loop
        }
    }
}
#endif
