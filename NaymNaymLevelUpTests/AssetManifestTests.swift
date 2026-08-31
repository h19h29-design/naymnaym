import CryptoKit
import XCTest
@testable import NaymNaymLevelUp

final class AssetManifestTests: XCTestCase {
    func testStagesOneThroughTwelveHaveDeterministicAssetResolution() {
        for stageID in 1...12 {
            let first = GrowthStageArtResolver.resolve(stageID: stageID)
            let second = GrowthStageArtResolver.resolve(stageID: stageID)

            XCTAssertEqual(first, second, "stage \(stageID) must resolve deterministically")
            XCTAssertEqual(first.stageID, stageID)
            XCTAssertEqual(first.artStageID, stageID)
            XCTAssertEqual(
                first.usesNeutralFallback,
                !MascotRigLevelCatalog.definitions.keys.contains(stageID),
                "stage \(stageID) must reflect the verified rig catalog"
            )
        }
    }

    func testMissingStageAssetReturnsNeutralFallback() throws {
        let resolution = GrowthStageArtResolver.resolve(stageID: 8)

        XCTAssertEqual(resolution.stageID, 8)
        XCTAssertEqual(resolution.artStageID, 8)
        XCTAssertTrue(resolution.usesNeutralFallback)

        let manifest = try manifest(named: "CHARACTER_ASSET_MANIFEST.md")
        XCTAssertTrue(manifest.contains("그림 준비 중"))
        XCTAssertTrue(manifest.contains("neutral-fallback"))
    }

    func testFoodIconManifestContainsEveryResolverKey() throws {
        let manifest = try manifest(named: "MEAL_ICON_ASSET_MANIFEST.md")

        XCTAssertEqual(MealVisualIconManifest.semanticKeys.count, 13)
        for key in MealVisualIconManifest.semanticKeys.sorted() {
            XCTAssertTrue(
                manifest.contains("| \(key) |"),
                "missing manifest row for \(key)"
            )
        }
        for category in MealFoodCategory.allCases {
            let key = MealVisualIconManifest.iconKey(for: category)
            XCTAssertNotNil(MealVisualIconManifest.systemSymbol(for: key))
        }
    }

    func testIncompleteRigThrowsMissingSemanticDescriptorInsteadOfTrapping() {
        let descriptor = MascotRigKeyframeDescriptor(
            name: "missing",
            sha256: String(repeating: "0", count: 64)
        )
        let definition = MascotRigLevelDefinition(
            canvasSize: CGSize(width: 1_254, height: 1_254),
            anchor: CGPoint(x: 627, y: 1_128),
            rest: descriptor,
            blink: descriptor,
            celebrate: descriptor,
            semanticParts: [:]
        )

        XCTAssertThrowsError(try definition.semanticPart(.body)) { error in
            XCTAssertEqual(error as? MascotRigAssetError, .missingAsset("body"))
        }
    }

    func testUnlicensedOrUntrackedAssetIsRejected() throws {
        let characterManifest = try manifest(named: "CHARACTER_ASSET_MANIFEST.md")
        let mealManifest = try manifest(named: "MEAL_ICON_ASSET_MANIFEST.md")
        let combined = characterManifest + "\n" + mealManifest

        XCTAssertFalse(combined.localizedCaseInsensitiveContains("unlicensed"))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("unknown source"))
        XCTAssertFalse(combined.contains("http://"))
        XCTAssertTrue(combined.contains("license"))
        XCTAssertTrue(combined.contains("source"))

