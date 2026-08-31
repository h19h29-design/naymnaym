import CryptoKit
import Foundation
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

    func testEveryManifestAssetPathIsGitTrackedAndChecksumMatches() throws {
        let entries = try manifestEntries()

        XCTAssertFalse(entries.isEmpty)
        let failures = validate(entries: entries)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testManifestValidatorRejectsTamperedHashAndUntrackedPath() throws {
        let validEntry = try XCTUnwrap(manifestEntries().first { $0.sha256 != "N/A" })
        let tampered = ManifestEntry(
            path: validEntry.path,
            sha256: String(repeating: "0", count: 64)
        )
        let untracked = ManifestEntry(
            path: "build/verification/task8-fix-round1/untracked-fixture.png",
            sha256: validEntry.sha256
        )

        let failures = validate(entries: [tampered, untracked])

        XCTAssertTrue(
            failures.contains { $0.contains("checksum mismatch") },
            "tampered manifest hashes must be rejected"
        )
        XCTAssertTrue(
            failures.contains { $0.contains("not Git-tracked") },
            "untracked manifest paths must be rejected"
        )
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

    private struct ManifestEntry {
        let path: String
        let sha256: String
    }

    private func manifestEntries() throws -> [ManifestEntry] {
        let manifests = [
            try manifest(named: "CHARACTER_ASSET_MANIFEST.md"),
            try manifest(named: "MEAL_ICON_ASSET_MANIFEST.md"),
        ]
        return manifests.flatMap(parseEntries)
    }

    private func parseEntries(_ text: String) -> [ManifestEntry] {
        var entries: [ManifestEntry] = []
        var header: [String: Int]?

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.contains("|") else {
                header = nil
                continue
            }
            let cells = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            if cells.contains("sha256"),
               let pathIndex = cells.firstIndex(where: {
                   $0 == "source_path" || $0 == "path"
               }),
               let checksumIndex = cells.firstIndex(of: "sha256") {
                header = [
                    "path": pathIndex,
                    "sha256": checksumIndex,
                ]
                continue
            }

            guard let header,
                  header.values.allSatisfy({ $0 < cells.count }),
                  cells.allSatisfy({ $0 != "---" })
            else {
                continue
            }
            let path = cells[header["path"]!]
            let sha256 = cells[header["sha256"]!]
            guard path != "N/A", sha256 != "N/A" else {
                continue
            }
            entries.append(ManifestEntry(path: path, sha256: sha256))
        }

        return entries
    }

    private func validate(entries: [ManifestEntry]) -> [String] {
        entries.flatMap { entry in
            var failures: [String] = []
            guard gitTracks(entry.path) else {
                failures.append("\(entry.path) is not Git-tracked")
                return failures
            }

            let url = repositoryRoot.appendingPathComponent(entry.path)
            guard let data = try? Data(contentsOf: url) else {
                failures.append("\(entry.path) is missing")
                return failures
            }
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            if digest != entry.sha256 {
                failures.append("\(entry.path) checksum mismatch")
            }
            return failures
        }
    }

    private func gitTracks(_ path: String) -> Bool {
        // XCTest runs against the iOS SDK, where Foundation.Process is
        // unavailable. Reading the worktree's Git index is the equivalent of
        // `git ls-files --error-unmatch -- <path>` and does not rely on a
        // shell or mutate the repository.
        guard let indexData = try? Data(contentsOf: gitIndexURL),
              indexData.count >= 12,
              indexData.prefix(4).elementsEqual(Data("DIRC".utf8)),
              readUInt32(indexData, at: 4) == 2
        else {
            return false
        }

        let entryCount = Int(readUInt32(indexData, at: 8))
        var offset = 12
        for _ in 0..<entryCount {
            guard offset + 62 <= indexData.count else { return false }
            let nameStart = offset + 62
            guard let nameEnd = indexData[nameStart...].firstIndex(of: 0) else {
                return false
            }
            let name = String(
                bytes: indexData[nameStart..<nameEnd],
                encoding: .utf8
            )
            if name == path {
                return true
            }
            let recordLength = nameEnd - offset + 1
            offset += (recordLength + 7) / 8 * 8
        }
        return false
    }

    private var gitIndexURL: URL {
        let gitFile = repositoryRoot.appendingPathComponent(".git")
        guard let pointer = try? String(contentsOf: gitFile, encoding: .utf8),
              pointer.hasPrefix("gitdir:")
        else {
            return gitFile.appendingPathComponent("index")
        }
        let target = pointer
            .dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURL = URL(fileURLWithPath: String(target), relativeTo: repositoryRoot)
        return targetURL.standardizedFileURL.appendingPathComponent("index")
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
    }
}
