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
    func observeCommittedValue(
        _ listener: @escaping @Sendable (String?, Int) -> Void
    ) -> RebuildIntroDateStoreObservation?
}

extension RebuildIntroDateStoring {
    func observeCommittedValue(
        _ listener: @escaping @Sendable (String?, Int) -> Void
    ) -> RebuildIntroDateStoreObservation? {
        nil
    }
}

final class RebuildIntroDateStoreObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (@Sendable () -> Void)?

    init(cancellation: @escaping @Sendable () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        let cancellation = lock.withLock {
            let cancellation = self.cancellation
            self.cancellation = nil
            return cancellation
        }
        cancellation?()
    }

    deinit {
        cancel()
    }
}

private let rebuildIntroStorageKey = "last-intro-date"
private let rebuildIntroDurableStorageKey =
    "last-intro-date.rebuild-durable-record"
private let rebuildIntroDurableRecordOwner =
    "rebuild-intro-daily-gate-v1"

private enum RebuildIntroDurableRecordState: String {
    case pending
    case published
    case superseded
}

private struct RebuildIntroDurableRecord {
    let owner: String
    let version: Int
    let state: RebuildIntroDurableRecordState
    let value: String
    let previousPublicValue: String

    init(
        version: Int,
        state: RebuildIntroDurableRecordState,
        value: String,
        previousPublicValue: String
    ) {
        owner = rebuildIntroDurableRecordOwner
        self.version = version
        self.state = state
        self.value = value
        self.previousPublicValue = previousPublicValue
    }

    init?(dictionary: [String: Any]) {
        guard
            let owner = dictionary["owner"] as? String,
            owner == rebuildIntroDurableRecordOwner,
            let version = dictionary["version"] as? Int,
            version > 0,
            let stateValue = dictionary["state"] as? String,
            let state = RebuildIntroDurableRecordState(rawValue: stateValue),
            let value = dictionary["value"] as? String,
            let previousPublicValue =
                dictionary["previousPublicValue"] as? String
        else {
            return nil
        }
        self.owner = owner
        self.version = version
        self.state = state
        self.value = value
        self.previousPublicValue = previousPublicValue
    }

    var dictionary: [String: Any] {
        [
            "owner": owner,
            "version": version,
            "state": state.rawValue,
            "value": value,
            "previousPublicValue": previousPublicValue,
        ]
    }

    func changingState(
        to state: RebuildIntroDurableRecordState
    ) -> RebuildIntroDurableRecord {
        RebuildIntroDurableRecord(
            version: version,
            state: state,
            value: value,
            previousPublicValue: previousPublicValue
        )
    }
}

private final class RebuildIntroPersistenceCoordinator: @unchecked Sendable {
    typealias Listener = @Sendable (String?, Int) -> Void

    private let stateLock = NSLock()
    private let writerLock = NSLock()
    private let orderingQueue = DispatchQueue(
        label: "com.h19h29.naymnaymlevelup.rebuild-intro-ordering",
        qos: .utility
    )
    private var activeWriteCount = 0
    private var nextRequestID = 0
    private var latestCommittedRequestID = 0
    private var reservedValues: [Int: String] = [:]
    private var committedValue: String?
    private var hasLoadedCommittedValue = false
    private var version = 0
    private var listeners: [UUID: Listener] = [:]

    func readThrough(
        authoritativeValue: () -> String?
    ) -> String? {
        let inFlight = stateLock.withLock {
            (
                isActive: activeWriteCount > 0,
                value: committedValue,
                isLoaded: hasLoadedCommittedValue
            )
        }
        if inFlight.isActive {
            return inFlight.isLoaded ? inFlight.value : nil
        }

        guard writerLock.try() else {
            let snapshot = stateLock.withLock {
                (
                    value: committedValue,
                    isLoaded: hasLoadedCommittedValue
                )
            }
            return snapshot.isLoaded ? snapshot.value : nil
        }
        defer { writerLock.unlock() }
        let afterLock = stateLock.withLock {
            (
                isActive: activeWriteCount > 0,
                value: committedValue,
                isLoaded: hasLoadedCommittedValue
            )
        }
        if afterLock.isActive {
            return afterLock.isLoaded ? afterLock.value : nil
        }
        let value = authoritativeValue()
        publishReadThrough(value)
        return value
    }

