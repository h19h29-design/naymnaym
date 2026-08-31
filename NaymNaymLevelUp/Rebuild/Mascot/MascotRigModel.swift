import CryptoKit
import Foundation
import ImageIO
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

enum MascotRigSemanticPart: String, CaseIterable, Sendable {
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

struct MascotRigKeyframeDescriptor: Sendable {
    let name: String
    let sha256: String
}

struct MascotRigLevelDefinition: Sendable {
    let canvasSize: CGSize
    let anchor: CGPoint
    let rest: MascotRigKeyframeDescriptor
    let blink: MascotRigKeyframeDescriptor
    let celebrate: MascotRigKeyframeDescriptor
    let semanticParts: [
        MascotRigSemanticPart: MascotRigKeyframeDescriptor
    ]

    func semanticPart(
        _ part: MascotRigSemanticPart
    ) throws -> MascotRigKeyframeDescriptor {
        guard let descriptor = semanticParts[part] else {
            throw MascotRigAssetError.missingAsset(part.rawValue)
        }
        return descriptor
    }
}

enum MascotRigLevelCatalog {
    static let definitions: [Int: MascotRigLevelDefinition] = [
        1: definition(
            rest: "ab0e53ee0d330490efa9dd4c3eaf3138ec6ef4d44a93079e928cf5a415fa9f60",
            blink: "8f751b950d36776865c026564cb3460eaab0b1fcde3efb71d27f62006f4b9c3e",
            celebrate: "d22f37412faed68e14eb5fe96a6798846ddc1c90940fa23108b4f53864dbcd95",
            parts: [
                .tailBack: "ca6ab285e97b48cffc3cbc9e150d339e4038de7342a8066ac912586a663ef430",
                .body: "172d92553ad92f6f3f62ecd0ea32840797b41a16f252f47196bdb81ab71ece6e",
                .scarf: "d6c797b034967d730149e1e080219f377ba1025350e8007ff7333bb0afbf6573",
                .head: "7bf20a006e56ad2f293b6570866d94886afe4166c66b26245ceab6a3ea52acc9",
                .armLeft: "12d48cb3c2b2e8412e98c799b75c7aa2bbbdd4f767cc5315825740d55e216d4a",
                .armRight: "c66643c2c4e22cb6ad599b62b1c62df13cf5a80e6754cc27d961480c0c77470c",
                .eyesOpen: "26128c66d978b4ce3a107eed82193d6f50805c0bcf23fceaf7bd01f785df59ac",
                .eyesClosed: "6a12e0427b844d67c126904e49b0bd65f0c01cbabba3ba57bc37b7892330c0bc",
                .mouthNeutral: "0234f8509bb923252182165799703f86a32bc4f366c4002194df3dda1d2649df",
                .mouthSmile: "27e1a3e31935b9a737cbe0cf99f9e5dca6b0ebede13413cd2a39198b67cc9304",
                .sprout: "ce444e770a05ebabf9db431c56c90985644be32eb6327b0c66403794b86100b6",
            ]
        ),
        2: definition(
            rest: "e99fe61d9fe6aaf6a4b85d6390f96a47de74d0420cb181dae75bc890dea90878",
            blink: "7dd5b5d5a4f759669a27426b63f9c11c80dd86b7c1f37b63cef2ccff543cfb05",
            celebrate: "b15d29cb486e1000ab799af5f019cd4b8660b31b8330f640e7dd2673f308b502",
            parts: [
                .tailBack: "65f512f9b61ca037247d6052cd3d8b5ed3ce2563e76e5351acc3ef51f1f445f6",
                .body: "ca5da65aaf7c48a2e52c51a0a1b56de7ea1f5c5db28979d6e47524d7874fb9af",
                .scarf: "1fedc78c46ee9180771f16d9e7744a6d80bdce4cac330a3cee660c5a4a6e5e44",
                .head: "28aeec40445187d5a3199f909090a95d68e19e0e3ca74ceef6f5b86120c32127",
                .armLeft: "fa0ae0de5718e29f321949c518c8a62f1b42d45662f2b88b800484a49c718576",
                .armRight: "cf3291c0e0bbc1196cdbfdd195773d97a588ce7a0bf8b7dfd5cd7abcf38fe879",
                .eyesOpen: "baf4beaac11e26316005688abcff2500822a546ecc5514ebeb6c8171d801be94",
                .eyesClosed: "da830918750959e29820cd0baab9c1d528dd6b210fcccb4af445c21e4c357e94",
                .mouthNeutral: "ebf01703e435e7c720a405cdcd84c9308eaf1a6d3089040e1f870552de6a791c",
                .mouthSmile: "b24dca5b6f1074881e7bde4215b3cccf6c2f9f9eaa2e60966b3cfbe77f390360",
                .sprout: "4fed1cfaf44fb9ce5e58d7f885c8a4da7b71a620b39b5a532d69a798b009d71d",
            ]
        ),
        3: definition(
            rest: "4206e8ad0fd2b4822805ac1cb9468f6779af6d25e36a00137e4289d399e65ae5",
            blink: "1f887a111aa37d2d9516e1473f3a0f31ec82b4246344d719e5b38157927da46c",
            celebrate: "228bdde37c3b6558f02fbc34c7c41c789691bc4df5e0c4f68c239f386e43f586",
            parts: [
                .tailBack: "a947d147d762b5a6e1f50057da134902716e807d11c4f22f6ffc0cde5f7cf1d1",
                .body: "725fdd572f8b6f8580675902cb5c9416e0d409f2981fa5f183b72af6939cf0f0",
                .scarf: "9a84c9d891b7d3ecb9388caeebcd440c3109f74cecefd20ee0eb0fa74b358aec",
                .head: "a120468a8534af27cf610340dd87a05b57bbfa8e2b1c4fd4d82eed7590085ce6",
                .armLeft: "55c032d79e74ec67fcb40aeb9be92a2f79dd833eebfc7d94470043d030700b88",
                .armRight: "a75fb9592c5a24d5cc7edaaac7762c27c602c5e359449b101dce556b934e89b7",
                .eyesOpen: "2963be9b10b5c84b372d6396c5cda7307588efeb1d62d7c624568b4011d24fe6",
                .eyesClosed: "1bbfc527b5fa39d4aa9e12d255c556f8da9b417751492077e715bd1d34d85298",
                .mouthNeutral: "06d7cfb2024fb69a33af4d6db5b0436e1227e73cca162ad03dec36282ab03295",
                .mouthSmile: "e8e2939d90147f4076b45680e1860f9f9487da57f74b0aae163d76bd3cd9c6b1",
                .sprout: "c4069cfbad90e2093dc4db97494ea12278f42db322bf12ae3cc1a2cd8a22f701",
            ]
        ),
        4: definition(
            rest: "a24f6a94115ceabb67cf547b7d2934de7bc9244f0c97ffdbabf1b20d76010dd1",
            blink: "1b51c6a4b3c3ce50c342075b0ca70c83ba3e91f42eca02c5d44f80a3671cdebd",
            celebrate: "abc3f8c6b695a7dedbc68d2b31992fb449b88a2ea2616be4123059190aee516d",
            parts: [
                .tailBack: "ade2b07ec9045b32a6cd06ffd1c5267f0b168d217488b585220b7ffaa36cdea0",
                .body: "18bbad6ab4c65ef65c84dfddd29d9c56d08818b4a293fbad395b04821636de58",
                .scarf: "de38a816bf8dd9dee3f62d19542dce7805d306e7a88ba02536ad8c985aff1d80",
                .head: "878c6c8e0a88593142c22c1e3c954e0897f9e6d663d45e9933362b6724dee6d3",
                .armLeft: "386d1cef17327c18abe6341ae15173e69cff57a9e5b92431cd17891524d34035",
                .armRight: "06001b100ad4850b4b894ac3d99b61c4f174d5459294a9f5dc9ef8f78c360449",
                .eyesOpen: "478cf67960652d74659e24bd6dd3612c11a174c6ffd3bac684a2ed4343f7bd35",
                .eyesClosed: "d9b6895adc6e369d4a93f7742d3a1da9a2a4fdadbb10b9245d1528c96958920c",
                .mouthNeutral: "d18d2d92eaded1a558e1dbbb072ed362d8b5258487bfe7d9183904e10ec7eb1b",
                .mouthSmile: "e2cb52dd52897a51afcac958c68a284f0da65d3a6b57a3cf1f1543a6285137c4",
                .sprout: "117bd677ac490f517bde2d89c58e6381ff7cee44ea7a40f7e6939ef3de81724c",
            ]
        ),
        5: definition(
            rest: "4d7518d077ef0c07b884337b2646972ab03b03353a463b394c5957510238b4d2",
            blink: "e78dadf2f4145ce181468e48cfc0146e08abf70c6e1f8d4fb2dae12393a8d387",
            celebrate: "483741d8b7beac6a76fe9b84be054f3de6ac1a5dd7f97aa55be0029b91ab998c",
            parts: [
                .tailBack: "d4a447541dc9bb4608301303baca79fa05900e413d64dd0673501e234a246262",
                .body: "eb7eb5f850e609af972cc7d04b7ade6bba3eeaf960610b71ad620e790bddbf6b",
                .scarf: "7fbf8cc0dad904c87e12f17681f70acd33d9584348b1a5de239a7137ff54dfff",
                .head: "865ecd410a4a29d9018a14bca326ace9281e9ec3d3683212f8c6e596bfd57122",
                .armLeft: "71752e68b93632fb76f6b5703aacbec2453f653988b19ec9224db89c155db62d",
                .armRight: "3283a95c669bbcb1308ba15cc589abd65a0d645cc66a052d264c55661703fa18",
                .eyesOpen: "e38f71c880cfbf5dc16dd94b3a0d6afbace288e5463f132be365d4a828a7df4e",
                .eyesClosed: "8581d7d7cba61bab9c144e6efd40bffabf8f4c5e210ae126ed3bd7e899211def",
                .mouthNeutral: "6aa7f70c9260d99bf2d4ad4cecfab3b38c973178bbdb5b725652e209e5c7f284",
                .mouthSmile: "150953cc1260c60831c4a045478917f219012b70d651e5d12bacd0c20898f4a0",
                .sprout: "43538889f5ca8f029bfb170468bc23a6f82105c257141eb4461a011bf9f9ed3f",
            ]
        ),
        6: definition(
            rest: "5351093f343254da3c36f53e15030d81bba9655749df0c94754c028944efc188",
            blink: "a9f451057ffbcb951e5643628fb9a3c773c6e2113f53711e3c8f2fe0ccca56d5",
            celebrate: "2b6e14ed32d11b48097c7c732de81a586ca4d12b260e71c197a4b6c822e95322",
            parts: [
                .tailBack: "80639d87e274206e40230b82138ff12583c68dfe7e272ec4415f974a1ace0a71",
                .body: "72687ec0c018df1230b49dffe114080e0b995617e7e3f4d3c8794276a6ad4439",
                .scarf: "6173bd6b01a1e1bdc9c46af98242c6ee23a07381ccf406373b53a14a2f290cde",
                .head: "3d22e35a6331ccbf9efb5548d78c1765c0395b1e2f6a39f6579015e22c8d0299",
                .armLeft: "8b159d9cefca889d774e6a24a0a1b3f45d7ceef387b3cf323e14d6d05cd90085",
                .armRight: "98f63e856f463f5065d82ce0ce79c71258634ad3ca4843330f72e20d0559ec4b",
                .eyesOpen: "4691ff24ad39babb51920a6691535e3a8e69543dd24baa6f294d38524131ad6a",
                .eyesClosed: "84c659cfd9cb81deeb593d194e0134002bf41a4aa009b6235ceb0ba9137f79f4",
                .mouthNeutral: "8db30ee467e8b10978f5219fb412cd1495c75cc8de2db40363ce2473744524b2",
                .mouthSmile: "9b303b7db481d602e5f65c15b9788e323d38507b5fa147db29f943766705472a",
                .sprout: "e0f92f1dbacdd2fedeb507718f91b4adf2cb18e828448b7c5a92d6a70c27bc3e",
            ]
        ),
        7: definition(
            rest: "bd68b019f9a9bf3a1d149bdd1735ac7d0dc063aad6eefa3a9d0311c5f7b09ccb",
            blink: "f33d5dd292fca15a61a8108d58ac86c6b843995b5c44c7ec59cafc742c193f8d",
            celebrate: "c8bb0c3e254ff5cdc5a77ca56d84ca6465f7600378692f02c1a6df43422ffa45",
            parts: [
                .tailBack: "ffc908c582b6cdaf2c974012ffb29a33a695b2c13b3debf573e0db74239ae5ff",
                .body: "f7e0bd19db763389d7890e8ce3dc0fa53d948d4bcfc02adc053b6ae1e8841dc2",
                .scarf: "1dc3672000fe13177d94a41b89e5c1dac6457e309ca710d7e54201a34bc1cf25",
                .head: "fcc62ec0d05be6f33e6730a30614070be4d6d71ec220563b3867f9e9706602b6",
                .armLeft: "57386f6eb602a916e185f4d355ed72ee326c0aadaa7a3a5e6316124cf06f31fb",
                .armRight: "2d7dfff1dde9310ce239c803bcdf1c65666ad43a4fe66738f0dce630c65b6ce3",
                .eyesOpen: "e457727a3af48735faaa34f19d9f771c687502efe6d7473c425f2a71897b97ed",
                .eyesClosed: "bfa65b302aba6653a03439c42f46f1bfd7a97b201d8437fc49a3318d6b68be43",
                .mouthNeutral: "86c23a570163cc0f0c88326fc7487813687873d93022606931571047230db57f",
                .mouthSmile: "e05f2beb992dcf67602d977ffc4505fe08c485657a3d2893580857bf9b93af9e",
                .sprout: "49b49b093d3b3580b4396cc9a37555db94000d93c3e06e802cf5ec731a107472",
            ]
        ),
    ]

