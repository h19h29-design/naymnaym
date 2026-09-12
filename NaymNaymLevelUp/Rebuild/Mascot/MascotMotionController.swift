import AVFoundation
import Combine
import SwiftUI

enum MascotReducedMotionRenderMode: Equatable {
    case staticFinal
}

enum MascotReducedMotionPolicy {
    static let renderMode: MascotReducedMotionRenderMode = .staticFinal
    static let transitionDuration: TimeInterval = 0
    static let schedulesCompletion = false
    static let emitsHaptic = false

    static var animation: Animation? {
        guard transitionDuration > 0 else { return nil }
        return .easeInOut(duration: transitionDuration)
    }
}

@MainActor
final class MascotMotionController: ObservableObject {
    @Published private(set) var pose: MascotPose = .rest
    @Published private(set) var activeState: RebuildMotionState = .idle
    @Published private(set) var playbackStartedAt: TimeInterval
    @Published private(set) var isPlaybackActive = false

    let spec: MascotMotionSpec
    private let timeSource: RebuildMonotonicTimeSource
    private var completionTask: Task<Void, Never>?
    private var playbackGeneration = 0

    init(
        spec: MascotMotionSpec,
        timeSource: RebuildMonotonicTimeSource = .system
    ) {
        self.spec = spec
        self.timeSource = timeSource
        self.playbackStartedAt = timeSource.now()
    }

    func play(_ state: RebuildMotionState) {
        play(state, reduceMotion: false)
    }

    func play(_ state: RebuildMotionState, at time: TimeInterval) {
        play(state, reduceMotion: false, at: time)
    }

    func play(
        _ state: RebuildMotionState,
        reduceMotion: Bool,
        at time: TimeInterval? = nil
    ) {
        completionTask?.cancel()
        playbackGeneration += 1
        let generation = playbackGeneration
        playbackStartedAt = time ?? timeSource.now()

        if reduceMotion {
            activeState = .reducedMotion
            isPlaybackActive = false
            switch MascotReducedMotionPolicy.renderMode {
            case .staticFinal:
                pose = pose(for: state, progress: 0.5, reduceMotion: true)
            }
            if MascotReducedMotionPolicy.schedulesCompletion {
                scheduleCompletion(
                    after: spec.state(for: .reducedMotion).duration,
                    generation: generation
                )
            }
            return
        }

        guard state != .idle else {
            activeState = .idle
            isPlaybackActive = false
            pose = .rest
            return
        }

        activeState = state
        isPlaybackActive = true
        pose = pose(for: state, progress: 0)
        let stateSpec = spec.state(for: state)
        if !stateSpec.loops {
            scheduleCompletion(
                after: stateSpec.duration,
                generation: generation
            )
        }
    }

    func sampledPose() -> MascotPose {
        sampledPose(at: timeSource.now())
    }

    func sampledPose(at time: TimeInterval) -> MascotPose {
        guard isPlaybackActive else { return pose }
        let elapsed = time - playbackStartedAt
        let sampledProgress = progress(
            for: activeState,
            elapsed: elapsed
        )
        return pose(
            for: activeState,
            progress: sampledProgress,
            reduceMotion: activeState == .reducedMotion
        )
    }

    func pose(
        for state: RebuildMotionState,
        progress rawProgress: Double,
        reduceMotion: Bool = false
    ) -> MascotPose {
        let progress = min(max(rawProgress, 0), 1)
        let animatedPose = poseForFullMotion(state, progress: progress)
        guard reduceMotion else { return animatedPose }

        var reducedPose = MascotPose.rest
        reducedPose.eyesClosed = (0.35 ... 0.65).contains(progress)
        reducedPose.smiling = animatedPose.smiling
        return reducedPose
    }

    func progress(
        for state: RebuildMotionState,
        elapsed rawElapsed: TimeInterval
    ) -> Double {
        let elapsed = max(rawElapsed, 0)
        let stateSpec = spec.state(for: state)
        if stateSpec.loops {
            return elapsed.truncatingRemainder(
                dividingBy: stateSpec.duration
            ) / stateSpec.duration
        }
        return min(elapsed / stateSpec.duration, 1)
    }

