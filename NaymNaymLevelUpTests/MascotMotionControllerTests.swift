import XCTest
@testable import NaymNaymLevelUp

@MainActor
final class MascotMotionControllerTests: XCTestCase {
    func testMealSuccessUsesSquashThenJumpThenRest() {
        let controller = MascotMotionController(spec: .fixture)

        XCTAssertEqual(
            controller.pose(for: .mealSuccess, progress: 0.0).bodyScaleY,
            1.0
        )
        XCTAssertEqual(
            controller.pose(for: .mealSuccess, progress: 0.2).bodyScaleY,
            0.96,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            controller.pose(for: .mealSuccess, progress: 0.5).bodyOffsetY,
            0
        )
        XCTAssertEqual(
            controller.pose(for: .mealSuccess, progress: 1.0),
            .rest
        )
    }

    func testTapReactionClosesEyesAtItsPeak() {
        let controller = MascotMotionController(spec: .fixture)

        let pose = controller.pose(for: .tapReaction, progress: 0.5)

        XCTAssertTrue(pose.eyesClosed)
        XCTAssertTrue(pose.smiling)
        XCTAssertLessThan(pose.bodyOffsetY, 0)
        XCTAssertNotEqual(pose.headRotation, .zero)
    }

    func testReduceMotionKeepsExpressionAndRemovesSpatialTransforms() {
        let controller = MascotMotionController(spec: .fixture)

        let pose = controller.pose(
            for: .tapReaction,
            progress: 0.5,
            reduceMotion: true
        )

        XCTAssertTrue(pose.eyesClosed)
        XCTAssertEqual(pose.bodyOffsetY, 0)
        XCTAssertEqual(pose.bodyScaleX, 1)
        XCTAssertEqual(pose.bodyScaleY, 1)
        XCTAssertEqual(pose.headRotation, .zero)
        XCTAssertEqual(pose.leftArmRotation, .zero)
        XCTAssertEqual(pose.rightArmRotation, .zero)
        XCTAssertEqual(pose.tailRotation, .zero)
    }

    func testReduceMotionUsesEyeCrossfadeForMealSuccess() {
        let controller = MascotMotionController(spec: .fixture)

        let pose = controller.pose(
            for: .mealSuccess,
            progress: 0.5,
            reduceMotion: true
        )

        XCTAssertTrue(pose.eyesClosed)
        XCTAssertEqual(pose.bodyOffsetY, 0)
        XCTAssertEqual(pose.bodyScaleX, 1)
        XCTAssertEqual(pose.bodyScaleY, 1)
    }

    func testPlayPublishesTheSelectedStatesStartingPose() {
        let controller = MascotMotionController(spec: .fixture)

        controller.play(.mealSuccess)

        XCTAssertEqual(controller.activeState, .mealSuccess)
        XCTAssertEqual(
            controller.pose,
            controller.pose(for: .mealSuccess, progress: 0)
        )
    }

    func testSampledPoseUsesThePlaybackStartDate() {
        let controller = MascotMotionController(spec: .fixture)
        let start = Date(timeIntervalSince1970: 1_000)
        controller.play(.mealSuccess, at: start)

        let pose = controller.sampledPose(
            at: start.addingTimeInterval(0.7)
        )

        XCTAssertLessThan(pose.bodyOffsetY, 0)
        XCTAssertEqual(pose.bodyScaleY, 0.96, accuracy: 0.001)
    }