    private static func definition(
        rest: String,
        blink: String,
        celebrate: String,
        parts: [MascotRigSemanticPart: String]
    ) -> MascotRigLevelDefinition {
        MascotRigLevelDefinition(
            canvasSize: CGSize(width: 1_254, height: 1_254),
            anchor: CGPoint(x: 627, y: 1_128),
            rest: MascotRigKeyframeDescriptor(
                name: "composite-rest",
                sha256: rest
            ),
            blink: MascotRigKeyframeDescriptor(
                name: "composite-blink",
                sha256: blink
            ),
            celebrate: MascotRigKeyframeDescriptor(
                name: "composite-celebrate",
                sha256: celebrate
            ),
            semanticParts: Dictionary(
                uniqueKeysWithValues: parts.map { part, hash in
                    (
                        part,
                        MascotRigKeyframeDescriptor(
                            name: part.rawValue,
                            sha256: hash
                        )
                    )
                }
            )
        )
    }

    /// The catalog is the single source of truth for art that is present and verified.
    static let verifiedLevelIDs = definitions.keys.sorted()

    static func hasVerifiedArt(for levelID: Int) -> Bool {
        definitions[levelID] != nil
    }
}

final class MascotRigImages: @unchecked Sendable {
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

struct MascotRigFallbackLayer: @unchecked Sendable {
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
final class MascotRestArtLoader: ObservableObject {
    typealias ImageLoader =
        @MainActor (Int, Bundle) async throws -> UIImage

    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: MascotRigAssetError?
    @Published private(set) var loadedLevel: Int?
    @Published private(set) var requestedLevel: Int?