    func observe(_ listener: @escaping Listener)
        -> RebuildIntroDateStoreObservation {
        let id = UUID()
        let snapshot = stateLock.withLock {
            listeners[id] = listener
            return (
                value: committedValue,
                version: version,
                isLoaded: hasLoadedCommittedValue
            )
        }
        if snapshot.isLoaded {
            listener(snapshot.value, snapshot.version)
        }
        return RebuildIntroDateStoreObservation { [weak self] in
            _ = self?.stateLock.withLock {
                self?.listeners.removeValue(forKey: id)
            }
        }
    }

    func withSerializedWrite<Result>(
        _ body: () -> Result
    ) -> Result {
        writerLock.lock()
        stateLock.withLock {
            activeWriteCount += 1
        }
        defer {
            stateLock.withLock {
                activeWriteCount -= 1
            }
            writerLock.unlock()
        }
        return body()
    }

    func reserveRequestID(
        value: String,
        readPublicValue: @escaping @Sendable () -> String?
    ) async -> (requestID: Int, publicValue: String?) {
        await withCheckedContinuation { continuation in
            orderingQueue.async { [self] in
                let publicValue = readPublicValue()
                let reservation = stateLock.withLock {
                    if !hasLoadedCommittedValue {
                        committedValue = publicValue
                        hasLoadedCommittedValue = true
                    }
                    nextRequestID += 1
                    reservedValues[nextRequestID] = value
                    return (
                        requestID: nextRequestID,
                        publicValue: publicValue
                    )
                }
                continuation.resume(returning: reservation)
            }
        }
    }

    func isSuperseded(
        requestID: Int,
        value: String
    ) -> Bool {
        stateLock.withLock {
            requestID < latestCommittedRequestID
                || reservedValues.contains {
                    $0.key > requestID && $0.value != value
                }
        }
    }

    func finishRequest(requestID: Int) {
        _ = stateLock.withLock {
            reservedValues.removeValue(forKey: requestID)
        }
    }

    func adoptAuthoritativeValue(_ value: String?) {
        publishReadThrough(value)
    }

    func completeWithoutWrite(
        requestID: Int,
        value: String
    ) -> Bool {
        let result = orderingQueue.sync {
            stateLock.withLock {
                guard !isSupersededLocked(
                    requestID: requestID,
                    value: value
                ) else {
                    return (
                        didComplete: false,
                        listeners: [Listener](),
                        version: 0
                    )
                }
                latestCommittedRequestID = max(
                    latestCommittedRequestID,
                    requestID
                )
                guard
                    !hasLoadedCommittedValue || committedValue != value
                else {
                    return (
                        didComplete: true,
                        listeners: [Listener](),
                        version: 0
                    )
                }
                committedValue = value
                hasLoadedCommittedValue = true
                version += 1
                return (
                    didComplete: true,
                    listeners: Array(listeners.values),
                    version: version
                )
            }
        }
        notify(
            result.listeners,
            value: value,
            version: result.version
        )
        return result.didComplete
    }

    func publishAtomically(
        requestID: Int,
        value: String,
        onClaimed: () -> Void = {},
        publication: () -> Bool
    ) -> Bool {
        let result = orderingQueue.sync {
            let canPublish = stateLock.withLock {
                !isSupersededLocked(
                    requestID: requestID,
                    value: value
                )
            }
            guard canPublish else {
                return (
                    didPublish: false,
                    listeners: [Listener](),
                    version: 0
                )
            }
            onClaimed()
            guard publication() else {
                return (
                    didPublish: false,
                    listeners: [Listener](),
                    version: 0
                )
            }
            return stateLock.withLock {
                latestCommittedRequestID = max(
                    latestCommittedRequestID,
                    requestID
                )
                committedValue = value
                hasLoadedCommittedValue = true
                version += 1
                return (
                    didPublish: true,
                    listeners: Array(listeners.values),
                    version: version
                )
            }
        }
        notify(
            result.listeners,
            value: value,
            version: result.version
        )
        return result.didPublish
    }

    private func publishReadThrough(_ value: String?) {
        var listenersToNotify: [Listener] = []
        var publishedVersion = 0
        let didChange = stateLock.withLock {
            guard !hasLoadedCommittedValue || committedValue != value else {
                return false
            }
            committedValue = value
            hasLoadedCommittedValue = true
            version += 1
            publishedVersion = version
            listenersToNotify = Array(listeners.values)
            return true
        }
        guard didChange else { return }
        notify(
            listenersToNotify,
            value: value,
            version: publishedVersion
        )
    }

    private func isSupersededLocked(
        requestID: Int,
        value: String
    ) -> Bool {
        requestID < latestCommittedRequestID
            || reservedValues.contains {
                $0.key > requestID && $0.value != value
            }
    }

