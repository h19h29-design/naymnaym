import CryptoKit
import Foundation
import SwiftUI
import UIKit

struct MascotPose: Equatable {
    var bodyOffsetY: CGFloat
    var bodyScaleX: CGFloat
    var bodyScaleY: CGFloat
    var headRotation: Angle
    var leftArmRotation: Angle
    var rightArmRotation: Angle
    var tailRotation: Angle
    var eyesClosed: Bool
    var smiling: Bool

    static let rest = MascotPose(
        bodyOffsetY: 0,
        bodyScaleX: 1,
        bodyScaleY: 1,
        headRotation: .zero,
        leftArmRotation: .zero,
        rightArmRotation: .zero,
        tailRotation: .zero,
        eyesClosed: false,
        smiling: true
    )
}

struct MascotRenderProjection: Equatable {
    let celebrationBlend: CGFloat
    let bodyOffsetY: CGFloat
    let bodyScaleX: CGFloat
    let bodyScaleY: CGFloat
    let wholeCharacterRotation: Angle
    let eyesClosed: Bool
    let smiling: Bool

    init(state: RebuildMotionState, pose: MascotPose) {
        let blend: CGFloat
        switch state {
        case .mealSuccess, .levelUp:
            blend = min(
                max(
                    max(
                        CGFloat(abs(pose.leftArmRotation.degrees) / 12),
                        CGFloat(abs(pose.rightArmRotation.degrees) / 12)
                    ),
                    CGFloat(abs(pose.tailRotation.degrees) / 8)
                ),
                1
            )
        case .idle, .tapReaction, .comfort, .reducedMotion:
            blend = 0
        }

        celebrationBlend = blend
        bodyOffsetY = pose.bodyOffsetY
        bodyScaleX = 1 + ((pose.bodyScaleX - 1) * (1 - blend))
        bodyScaleY = 1 + ((pose.bodyScaleY - 1) * (1 - blend))
        wholeCharacterRotation = pose.headRotation
        eyesClosed = pose.eyesClosed
        smiling = pose.smiling
    }
}

struct MascotMotionSpec: Equatable {
    struct State: Equatable {
        let duration: TimeInterval
        let loops: Bool
    }

    let states: [RebuildMotionState: State]

    init(states: [RebuildMotionState: State]) {
        self.states = states
    }

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else {
            throw MascotMotionSpecError.unsupportedVersion(document.version)
        }

        let expectedStates: [RebuildMotionState] = [
            .idle,
            .tapReaction,
            .mealSuccess,
            .levelUp,
            .comfort,
            .reducedMotion,
        ]
        var decodedStates: [RebuildMotionState: State] = [:]
        for state in expectedStates {
            guard let value = document.states[state.rawValue],
                  value.durationMs > 0 else {
                throw MascotMotionSpecError.invalidState(state.rawValue)
            }
            decodedStates[state] = State(
                duration: TimeInterval(value.durationMs) / 1_000,
                loops: value.loop
            )
        }
        guard document.states.count == expectedStates.count else {
            throw MascotMotionSpecError.unexpectedStateCount(
                document.states.count
            )
        }
        states = decodedStates
    }

    func state(for motion: RebuildMotionState) -> State {
        states[motion]!
    }

    static func bundled(bundle: Bundle = .main) throws -> MascotMotionSpec {
        try MascotMotionSpec(
            data: loadRebuildContractData(
                named: "mascot-motion.json",
                bundle: bundle
            )
        )
    }

    static let fixture = MascotMotionSpec(
        states: [
            .idle: State(duration: 6.0, loops: true),
            .tapReaction: State(duration: 0.42, loops: false),
            .mealSuccess: State(duration: 1.4, loops: false),
            .levelUp: State(duration: 3.0, loops: false),
            .comfort: State(duration: 1.2, loops: false),
            .reducedMotion: State(duration: 0.25, loops: false),
        ]
    )

    private struct Document: Decodable {
        let version: Int
        let states: [String: RawState]
    }

    private struct RawState: Decodable {
        let durationMs: Int
        let loop: Bool
    }
}

