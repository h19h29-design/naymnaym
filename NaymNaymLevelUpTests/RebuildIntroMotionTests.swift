import XCTest
import Foundation
import CryptoKit
import SwiftUI
import UIKit
@testable import NaymNaymLevelUp

@MainActor
final class RebuildIntroMotionTests: XCTestCase {
    func testNormalMotionUsesApprovedBoundaryFramesAndBecomesExactlyStatic() {
        let initial = RebuildIntroMotionSpec.frame(at: 0, reduceMotion: false)
        XCTAssertEqual(initial.leftWord.opacity, 0, accuracy: 0.000_001)
        XCTAssertEqual(initial.leftWord.translationY, 10, accuracy: 0.000_001)
        XCTAssertEqual(initial.leftWord.scale, 0.988, accuracy: 0.000_001)
        XCTAssertEqual(initial.rightWord, initial.leftWord)
        XCTAssertNil(initial.shineProgress)
        XCTAssertFalse(initial.rendersWholeLogo)

        let leftStart = RebuildIntroMotionSpec.frame(at: 0.04, reduceMotion: false)
        XCTAssertEqual(leftStart.leftWord, initial.leftWord)
        XCTAssertEqual(leftStart.rightWord, initial.rightWord)

        let rightStart = RebuildIntroMotionSpec.frame(at: 0.34, reduceMotion: false)
        XCTAssertGreaterThan(rightStart.leftWord.opacity, 0)
        XCTAssertLessThan(rightStart.leftWord.translationY, 10)
        XCTAssertEqual(rightStart.rightWord, initial.rightWord)

        let leftMiddle = RebuildIntroMotionSpec.frame(
            at: 0.42,
            reduceMotion: false
        )
        XCTAssertEqual(
            leftMiddle.leftWord.opacity,
            0.911_465,
            accuracy: 0.000_01
        )

        let leftEnd = RebuildIntroMotionSpec.frame(at: 0.80, reduceMotion: false)
        XCTAssertEqual(leftEnd.leftWord, .visible)
        XCTAssertNotEqual(leftEnd.rightWord, .visible)

        let rightEnd = RebuildIntroMotionSpec.frame(at: 1.10, reduceMotion: false)
        XCTAssertEqual(rightEnd.leftWord, .visible)
        XCTAssertEqual(rightEnd.rightWord, .visible)
        XCTAssertNil(rightEnd.shineProgress)

        let shineStart = RebuildIntroMotionSpec.frame(at: 1.18, reduceMotion: false)
        XCTAssertEqual(shineStart.shineProgress, 0)
        XCTAssertFalse(shineStart.rendersWholeLogo)

        let shineMiddle = RebuildIntroMotionSpec.frame(at: 1.59, reduceMotion: false)
        XCTAssertEqual(shineMiddle.shineProgress ?? -1, 0.5, accuracy: 0.000_001)

        let final = RebuildIntroMotionSpec.frame(at: 2.00, reduceMotion: false)
        XCTAssertEqual(final.leftWord, .visible)
        XCTAssertEqual(final.rightWord, .visible)
        XCTAssertEqual(final.wholeLogoOpacity, 1, accuracy: 0.000_001)
        XCTAssertNil(final.shineProgress)
        XCTAssertTrue(final.rendersWholeLogo)
        XCTAssertEqual(
            final,
            RebuildIntroMotionSpec.frame(at: 2.50, reduceMotion: false)
        )
        XCTAssertEqual(
            final,
            RebuildIntroMotionSpec.frame(at: 200, reduceMotion: false)
        )
    }