    func testReducedMotionPlayPublishesExpressionOnlyPose() {
        let controller = MascotMotionController(spec: .fixture)

        controller.play(
            .mealSuccess,
            reduceMotion: true,
            at: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(controller.activeState, .reducedMotion)
        XCTAssertTrue(controller.pose.eyesClosed)
        XCTAssertEqual(controller.pose.bodyOffsetY, 0)
        XCTAssertEqual(controller.pose.bodyScaleX, 1)
        XCTAssertEqual(controller.pose.bodyScaleY, 1)
    }

    func testIdlePlaybackUsesTheStaticRestBoundary() {
        let controller = MascotMotionController(spec: .fixture)

        controller.play(
            .idle,
            at: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertFalse(controller.isPlaybackActive)
        XCTAssertEqual(controller.activeState, .idle)
        XCTAssertEqual(controller.pose, .rest)
    }

    func testNonRestPlaybackActivatesFrameSampling() {
        let controller = MascotMotionController(spec: .fixture)

        controller.play(
            .mealSuccess,
            at: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(controller.isPlaybackActive)
    }

    func testRenderProjectionConsumesTheApprovedCelebrationSignals() {
        let controller = MascotMotionController(spec: .fixture)
        let pose = controller.pose(for: .mealSuccess, progress: 0.5)

        let projection = MascotRenderProjection(
            state: .mealSuccess,
            pose: pose
        )

        XCTAssertEqual(projection.celebrationBlend, 1, accuracy: 0.001)
        XCTAssertEqual(projection.bodyScaleX, 1, accuracy: 0.001)
        XCTAssertEqual(projection.bodyScaleY, 1, accuracy: 0.001)
        XCTAssertEqual(projection.bodyOffsetY, -52, accuracy: 0.001)
        XCTAssertEqual(projection.wholeCharacterRotation.degrees, -2)
    }

    func testRenderProjectionKeepsTapMotionOnTheRestKeyframe() {
        let controller = MascotMotionController(spec: .fixture)
        let pose = controller.pose(for: .tapReaction, progress: 0.5)

        let projection = MascotRenderProjection(
            state: .tapReaction,
            pose: pose
        )

        XCTAssertEqual(projection.celebrationBlend, 0)
        XCTAssertEqual(projection.bodyScaleX, 1.015, accuracy: 0.001)
        XCTAssertEqual(projection.bodyScaleY, 0.985, accuracy: 0.001)
        XCTAssertEqual(projection.bodyOffsetY, -8, accuracy: 0.001)
        XCTAssertEqual(projection.wholeCharacterRotation.degrees, -4)
        XCTAssertTrue(projection.eyesClosed)
    }

    func testMotionSpecDecodesTheSharedContractTimings() throws {
        let data = Data(
            """
            {
              "version": 1,
              "states": {
                "idle": {"durationMs": 6000, "loop": true},
                "tapReaction": {"durationMs": 420, "loop": false},
                "mealSuccess": {"durationMs": 1400, "loop": false},
                "levelUp": {"durationMs": 3000, "loop": false},
                "comfort": {"durationMs": 1200, "loop": false},
                "reducedMotion": {"durationMs": 250, "loop": false}
              }
            }
            """.utf8
        )

        let spec = try MascotMotionSpec(data: data)

        XCTAssertEqual(spec.state(for: .idle).duration, 6.0, accuracy: 0.001)
        XCTAssertTrue(spec.state(for: .idle).loops)
        XCTAssertEqual(
            spec.state(for: .tapReaction).duration,
            0.42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            spec.state(for: .mealSuccess).duration,
            1.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            spec.state(for: .reducedMotion).duration,
            0.25,
            accuracy: 0.001
        )
        XCTAssertFalse(spec.state(for: .reducedMotion).loops)
    }

    func testBundledMotionSpecUsesTheSharedContract() throws {
        let spec = try MascotMotionSpec.bundled(bundle: .main)

        XCTAssertEqual(
            spec.state(for: .levelUp).duration,
            3.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            spec.state(for: .comfort).duration,
            1.2,
            accuracy: 0.001
        )
        XCTAssertFalse(spec.state(for: .comfort).loops)
    }

    func testProgressLoopsIdleAndClampsOneShotStates() {
        let controller = MascotMotionController(spec: .fixture)

        XCTAssertEqual(
            controller.progress(for: .idle, elapsed: 6.6),
            0.1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            controller.progress(for: .mealSuccess, elapsed: 2.8),
            1.0,
            accuracy: 0.001
        )
    }

    func testLevelOneApprovedAssetsAreVerifiedAndCached() throws {
        let store = MascotRigAssetStore()

        let first = try store.images(level: 1, bundle: .main)
        let second = try store.images(level: 1, bundle: .main)

        XCTAssertEqual(first.verifiedKeyframeCount, 3)
        XCTAssertEqual(first.semanticPartNames.count, 11)
        XCTAssertEqual(first.rest.size.width, 1254, accuracy: 0.001)
        XCTAssertEqual(first.rest.size.height, 1254, accuracy: 0.001)
        XCTAssertEqual(first.blink.size, first.rest.size)
        XCTAssertEqual(first.celebrate.size, first.rest.size)
        XCTAssertTrue(first.rest === second.rest)
        XCTAssertTrue(first.blink === second.blink)
        XCTAssertTrue(first.celebrate === second.celebrate)
    }

    func testRestOnlyLoaderVerifiesAndCachesWithoutDecodingAnimationFrames() throws {
        let store = MascotRigAssetStore()

        let first = try store.restImage(level: 4, bundle: .main)
        let second = try store.restImage(level: 4, bundle: .main)

        XCTAssertEqual(first.size.width, 1254, accuracy: 0.001)
        XCTAssertEqual(first.size.height, 1254, accuracy: 0.001)
        XCTAssertTrue(first === second)
        XCTAssertEqual(store.cachedRestImageCount, 1)
        XCTAssertEqual(store.cachedRigImageSetCount, 0)
    }

    func testRestArtLoaderExposesFailureWithoutLegacyFallback() {
        let loader = MascotRestArtLoader(
            level: 3,
            loadImage: { _, _ in
                throw MascotRigAssetError.missingAsset("composite-rest")
            }
        )

        loader.load()

        XCTAssertNil(loader.image)
        XCTAssertFalse(loader.isLoading)
        XCTAssertEqual(
            loader.loadError,
            .missingAsset("composite-rest")
        )
    }

    func testSemanticFallbackLayersAreVerifiedAndCached() throws {
        let store = MascotRigAssetStore()

        let first = try store.fallbackLayers(level: 1, bundle: .main)
        let second = try store.fallbackLayers(level: 1, bundle: .main)

        XCTAssertEqual(first.count, 11)
        XCTAssertEqual(first.map(\.part), MascotRigSemanticPart.allCases)
        for (firstLayer, secondLayer) in zip(first, second) {
            XCTAssertTrue(firstLayer.image === secondLayer.image)
        }
    }

    func testAllSevenLevelsHaveDistinctExplicitKeyframesAndFallbacks() throws {
        let definitions = MascotRigLevelCatalog.definitions

        XCTAssertEqual(Array(definitions.keys).sorted(), Array(1...7))
        XCTAssertEqual(
            Set(definitions.values.map(\.rest.sha256)).count,
            7
        )
        XCTAssertEqual(
            Set(definitions.values.map(\.blink.sha256)).count,
            7
        )
        XCTAssertEqual(
            Set(definitions.values.map(\.celebrate.sha256)).count,
            7
        )
        for part in MascotRigSemanticPart.allCases {
            XCTAssertEqual(
                Set(
                    definitions.values.map {
                        $0.semanticParts[part]!.sha256
                    }
                ).count,
                7,
                "Every growth level needs a distinct \(part) fallback"
            )
        }

        let store = MascotRigAssetStore()
        for level in [1, 4, 7] {
            XCTAssertEqual(
                try store.images(level: level, bundle: .main)
                    .verifiedKeyframeCount,
                3
            )
            XCTAssertEqual(
                try store.fallbackLayers(level: level, bundle: .main).count,
                11
            )
        }
    }
}