    var canRetry: Bool { loadError != nil }

    func renderedImage(for level: Int) -> UIImage? {
        loadedLevel == level ? image : nil
    }

    func canRetry(for level: Int) -> Bool {
        requestedLevel == level && loadError != nil
    }

    private let loadImage: ImageLoader
    private var requestID = 0

    init(
        loadImage: @escaping ImageLoader = { level, bundle in
            try await MascotRigAssetStore.shared.restThumbnail(
                level: level,
                bundle: bundle
            )
        }
    ) {
        self.loadImage = loadImage
    }

    func load(
        level: Int,
        bundle: Bundle = .main
    ) async {
        requestID += 1
        let activeRequestID = requestID
        requestedLevel = level
        isLoading = true
        loadError = nil
        image = nil
        loadedLevel = nil

        do {
            let loadedImage = try await loadImage(level, bundle)
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            image = loadedImage
            loadedLevel = level
        } catch is CancellationError {
            if activeRequestID == requestID {
                isLoading = false
            }
            return
        } catch let error as MascotRigAssetError {
            guard activeRequestID == requestID else { return }
            loadError = error
        } catch {
            guard activeRequestID == requestID else { return }
            loadError = .invalidImage("composite-rest")
        }
        if activeRequestID == requestID {
            isLoading = false
        }
    }
}

@MainActor
final class MascotRigLoader: ObservableObject {
    typealias ImagesLoader =
        @MainActor (Int, Bundle) async throws -> MascotRigImages
    typealias FallbackLoader =
        @MainActor (Int, Bundle) async throws -> [MascotRigFallbackLayer]

