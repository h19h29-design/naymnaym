import Foundation

enum MascotAnimationLoopMode: Equatable {
    case playOnce
    case loop

    var isLooping: Bool {
        self == .loop
    }
}

enum MascotAnimationState: String, CaseIterable, Equatable {
    case intro
    case idle
    case wave
    case success
    case levelup
    case allergyWarning
    case fallback

    var animationName: String {
        switch self {
        case .intro:
            return "mascot_intro"
        case .idle:
            return "mascot_idle_loop"
        case .wave:
            return "mascot_wave"
        case .success:
            return "mascot_success"
        case .levelup:
            return "mascot_levelup"
        case .allergyWarning:
            return "mascot_allergy_warning"
        case .fallback:
            return "mascot_idle_loop"
        }
    }

    var loopMode: MascotAnimationLoopMode {
        switch self {
        case .idle, .allergyWarning, .fallback:
            return .loop
        case .intro, .wave, .success, .levelup:
            return .playOnce
        }
    }

    var fallbackAssetName: String {
        switch self {
        case .wave:
            return "mascot_wave_2"
        case .success, .levelup:
            return "mascot_jump"
        case .intro, .idle, .allergyWarning, .fallback:
            return "mascot_onboarding"
        }
    }

    var stateAfterCompletion: MascotAnimationState? {
        switch self {
        case .intro, .wave, .success, .levelup:
            return .idle
        case .idle, .allergyWarning, .fallback:
            return nil
        }
    }
}

enum LottieAnimationCatalog {
    static let resourceSubdirectory = "Animations"

    static let expectedAnimationNames = [
        MascotAnimationState.intro.animationName,
        MascotAnimationState.idle.animationName,
        MascotAnimationState.wave.animationName,
        MascotAnimationState.success.animationName,
        MascotAnimationState.levelup.animationName,
        MascotAnimationState.allergyWarning.animationName
    ]

    static func url(for animationName: String, bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: animationName,
            withExtension: "json",
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(forResource: animationName, withExtension: "json")
    }

    static func isAnimationBundled(_ animationName: String, bundle: Bundle = .main) -> Bool {
        url(for: animationName, bundle: bundle) != nil
    }
}