enum MascotMotionSpecError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidState(String)
    case unexpectedStateCount(Int)
}

enum MascotRigSemanticPart: String, CaseIterable {
    case tailBack
    case body
    case scarf
    case head
    case armLeft
    case armRight
    case eyesOpen
    case eyesClosed
    case mouthNeutral
    case mouthSmile
    case sprout
}

private struct MascotRigKeyframeDescriptor {
    let name: String
    let sha256: String
}

private struct MascotRigLevelDefinition {
    let canvasSize: CGSize
    let anchor: CGPoint
    let rest: MascotRigKeyframeDescriptor
    let blink: MascotRigKeyframeDescriptor
    let celebrate: MascotRigKeyframeDescriptor
    let semanticParts: [MascotRigSemanticPart]

    static let levelOne = MascotRigLevelDefinition(
        canvasSize: CGSize(width: 1_254, height: 1_254),
        anchor: CGPoint(x: 627, y: 1_128),
        rest: MascotRigKeyframeDescriptor(
            name: "composite-rest",
            sha256: "ab0e53ee0d330490efa9dd4c3eaf3138ec6ef4d44a93079e928cf5a415fa9f60"
        ),
        blink: MascotRigKeyframeDescriptor(
            name: "composite-blink",
            sha256: "8f751b950d36776865c026564cb3460eaab0b1fcde3efb71d27f62006f4b9c3e"
        ),
        celebrate: MascotRigKeyframeDescriptor(
            name: "composite-celebrate",
            sha256: "d22f37412faed68e14eb5fe96a6798846ddc1c90940fa23108b4f53864dbcd95"
        ),
        semanticParts: MascotRigSemanticPart.allCases
    )
}

final class MascotRigImages {
    let rest: UIImage
    let blink: UIImage
    let celebrate: UIImage
    let semanticPartNames: [String]

    var verifiedKeyframeCount: Int { 3 }

    init(
        rest: UIImage,
        blink: UIImage,
        celebrate: UIImage,
        semanticPartNames: [String]
    ) {
        self.rest = rest
        self.blink = blink
        self.celebrate = celebrate
        self.semanticPartNames = semanticPartNames
    }
}

struct MascotRigFallbackLayer {
    let part: MascotRigSemanticPart
    let image: UIImage
}

enum MascotRigAssetError: Error, Equatable {
    case unsupportedLevel(Int)
    case missingAsset(String)
    case checksumMismatch(String)
    case invalidDimensions(String)
    case invalidImage(String)
}

@MainActor
final class MascotRigAssetStore {
    static let shared = MascotRigAssetStore()

    private var cache: [String: MascotRigImages] = [:]
    private var fallbackCache: [String: [MascotRigFallbackLayer]] = [:]

    func images(level: Int, bundle: Bundle = .main) throws -> MascotRigImages {
        let cacheKey = "\(bundle.bundleURL.path)#\(level)"
        if let cached = cache[cacheKey] {
            return cached
        }

        guard level == 1 else {
            throw MascotRigAssetError.unsupportedLevel(level)
        }
        let definition = MascotRigLevelDefinition.levelOne
        let subdirectory = "MascotRig/level_01"

        for part in definition.semanticParts {
            guard bundle.url(
                forResource: part.rawValue,
                withExtension: "png",
                subdirectory: subdirectory
            ) != nil else {
                throw MascotRigAssetError.missingAsset(part.rawValue)
            }
        }

        let result = MascotRigImages(
            rest: try load(
                definition.rest,
                definition: definition,
                bundle: bundle,
                subdirectory: subdirectory
            ),
            blink: try load(
                definition.blink,
                definition: definition,
                bundle: bundle,
                subdirectory: subdirectory
            ),
            celebrate: try load(
                definition.celebrate,
                definition: definition,
                bundle: bundle,
                subdirectory: subdirectory
            ),
            semanticPartNames: definition.semanticParts.map(\.rawValue)
        )
        cache[cacheKey] = result
        return result
    }

