import CoreGraphics
import Foundation

enum ForestSceneLayer: String, CaseIterable, Equatable {
    case sky
    case distantTrees
    case midgroundTrees
    case foregroundLeaves
    case ground

    static let contentZIndex = 10.0

    var zIndex: Double {
        switch self {
        case .sky: return 0
        case .distantTrees: return 1
        case .midgroundTrees: return 2
        case .foregroundLeaves: return 3
        case .ground: return 4
        }
    }
}

struct ForestSceneOffset: Equatable {
    var x: CGFloat
    var y: CGFloat

    static let zero = ForestSceneOffset(x: 0, y: 0)
}

struct ForestSceneFrame: Equatable {
    let progress: CGFloat
    private let transforms: [ForestSceneLayer: ForestSceneOffset]

    init(
        progress: CGFloat,
        transforms: [ForestSceneLayer: ForestSceneOffset]
    ) {
        self.progress = progress
        self.transforms = transforms
    }

    subscript(layer: ForestSceneLayer) -> ForestSceneOffset {
        transforms[layer] ?? .zero
    }
}

struct ForestSceneActivity: Equatable {
    let isSheetPresented: Bool
    let isTabActive: Bool
    let isAppActive: Bool

    static let active = ForestSceneActivity(
        isSheetPresented: false,
        isTabActive: true,
        isAppActive: true
    )

    var isPaused: Bool {
        isSheetPresented || !isTabActive || !isAppActive
    }
}

struct ForestSceneMotionClock {
    private let startTime: TimeInterval
    private var accumulatedPauseDuration: TimeInterval = 0
    private var pauseStartedAt: TimeInterval?

    init(startTime: TimeInterval) {
        self.startTime = startTime
    }

    mutating func update(
        activity: ForestSceneActivity,
        at time: TimeInterval
    ) {
        if activity.isPaused {
            if pauseStartedAt == nil {
                pauseStartedAt = time
            }
        } else if let pauseStartedAt {
            accumulatedPauseDuration += max(0, time - pauseStartedAt)
            self.pauseStartedAt = nil
        }
    }

    func elapsed(at time: TimeInterval) -> TimeInterval {
        let effectiveTime = pauseStartedAt ?? time
        return max(0, effectiveTime - startTime - accumulatedPauseDuration)
    }
}

enum ForestSceneMotionSpec {
    static let cycleDuration: TimeInterval = 8

    static func frame(
        elapsed: TimeInterval,
        reduceMotion: Bool
    ) -> ForestSceneFrame {
        guard !reduceMotion else {
            return ForestSceneFrame(
                progress: 0,
                transforms: Dictionary(
                    uniqueKeysWithValues: ForestSceneLayer.allCases.map {
                        ($0, .zero)
                    }
                )
            )
        }

        let wrapped = max(0, elapsed).truncatingRemainder(
            dividingBy: cycleDuration
        )
        let progress = CGFloat(
            wrapped <= cycleDuration / 2
                ? wrapped / (cycleDuration / 2)
                : (cycleDuration - wrapped) / (cycleDuration / 2)
        )
        return ForestSceneFrame(
            progress: progress,
            transforms: [
                .sky: .zero,
                .distantTrees: ForestSceneOffset(x: 0, y: -2 * progress),
                .midgroundTrees: ForestSceneOffset(x: 0, y: -4 * progress),
                .foregroundLeaves: ForestSceneOffset(
                    x: 6 * progress,
                    y: -3 * progress
                ),
                .ground: .zero,
            ]
        )
    }

    static func shouldScheduleFrameCallback(
        reduceMotion: Bool,
        activity: ForestSceneActivity
    ) -> Bool {
        !reduceMotion && !activity.isPaused
    }
}