    func testNormalMotionContractKeepsComplementarySplitInsideTransparentGap() {
        XCTAssertEqual(RebuildIntroMotionSpec.splitFraction, 0.40, accuracy: 0.000_001)
        XCTAssertEqual(RebuildIntroMotionSpec.leftStart, 0.04, accuracy: 0.000_001)
        XCTAssertEqual(RebuildIntroMotionSpec.rightStart, 0.34, accuracy: 0.000_001)
        XCTAssertEqual(RebuildIntroMotionSpec.riseDuration, 0.76, accuracy: 0.000_001)
        XCTAssertEqual(RebuildIntroMotionSpec.shineStart, 1.18, accuracy: 0.000_001)
        XCTAssertEqual(RebuildIntroMotionSpec.shineDuration, 0.82, accuracy: 0.000_001)

        let layout = RebuildIntroMaskLayout(sourceWidth: 357)
        XCTAssertEqual(layout.left.lowerBound, 0, accuracy: 0.000_001)
        XCTAssertEqual(layout.left.upperBound, layout.right.lowerBound, accuracy: 0.000_001)
        XCTAssertEqual(layout.right.upperBound, 357, accuracy: 0.000_001)
        XCTAssertGreaterThan(layout.left.upperBound, 139)
        XCTAssertLessThan(layout.left.upperBound, 146)
    }