    @Published private(set) var images: MascotRigImages?
    @Published private(set) var fallbackLayers: [MascotRigFallbackLayer]?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: MascotRigAssetError?
    @Published private(set) var loadedLevel: Int?
    @Published private(set) var requestedLevel: Int?

    var canRetry: Bool { loadError != nil }

    func renderedImages(for level: Int) -> MascotRigImages? {
        loadedLevel == level ? images : nil
    }

    func renderedFallbackLayers(
        for level: Int
    ) -> [MascotRigFallbackLayer]? {
        loadedLevel == level ? fallbackLayers : nil
    }

    func canRetry(for level: Int) -> Bool {
        requestedLevel == level && loadError != nil
    }

    private let loadImages: ImagesLoader
    private let loadFallbackLayers: FallbackLoader
    private var requestID = 0

    init(
        loadImages: @escaping ImagesLoader = { level, bundle in
            try await MascotRigAssetStore.shared.images(
                level: level,
                bundle: bundle
            )
        },
        loadFallbackLayers: @escaping FallbackLoader = { level, bundle in
            try await MascotRigAssetStore.shared.fallbackLayers(
                level: level,
                bundle: bundle
            )
        }
    ) {
        self.loadImages = loadImages
        self.loadFallbackLayers = loadFallbackLayers
    }

