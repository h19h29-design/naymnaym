import SwiftUI
import ImageIO

struct GrowthCharacterView: View {
    let level: Int
    let size: CGFloat
    let pose: GrowthCharacterPose
    let blendsCreamBackground: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        level: Int,
        size: CGFloat,
        pose: GrowthCharacterPose = .idle,
        blendsCreamBackground: Bool = false
    ) {
        self.level = level
        self.size = size
        self.pose = pose
        self.blendsCreamBackground = blendsCreamBackground
    }

    var body: some View {
        ZStack {
            if !blendsCreamBackground {
                Color.growthCharacterCream
            }

            if CompanionPlayback.supports(level: level), pose != .idle {
                CompanionAnimationView(
                    clip: pose == .eating ? .eating : pose == .celebrate ? .growth : .greeting,
                    reduceMotion: reduceMotion
                )
            } else {
                Image(GrowthCharacterAssets.imageName(for: level))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .frame(width: renderedSize, height: renderedSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("레벨 \(clampedLevel), \(GrowthCharacterAssets.stageTitle(for: level)) 다람쥐")
        .accessibilityValue(pose.accessibilityValue)
    }

    private var renderedSize: CGFloat {
        max(0, size)
    }

    private var clampedLevel: Int {
        GrowthCharacterAssets.atlasCell(for: level) + 1
    }

}

private extension GrowthCharacterPose {
    var accessibilityValue: String {
        switch self {
        case .idle:
            return "기본 자세"
        case .wave:
            return "손 흔드는 자세"
        case .celebrate:
            return "축하 자세"
        case .eating:
            return "한 입 먹는 자세"
        }
    }
}

enum CompanionClip: String, CaseIterable {
    case greeting, eating, growth, idleBreathing, listening, thinking, encouraging

    init?(motion: RebuildMotionState) {
        switch motion {
        case .idle, .tapReaction: self = .greeting
        case .mealSuccess: self = .eating
        case .levelUp: self = .growth
        case .comfort, .reducedMotion: return nil
        }
    }
}

enum CompanionPlayback {
    static let frameCount = 121
    static let frameRate = 32.0 * 0.8
    static let duration = Double(frameCount) / frameRate
    static func supports(level: Int) -> Bool { level == 1 }
    static func frame(at elapsed: TimeInterval, reduced: Bool) -> Int {
        guard !reduced, elapsed.isFinite else { return 0 }
        return Int(min(Double(frameCount - 1), max(0, elapsed) * frameRate))
    }
}

// Decode one frame at a time off the UI thread. Never retain 121 UIImages.
private final class CompanionFrameSource: @unchecked Sendable {
    let source: CGImageSource
    init?(clip: CompanionClip) {
        guard let url = Bundle.main.url(forResource: clip.rawValue, withExtension: "png", subdirectory: "MascotRig/Companion"),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == CompanionPlayback.frameCount else { return nil }
        self.source = source
    }
    func image(at index: Int) -> CGImage? {
        CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary)
    }
}

struct CompanionAnimationView: View {
    let clip: CompanionClip
    let reduceMotion: Bool
    var playbackRevision: Int = 0
    var isActive = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var replay = 0

    private var playbackKey: String {
        "\(clip.rawValue)-\(reduceMotion)-\(playbackRevision)-\(replay)-\(scenePhase)-\(isActive)"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(GrowthCharacterAssets.imageName(for: 1)).resizable().scaledToFit()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { if !reduceMotion { replay += 1 } }
        .accessibilityLabel("냠냠 다람쥐")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !reduceMotion { replay += 1 } }
        .accessibilityIdentifier("companion_\(clip.rawValue)")
        .task(id: playbackKey) {
            guard scenePhase == .active, isActive else { return }
            let source = await Task.detached(priority: .userInitiated) {
                CompanionFrameSource(clip: clip)
            }.value
            guard let source, !Task.isCancelled else { return }
            let started = ProcessInfo.processInfo.systemUptime
            var previous = -1
            while !Task.isCancelled {
                let totalElapsed = ProcessInfo.processInfo.systemUptime - started
                let elapsed = clip == .idleBreathing ? totalElapsed.truncatingRemainder(dividingBy: CompanionPlayback.duration + 2) : totalElapsed
                let index = CompanionPlayback.frame(at: elapsed, reduced: reduceMotion)
                if index != previous {
                    let decoded = await Task.detached(priority: .userInitiated) {
                        source.image(at: index)
                    }.value
                    guard !Task.isCancelled else { return }
                    if let decoded { image = UIImage(cgImage: decoded) }
                    previous = index
                }
                if reduceMotion || (clip != .idleBreathing && index == CompanionPlayback.frameCount - 1) { return }
                do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            }
        }
    }
}

private extension Color {
    static let growthCharacterCream = Color(
        red: 1,
        green: 249.0 / 255.0,
        blue: 238.0 / 255.0
    )
}