    func testReduceMotionUsesOnlyWholeLogoQuarterSecondFade() {
        let initial = RebuildIntroMotionSpec.frame(at: 0, reduceMotion: true)
        XCTAssertEqual(initial.wholeLogoOpacity, 0, accuracy: 0.000_001)
        XCTAssertEqual(initial.leftWord, .visible)
        XCTAssertEqual(initial.rightWord, .visible)
        XCTAssertNil(initial.shineProgress)
        XCTAssertTrue(initial.rendersWholeLogo)

        let middle = RebuildIntroMotionSpec.frame(at: 0.125, reduceMotion: true)
        XCTAssertEqual(middle.wholeLogoOpacity, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(middle.leftWord.translationY, 0, accuracy: 0.000_001)
        XCTAssertEqual(middle.rightWord.translationY, 0, accuracy: 0.000_001)
        XCTAssertEqual(middle.leftWord.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(middle.rightWord.scale, 1, accuracy: 0.000_001)
        XCTAssertNil(middle.shineProgress)

        let final = RebuildIntroMotionSpec.frame(at: 0.25, reduceMotion: true)
        XCTAssertEqual(final.wholeLogoOpacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(
            final,
            RebuildIntroMotionSpec.frame(at: 2.50, reduceMotion: true)
        )
    }

    func testSecondStartCannotResetSequenceAndCancellationBlocksLateCompletion() async {
        let sleepStarted = expectation(description: "first sleep started")
        sleepStarted.expectedFulfillmentCount = 1
        let gate = RebuildIntroSleepGate()
        var completions = 0
        let controller = RebuildIntroMotionController { _ in
            sleepStarted.fulfill()
            try await gate.wait()
        }

        XCTAssertTrue(
            controller.start(reduceMotion: false) {
                completions += 1
            }
        )
        XCTAssertEqual(controller.effectiveReduceMotion, false)
        await fulfillment(of: [sleepStarted], timeout: 1)
        let firstElapsed = controller.elapsed

        XCTAssertFalse(
            controller.start(reduceMotion: true) {
                completions += 100
            }
        )
        XCTAssertEqual(controller.effectiveReduceMotion, false)
        XCTAssertEqual(controller.elapsed, firstElapsed, accuracy: 0.000_001)

        controller.cancel()
        await gate.resume()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(controller.elapsed, firstElapsed, accuracy: 0.000_001)
        XCTAssertFalse(controller.isComplete)
        XCTAssertEqual(completions, 0)
    }

    func testPresentationLatchesReducedMotionInBothToggleDirections() {
        let normal = RebuildIntroMotionController { _ in }
        XCTAssertTrue(normal.start(reduceMotion: false) {})
        XCTAssertFalse(normal.start(reduceMotion: true) {})
        XCTAssertEqual(normal.effectiveReduceMotion, false)
        normal.cancel()

        let reduced = RebuildIntroMotionController { _ in }
        XCTAssertTrue(reduced.start(reduceMotion: true) {})
        XCTAssertFalse(reduced.start(reduceMotion: false) {})
        XCTAssertEqual(reduced.effectiveReduceMotion, true)
        reduced.cancel()
    }

    func testBundledLogoMatchesExactPixelAndSourceFileContract() throws {
        let image = try XCTUnwrap(UIImage(named: "logo_naym_levelup"))
        let pixels = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(pixels.width, 357)
        XCTAssertEqual(pixels.height, 86)

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("NaymNaymLevelUp")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("logo_naym_levelup.imageset")
            .appendingPathComponent("logo_naym_levelup.png")
        let source = try Data(contentsOf: sourceURL)
        XCTAssertEqual(source.pngHeaderContract, .rgba(width: 357, height: 86))
        XCTAssertEqual(
            SHA256.hash(data: source).hexString,
            "0132e9075a8a3953cc87ae43154be317fb846630ea5e1f7dfbced8fb0860120b"
        )
    }

    func testComplementarySplitRenderMatchesWholeLogoAtSupportedWidths() throws {
        let split = RebuildIntroMotionSpec.frame(
            at: 1.10,
            reduceMotion: false
        )
        let whole = RebuildIntroMotionSpec.frame(
            at: 2.00,
            reduceMotion: false
        )

        for width in [272.0, 345.0, 357.0] {
            let splitImage = try renderLogo(frame: split, width: width)
            let wholeImage = try renderLogo(frame: whole, width: width)
            XCTAssertEqual(splitImage.width, wholeImage.width)
            XCTAssertEqual(splitImage.height, wholeImage.height)
            XCTAssertEqual(
                splitImage.dataProvider?.data as Data?,
                wholeImage.dataProvider?.data as Data?,
                "Split mask changed source pixels at canvas width \(width)"
            )
        }
    }

    func testDailyGateWritesOnlyOnCompletionAndRefreshesAcrossLocalMidnight() async throws {
        let suiteName = "RebuildIntroMotionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let beforeMidnight = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        ).addingTimeInterval(23 * 60 * 60)
        let afterMidnight = beforeMidnight.addingTimeInterval(2 * 60 * 60)
        let gate = RebuildIntroDailyGate(
            defaults: defaults,
            now: { beforeMidnight }
        )

        XCTAssertTrue(gate.shouldPresent)
        XCTAssertNil(defaults.string(forKey: RebuildIntroDailyGate.storageKey))

        let didComplete = await gate.markCompleted(at: beforeMidnight)
        XCTAssertTrue(didComplete)
        XCTAssertFalse(gate.shouldPresent)
        XCTAssertEqual(
            defaults.string(forKey: RebuildIntroDailyGate.storageKey),
            DateUtils.apiString(from: beforeMidnight)
        )

        gate.refresh(at: afterMidnight)
        XCTAssertTrue(gate.shouldPresent)
        XCTAssertNotEqual(
            defaults.string(forKey: RebuildIntroDailyGate.storageKey),
            DateUtils.apiString(from: afterMidnight)
        )
    }

    func testDailyGateTreatsMissingAndMalformedValuesAsUnseen() throws {
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let missing = RebuildIntroDateStoreStub(value: nil)
        let missingGate = RebuildIntroDailyGate(
            store: missing,
            now: { date }
        )
        XCTAssertTrue(missingGate.shouldPresent)
        XCTAssertEqual(missingGate.entryPhase, .intro)

        let malformed = RebuildIntroDateStoreStub(value: "July 26")
        let malformedGate = RebuildIntroDailyGate(
            store: malformed,
            now: { date }
        )
        XCTAssertTrue(malformedGate.shouldPresent)
        XCTAssertEqual(malformedGate.entryPhase, .intro)
    }

    func testDailyGateReevaluatesInjectedLocalTimeZoneAfterTravel() async throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-26T16:30:00Z")
        )
        let store = RebuildIntroDateStoreStub(value: nil)
        var timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let gate = RebuildIntroDailyGate(
            store: store,
            now: { instant },
            dayKey: {
                RebuildIntroLocalDay.key(for: $0, timeZone: timeZone)
            }
        )

        let didCompleteBeforeTravel = await gate.markCompleted()
        XCTAssertTrue(didCompleteBeforeTravel)
        XCTAssertEqual(store.value, "20260726")
        XCTAssertFalse(gate.shouldPresent)

        timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        gate.refresh()

        XCTAssertTrue(gate.shouldPresent)
        let didCompleteAfterTravel = await gate.markCompleted()
        XCTAssertTrue(didCompleteAfterTravel)
        XCTAssertEqual(store.value, "20260727")
    }

    func testFailedDailyWriteKeepsIntroActiveAndBlocksBootstrap() async throws {
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let store = RebuildIntroDateStoreStub(
            value: nil,
            acceptsWrites: false
        )
        let gate = RebuildIntroDailyGate(store: store, now: { date })

        let failedCompletion = await gate.markCompleted(at: date)
        XCTAssertFalse(failedCompletion)

        XCTAssertTrue(gate.shouldPresent)
        XCTAssertEqual(gate.entryPhase, .intro)
        XCTAssertNil(store.value)

        store.acceptsWrites = true
        let retryCompletion = await gate.markCompleted(at: date)
        XCTAssertTrue(retryCompletion)
        XCTAssertEqual(gate.entryPhase, .bootstrap)
        XCTAssertEqual(store.value, "20260726")
    }

    func testSuccessfulDailyWriteMovesEntryFromIntroToBootstrap() async throws {
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let store = RebuildIntroDateStoreStub(value: nil)
        let gate = RebuildIntroDailyGate(store: store, now: { date })
        XCTAssertEqual(gate.entryPhase, .intro)

        let didComplete = await gate.markCompleted(at: date)
        XCTAssertTrue(didComplete)

        XCTAssertEqual(gate.entryPhase, .bootstrap)
        XCTAssertEqual(store.value, "20260726")
    }

    func testCompletedTodayDeepLinkRoutesWithoutRewritingOrReopeningIntro() async throws {
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let store = RebuildIntroDateStoreStub(value: "20260726")
        let gate = RebuildIntroDailyGate(store: store, now: { date })
        var didApplyDismissal = false

        XCTAssertFalse(gate.shouldPresent)
        let route = await RebuildIntroDeepLinkCoordinator.resolve(
            url: URL(string: "naymnaym://invite")!,
            resolver: { _ in .parentSummary },
            persistIntroCompletion: {
                await gate.markCompleted()
            },
            applyIntroCompletion: {
                didApplyDismissal = true
            }
        )

        XCTAssertEqual(route, .parentSummary)
        XCTAssertTrue(didApplyDismissal)
        XCTAssertFalse(gate.shouldPresent)
        XCTAssertEqual(store.writeCount, 0)
    }

    func testProductionStoreSynchronizesOffMainAndRollsBackFailedWrite() async throws {
        let suiteName = "RebuildIntroDurableStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let successThread = RebuildIntroThreadObservation()
        let successPublicValues = RebuildIntroStringObservation()
        let successStore = UserDefaultsRebuildIntroDateStore(
            defaults: defaults,
            queue: DispatchQueue(label: "\(suiteName).success"),
            synchronize: { defaults in
                successThread.recordCurrentThread()
                successPublicValues.record(
                    defaults.string(
                        forKey: RebuildIntroDailyGate.storageKey
                    )
                )
                return defaults.synchronize()
            }
        )

        let didWrite = await successStore.writeDurably("20260726")
        XCTAssertTrue(didWrite)
        XCTAssertEqual(successStore.read(), "20260726")
        XCTAssertEqual(successThread.wasMainThread, false)
        XCTAssertEqual(successPublicValues.values, [nil])

        defaults.set(
            "20260725",
            forKey: RebuildIntroDailyGate.storageKey
        )
        XCTAssertTrue(defaults.synchronize())
        let failureThread = RebuildIntroThreadObservation()
        let failurePublicValues = RebuildIntroStringObservation()
        let failureStore = UserDefaultsRebuildIntroDateStore(
            defaults: defaults,
            queue: DispatchQueue(label: "\(suiteName).failure"),
            synchronize: { defaults in
                failureThread.recordCurrentThread()
                failurePublicValues.record(
                    defaults.string(
                        forKey: RebuildIntroDailyGate.storageKey
                    )
                )
                return false
            }
        )

        let didFail = await failureStore.writeDurably("20260727")
        XCTAssertFalse(didFail)
        XCTAssertEqual(failureStore.read(), "20260725")
        XCTAssertEqual(failureThread.wasMainThread, false)
        XCTAssertFalse(failurePublicValues.values.isEmpty)
        XCTAssertTrue(
            failurePublicValues.values.allSatisfy {
                $0 == "20260725"
            }
        )
    }

    func testPublicIntroDateAndRoutingWaitForDurableSuccess() async throws {
        let suiteName = "RebuildIntroVisibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "20260725",
            forKey: RebuildIntroDailyGate.storageKey
        )
        XCTAssertTrue(defaults.synchronize())
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let synchronizer = RebuildIntroBlockingSynchronizer(
            entered: expectation(description: "durable sync entered")
        )
        let store = UserDefaultsRebuildIntroDateStore(
            defaults: defaults,
            queue: DispatchQueue(label: "\(suiteName).visibility"),
            synchronize: { defaults in
                synchronizer.synchronize(defaults)
            }
        )
        let gate = RebuildIntroDailyGate(store: store, now: { date })
        var didApplyDismissal = false

        let deepLink = Task {
            await RebuildIntroDeepLinkCoordinator.resolve(
                url: URL(string: "naymnaym://invite")!,
                resolver: { _ in .parentSummary },
                persistIntroCompletion: {
                    await gate.markCompleted()
                },
                applyIntroCompletion: {
                    didApplyDismissal = true
                }
            )
        }
        await fulfillment(of: [synchronizer.entered], timeout: 1)

        XCTAssertEqual(
            defaults.string(forKey: RebuildIntroDailyGate.storageKey),
            "20260725"
        )
        XCTAssertTrue(gate.shouldPresent)
        XCTAssertFalse(didApplyDismissal)
        let concurrentDefaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        let concurrentStore = UserDefaultsRebuildIntroDateStore(
            defaults: concurrentDefaults
        )
        let concurrentGate = RebuildIntroDailyGate(
            store: concurrentStore,
            now: { date }
        )
        XCTAssertTrue(concurrentGate.shouldPresent)

        synchronizer.resume()
        let route = await deepLink.value
        XCTAssertEqual(route, .parentSummary)
        XCTAssertEqual(
            defaults.string(forKey: RebuildIntroDailyGate.storageKey),
            "20260726"
        )
        XCTAssertFalse(gate.shouldPresent)
        XCTAssertTrue(didApplyDismissal)

        defaults.set(
            "20260725",
            forKey: RebuildIntroDailyGate.storageKey
        )
        let recoveredStore = UserDefaultsRebuildIntroDateStore(
            defaults: defaults
        )
        XCTAssertEqual(recoveredStore.read(), "20260726")
        XCTAssertEqual(
            defaults.string(forKey: RebuildIntroDailyGate.storageKey),
            "20260726"
        )
    }

