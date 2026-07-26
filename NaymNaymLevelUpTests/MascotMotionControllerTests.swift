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

    func testImageLoadingWorkerPropagatesCallerCancellation() async {
        let started = expectation(description: "detached work started")
        let task = Task {
            try await MascotImageLoadingWorker.run {
                started.fulfill()
                let deadline = Date().addingTimeInterval(0.25)
                while Date() < deadline {
                    try Task.checkCancellation()
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return false
            }
        }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelling the caller must cancel detached image work")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLatestActiveCacheRejectsAnAlreadyCancelledCaller() async throws {
        let cache = LatestActiveAssetCache<String, String>(
            maxCost: 100,
            costOf: { $0.utf8.count }
        )
        _ = try await cache.value(for: "level-1-rig") {
            "level-1"
        }
        let gate = AsyncTestGate()
        let counter = AsyncTestCounter()
        let waiting = expectation(description: "caller waiting")
        let task = Task { @MainActor in
            waiting.fulfill()
            await gate.wait()
            return try await cache.value(for: "level-4-rig") {
                await counter.increment()
                return "level-4"
            }
        }
        await fulfillment(of: [waiting], timeout: 1)

        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("An already cancelled caller must not mutate the cache")
        } catch is CancellationError {
            // Expected.
        }
        let loadCount = await counter.value
        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(cache.cachedKey, "level-1-rig")
        XCTAssertEqual(cache.cachedValue, "level-1")
    }

    func testLatestActiveCacheRejectsAnOlderOutOfOrderCompletion() async throws {
        let cache = LatestActiveAssetCache<String, String>(
            maxCost: 100,
            costOf: { $0.utf8.count }
        )
        let olderGate = AsyncTestGate()
        let newerGate = AsyncTestGate()
        let olderStarted = expectation(description: "older load started")
        let newerStarted = expectation(description: "newer load started")

        let olderTask = Task { @MainActor in
            try await cache.value(for: "level-1-rig") {
                olderStarted.fulfill()
                await olderGate.wait()
                return "older"
            }
        }
        await fulfillment(of: [olderStarted], timeout: 1)

        let newerTask = Task { @MainActor in
            try await cache.value(for: "level-4-rig") {
                newerStarted.fulfill()
                await newerGate.wait()
                return "newer"
            }
        }
        await fulfillment(of: [newerStarted], timeout: 1)

        await newerGate.open()
        let newerResult = try await newerTask.value
        XCTAssertEqual(newerResult, "newer")
        XCTAssertEqual(cache.cachedKey, "level-4-rig")

        await olderGate.open()
        let olderResult = try await olderTask.value
        XCTAssertEqual(olderResult, "older")
        XCTAssertEqual(cache.cachedKey, "level-4-rig")
        XCTAssertEqual(cache.cachedValue, "newer")
    }

    func testLatestActiveCacheCoalescesConcurrentSameKeyLoads() async throws {
        let cache = LatestActiveAssetCache<String, String>(
            maxCost: 100,
            costOf: { $0.utf8.count }
        )
        let gate = AsyncTestGate()
        let counter = AsyncTestCounter()
        let firstStarted = expectation(description: "first load started")
        let secondCallerEntered = expectation(
            description: "second caller entered"
        )

        let firstTask = Task { @MainActor in
            try await cache.value(for: "level-4-rig") {
                await counter.increment()
                firstStarted.fulfill()
                await gate.wait()
                return "shared"
            }
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        let secondTask = Task { @MainActor in
            secondCallerEntered.fulfill()
            return try await cache.value(for: "level-4-rig") {
                await counter.increment()
                return "duplicate"
            }
        }
        await fulfillment(of: [secondCallerEntered], timeout: 1)
        await gate.open()

        let firstResult = try await firstTask.value
        let secondResult = try await secondTask.value
        XCTAssertEqual(firstResult, "shared")
        XCTAssertEqual(secondResult, "shared")
        let loadCount = await counter.value
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(cache.cachedValue, "shared")
    }

    func testLatestActiveCacheCancelsAnOlderDifferentKeyLoad() async throws {
        let cache = LatestActiveAssetCache<String, String>(
            maxCost: 100,
            costOf: { $0.utf8.count }
        )
        let gate = AsyncTestGate()
        let olderStarted = expectation(description: "older load started")
        let olderCancelled = expectation(
            description: "older load cancelled"
        )

        let olderTask = Task { @MainActor in
            try await cache.value(for: "level-1-rig") {
                olderStarted.fulfill()
                return try await withTaskCancellationHandler {
                    await gate.wait()
                    try Task.checkCancellation()
                    return "older"
                } onCancel: {
                    olderCancelled.fulfill()
                }
            }
        }
        await fulfillment(of: [olderStarted], timeout: 1)

        let newer = try await cache.value(for: "level-4-rig") {
            "newer"
        }
        XCTAssertEqual(newer, "newer")
        await fulfillment(of: [olderCancelled], timeout: 1)

        await gate.open()
        do {
            _ = try await olderTask.value
            XCTFail("The superseded heavy load must be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertEqual(cache.cachedKey, "level-4-rig")
        XCTAssertEqual(cache.cachedValue, "newer")
    }

    func testRestLoaderTreatsCancellationAsSilent() async {
        let gate = AsyncTestGate()
        let started = expectation(description: "rest load started")
        let image = UIImage(
            color: .red,
            size: CGSize(width: 1, height: 1)
        )
        let loader = MascotRestArtLoader(
            loadImage: { _, _ in
                started.fulfill()
                await gate.wait()
                try Task.checkCancellation()
                return image
            }
        )
        let task = Task { @MainActor in
            await loader.load(level: 1)
        }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()
        await gate.open()
        await task.value

        XCTAssertNil(loader.image)
        XCTAssertNil(loader.loadedLevel)
        XCTAssertNil(loader.loadError)
        XCTAssertFalse(loader.isLoading)
    }

    func testRigLoaderDoesNotFallbackAfterCancellation() async {
        let gate = AsyncTestGate()
        let counter = AsyncTestCounter()
        let started = expectation(description: "rig load started")
        let image = UIImage(
            color: .green,
            size: CGSize(width: 1, height: 1)
        )
        let loader = MascotRigLoader(
            loadImages: { _, _ in
                started.fulfill()
                await gate.wait()
                try Task.checkCancellation()
                return MascotRigImages(
                    rest: image,
                    blink: image,
                    celebrate: image,
                    semanticPartNames: []
                )
            },
            loadFallbackLayers: { _, _ in
                await counter.increment()
                return [
                    MascotRigFallbackLayer(
                        part: .body,
                        image: image
                    ),
                ]
            }
        )
        let task = Task { @MainActor in
            await loader.load(level: 1)
        }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()
        await gate.open()
        await task.value

        let fallbackCount = await counter.value
        XCTAssertEqual(fallbackCount, 0)
        XCTAssertNil(loader.images)
        XCTAssertNil(loader.fallbackLayers)
        XCTAssertNil(loader.loadedLevel)
        XCTAssertNil(loader.loadError)
        XCTAssertFalse(loader.isLoading)
    }

    func testCancelledStaleRigLoadCannotReplaceTheNewActiveCacheKey() async {
        let cache = LatestActiveAssetCache<String, String>(
            maxCost: 100,
            costOf: { $0.utf8.count }
        )
        let levelOneGate = AsyncTestGate()
        let levelFourGate = AsyncTestGate()
        let fallbackCounter = AsyncTestCounter()
        let levelOneStarted = expectation(
            description: "level one rig started"
        )
        let levelFourStarted = expectation(
            description: "level four rig started"
        )
        let image = UIImage(
            color: .orange,
            size: CGSize(width: 1, height: 1)
        )
        let keyframes = MascotRigImages(
            rest: image,
            blink: image,
            celebrate: image,
            semanticPartNames: []
        )
        let loader = MascotRigLoader(
            loadImages: { level, _ in
                _ = try await cache.value(for: "rig-\(level)") {
                    if level == 1 {
                        levelOneStarted.fulfill()
                        await levelOneGate.wait()
                    } else {
                        levelFourStarted.fulfill()
                        await levelFourGate.wait()
                    }
                    try Task.checkCancellation()
                    return "rig-\(level)"
                }
                return keyframes
            },
            loadFallbackLayers: { level, _ in
                await fallbackCounter.increment()
                _ = try await cache.value(for: "fallback-\(level)") {
                    "fallback-\(level)"
                }
                return [
                    MascotRigFallbackLayer(
                        part: .body,
                        image: image
                    ),
                ]
            }
        )
        let staleTask = Task { @MainActor in
            await loader.load(level: 1)
        }
        await fulfillment(of: [levelOneStarted], timeout: 1)

        staleTask.cancel()
        let activeTask = Task { @MainActor in
            await loader.load(level: 4)
        }
        await fulfillment(of: [levelFourStarted], timeout: 1)

        await levelOneGate.open()
        await staleTask.value
        await levelFourGate.open()
        await activeTask.value

        let fallbackCount = await fallbackCounter.value
        XCTAssertEqual(fallbackCount, 0)
        XCTAssertEqual(cache.cachedKey, "rig-4")
        XCTAssertTrue(loader.renderedImages(for: 4) === keyframes)
        XCTAssertNil(loader.renderedFallbackLayers(for: 4))
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
        let rigDiagnostics = store.cacheDiagnostics()
        XCTAssertEqual(rigDiagnostics.rigLevels, [4])
        XCTAssertEqual(rigDiagnostics.fallbackLevels, [])
        XCTAssertGreaterThan(rigDiagnostics.heavyCost, 0)
        XCTAssertLessThanOrEqual(
            rigDiagnostics.heavyCost,
            20 * 1_024 * 1_024
        )

        _ = try await store.fallbackLayers(level: 1, bundle: .main)
        _ = try await store.fallbackLayers(level: 4, bundle: .main)
        let diagnostics = store.cacheDiagnostics()

        XCTAssertEqual(diagnostics.rigLevels, [])
        XCTAssertEqual(diagnostics.fallbackLevels, [4])
        XCTAssertGreaterThan(diagnostics.heavyCost, 0)
        XCTAssertLessThanOrEqual(
            diagnostics.heavyCost,
            12 * 1_024 * 1_024
        )
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

    func testRestLoaderDoesNotExposeAPreviousImageForANewRequestedLevel() async {
        let levelOne = UIImage(
            color: .red,
            size: CGSize(width: 1, height: 1)
        )
        let loader = MascotRestArtLoader(
            loadImage: { _, _ in levelOne }
        )
        await loader.load(level: 1)

        XCTAssertTrue(loader.renderedImage(for: 1) === levelOne)
        XCTAssertNil(loader.renderedImage(for: 4))
    }

    func testRigLoaderDoesNotExposePreviousKeyframesForANewRequestedLevel() async {
        let image = UIImage(
            color: .green,
            size: CGSize(width: 1, height: 1)
        )
        let keyframes = MascotRigImages(
            rest: image,
            blink: image,
            celebrate: image,
            semanticPartNames: []
        )
        let loader = MascotRigLoader(
            loadImages: { _, _ in keyframes },
            loadFallbackLayers: { _, _ in [] }
        )
        await loader.load(level: 1)

        XCTAssertTrue(loader.renderedImages(for: 1) === keyframes)
        XCTAssertNil(loader.renderedImages(for: 4))
    }

    func testRigLoaderDoesNotExposePreviousFallbackForANewRequestedLevel() async {
        let image = UIImage(
            color: .orange,
            size: CGSize(width: 1, height: 1)
        )
        let fallback = [
            MascotRigFallbackLayer(part: .body, image: image),
        ]
        let loader = MascotRigLoader(
            loadImages: { _, _ in
                throw MascotRigAssetError.missingAsset("rest")
            },
            loadFallbackLayers: { _, _ in fallback }
        )
        await loader.load(level: 1)

        XCTAssertEqual(
            loader.renderedFallbackLayers(for: 1)?.count,
            1
        )
        XCTAssertNil(loader.renderedFallbackLayers(for: 4))
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
            let cgImage = try XCTUnwrap(firstLayer.image.cgImage)
            XCTAssertLessThanOrEqual(cgImage.width, 512)
            XCTAssertLessThanOrEqual(cgImage.height, 512)
            XCTAssertEqual(cgImage.width, cgImage.height)
            XCTAssertTrue(
                [
                    CGImageAlphaInfo.first,
                    .last,
                    .premultipliedFirst,
                    .premultipliedLast,
                    .alphaOnly,
                ].contains(cgImage.alphaInfo),
                "\(firstLayer.part) must preserve alpha"
            )
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

private actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private actor AsyncTestCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
