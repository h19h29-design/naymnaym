import Foundation
import SwiftUI

struct RebuildIntroWordFrame: Equatable {
    var opacity: CGFloat
    var translationY: CGFloat
    var scale: CGFloat

    static let hidden = RebuildIntroWordFrame(
        opacity: 0,
        translationY: RebuildIntroMotionSpec.initialTranslationY,
        scale: RebuildIntroMotionSpec.initialScale
    )
    static let visible = RebuildIntroWordFrame(
        opacity: 1,
        translationY: 0,
        scale: 1
    )
}

struct RebuildIntroLogoFrame: Equatable {
    var leftWord: RebuildIntroWordFrame
    var rightWord: RebuildIntroWordFrame
    var wholeLogoOpacity: CGFloat
    var shineProgress: CGFloat?
    var rendersWholeLogo: Bool
}

struct RebuildIntroMaskLayout: Equatable {
    let left: Range<CGFloat>
    let right: Range<CGFloat>

    init(sourceWidth: CGFloat) {
        let split = sourceWidth * RebuildIntroMotionSpec.splitFraction
        left = 0..<split
        right = split..<sourceWidth
    }
}

enum RebuildIntroMotionSpec {
    static let sourceWidth: CGFloat = 357
    static let sourceHeight: CGFloat = 86
    static let sourceAspectRatio = sourceWidth / sourceHeight
    static let splitFraction: CGFloat = 0.40
    static let initialTranslationY: CGFloat = 10
    static let initialScale: CGFloat = 0.988
    static let leftStart: TimeInterval = 0.04
    static let rightStart: TimeInterval = 0.34
    static let riseDuration: TimeInterval = 0.76
    static let shineStart: TimeInterval = 1.18
    static let shineDuration: TimeInterval = 0.82
    static let normalDuration: TimeInterval = 2.00
    static let reduceMotionDuration: TimeInterval = 0.25
    static let frameInterval: TimeInterval = 1.0 / 60.0

    static func frame(
        at elapsed: TimeInterval,
        reduceMotion: Bool
    ) -> RebuildIntroLogoFrame {
        let elapsed = max(0, elapsed)
        if reduceMotion {
            let opacity = min(elapsed / reduceMotionDuration, 1)
            return RebuildIntroLogoFrame(
                leftWord: .visible,
                rightWord: .visible,
                wholeLogoOpacity: opacity,
                shineProgress: nil,
                rendersWholeLogo: true
            )
        }

        if elapsed >= normalDuration {
            return RebuildIntroLogoFrame(
                leftWord: .visible,
                rightWord: .visible,
                wholeLogoOpacity: 1,
                shineProgress: nil,
                rendersWholeLogo: true
            )
        }

        let shineProgress: CGFloat?
        if elapsed >= shineStart {
            shineProgress = CGFloat(
                min(max((elapsed - shineStart) / shineDuration, 0), 1)
            )
        } else {
            shineProgress = nil
        }

        return RebuildIntroLogoFrame(
            leftWord: wordFrame(at: elapsed, start: leftStart),
            rightWord: wordFrame(at: elapsed, start: rightStart),
            wholeLogoOpacity: 1,
            shineProgress: shineProgress,
            rendersWholeLogo: false
        )
    }

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionDuration : normalDuration
    }

    private static func wordFrame(
        at elapsed: TimeInterval,
        start: TimeInterval
    ) -> RebuildIntroWordFrame {
        let linear = min(max((elapsed - start) / riseDuration, 0), 1)
        let progress = CGFloat(cubicBezierEase(linear))
        return RebuildIntroWordFrame(
            opacity: progress,
            translationY: initialTranslationY * (1 - progress),
            scale: initialScale + ((1 - initialScale) * progress)
        )
    }

    // CSS-equivalent cubic-bezier(.22, .78, .36, 1).
    private static func cubicBezierEase(_ progress: Double) -> Double {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return 1 }

        var lower = 0.0
        var upper = 1.0
        for _ in 0..<18 {
            let parameter = (lower + upper) / 2
            if cubicCoordinate(parameter, first: 0.22, second: 0.36)
                < progress {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return cubicCoordinate(
            (lower + upper) / 2,
            first: 0.78,
            second: 1
        )
    }

    private static func cubicCoordinate(
        _ parameter: Double,
        first: Double,
        second: Double
    ) -> Double {
        let inverse = 1 - parameter
        return (3 * inverse * inverse * parameter * first)
            + (3 * inverse * parameter * parameter * second)
            + (parameter * parameter * parameter)
    }
}

@MainActor
final class RebuildIntroMotionController: ObservableObject {
    typealias Sleep = (UInt64) async throws -> Void

    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isComplete = false
    @Published private(set) var effectiveReduceMotion: Bool?
    private(set) var hasStarted = false

    private let sleep: Sleep
    private var generation = 0
    private var playbackTask: Task<Void, Never>?

    init(
        sleep: @escaping Sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.sleep = sleep
    }

    @discardableResult
    func start(
        reduceMotion: Bool,
        onCompleted: @escaping () -> Void
    ) -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        isComplete = false
        elapsed = 0
        effectiveReduceMotion = reduceMotion
        generation += 1
        let playbackGeneration = generation
        let duration = RebuildIntroMotionSpec.duration(
            reduceMotion: reduceMotion
        )