    func load(
        level: Int,
        bundle: Bundle = .main
    ) async {
        requestID += 1
        let activeRequestID = requestID
        requestedLevel = level
        isLoading = true
        loadError = nil
        loadedLevel = nil
        images = nil
        fallbackLayers = nil

        do {
            let loadedImages = try await loadImages(level, bundle)
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            images = loadedImages
            loadedLevel = level
        } catch is CancellationError {
            if activeRequestID == requestID {
                isLoading = false
            }
            return
        } catch {
            do {
                guard activeRequestID == requestID else { return }
                try Task.checkCancellation()
                let loadedLayers = try await loadFallbackLayers(
                    level,
                    bundle
                )
                try Task.checkCancellation()
                guard activeRequestID == requestID else { return }
                fallbackLayers = loadedLayers
                loadedLevel = level
            } catch is CancellationError {
                if activeRequestID == requestID {
                    isLoading = false
                }
                return
            } catch let fallbackError as MascotRigAssetError {
                guard activeRequestID == requestID else { return }
                loadError = fallbackError
            } catch {
                guard activeRequestID == requestID else { return }
                loadError = .invalidImage("semantic-fallback")
            }
        }
        if activeRequestID == requestID {
            isLoading = false
        }
    }
}

struct MascotRigCacheDiagnostics: Equatable {
    let rigLevels: [Int]
    let restLevels: [Int]
    let fallbackLevels: [Int]
    let heavyCost: Int
    let restCost: Int
}

enum MascotImageLoadingWorker {
    nonisolated static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let value = try operation()
            try Task.checkCancellation()
            return value
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

@MainActor
final class LatestActiveAssetCache<
    Key: Hashable & Sendable,
    Value: Sendable
> {
    private struct CachedEntry {
        let key: Key
        let value: Value
        let cost: Int
    }

    private final class WaiterCancellation: @unchecked Sendable {
        private enum State {
            case waiting
            case cancelled
            case completed
        }

        private let lock = NSLock()
        private var state = State.waiting

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            if case .cancelled = state {
                return true
            }
            return false
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            guard case .waiting = state else {
                return
            }
            state = .cancelled
        }

        func claimForCompletion() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard case .waiting = state else {
                return false
            }
            state = .completed
            return true
        }
    }

    private struct Waiter {
        let continuation: CheckedContinuation<Value, Error>
        let cancellation: WaiterCancellation
    }

    private struct InFlightEntry {
        let id: Int
        let key: Key
        let task: Task<Value, Error>
        var acceptsWaiters: Bool
        var waiters: [Int: Waiter]
    }

    private let maxCost: Int
    private let costOf: (Value) -> Int
    private var nextRequestID = 0
    private var nextWaiterID = 0
    private var cached: CachedEntry?
    private var inFlight: InFlightEntry?
    private var serialTail: Task<Void, Never>?

    var cachedKey: Key? { cached?.key }
    var cachedValue: Value? { cached?.value }
    var cachedCost: Int { cached?.cost ?? 0 }

    init(
        maxCost: Int,
        costOf: @escaping (Value) -> Int
    ) {
        self.maxCost = max(maxCost, 0)
        self.costOf = costOf
    }

    func value(
        for key: Key,
        load: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        if cached?.key == key,
           let cached {
            return cached.value
        }

        nextWaiterID += 1
        let waiterID = nextWaiterID
        let cancellation = WaiterCancellation()
        let value: Value = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation {
                continuation in
                register(
                    waiterID: waiterID,
                    key: key,
                    continuation: continuation,
                    cancellation: cancellation,
                    load: load
                )
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID)
            }
        }
        try Task.checkCancellation()
        return value
    }

