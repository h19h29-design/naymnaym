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

    func testDailyGateWritesOnlyOnCompletionAndRefreshesAcrossLocalMidnight() throws {
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

        gate.markCompleted(at: beforeMidnight)
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

    func testDailyGateReevaluatesInjectedLocalTimeZoneAfterTravel() throws {
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

        XCTAssertTrue(gate.markCompleted())
        XCTAssertEqual(store.value, "20260726")
        XCTAssertFalse(gate.shouldPresent)

        timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        gate.refresh()

        XCTAssertTrue(gate.shouldPresent)
        XCTAssertTrue(gate.markCompleted())
        XCTAssertEqual(store.value, "20260727")
    }

    func testFailedDailyWriteKeepsIntroActiveAndBlocksBootstrap() throws {
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let store = RebuildIntroDateStoreStub(
            value: nil,
            acceptsWrites: false
        )
        let gate = RebuildIntroDailyGate(store: store, now: { date })

        XCTAssertFalse(gate.markCompleted(at: date))

        XCTAssertTrue(gate.shouldPresent)
        XCTAssertEqual(gate.entryPhase, .intro)
        XCTAssertNil(store.value)

        store.acceptsWrites = true
        XCTAssertTrue(gate.markCompleted(at: date))
        XCTAssertEqual(gate.entryPhase, .bootstrap)
        XCTAssertEqual(store.value, "20260726")
    }

    func testSuccessfulDailyWriteMovesEntryFromIntroToBootstrap() throws {
        let date = try XCTUnwrap(
            DateUtils.apiDateFormatter.date(from: "20260726")
        )
        let store = RebuildIntroDateStoreStub(value: nil)
        let gate = RebuildIntroDailyGate(store: store, now: { date })
        XCTAssertEqual(gate.entryPhase, .intro)

        XCTAssertTrue(gate.markCompleted(at: date))

        XCTAssertEqual(gate.entryPhase, .bootstrap)
        XCTAssertEqual(store.value, "20260726")
    }

    func testDeepLinkMarksIntroOnlyAfterRouteResolutionSucceeds() async {
        var events: [String] = []
        let invalid = await RebuildIntroDeepLinkCoordinator.resolve(
            url: URL(string: "naymnaym://invalid")!,
            resolver: { _ in
                events.append("resolve-invalid")
                return nil
            },
            markIntroCompleted: {
                events.append("mark-invalid")
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
            markIntroCompleted: {
                events.append("mark")
            }
        )
        XCTAssertEqual(valid, .parentSummary)
        XCTAssertEqual(events, ["resolve", "mark"])
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

private final class RebuildIntroDateStoreStub: RebuildIntroDateStoring {
    var value: String?
    var acceptsWrites: Bool

    init(value: String?, acceptsWrites: Bool = true) {
        self.value = value
        self.acceptsWrites = acceptsWrites
    }

    func read() -> String? {
        value
    }

    func writeSynchronously(_ value: String) -> Bool {
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
