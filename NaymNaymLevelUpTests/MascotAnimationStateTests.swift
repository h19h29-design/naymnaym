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
}