    private func register(
        waiterID: Int,
        key: Key,
        continuation: CheckedContinuation<Value, Error>,
        cancellation: WaiterCancellation,
        load: @escaping @Sendable () async throws -> Value
    ) {
        guard !cancellation.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        if cached?.key == key,
           let cached {
            continuation.resume(returning: cached.value)
            return
        }

        if var existing = inFlight,
           existing.key == key,
           existing.acceptsWaiters {
            existing.waiters[waiterID] = Waiter(
                continuation: continuation,
                cancellation: cancellation
            )
            inFlight = existing
            return
        }

        supersedeCurrent()
        cached = nil
        nextRequestID += 1
        let requestID = nextRequestID
        let predecessor = serialTail
        let task = Task<Value, Error> {
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            return try await load()
        }
        inFlight = InFlightEntry(
            id: requestID,
            key: key,
            task: task,
            acceptsWaiters: true,
            waiters: [
                waiterID: Waiter(
                    continuation: continuation,
                    cancellation: cancellation
                ),
            ]
        )
        let monitor = Task<Void, Never> { [weak self] in
            let result = await task.result
            self?.complete(
                requestID: requestID,
                result: result
            )
        }
        serialTail = monitor
    }

    private func complete(
        requestID: Int,
        result: Result<Value, Error>
    ) {
        guard let entry = inFlight,
              entry.id == requestID else {
            return
        }
        inFlight = nil
        serialTail = nil
        let waiters = Array(entry.waiters.values)

        switch result {
        case let .success(value):
            let cost = waiters.isEmpty
                ? 0
                : max(costOf(value), 0)
            let activeWaiters = waiters.filter {
                $0.cancellation.claimForCompletion()
            }
            if !activeWaiters.isEmpty,
               cost <= maxCost {
                cached = CachedEntry(
                    key: entry.key,
                    value: value,
                    cost: cost
                )
            } else {
                cached = nil
            }
            for waiter in activeWaiters {
                waiter.continuation.resume(returning: value)
            }
            for waiter in waiters where waiter.cancellation.isCancelled {
                waiter.continuation.resume(
                    throwing: CancellationError()
                )
            }
        case let .failure(error):
            for waiter in waiters {
                if waiter.cancellation.claimForCompletion() {
                    waiter.continuation.resume(throwing: error)
                } else if waiter.cancellation.isCancelled {
                    waiter.continuation.resume(
                        throwing: CancellationError()
                    )
                }
            }
        }
    }

    private func cancelWaiter(_ waiterID: Int) {
        guard var entry = inFlight,
              let continuation = entry.waiters.removeValue(
                  forKey: waiterID
              ) else {
            return
        }
        let shouldCancelLoad = entry.waiters.isEmpty
        if shouldCancelLoad {
            entry.acceptsWaiters = false
        }
        inFlight = entry
        if shouldCancelLoad {
            entry.task.cancel()
        }
        continuation.cancellation.cancel()
        continuation.continuation.resume(
            throwing: CancellationError()
        )
    }

    private func supersedeCurrent() {
        guard let entry = inFlight else {
            return
        }
        inFlight = nil
        entry.task.cancel()
        for waiter in entry.waiters.values {
            waiter.cancellation.cancel()
            waiter.continuation.resume(
                throwing: CancellationError()
            )
        }
    }
}

@MainActor
final class MascotRigAssetStore {
    static let shared = MascotRigAssetStore()

    private enum HeavyRepresentation: @unchecked Sendable {
        case rig(
            level: Int,
            images: MascotRigImages,
            cost: Int
        )
        case fallback(
            level: Int,
            layers: [MascotRigFallbackLayer],
            cost: Int
        )

        var cost: Int {
            switch self {
            case let .rig(_, _, cost),
                 let .fallback(_, _, cost):
                return cost
            }
        }
    }

    private struct RestCacheEntry {
        let level: Int
        let image: UIImage
        let cost: Int
    }

    private struct ImageLoadRequest: Sendable {
        let part: MascotRigSemanticPart?
        let descriptor: MascotRigKeyframeDescriptor
        let url: URL
    }

    private struct LoadedImage: @unchecked Sendable {
        let image: UIImage
        let cost: Int
    }

    private let restCacheCostLimit: Int
    private let restThumbnailMaxPixelSize: Int
    private let fallbackThumbnailMaxPixelSize: Int
    private let heavyCache: LatestActiveAssetCache<
        String,
        HeavyRepresentation
    >
    private var restCache: [String: RestCacheEntry] = [:]
    private var restLRU: [String] = []
    private var restCacheCost = 0