    func testCompletionAttemptsCannotOverlapAndRetryCanSucceed() async {
        let firstAttemptStarted = expectation(
            description: "first completion attempt started"
        )
        let firstAttemptGate = RebuildIntroBoolGate()
        let controller = RebuildIntroCompletionController()
        var attempts = 0

        XCTAssertTrue(
            controller.attempt {
                attempts += 1
                firstAttemptStarted.fulfill()
                return await firstAttemptGate.wait()
            }
        )
        await fulfillment(of: [firstAttemptStarted], timeout: 1)
        XCTAssertTrue(controller.isAttemptInFlight)
        XCTAssertFalse(
            controller.attempt {
                attempts += 100
                return true
            }
        )
        XCTAssertEqual(attempts, 1)

        await firstAttemptGate.resume(returning: false)
        await controller.waitUntilSettled()
        XCTAssertFalse(controller.isAttemptInFlight)
        XCTAssertTrue(controller.completionFailed)

        XCTAssertTrue(
            controller.attempt {
                attempts += 1
                return true
            }
        )
        await controller.waitUntilSettled()
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(controller.completionFailed)
    }

    func testInFlightRefreshCannotConsumePendingValueAndRolloverBlocksCompletion() async throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-26T16:30:00Z")
        )
        var timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let writeStarted = expectation(description: "durable write started")
        let store = RebuildIntroDelayedDateStore(writeStarted: writeStarted)
        let gate = RebuildIntroDailyGate(
            store: store,
            now: { instant },
            dayKey: {
                RebuildIntroLocalDay.key(for: $0, timeZone: timeZone)
            }
        )

        let completion = Task {
            await gate.markCompleted()
        }
        await fulfillment(of: [writeStarted], timeout: 1)
        XCTAssertEqual(store.read(), "20260726")

        gate.refresh()
        XCTAssertTrue(gate.shouldPresent)

        timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        gate.refresh()
        await store.finish(returning: true)

        let didComplete = await completion.value
        XCTAssertFalse(didComplete)
        XCTAssertTrue(gate.shouldPresent)
        XCTAssertEqual(store.read(), "20260726")
    }

    func testDeepLinkMarksIntroOnlyAfterRouteResolutionSucceeds() async {
        var events: [String] = []
        let invalid = await RebuildIntroDeepLinkCoordinator.resolve(
            url: URL(string: "naymnaym://invalid")!,
            resolver: { _ in
                events.append("resolve-invalid")
                return nil
            },
            persistIntroCompletion: {
                events.append("persist-invalid")
                return true
            },
            applyIntroCompletion: {
                events.append("apply-invalid")
            }
        )
        XCTAssertNil(invalid)
        XCTAssertEqual(events, ["resolve-invalid"])

        events = []
        let valid = await RebuildIntroDeepLinkCoordinator.resolve(
            url: URL(string: "naymnaym://invite")!,
            resolver: { _ in
                events.append("resolve")
                return .parentSummary
            },
            persistIntroCompletion: {
                events.append("persist")
                return true
            },
            applyIntroCompletion: {
                events.append("apply")
            }
        )
        XCTAssertEqual(valid, .parentSummary)
        XCTAssertEqual(events, ["resolve", "persist", "apply"])
    }

    func testDeepLinkStorageFailureStopsBeforeDismissalAndRouting() async {
        var events: [String] = []
        var introDismissed = false
        var legacyDateWritten = false
        let route = await RebuildIntroDeepLinkCoordinator.resolve(
            url: URL(string: "naymnaym://invite")!,
            resolver: { _ in
                events.append("resolve")
                return .parentSummary
            },
            persistIntroCompletion: { () async -> Bool in
                events.append("persist")
                return false
            },
            applyIntroCompletion: {
                introDismissed = true
                legacyDateWritten = true
                events.append("apply")
            }
        )

        if route != nil {
            events.append("route")
        }

        XCTAssertNil(route)
        XCTAssertFalse(introDismissed)
        XCTAssertFalse(legacyDateWritten)
        XCTAssertEqual(events, ["resolve", "persist"])
    }

    func testValidDeepLinkCoalescesWithInFlightCompletionAndStillRoutes() async throws {
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let writeStarted = expectation(description: "durable write started")
        let persistenceJoined = expectation(
            description: "deep link joined persistence"
        )
        let store = RebuildIntroDelayedDateStore(writeStarted: writeStarted)
        let gate = RebuildIntroDailyGate(store: store, now: { date })
        var didApplyIntroCompletion = false

        let automaticCompletion = Task {
            await gate.markCompleted()
        }
        await fulfillment(of: [writeStarted], timeout: 1)

        let deepLink = Task {
            await RebuildIntroDeepLinkCoordinator.resolve(
                url: URL(string: "naymnaym://invite")!,
                resolver: { _ in .parentSummary },
                persistIntroCompletion: {
                    persistenceJoined.fulfill()
                    return await gate.markCompleted()
                },
                applyIntroCompletion: {
                    didApplyIntroCompletion = true
                }
            )
        }
        await fulfillment(of: [persistenceJoined], timeout: 1)
        XCTAssertEqual(store.writeCount, 1)
        XCTAssertFalse(didApplyIntroCompletion)

        await store.finish(returning: true)
        let didComplete = await automaticCompletion.value
        let route = await deepLink.value

        XCTAssertTrue(didComplete)
        XCTAssertEqual(route, .parentSummary)
        XCTAssertTrue(didApplyIntroCompletion)
        XCTAssertEqual(store.writeCount, 1)
    }

    func testRolloverDeepLinkPersistsCurrentDayAfterStaleWrite() async throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-26T16:30:00Z")
        )
        var timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let store = RebuildIntroRolloverDateStore(
            firstWriteStarted: expectation(
                description: "previous-day write started"
            ),
            secondWriteStarted: expectation(
                description: "current-day write started"
            )
        )
        let gate = RebuildIntroDailyGate(
            store: store,
            now: { instant },
            dayKey: {
                RebuildIntroLocalDay.key(for: $0, timeZone: timeZone)
            }
        )
        let deepLinkRequested = expectation(
            description: "deep link requested persistence"
        )
        let secondDeepLinkRequested = expectation(
            description: "second deep link requested persistence"
        )
        var dismissalCount = 0

        let automaticCompletion = Task {
            await gate.markCompleted()
        }
        await fulfillment(of: [store.firstWriteStarted], timeout: 1)

        timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        gate.refresh()
        let deepLink = Task {
            await RebuildIntroDeepLinkCoordinator.resolve(
                url: URL(string: "naymnaym://invite")!,
                resolver: { _ in .parentSummary },
                persistIntroCompletion: {
                    deepLinkRequested.fulfill()
                    return await gate.markCompleted()
                },
                applyIntroCompletion: {
                    dismissalCount += 1
                }
            )
        }
        let secondDeepLink = Task {
            await RebuildIntroDeepLinkCoordinator.resolve(
                url: URL(string: "naymnaym://invite")!,
                resolver: { _ in .parentSummary },
                persistIntroCompletion: {
                    secondDeepLinkRequested.fulfill()
                    return await gate.markCompleted()
                },
                applyIntroCompletion: {
                    dismissalCount += 1
                }
            )
        }
        await fulfillment(
            of: [deepLinkRequested, secondDeepLinkRequested],
            timeout: 1
        )
        XCTAssertEqual(store.writeCount, 1)

        await store.finishFirstWrite(returning: true)
        await fulfillment(of: [store.secondWriteStarted], timeout: 1)
        let staleResult = await automaticCompletion.value
        let route = await deepLink.value
        let secondRoute = await secondDeepLink.value

        XCTAssertFalse(staleResult)
        XCTAssertEqual(route, .parentSummary)
        XCTAssertEqual(secondRoute, .parentSummary)
        XCTAssertEqual(dismissalCount, 2)
        XCTAssertFalse(gate.shouldPresent)
        XCTAssertEqual(store.read(), "20260727")
        XCTAssertEqual(store.writeCount, 2)
    }

    private func renderLogo(
        frame: RebuildIntroLogoFrame,
        width: CGFloat
    ) throws -> CGImage {
        let renderer = ImageRenderer(
            content: RebuildIntroLogoCanvas(frame: frame)
                .frame(
                    width: width,
                    height: width / RebuildIntroMotionSpec.sourceAspectRatio
                )
        )
        renderer.scale = 3
        return try XCTUnwrap(renderer.cgImage)
    }
}