        playbackTask = Task { [weak self] in
            guard let self else { return }
            var sampledElapsed: TimeInterval = 0
            while sampledElapsed < duration {
                let delta = min(
                    RebuildIntroMotionSpec.frameInterval,
                    duration - sampledElapsed
                )
                do {
                    try await sleep(
                        UInt64((delta * 1_000_000_000).rounded())
                    )
                } catch {
                    return
                }
                guard
                    !Task.isCancelled,
                    playbackGeneration == generation
                else {
                    return
                }
                sampledElapsed += delta
                elapsed = sampledElapsed
            }
            guard
                !Task.isCancelled,
                playbackGeneration == generation
            else {
                return
            }
            elapsed = duration
            isComplete = true
            onCompleted()
        }
        return true
    }

    func cancel() {
        generation += 1
        playbackTask?.cancel()
        playbackTask = nil
    }
}

protocol RebuildIntroDateStoring: AnyObject {
    func read() -> String?
    func writeDurably(_ value: String) async -> Bool
}

private let rebuildIntroStorageKey = "last-intro-date"

enum RebuildIntroLocalDay {
    static func key(
        for date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return ""
        }
        return String(format: "%04d%02d%02d", year, month, day)
    }
}

final class UserDefaultsRebuildIntroDateStore:
    RebuildIntroDateStoring, @unchecked Sendable {
    typealias Synchronize = @Sendable (UserDefaults) -> Bool

    private let defaults: UserDefaults
    private let queue: DispatchQueue
    private let synchronize: Synchronize

    init(
        defaults: UserDefaults,
        queue: DispatchQueue = DispatchQueue(
            label: "com.h19h29.naymnaymlevelup.rebuild-intro-persistence",
            qos: .utility
        ),
        synchronize: @escaping Synchronize = { $0.synchronize() }
    ) {
        self.defaults = defaults
        self.queue = queue
        self.synchronize = synchronize
    }

    func read() -> String? {
        defaults.string(forKey: rebuildIntroStorageKey)
    }

    func writeDurably(_ value: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let previousValue = defaults.object(
                    forKey: rebuildIntroStorageKey
                )
                defaults.set(value, forKey: rebuildIntroStorageKey)
                let didSynchronize = synchronize(defaults)
                let didReadBack = defaults.string(
                    forKey: rebuildIntroStorageKey
                ) == value

                guard didSynchronize, didReadBack else {
                    if let previousValue {
                        defaults.set(
                            previousValue,
                            forKey: rebuildIntroStorageKey
                        )
                    } else {
                        defaults.removeObject(
                            forKey: rebuildIntroStorageKey
                        )
                    }
                    _ = synchronize(defaults)
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: true)
            }
        }
    }
}

enum RebuildIntroEntryPhase: Equatable {
    case intro
    case bootstrap
}

@MainActor
final class RebuildIntroDailyGate: ObservableObject {
    static let storageKey = rebuildIntroStorageKey

    @Published private(set) var shouldPresent: Bool

    private let store: RebuildIntroDateStoring
    private let now: () -> Date
    private let dayKey: (Date) -> String
    private var completionTask: Task<Bool, Never>?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        dayKey: @escaping (Date) -> String = {
            RebuildIntroLocalDay.key(for: $0)
        }
    ) {
        store = UserDefaultsRebuildIntroDateStore(defaults: defaults)
        self.now = now
        self.dayKey = dayKey
        let today = dayKey(now())
        shouldPresent = store.read() != today
    }

    init(
        store: RebuildIntroDateStoring,
        now: @escaping () -> Date = Date.init,
        dayKey: @escaping (Date) -> String = {
            RebuildIntroLocalDay.key(for: $0)
        }
    ) {
        self.store = store
        self.now = now
        self.dayKey = dayKey
        let today = dayKey(now())
        shouldPresent = store.read() != today
    }

    var entryPhase: RebuildIntroEntryPhase {
        shouldPresent ? .intro : .bootstrap
    }

    func refresh(at date: Date? = nil) {
        guard completionTask == nil else {
            shouldPresent = true
            return
        }
        let today = dayKey(date ?? now())
        shouldPresent = store.read() != today
    }

    @discardableResult
    func markCompleted(at date: Date? = nil) async -> Bool {
        if let completionTask {
            return await completionTask.value
        }
        shouldPresent = true
        let completedDay = dayKey(date ?? now())
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            let didPersist = await store.writeDurably(completedDay)
            let currentDay = dayKey(now())
            let didComplete = didPersist && completedDay == currentDay
            shouldPresent = !didComplete
            completionTask = nil
            return didComplete
        }
        completionTask = task
        return await task.value
    }
}

@MainActor
final class RebuildIntroCompletionController: ObservableObject {
    @Published private(set) var completionFailed = false
    @Published private(set) var isAttemptInFlight = false

    private var attemptTask: Task<Void, Never>?

    @discardableResult
    func attempt(
        _ operation: @escaping @MainActor () async -> Bool
    ) -> Bool {
        guard !isAttemptInFlight else { return false }
        isAttemptInFlight = true
        attemptTask = Task { [weak self] in
            let succeeded = await operation()
            guard let self else { return }
            completionFailed = !succeeded
            isAttemptInFlight = false
            attemptTask = nil
        }
        return true
    }

    func waitUntilSettled() async {
        while isAttemptInFlight {
            await Task.yield()
        }
    }
}

enum RebuildIntroDeepLinkCoordinator {
    @MainActor
    static func resolve(
        url: URL,
        resolver: (URL) async -> AppDeepLinkRoute?,
        persistIntroCompletion: () async -> Bool,
        applyIntroCompletion: () -> Void
    ) async -> AppDeepLinkRoute? {
        guard let route = await resolver(url) else { return nil }
        guard await persistIntroCompletion() else { return nil }
        applyIntroCompletion()
        return route
    }
}