    init(
        restCacheCostLimit: Int = 2 * 1_024 * 1_024,
        restThumbnailMaxPixelSize: Int = 256,
        heavyCacheCostLimit: Int = 24 * 1_024 * 1_024,
        fallbackThumbnailMaxPixelSize: Int = 512
    ) {
        self.restCacheCostLimit = max(restCacheCostLimit, 0)
        self.restThumbnailMaxPixelSize = max(
            restThumbnailMaxPixelSize,
            1
        )
        self.fallbackThumbnailMaxPixelSize = max(
            fallbackThumbnailMaxPixelSize,
            1
        )
        heavyCache = LatestActiveAssetCache(
            maxCost: heavyCacheCostLimit,
            costOf: \.cost
        )
    }

    func restThumbnail(
        level: Int,
        bundle: Bundle = .main
    ) async throws -> UIImage {
        let cacheKey = "\(bundle.bundleURL.path)#rest#\(level)"
        if let cached = restCache[cacheKey] {
            touchRestCache(cacheKey)
            return cached.image
        }
        guard let definition = MascotRigLevelCatalog.definitions[level] else {
            throw MascotRigAssetError.unsupportedLevel(level)
        }
        let subdirectory = String(
            format: "MascotRig/level_%02d",
            level
        )
        let request = try imageLoadRequest(
            descriptor: definition.rest,
            part: nil,
            bundle: bundle,
            subdirectory: subdirectory
        )
        let maxPixelSize = restThumbnailMaxPixelSize
        let loaded = try await MascotImageLoadingWorker.run {
            try Self.loadVerifiedImage(
                request,
                definition: definition,
                thumbnailMaxPixelSize: maxPixelSize
            )
        }
        insertRestCache(
            loaded,
            level: level,
            key: cacheKey
        )
        return loaded.image
    }

    func images(
        level: Int,
        bundle: Bundle = .main
    ) async throws -> MascotRigImages {
        guard let definition = MascotRigLevelCatalog.definitions[level] else {
            throw MascotRigAssetError.unsupportedLevel(level)
        }
        let cacheKey = "\(bundle.bundleURL.path)#rig#\(level)"
        let subdirectory = String(
            format: "MascotRig/level_%02d",
            level
        )

        _ = try MascotRigSemanticPart.allCases.map { part in
            try imageLoadRequest(
                descriptor: try definition.semanticPart(part),
                part: part,
                bundle: bundle,
                subdirectory: subdirectory
            )
        }
        let restRequest = try imageLoadRequest(
            descriptor: definition.rest,
            part: nil,
            bundle: bundle,
            subdirectory: subdirectory
        )
        let blinkRequest = try imageLoadRequest(
            descriptor: definition.blink,
            part: nil,
            bundle: bundle,
            subdirectory: subdirectory
        )
        let celebrateRequest = try imageLoadRequest(
            descriptor: definition.celebrate,
            part: nil,
            bundle: bundle,
            subdirectory: subdirectory
        )

        let representation = try await heavyCache.value(
            for: cacheKey
        ) {
            try await MascotImageLoadingWorker.run {
                let rest = try Self.loadVerifiedImage(
                    restRequest,
                    definition: definition
                )
                let blink = try Self.loadVerifiedImage(
                    blinkRequest,
                    definition: definition
                )
                let celebrate = try Self.loadVerifiedImage(
                    celebrateRequest,
                    definition: definition
                )
                return .rig(
                    level: level,
                    images: MascotRigImages(
                        rest: rest.image,
                        blink: blink.image,
                        celebrate: celebrate.image,
                        semanticPartNames: MascotRigSemanticPart.allCases
                            .map(\.rawValue)
                    ),
                    cost: rest.cost + blink.cost + celebrate.cost
                )
            }
        }
        guard case let .rig(cachedLevel, images, _) = representation,
              cachedLevel == level else {
            throw MascotRigAssetError.invalidImage("rig-\(level)")
        }
        return images
    }