    private func notify(
        _ listeners: [Listener],
        value: String?,
        version: Int
    ) {
        guard version > 0 else { return }
        listeners.forEach { $0(value, version) }
    }
}

private final class RebuildIntroPersistenceRegistry:
    @unchecked Sendable {
    static let shared = RebuildIntroPersistenceRegistry()

    private final class ObjectEntry {
        weak var defaults: UserDefaults?
        let coordinator: RebuildIntroPersistenceCoordinator

        init(
            defaults: UserDefaults,
            coordinator: RebuildIntroPersistenceCoordinator
        ) {
            self.defaults = defaults
            self.coordinator = coordinator
        }
    }

    private let lock = NSLock()
    private let standardCoordinator =
        RebuildIntroPersistenceCoordinator()
    private var namedCoordinators:
        [String: RebuildIntroPersistenceCoordinator] = [:]
    private var objectEntries:
        [ObjectIdentifier: ObjectEntry] = [:]

    private init() {}

    func coordinator(
        defaults: UserDefaults,
        scopeIdentifier: String?
    ) -> RebuildIntroPersistenceCoordinator {
        if let scopeIdentifier {
            return lock.withLock {
                if let coordinator =
                    namedCoordinators[scopeIdentifier] {
                    return coordinator
                }
                let coordinator =
                    RebuildIntroPersistenceCoordinator()
                namedCoordinators[scopeIdentifier] = coordinator
                return coordinator
            }
        }
        if defaults === UserDefaults.standard {
            return standardCoordinator
        }
        let identifier = ObjectIdentifier(defaults)
        return lock.withLock {
            if
                let entry = objectEntries[identifier],
                entry.defaults === defaults
            {
                return entry.coordinator
            }
            let coordinator = RebuildIntroPersistenceCoordinator()
            objectEntries[identifier] = ObjectEntry(
                defaults: defaults,
                coordinator: coordinator
            )
            return coordinator
        }
    }
}

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
    typealias RequestReserved = @Sendable () -> Void
    typealias BeforePublication = @Sendable () -> Void
    typealias PublicValueRead = @Sendable () -> Void
    typealias PublicationClaimed = @Sendable () -> Void

    private let defaults: UserDefaults
    private let queue: DispatchQueue
    private let synchronize: Synchronize
    private let onRequestReserved: RequestReserved
    private let beforePublication: BeforePublication
    private let onPublicValueRead: PublicValueRead
    private let onPublicationClaimed: PublicationClaimed
    private let coordinator: RebuildIntroPersistenceCoordinator

    init(
        defaults: UserDefaults,
        scopeIdentifier: String? = nil,
        queue: DispatchQueue = DispatchQueue(
            label: "com.h19h29.naymnaymlevelup.rebuild-intro-persistence",
            qos: .utility
        ),
        synchronize: @escaping Synchronize = { $0.synchronize() },
        onRequestReserved: @escaping RequestReserved = {},
        beforePublication: @escaping BeforePublication = {},
        onPublicValueRead: @escaping PublicValueRead = {},
        onPublicationClaimed: @escaping PublicationClaimed = {}
    ) {
        self.defaults = defaults
        self.queue = queue
        self.synchronize = synchronize
        self.onRequestReserved = onRequestReserved
        self.beforePublication = beforePublication
        self.onPublicValueRead = onPublicValueRead
        self.onPublicationClaimed = onPublicationClaimed
        coordinator = RebuildIntroPersistenceRegistry.shared.coordinator(
            defaults: defaults,
            scopeIdentifier: scopeIdentifier
        )
    }

    func read() -> String? {
        coordinator.readThrough {
            authoritativeCommittedValue()
        }
    }

    func observeCommittedValue(
        _ listener: @escaping @Sendable (String?, Int) -> Void
    ) -> RebuildIntroDateStoreObservation? {
        coordinator.observe(listener)
    }

    func writeDurably(_ value: String) async -> Bool {
        let reservation = await coordinator.reserveRequestID(
            value: value
        ) { [self] in
            let publicValue = self.defaults.string(
                forKey: rebuildIntroStorageKey
            )
            self.onPublicValueRead()
            return publicValue
        }
        let requestID = reservation.requestID
        let publicValueAtRequest = reservation.publicValue
        onRequestReserved()
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                let didComplete = coordinator.withSerializedWrite {
                    defer {
                        coordinator.finishRequest(requestID: requestID)
                    }

                    let authoritativeValue = authoritativeCommittedValue()
                    coordinator.adoptAuthoritativeValue(
                        authoritativeValue
                    )
                    if authoritativeValue == value {
                        return coordinator.completeWithoutWrite(
                            requestID: requestID,
                            value: value
                        )
                    }
                    guard authoritativeValue == publicValueAtRequest else {
                        return false
                    }
                    guard !coordinator.isSuperseded(
                        requestID: requestID,
                        value: value
                    ) else {
                        return false
                    }

                    let previousPublicValue = defaults.string(
                        forKey: rebuildIntroStorageKey
                    )
                    guard previousPublicValue == publicValueAtRequest else {
                        return false
                    }
                    let previousDurableRecord = defaults.object(
                        forKey: rebuildIntroDurableStorageKey
                    )
                    let previousVersion = defaults.dictionary(
                        forKey: rebuildIntroDurableStorageKey
                    )
                    .flatMap(
                        RebuildIntroDurableRecord.init(dictionary:)
                    )?
                    .version ?? 0
                    let record = RebuildIntroDurableRecord(
                        version: max(requestID, previousVersion + 1),
                        state: .pending,
                        value: value,
                        previousPublicValue: previousPublicValue ?? ""
                    )
                    defaults.set(
                        record.dictionary,
                        forKey: rebuildIntroDurableStorageKey
                    )
                    let didSynchronize = synchronize(defaults)
                    let readBackRecord = defaults.dictionary(
                        forKey: rebuildIntroDurableStorageKey
                    )
                    .flatMap(
                        RebuildIntroDurableRecord.init(dictionary:)
                    )
                    let didReadBack =
                        readBackRecord?.version == record.version
                        && readBackRecord?.state == .pending
                        && readBackRecord?.value == value
                        && readBackRecord?.previousPublicValue
                            == previousPublicValue ?? ""

                    guard didSynchronize, didReadBack else {
                        if let previousDurableRecord {
                            defaults.set(
                                previousDurableRecord,
                                forKey: rebuildIntroDurableStorageKey
                            )
                        } else {
                            defaults.removeObject(
                                forKey: rebuildIntroDurableStorageKey
                            )
                        }
                        _ = synchronize(defaults)
                        return false
                    }

                    beforePublication()
                    let didPublish = coordinator.publishAtomically(
                        requestID: requestID,
                        value: value,
                        onClaimed: onPublicationClaimed
                    ) {
                        let publicValueBeforePublication =
                            defaults.string(
                                forKey: rebuildIntroStorageKey
                            )
                        guard
                            publicValueBeforePublication
                                == previousPublicValue
                                || publicValueBeforePublication == value
                        else {
                            return false
                        }
                        defaults.set(
                            value,
                            forKey: rebuildIntroStorageKey
                        )
                        defaults.set(
                            record.changingState(
                                to: .published
                            ).dictionary,
                            forKey: rebuildIntroDurableStorageKey
                        )
                        let didSynchronizePublication =
                            synchronize(defaults)
                        let didReadBackPublication =
                            defaults.string(
                                forKey: rebuildIntroStorageKey
                            ) == value
                            && defaults.dictionary(
                                forKey: rebuildIntroDurableStorageKey
                            )
                            .flatMap(
                                RebuildIntroDurableRecord.init(
                                    dictionary:
                                )
                            )?
                            .state == .published
                        guard
                            didSynchronizePublication,
                            didReadBackPublication
                        else {
                            if let previousPublicValue {
                                defaults.set(
                                    previousPublicValue,
                                    forKey: rebuildIntroStorageKey
                                )
                            } else {
                                defaults.removeObject(
                                    forKey: rebuildIntroStorageKey
                                )
                            }
                            defaults.set(
                                record.dictionary,
                                forKey: rebuildIntroDurableStorageKey
                            )
                            _ = synchronize(defaults)
                            return false
                        }
                        return true
                    }
                    guard didPublish else {
                        defaults.set(
                            record.changingState(
                                to: .superseded
                            ).dictionary,
                            forKey: rebuildIntroDurableStorageKey
                        )
                        _ = synchronize(defaults)
                        return false
                    }
                    return true
                }
                continuation.resume(returning: didComplete)
            }
        }
    }

    private func authoritativeCommittedValue() -> String? {
        let publicValue = defaults.string(forKey: rebuildIntroStorageKey)
        guard
            let dictionary = defaults.dictionary(
                forKey: rebuildIntroDurableStorageKey
            ),
            let record = RebuildIntroDurableRecord(dictionary: dictionary)
        else {
            return publicValue
        }

        switch record.state {
        case .published, .superseded:
            return publicValue
        case .pending:
            if publicValue == record.value {
                defaults.set(
                    record.changingState(to: .published).dictionary,
                    forKey: rebuildIntroDurableStorageKey
                )
                return record.value
            }
            guard (publicValue ?? "") == record.previousPublicValue else {
                defaults.set(
                    record.changingState(to: .superseded).dictionary,
                    forKey: rebuildIntroDurableStorageKey
                )
                return publicValue
            }
            defaults.set(record.value, forKey: rebuildIntroStorageKey)
            defaults.set(
                record.changingState(to: .published).dictionary,
                forKey: rebuildIntroDurableStorageKey
            )
            return record.value
        }
    }
}