    func fallbackLayers(
        level: Int,
        bundle: Bundle = .main
    ) throws -> [MascotRigFallbackLayer] {
        let cacheKey = "\(bundle.bundleURL.path)#fallback#\(level)"
        if let cached = fallbackCache[cacheKey] {
            return cached
        }
        guard level == 1 else {
            throw MascotRigAssetError.unsupportedLevel(level)
        }

        let definition = MascotRigLevelDefinition.levelOne
        let subdirectory = "MascotRig/level_01"
        let layers = try definition.semanticParts.map { part in
            MascotRigFallbackLayer(
                part: part,
                image: try load(
                    descriptor(for: part),
                    definition: definition,
                    bundle: bundle,
                    subdirectory: subdirectory
                )
            )
        }
        fallbackCache[cacheKey] = layers
        return layers
    }

    private func load(
        _ descriptor: MascotRigKeyframeDescriptor,
        definition: MascotRigLevelDefinition,
        bundle: Bundle,
        subdirectory: String
    ) throws -> UIImage {
        guard let url = bundle.url(
            forResource: descriptor.name,
            withExtension: "png",
            subdirectory: subdirectory
        ) else {
            throw MascotRigAssetError.missingAsset(descriptor.name)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == descriptor.sha256 else {
            throw MascotRigAssetError.checksumMismatch(descriptor.name)
        }
        guard let sourceImage = UIImage(data: data, scale: 1),
              let cgImage = sourceImage.cgImage else {
            throw MascotRigAssetError.invalidImage(descriptor.name)
        }
        guard cgImage.width == Int(definition.canvasSize.width),
              cgImage.height == Int(definition.canvasSize.height) else {
            throw MascotRigAssetError.invalidDimensions(descriptor.name)
        }
        return sourceImage.preparingForDisplay() ?? sourceImage
    }

    private func descriptor(
        for part: MascotRigSemanticPart
    ) -> MascotRigKeyframeDescriptor {
        let sha256: String
        switch part {
        case .tailBack:
            sha256 = "ca6ab285e97b48cffc3cbc9e150d339e4038de7342a8066ac912586a663ef430"
        case .body:
            sha256 = "172d92553ad92f6f3f62ecd0ea32840797b41a16f252f47196bdb81ab71ece6e"
        case .scarf:
            sha256 = "d6c797b034967d730149e1e080219f377ba1025350e8007ff7333bb0afbf6573"
        case .head:
            sha256 = "7bf20a006e56ad2f293b6570866d94886afe4166c66b26245ceab6a3ea52acc9"
        case .armLeft:
            sha256 = "12d48cb3c2b2e8412e98c799b75c7aa2bbbdd4f767cc5315825740d55e216d4a"
        case .armRight:
            sha256 = "c66643c2c4e22cb6ad599b62b1c62df13cf5a80e6754cc27d961480c0c77470c"
        case .eyesOpen:
            sha256 = "26128c66d978b4ce3a107eed82193d6f50805c0bcf23fceaf7bd01f785df59ac"
        case .eyesClosed:
            sha256 = "6a12e0427b844d67c126904e49b0bd65f0c01cbabba3ba57bc37b7892330c0bc"
        case .mouthNeutral:
            sha256 = "0234f8509bb923252182165799703f86a32bc4f366c4002194df3dda1d2649df"
        case .mouthSmile:
            sha256 = "27e1a3e31935b9a737cbe0cf99f9e5dca6b0ebede13413cd2a39198b67cc9304"
        case .sprout:
            sha256 = "ce444e770a05ebabf9db431c56c90985644be32eb6327b0c66403794b86100b6"
        }
        return MascotRigKeyframeDescriptor(
            name: part.rawValue,
            sha256: sha256
        )
    }
}