    func fallbackLayers(
        level: Int,
        bundle: Bundle = .main
    ) async throws -> [MascotRigFallbackLayer] {
        let cacheKey = "\(bundle.bundleURL.path)#fallback#\(level)"
        guard let definition = MascotRigLevelCatalog.definitions[level] else {
            throw MascotRigAssetError.unsupportedLevel(level)
        }

        let subdirectory = String(
            format: "MascotRig/level_%02d",
            level
        )
        let requests = try MascotRigSemanticPart.allCases.map { part in
            guard let descriptor = definition.semanticParts[part] else {
                throw MascotRigAssetError.missingAsset(part.rawValue)
            }
            return try imageLoadRequest(
                descriptor: descriptor,
                part: part,
                bundle: bundle,
                subdirectory: subdirectory
            )
        }
        let thumbnailMaxPixelSize = fallbackThumbnailMaxPixelSize
        let representation = try await heavyCache.value(
            for: cacheKey
        ) {
            try await MascotImageLoadingWorker.run {
                var cost = 0
                let layers = try requests.map { request in
                    guard let part = request.part else {
                        throw MascotRigAssetError.invalidImage(
                            request.descriptor.name
                        )
                    }
                    let loaded = try Self.loadVerifiedImage(
                        request,
                        definition: definition,
                        thumbnailMaxPixelSize: thumbnailMaxPixelSize
                    )
                    cost += loaded.cost
                    return MascotRigFallbackLayer(
                        part: part,
                        image: loaded.image
                    )
                }
                return .fallback(
                    level: level,
                    layers: layers,
                    cost: cost
                )
            }
        }
        guard case let .fallback(
            cachedLevel,
            layers,
            _
        ) = representation,
        cachedLevel == level else {
            throw MascotRigAssetError.invalidImage(
                "semantic-fallback-\(level)"
            )
        }
        return layers
    }

    func cacheDiagnostics() -> MascotRigCacheDiagnostics {
        let rigLevels: [Int]
        let fallbackLevels: [Int]
        switch heavyCache.cachedValue {
        case let .rig(level, _, _):
            rigLevels = [level]
            fallbackLevels = []
        case let .fallback(level, _, _):
            rigLevels = []
            fallbackLevels = [level]
        case nil:
            rigLevels = []
            fallbackLevels = []
        }
        return MascotRigCacheDiagnostics(
            rigLevels: rigLevels,
            restLevels: restLRU.compactMap { restCache[$0]?.level },
            fallbackLevels: fallbackLevels,
            heavyCost: heavyCache.cachedCost,
            restCost: restCacheCost
        )
    }

    private func imageLoadRequest(
        descriptor: MascotRigKeyframeDescriptor,
        part: MascotRigSemanticPart?,
        bundle: Bundle,
        subdirectory: String
    ) throws -> ImageLoadRequest {
        guard let url = bundle.url(
            forResource: descriptor.name,
            withExtension: "png",
            subdirectory: subdirectory
        ) else {
            throw MascotRigAssetError.missingAsset(descriptor.name)
        }
        return ImageLoadRequest(
            part: part,
            descriptor: descriptor,
            url: url
        )
    }

    nonisolated private static func loadVerifiedImage(
        _ request: ImageLoadRequest,
        definition: MascotRigLevelDefinition,
        thumbnailMaxPixelSize: Int? = nil
    ) throws -> LoadedImage {
        try Task.checkCancellation()
        let descriptor = request.descriptor
        let data = try Data(
            contentsOf: request.url,
            options: .mappedIfSafe
        )
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == descriptor.sha256 else {
            throw MascotRigAssetError.checksumMismatch(descriptor.name)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ),
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw MascotRigAssetError.invalidImage(descriptor.name)
        }
        guard width == Int(definition.canvasSize.width),
              height == Int(definition.canvasSize.height) else {
            throw MascotRigAssetError.invalidDimensions(descriptor.name)
        }

        let cgImage: CGImage?
        if let thumbnailMaxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            )
        } else {
            cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            )
        }
        guard let cgImage else {
            throw MascotRigAssetError.invalidImage(descriptor.name)
        }
        try Task.checkCancellation()
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        let preparedImage = image.preparingForDisplay() ?? image
        let preparedCGImage = preparedImage.cgImage ?? cgImage
        return LoadedImage(
            image: preparedImage,
            cost: preparedCGImage.bytesPerRow * preparedCGImage.height
        )
    }

    private func touchRestCache(_ key: String) {
        restLRU.removeAll { $0 == key }
        restLRU.append(key)
    }

    private func insertRestCache(
        _ loaded: LoadedImage,
        level: Int,
        key: String
    ) {
        guard restCacheCostLimit > 0,
              loaded.cost <= restCacheCostLimit else {
            return
        }
        if let existing = restCache.removeValue(forKey: key) {
            restCacheCost -= existing.cost
        }
        restLRU.removeAll { $0 == key }
        while restCacheCost + loaded.cost > restCacheCostLimit,
              let oldestKey = restLRU.first {
            restLRU.removeFirst()
            if let evicted = restCache.removeValue(forKey: oldestKey) {
                restCacheCost -= evicted.cost
            }
        }
        restCache[key] = RestCacheEntry(
            level: level,
            image: loaded.image,
            cost: loaded.cost
        )
        restLRU.append(key)
        restCacheCost += loaded.cost
    }
}