enum RebuildIntroEntryPhase: Equatable {
    case intro
    case bootstrap
}

@MainActor
final class RebuildIntroDailyGate: ObservableObject {
    nonisolated static let storageKey = rebuildIntroStorageKey

    @Published private(set) var shouldPresent: Bool

    private struct CompletionAttempt {
        let day: String
        let observedVersionAtStart: Int
        let task: Task<Bool, Never>
    }

    private let store: RebuildIntroDateStoring
    private let now: () -> Date
    private let dayKey: (Date) -> String
    private var completionAttempt: CompletionAttempt?
    private var storeObservation: RebuildIntroDateStoreObservation?
    private var lastAppliedStoreVersion = Int.min
    private var latestObservedCommittedDay: String?

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
        observeStore()
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
        observeStore()
    }

    var entryPhase: RebuildIntroEntryPhase {
        shouldPresent ? .intro : .bootstrap
    }

    func refresh(at date: Date? = nil) {
        let today = dayKey(date ?? now())
        if let completionAttempt {
            let didObserveCurrentDayAfterAttempt =
                lastAppliedStoreVersion
                    > completionAttempt.observedVersionAtStart
                && latestObservedCommittedDay == today
            shouldPresent = !didObserveCurrentDayAfterAttempt
            return
        }
        shouldPresent = latestObservedCommittedDay != today
            && store.read() != today
    }

    @discardableResult
    func markCompleted(at date: Date? = nil) async -> Bool {
        while true {
            let requestedDay = dayKey(date ?? now())

            if let completionAttempt {
                let didComplete = await completionAttempt.task.value
                let refreshedRequestedDay = dayKey(date ?? now())
                let refreshedCurrentDay = dayKey(now())
                if completionAttempt.day == refreshedRequestedDay,
                   completionAttempt.day == refreshedCurrentDay {
                    return didComplete
                }
                continue
            }

            let currentDay = dayKey(now())
            if requestedDay == currentDay,
               store.read() == requestedDay {
                shouldPresent = false
                return true
            }

            shouldPresent = true
            let observedVersionAtStart = lastAppliedStoreVersion
            let task = Task { @MainActor [weak self] in
                guard let self else { return false }
                let didPersist = await store.writeDurably(requestedDay)
                let currentDay = dayKey(now())
                let didObserveCurrentDay =
                    lastAppliedStoreVersion >= observedVersionAtStart
                    && latestObservedCommittedDay == currentDay
                let didComplete =
                    (didPersist && requestedDay == currentDay)
                    || store.read() == currentDay
                    || didObserveCurrentDay
                if didComplete {
                    shouldPresent = false
                } else if lastAppliedStoreVersion <= observedVersionAtStart {
                    shouldPresent = true
                } else {
                    shouldPresent = latestObservedCommittedDay != currentDay
                }
                completionAttempt = nil
                return didComplete
            }
            completionAttempt = CompletionAttempt(
                day: requestedDay,
                observedVersionAtStart: observedVersionAtStart,
                task: task
            )
            return await task.value
        }
    }

    private func observeStore() {
        storeObservation = store.observeCommittedValue {
            [weak self] committedDay, version in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard version >= lastAppliedStoreVersion else { return }
                lastAppliedStoreVersion = version
                latestObservedCommittedDay = committedDay
                let today = dayKey(now())
                shouldPresent = committedDay != today
            }
        }
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

enum RebuildIntroLegacyCompletionCoordinator {
    @MainActor
    static func complete(
        currentDay: () -> String,
        persist: (String) async -> Bool,
        apply: () -> Void
    ) async -> Bool {
        let requestedDay = currentDay()
        guard await persist(requestedDay) else { return false }
        guard requestedDay == currentDay() else { return false }
        apply()
        return true
    }
}