        for path in assetPaths(in: combined) where path != "N/A" {
            let url = repositoryRoot.appendingPathComponent(path)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "manifest path is not tracked: \(path)"
            )
        }
    }

    func testExistingStageSourcesKeepStableNamesAndChecksums() throws {
        let expected: [Int: (String, String)] = [
            1: ("Squirrel_Growth_Level_1.png", "e5469a7652dc91989ddbf6c11ccb6355724fb831b4dac90ee66f249939882cfa"),
            2: ("Squirrel_Growth_Level_2.png", "e99fe61d9fe6aaf6a4b85d6390f96a47de74d0420cb181dae75bc890dea90878"),
            3: ("Squirrel_Growth_Level_3.png", "4206e8ad0fd2b4822805ac1cb9468f6779af6d25e36a00137e4289d399e65ae5"),
            4: ("Squirrel_Growth_Level_4.png", "a24f6a94115ceabb67cf547b7d2934de7bc9244f0c97ffdbabf1b20d76010dd1"),
            5: ("Squirrel_Growth_Level_5.png", "4d7518d077ef0c07b884337b2646972ab03b03353a463b394c5957510238b4d2"),
            6: ("Squirrel_Growth_Level_6.png", "5351093f343254da3c36f53e15030d81bba9655749df0c94754c028944efc188"),
            7: ("Squirrel_Growth_Level_7.png", "bd68b019f9a9bf3a1d149bdd1735ac7d0dc063aad6eefa3a9d0311c5f7b09ccb"),
        ]

        XCTAssertEqual(Set(expected.keys), Set(1...7))
        for stageID in 1...7 {
            let sourcePath = repositoryRoot
                .appendingPathComponent("NaymNaymLevelUp/Resources/Assets.xcassets")
                .appendingPathComponent("Squirrel_Growth_Level_\(stageID).imageset")
                .appendingPathComponent(expected[stageID]!.0)
            let data = try Data(contentsOf: sourcePath)
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(digest, expected[stageID]!.1, "stage \(stageID) source changed")
        }
    }

    func testFirstPartyLottieNamesAndChecksumsRemainStable() throws {
        let expected: [String: String] = [
            "mascot_intro": "785f97252ba465e81f7a8288ddf8ce9944bbe4828980cfc8cd44fa03937abfd5",
            "mascot_idle_loop": "98012e35436d1759a4e4225be714ea85f3536391f405340be132f840bccc73dd",
            "mascot_wave": "93c529a6a6243c7ffeb7bd8099dd89404db57484b97ae194453c6514b699448c",
            "mascot_success": "595d3e66aea23041945d3b8cc0d250de4f7a3819f48c1f58b4fbbdd01aa69ff0",
            "mascot_levelup": "9aec1417f61e8c014b26afa8a73b1855eafdb76add55eb2cc9b466440ec2c3ec",
            "mascot_allergy_warning": "8fb3ad67c160a626214861fe58ddc2719266f81b2167fdc47ce74b2c51286782",
        ]

        XCTAssertEqual(LottieAnimationCatalog.expectedAnimationNames.sorted(), expected.keys.sorted())
        for name in LottieAnimationCatalog.expectedAnimationNames {
            let path = repositoryRoot
                .appendingPathComponent("NaymNaymLevelUp/Resources/Animations")
                .appendingPathComponent("\(name).json")
            let digest = SHA256.hash(data: try Data(contentsOf: path))
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(digest, expected[name], "Lottie file changed: \(name)")
        }
    }

    func testNeutralFallbackDoesNotChangeXPOrEntitlement() throws {
        let policy = try GrowthPolicy(data: Data(
            #"{"version":1,"thresholds":[0,80,180,320,500,720,1000,1300,1650,2050,2500,3000],"titles":["냠냠 새싹","한 입 탐험가","냠냠 용사","편식 몬스터 사냥꾼","급식 히어로","영양 마스터","레전드 냠냠러","별빛 셰프","균형 수호자","숲의 영양 기사","황금 한입 챔피언","전설의 급식대장"]}"#.utf8
        ))
        let before = GrowthEntitlementResolver.resolve(
            policy: policy,
            totalXP: 1_300,
            legacy: .empty,
            stored: nil
        )
        _ = GrowthStageArtResolver.resolve(stageID: 8)
        let after = GrowthEntitlementResolver.resolve(
            policy: policy,
            totalXP: 1_300,
            legacy: .empty,
            stored: nil
        )

        XCTAssertEqual(before, after)
        XCTAssertEqual(before.highestUnlockedStageID, 8)
        XCTAssertEqual(before.selectedStageID, 8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func manifest(named name: String) throws -> String {
        let url = repositoryRoot
            .appendingPathComponent("docs")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assetPaths(in text: String) -> [String] {
        text.split(separator: "\n")
            .filter { $0.hasPrefix("|") }
            .flatMap { line in
                line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.contains("/") && !$0.contains("sha") }
            }
            .filter { $0.hasPrefix("NaymNaymLevelUp/") }
    }
}