private actor RebuildIntroSleepGate {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor RebuildIntroBoolGate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private final class RebuildIntroDelayedDateStore:
    RebuildIntroDateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let writeStarted: XCTestExpectation
    private let resultGate = RebuildIntroBoolGate()
    private var value: String?
    private var storedWriteCount = 0

    init(writeStarted: XCTestExpectation) {
        self.writeStarted = writeStarted
    }

    func read() -> String? {
        lock.withLock { value }
    }

    var writeCount: Int {
        lock.withLock { storedWriteCount }
    }

    func writeDurably(_ value: String) async -> Bool {
        lock.withLock {
            self.value = value
            storedWriteCount += 1
        }
        writeStarted.fulfill()
        return await resultGate.wait()
    }

    func finish(returning value: Bool) async {
        await resultGate.resume(returning: value)
    }
}

private final class RebuildIntroRolloverDateStore:
    RebuildIntroDateStoring, @unchecked Sendable {
    let firstWriteStarted: XCTestExpectation
    let secondWriteStarted: XCTestExpectation

    private let lock = NSLock()
    private let firstResultGate = RebuildIntroBoolGate()
    private var value: String?
    private var storedWriteCount = 0

    init(
        firstWriteStarted: XCTestExpectation,
        secondWriteStarted: XCTestExpectation
    ) {
        self.firstWriteStarted = firstWriteStarted
        self.secondWriteStarted = secondWriteStarted
    }

    var writeCount: Int {
        lock.withLock { storedWriteCount }
    }

    func read() -> String? {
        lock.withLock { value }
    }

    func writeDurably(_ value: String) async -> Bool {
        let count = lock.withLock {
            self.value = value
            storedWriteCount += 1
            return storedWriteCount
        }
        if count == 1 {
            firstWriteStarted.fulfill()
            return await firstResultGate.wait()
        }
        secondWriteStarted.fulfill()
        return true
    }

    func finishFirstWrite(returning value: Bool) async {
        await firstResultGate.resume(returning: value)
    }
}

