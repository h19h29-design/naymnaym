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

    func testLevelOneApprovedAssetsAreVerifiedAndCached() async throws {
        let store = MascotRigAssetStore()

        let first = try await store.images(level: 1, bundle: .main)
        let second = try await store.images(level: 1, bundle: .main)

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

    func testRestOnlyLoaderVerifiesAndCachesWithoutDecodingAnimationFrames() async throws {
        let store = MascotRigAssetStore()

        let first = try await store.restThumbnail(
            level: 4,
            bundle: .main
        )
        let second = try await store.restThumbnail(
            level: 4,
            bundle: .main
        )
        let diagnostics = store.cacheDiagnostics()

        XCTAssertLessThanOrEqual(first.size.width, 256)
        XCTAssertLessThanOrEqual(first.size.height, 256)
        XCTAssertTrue(first === second)
        XCTAssertEqual(diagnostics.restLevels, [4])
        XCTAssertEqual(diagnostics.rigLevels, [])
    }

    func testRestThumbnailIsDownsampledAndEvictsByByteCost() async throws {
        let store = MascotRigAssetStore(restCacheCostLimit: 300_000)

        let first = try await store.restThumbnail(
            level: 1,
            bundle: .main
        )
        let cached = try await store.restThumbnail(
            level: 1,
            bundle: .main
        )
        XCTAssertTrue(first === cached)
        XCTAssertLessThanOrEqual(first.cgImage?.width ?? .max, 256)
        XCTAssertLessThanOrEqual(first.cgImage?.height ?? .max, 256)

        _ = try await store.restThumbnail(level: 4, bundle: .main)
        let diagnostics = store.cacheDiagnostics()

        XCTAssertEqual(diagnostics.restLevels, [4])
        XCTAssertLessThanOrEqual(diagnostics.restCost, 300_000)
        XCTAssertEqual(diagnostics.rigLevels, [])
    }

    func testImageLoadingWorkerRunsOutsideTheMainThread() async throws {
        let ranOnMainThread = try await MascotImageLoadingWorker.run {
            Thread.isMainThread
        }

        XCTAssertFalse(ranOnMainThread)
    }

    func testFullRigAndFallbackCachesKeepOnlyTheActiveLevel() async throws {
        let store = MascotRigAssetStore()

        let levelOne = try await store.images(level: 1, bundle: .main)
        let cachedLevelOne = try await store.images(
            level: 1,
            bundle: .main
        )
        XCTAssertTrue(levelOne.rest === cachedLevelOne.rest)

        _ = try await store.images(level: 4, bundle: .main)
        _ = try await store.fallbackLayers(level: 1, bundle: .main)
        _ = try await store.fallbackLayers(level: 4, bundle: .main)
        let diagnostics = store.cacheDiagnostics()

        XCTAssertEqual(diagnostics.rigLevels, [4])
        XCTAssertEqual(diagnostics.fallbackLevels, [4])
    }

    func testRestArtLoaderExposesFailureWithoutLegacyFallback() async {
        let loader = MascotRestArtLoader(
            loadImage: { _, _ in
                throw MascotRigAssetError.missingAsset("composite-rest")
            }
        )

        await loader.load(level: 3)

        XCTAssertNil(loader.image)
        XCTAssertFalse(loader.isLoading)
        XCTAssertEqual(
            loader.loadError,
            .missingAsset("composite-rest")
        )
        XCTAssertTrue(loader.canRetry)
    }

    func testRestArtLoaderSwitchesToTheLatestRequestedLevel() async {
        let levelOne = UIImage(
            color: .red,
            size: CGSize(width: 1, height: 1)
        )
        let levelFour = UIImage(
            color: .green,
            size: CGSize(width: 1, height: 1)
        )
        var requestedLevels: [Int] = []
        let loader = MascotRestArtLoader(
            loadImage: { level, _ in
                requestedLevels.append(level)
                return level == 1 ? levelOne : levelFour
            }
        )

        await loader.load(level: 1)
        XCTAssertTrue(loader.image === levelOne)

        await loader.load(level: 4)

        XCTAssertEqual(requestedLevels, [1, 4])
        XCTAssertEqual(loader.loadedLevel, 4)
        XCTAssertTrue(loader.image === levelFour)
    }

    func testRigLoaderUsesVerifiedSemanticFallbackAfterKeyframeFailure() async {
        let fallbackImage = UIImage(
            color: .orange,
            size: CGSize(width: 1, height: 1)
        )
        let loader = MascotRigLoader(
            loadImages: { _, _ in
                throw MascotRigAssetError.checksumMismatch("composite-rest")
            },
            loadFallbackLayers: { _, _ in
                [
                    MascotRigFallbackLayer(
                        part: .body,
                        image: fallbackImage
                    ),
                ]
            }
        )

        await loader.load(level: 2)

        XCTAssertNil(loader.images)
        XCTAssertEqual(loader.fallbackLayers?.map(\.part), [.body])
        XCTAssertTrue(loader.fallbackLayers?.first?.image === fallbackImage)
        XCTAssertNil(loader.loadError)
        XCTAssertEqual(loader.loadedLevel, 2)
    }

    func testRigLoaderExposesRetryAfterAllVerifiedAssetsFail() async {
        let loader = MascotRigLoader(
            loadImages: { _, _ in
                throw MascotRigAssetError.checksumMismatch("composite-rest")
            },
            loadFallbackLayers: { _, _ in
                throw MascotRigAssetError.missingAsset("body")
            }
        )

        await loader.load(level: 5)

        XCTAssertNil(loader.images)
        XCTAssertNil(loader.fallbackLayers)
        XCTAssertEqual(loader.loadError, .missingAsset("body"))
        XCTAssertTrue(loader.canRetry)
    }

    func testSemanticFallbackLayersAreVerifiedAndCached() async throws {
        let store = MascotRigAssetStore()

        let first = try await store.fallbackLayers(
            level: 1,
            bundle: .main
        )
        let second = try await store.fallbackLayers(
            level: 1,
            bundle: .main
        )

        XCTAssertEqual(first.count, 11)
        XCTAssertEqual(first.map(\.part), MascotRigSemanticPart.allCases)
        for (firstLayer, secondLayer) in zip(first, second) {
            XCTAssertTrue(firstLayer.image === secondLayer.image)
        }
    }

    func testAllSevenLevelsHaveDistinctExplicitKeyframesAndFallbacks() async throws {
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
            let images = try await store.images(
                level: level,
                bundle: .main
            )
            let fallbackLayers = try await store.fallbackLayers(
                level: level,
                bundle: .main
            )
            XCTAssertEqual(
                images.verifiedKeyframeCount,
                3
            )
            XCTAssertEqual(
                fallbackLayers.count,
                11
            )
        }
    }
}

private extension UIImage {
    convenience init(color: UIColor, size: CGSize) {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        self.init(cgImage: image.cgImage!)
    }
}