    private func poseForFullMotion(
        _ state: RebuildMotionState,
        progress: Double
    ) -> MascotPose {
        guard progress > 0, progress < 1 else { return .rest }

        switch state {
        case .idle:
            let wave = sin(progress * .pi * 2)
            return MascotPose(
                bodyOffsetY: 0,
                bodyScaleX: 1 - (0.004 * wave),
                bodyScaleY: 1 + (0.008 * wave),
                headRotation: .degrees(1.2 * wave),
                leftArmRotation: .degrees(-0.8 * wave),
                rightArmRotation: .degrees(0.8 * wave),
                tailRotation: .degrees(-2.5 * wave),
                eyesClosed: (0.47 ... 0.51).contains(progress),
                smiling: true
            )
        case .tapReaction:
            let peak = triangularPeak(progress)
            return MascotPose(
                bodyOffsetY: -8 * peak,
                bodyScaleX: 1 + (0.015 * peak),
                bodyScaleY: 1 - (0.015 * peak),
                headRotation: .degrees(-4 * peak),
                leftArmRotation: .degrees(3 * peak),
                rightArmRotation: .degrees(-3 * peak),
                tailRotation: .degrees(4 * peak),
                eyesClosed: (0.35 ... 0.65).contains(progress),
                smiling: true
            )
        case .mealSuccess:
            return mealSuccessPose(progress: progress)
        case .levelUp:
            let peak = sin(progress * .pi)
            return MascotPose(
                bodyOffsetY: -36 * peak,
                bodyScaleX: 1 + (0.04 * peak),
                bodyScaleY: 1 - (0.04 * peak),
                headRotation: .degrees(-2 * peak),
                leftArmRotation: .degrees(12 * peak),
                rightArmRotation: .degrees(-12 * peak),
                tailRotation: .degrees(8 * peak),
                eyesClosed: false,
                smiling: true
            )
        case .comfort:
            let peak = sin(progress * .pi)
            return MascotPose(
                bodyOffsetY: -3 * peak,
                bodyScaleX: 1,
                bodyScaleY: 1,
                headRotation: .degrees(-5 * peak),
                leftArmRotation: .degrees(5 * peak),
                rightArmRotation: .degrees(-2 * peak),
                tailRotation: .degrees(-5 * peak),
                eyesClosed: (0.3 ... 0.7).contains(progress),
                smiling: true
            )
        case .reducedMotion:
            var pose = MascotPose.rest
            pose.eyesClosed = (0.35 ... 0.65).contains(progress)
            return pose
        }
    }

    private func mealSuccessPose(progress: Double) -> MascotPose {
        if progress <= 0.2 {
            let amount = progress / 0.2
            var pose = MascotPose.rest
            pose.bodyScaleX = 1 + (0.04 * amount)
            pose.bodyScaleY = 1 - (0.04 * amount)
            return pose
        }

        let celebrationAmount: Double
        let offsetAmount: Double
        if progress <= 0.5 {
            celebrationAmount = (progress - 0.2) / 0.3
            offsetAmount = celebrationAmount
        } else {
            celebrationAmount = (1 - progress) / 0.5
            offsetAmount = celebrationAmount
        }

        return MascotPose(
            bodyOffsetY: -52 * offsetAmount,
            bodyScaleX: 1 + (0.04 * celebrationAmount),
            bodyScaleY: 1 - (0.04 * celebrationAmount),
            headRotation: .degrees(-2 * celebrationAmount),
            leftArmRotation: .degrees(12 * celebrationAmount),
            rightArmRotation: .degrees(-12 * celebrationAmount),
            tailRotation: .degrees(8 * celebrationAmount),
            eyesClosed: false,
            smiling: true
        )
    }

    private func triangularPeak(_ progress: Double) -> Double {
        1 - abs((2 * progress) - 1)
    }

    private func scheduleCompletion(
        after duration: TimeInterval,
        generation: Int
    ) {
        completionTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.playbackGeneration == generation else {
                return
            }
            self.isPlaybackActive = false
            self.activeState = .idle
            self.playbackStartedAt = self.timeSource.now()
            self.pose = .rest
        }
    }
}

/// Stage 1 local voice output for the mascot.
///
/// The service intentionally uses Apple's on-device speech synthesizer so the
/// mascot can react immediately without an API key or network dependency. AI
/// can later provide the text while this remains the single playback layer.
@MainActor
final class MascotSpeechSynthesizer: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !normalized.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: normalized)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.12
        utterance.volume = 0.95
        utterance.preUtteranceDelay = 0.04
        utterance.postUtteranceDelay = 0.03
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension MascotSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
        }
    }
}