private final class RebuildIntroThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedWasMainThread: Bool?

    var wasMainThread: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return storedWasMainThread
    }

    func recordCurrentThread() {
        lock.lock()
        storedWasMainThread = Thread.isMainThread
        lock.unlock()
    }
}

private final class RebuildIntroStringObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String?] = []

    var values: [String?] {
        lock.withLock { storedValues }
    }

    func record(_ value: String?) {
        lock.withLock {
            storedValues.append(value)
        }
    }
}

private final class RebuildIntroBlockingSynchronizer: @unchecked Sendable {
    let entered: XCTestExpectation

    private let semaphore = DispatchSemaphore(value: 0)

    init(entered: XCTestExpectation) {
        self.entered = entered
    }

    func synchronize(_ defaults: UserDefaults) -> Bool {
        entered.fulfill()
        semaphore.wait()
        return defaults.synchronize()
    }

    func resume() {
        semaphore.signal()
    }
}

private final class RebuildIntroDateStoreStub: RebuildIntroDateStoring {
    var value: String?
    var acceptsWrites: Bool
    private(set) var writeCount = 0

    init(value: String?, acceptsWrites: Bool = true) {
        self.value = value
        self.acceptsWrites = acceptsWrites
    }

    func read() -> String? {
        value
    }

    func writeDurably(_ value: String) async -> Bool {
        writeCount += 1
        guard acceptsWrites else { return false }
        self.value = value
        return true
    }
}

private enum PNGHeaderContract: Equatable {
    case rgba(width: Int, height: Int)
}

private extension Data {
    var pngHeaderContract: PNGHeaderContract? {
        let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard
            count >= 26,
            prefix(signature.count) == signature,
            self[24] == 8,
            self[25] == 6
        else {
            return nil
        }
        let width = self[16..<20].reduce(0) {
            ($0 << 8) | Int($1)
        }
        let height = self[20..<24].reduce(0) {
            ($0 << 8) | Int($1)
        }
        return .rgba(width: width, height: height)
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
