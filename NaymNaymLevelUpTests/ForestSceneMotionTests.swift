import XCTest
@testable import NaymNaymLevelUp

final class ForestSceneMotionTests: XCTestCase {
    func testLayerOrderKeepsEveryDecorativePlaneBelowContent() {
        XCTAssertEqual(
            ForestSceneLayer.allCases,
            [.sky, .distantTrees, .midgroundTrees, .foregroundLeaves, .ground]
        )
        XCTAssertTrue(
            ForestSceneLayer.allCases.allSatisfy {
                $0.zIndex < ForestSceneLayer.contentZIndex
            }
        )
    }

    func testEightSecondTriangleCycleUsesSharedDepthOffsets() {
        let samples: [(TimeInterval, CGFloat)] = [
            (0, 0),
            (2, 0.5),
            (4, 1),
            (6, 0.5),
            (8, 0),
        ]

        for (elapsed, progress) in samples {
            let frame = ForestSceneMotionSpec.frame(
                elapsed: elapsed,
                reduceMotion: false
            )
            XCTAssertEqual(frame.progress, progress, accuracy: 0.0001)
            XCTAssertEqual(
                frame[.distantTrees].y,
                -2 * progress,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                frame[.midgroundTrees].y,
                -4 * progress,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                frame[.foregroundLeaves].x,
                6 * progress,
                accuracy: 0.0001
            )
            XCTAssertEqual(
                frame[.foregroundLeaves].y,
                -3 * progress,
                accuracy: 0.0001
            )
            XCTAssertEqual(frame[.ground], .zero)
        }
    }

    func testReduceMotionProducesZeroTransformsAndNoFrameCallback() {
        let frame = ForestSceneMotionSpec.frame(
            elapsed: 4,
            reduceMotion: true
        )

        XCTAssertEqual(frame.progress, 0)
        for layer in ForestSceneLayer.allCases {
            XCTAssertEqual(frame[layer], .zero)
        }
        XCTAssertFalse(
            ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion: true,
                activity: .active
            )
        )
    }

    func testSheetTabAndAppPauseSourcesFreezeThenResumeWithoutJump() {
        var clock = ForestSceneMotionClock(startTime: 0)

        XCTAssertEqual(clock.elapsed(at: 1), 1, accuracy: 0.0001)

        clock.update(
            activity: ForestSceneActivity(
                isSheetPresented: true,
                isTabActive: true,
                isAppActive: true
            ),
            at: 1
        )
        XCTAssertEqual(clock.elapsed(at: 5), 1, accuracy: 0.0001)

        clock.update(activity: .active, at: 5)
        XCTAssertEqual(clock.elapsed(at: 6), 2, accuracy: 0.0001)

        clock.update(
            activity: ForestSceneActivity(
                isSheetPresented: false,
                isTabActive: false,
                isAppActive: true
            ),
            at: 6
        )
        XCTAssertEqual(clock.elapsed(at: 9), 2, accuracy: 0.0001)

        clock.update(activity: .active, at: 9)
        clock.update(
            activity: ForestSceneActivity(
                isSheetPresented: false,
                isTabActive: true,
                isAppActive: false
            ),
            at: 10
        )
        XCTAssertEqual(clock.elapsed(at: 14), 3, accuracy: 0.0001)

        XCTAssertFalse(
            ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion: false,
                activity: ForestSceneActivity(
                    isSheetPresented: false,
                    isTabActive: true,
                    isAppActive: false
                )
            )
        )
        XCTAssertTrue(
            ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion: false,
                activity: .active
            )
        )
    }
}
