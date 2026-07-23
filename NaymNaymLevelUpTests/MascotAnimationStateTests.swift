import XCTest
@testable import NaymNaymLevelUp

final class MascotAnimationStateTests: XCTestCase {
    func testIntroStateUsesMascotIntroAnimation() {
        XCTAssertEqual(MascotAnimationState.intro.animationName, "mascot_intro")
        XCTAssertEqual(MascotAnimationState.intro.loopMode, .playOnce)
        XCTAssertEqual(MascotAnimationState.intro.stateAfterCompletion, .idle)
    }

    func testIdleStateLoops() {
        XCTAssertEqual(MascotAnimationState.idle.animationName, "mascot_idle_loop")
        XCTAssertEqual(MascotAnimationState.idle.loopMode, .loop)
        XCTAssertTrue(MascotAnimationState.idle.loopMode.isLooping)
        XCTAssertNil(MascotAnimationState.idle.stateAfterCompletion)
    }

    func testAllergyWarningStateUsesDedicatedAnimationAndLoops() {
        XCTAssertEqual(MascotAnimationState.allergyWarning.animationName, "mascot_allergy_warning")
        XCTAssertEqual(MascotAnimationState.allergyWarning.loopMode, .loop)
        XCTAssertEqual(MascotAnimationState.allergyWarning.fallbackAssetName, "mascot_onboarding")
    }

    func testOneShotResultStatesReturnToIdle() {
        XCTAssertEqual(MascotAnimationState.wave.animationName, "mascot_wave")
        XCTAssertEqual(MascotAnimationState.success.animationName, "mascot_success")
        XCTAssertEqual(MascotAnimationState.levelup.animationName, "mascot_levelup")
        XCTAssertEqual(MascotAnimationState.wave.stateAfterCompletion, .idle)
        XCTAssertEqual(MascotAnimationState.success.stateAfterCompletion, .idle)
        XCTAssertEqual(MascotAnimationState.levelup.stateAfterCompletion, .idle)
    }

    func testExpectedLottieResourceNamesStayStable() {
        XCTAssertEqual(
            LottieAnimationCatalog.expectedAnimationNames,
            [
                "mascot_intro",
                "mascot_idle_loop",
                "mascot_wave",
                "mascot_success",
                "mascot_levelup",
                "mascot_allergy_warning"
            ]
        )
    }

    func testMissingLottieResourceCanBeDetectedWithoutCrashing() {
        XCTAssertFalse(LottieAnimationCatalog.isAnimationBundled("__missing_mascot_animation__", bundle: .main))
    }

    func testAllExpectedLottieResourcesAreBundled() {
        XCTAssertTrue(LottieAnimationCatalog.areAllExpectedAnimationsBundled(bundle: .main))
    }

    func testLottieImageAssetsAreBundled() {
        let imageNames = [
            "mascot_onboarding",
            "mascot_wave_1",
            "mascot_wave_2",
            "mascot_jump"
        ]

        for imageName in imageNames {
            XCTAssertNotNil(
                Bundle.main.url(
                    forResource: imageName,
                    withExtension: "png",
                    subdirectory: LottieAnimationCatalog.imageSearchPath
                ),
                "\(imageName).png should be bundled for Lottie playback"
            )
        }
    }

    func testIntroLogoSplitFallsInsideVerifiedTransparentGap() {
        let splitX = IntroLogoMotionSpec.splitX(for: 357)

        XCTAssertEqual(splitX, 142.8, accuracy: 0.001)
        XCTAssertGreaterThan(splitX, 138)
        XCTAssertLessThan(splitX, 146)
    }

    func testIntroLogoMotionUsesApprovedOneShotTiming() {
        XCTAssertEqual(IntroLogoMotionSpec.initialYOffset, 10, accuracy: 0.001)
        XCTAssertEqual(IntroLogoMotionSpec.initialScale, 0.988, accuracy: 0.001)
        XCTAssertEqual(IntroLogoMotionSpec.nyamStart, 0.04, accuracy: 0.001)
        XCTAssertEqual(IntroLogoMotionSpec.levelUpStart, 0.34, accuracy: 0.001)
        XCTAssertEqual(IntroLogoMotionSpec.riseDuration, 0.76, accuracy: 0.001)
        XCTAssertEqual(IntroLogoMotionSpec.shineStart, 1.18, accuracy: 0.001)
        XCTAssertEqual(IntroLogoMotionSpec.shineDuration, 0.82, accuracy: 0.001)
        XCTAssertEqual(
            IntroLogoMotionSpec.shineStart + IntroLogoMotionSpec.shineDuration,
            2.0,
            accuracy: 0.001
        )
        XCTAssertEqual(IntroLogoMotionSpec.reduceMotionFadeDuration, 0.25, accuracy: 0.001)
    }

    func testReadabilityPolicyKeepsSupportingTextLegible() {
        XCTAssertGreaterThanOrEqual(AppReadabilityPolicy.minimumSupportingPointSize, 13)
        XCTAssertGreaterThanOrEqual(AppReadabilityPolicy.minimumTextScale, 0.90)
    }

    func testReadabilityPaletteMeetsNormalTextContrastOnLightSurfaces() {
        let foregrounds = [
            AppReadabilityPolicy.textPrimaryHex,
            AppReadabilityPolicy.textSecondaryHex,
            AppReadabilityPolicy.greenTextHex,
            AppReadabilityPolicy.orangeTextHex,
            AppReadabilityPolicy.successTextHex,
            AppReadabilityPolicy.warningTextHex
        ]
        let backgrounds = ["#FFFFFF", "#FFF8E7"]

        for foreground in foregrounds {
            for background in backgrounds {
                XCTAssertGreaterThanOrEqual(
                    AppReadabilityPolicy.contrastRatio(foregroundHex: foreground, backgroundHex: background),
                    4.5,
                    "Expected \(foreground) to remain readable on \(background)"
                )
            }
        }
    }

    func testPrimaryButtonGradientSupportsWhiteText() {
        for background in AppReadabilityPolicy.primaryButtonGradientHexes {
            XCTAssertGreaterThanOrEqual(
                AppReadabilityPolicy.contrastRatio(foregroundHex: "#FFFFFF", backgroundHex: background),
                4.5,
                "Expected white button text to remain readable on \(background)"
            )
        }
    }
}
