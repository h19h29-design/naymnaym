import CoreData
import Foundation
import XCTest
@testable import NaymNaymLevelUp

final class NutrientImpactSidecarTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NutrientImpactSidecarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testInstallRoundTripsOnlyForExactRevision() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let updatedAt = Date(timeIntervalSince1970: 10)
        let snapshot = fixtureSnapshot(status: .oneBite, updatedAt: updatedAt)

        try store.install(snapshot)
        let installedFile = try XCTUnwrap(singleJSONFile())
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: installedFile.path)[.posixPermissions]
                as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        XCTAssertEqual(
            try store.load(matching: fixtureRevision(status: .oneBite, updatedAt: updatedAt)),
            snapshot
        )
        XCTAssertNil(try store.load(matching: fixtureRevision(status: .finished, updatedAt: updatedAt)))
        XCTAssertNil(
            try store.load(matching: fixtureRevision(
                recordID: "different-record",
                status: .oneBite,
                updatedAt: updatedAt
            ))
        )
        XCTAssertNil(
            try store.load(matching: fixtureRevision(
                normalizedMenuName: "보리밥",
                status: .oneBite,
                updatedAt: updatedAt
            ))
        )
        XCTAssertNil(
            try store.load(matching: fixtureRevision(
                status: .oneBite,
                updatedAt: Date(timeIntervalSince1970: 11)
            ))
        )
    }

    func testStatusChangeCreatesNewImmutableFile() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let first = fixtureSnapshot(
            status: .oneBite,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        try store.install(first)
        let firstURL = try XCTUnwrap(singleJSONFile())
        let firstBytes = try Data(contentsOf: firstURL)

        let second = fixtureSnapshot(
            status: .finished,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try store.install(second)

        let files = try jsonFiles()
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(
            try store.load(matching: fixtureRevision(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))),
            first
        )
        XCTAssertEqual(
            try store.load(matching: fixtureRevision(status: .finished, updatedAt: Date(timeIntervalSince1970: 20))),
            second
        )
    }

    func testCorruptedOrMismatchedSnapshotFallsBackToCurrentGuidance() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let original = fixtureSnapshot(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))
        try store.install(original)
        let file = try XCTUnwrap(singleJSONFile())
        let originalBytes = try Data(contentsOf: file)
        try Data("{not-json".utf8).write(to: file)
        XCTAssertNil(
            try store.load(matching: fixtureRevision(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10)))
        )
        XCTAssertThrowsError(try store.install(original))

        try originalBytes.write(to: file)
        let replacement = fixtureSnapshot(status: .finished, updatedAt: Date(timeIntervalSince1970: 20))
        try store.install(replacement)
        let replacementURL = try XCTUnwrap(
            try jsonFiles().first { url in
                (try? decodedSnapshot(at: url)) == replacement
            }
        )
        try originalBytes.write(to: replacementURL)
        XCTAssertNil(
            try store.load(matching: fixtureRevision(status: .finished, updatedAt: Date(timeIntervalSince1970: 20)))
        )
    }

    func testPayloadTamperingWithoutIntegrityMetadataReturnsNil() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let snapshot = fixtureSnapshot(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))
        let revision = fixtureRevision(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))
        try store.install(snapshot)
        let file = try XCTUnwrap(singleJSONFile())
        let originalBytes = try Data(contentsOf: file)

        let tamperedValues: [(String, Any)] = [
            ("headline", "변조된 교육 문장이에요."),
            ("nutrients", ["protein"]),
            ("alternatives", ["다른 반찬을 살펴봐요."]),
        ]
        for (key, value) in tamperedValues {
            try originalBytes.write(to: file)
            var object = try jsonObject(at: file)
            var snapshotObject = try XCTUnwrap(object["snapshot"] as? [String: Any])
            snapshotObject[key] = value
            object["snapshot"] = snapshotObject
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file)

            XCTAssertNil(try store.load(matching: revision), "Tampered key was accepted: \(key)")
        }
    }

    func testSchemaRuleAndFingerprintMismatchReturnNil() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let snapshot = fixtureSnapshot(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))
        try store.install(snapshot)
        let file = try XCTUnwrap(singleJSONFile())
        let originalBytes = try Data(contentsOf: file)

        for (key, value) in [("schemaVersion", 2), ("ruleVersion", 99)] {
            try originalBytes.write(to: file)
            var object = try jsonObject(at: file)
            var snapshotObject = try XCTUnwrap(object["snapshot"] as? [String: Any])
            snapshotObject[key] = value
            object["snapshot"] = snapshotObject
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file)
            XCTAssertNil(
                try store.load(matching: fixtureRevision(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10)))
            )
        }

        try originalBytes.write(to: file)
        var object = try jsonObject(at: file)
        var snapshotObject = try XCTUnwrap(object["snapshot"] as? [String: Any])
        snapshotObject["recordID"] = "different-record"
        object["snapshot"] = snapshotObject
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file)
        XCTAssertNil(
            try store.load(matching: fixtureRevision(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10)))
        )

        for mutation in [
            { (object: inout [String: Any]) in object["envelopeVersion"] = 2 },
            { (object: inout [String: Any]) in object["unexpected"] = true },
            { (object: inout [String: Any]) in object["revisionFingerprint"] = String(repeating: "0", count: 64) },
            { (object: inout [String: Any]) in object["snapshotDigest"] = String(repeating: "0", count: 64) },
        ] {
            try originalBytes.write(to: file)
            var envelope = try jsonObject(at: file)
            mutation(&envelope)
            try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: file)
            XCTAssertNil(
                try store.load(matching: fixtureRevision(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10)))
            )
        }
    }

    func testFallbackRuleVersionRoundTripsAsCanonicalSnapshot() throws {
        XCTAssertEqual(NutrientImpactSnapshot.fallbackRuleVersion, 0)
        XCTAssertNotEqual(
            NutrientImpactSnapshot.fallbackRuleVersion,
            NutrientImpactSnapshot.supportedRuleVersion
        )
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let updatedAt = Date(timeIntervalSince1970: 10)
        let snapshot = try XCTUnwrap(
            NutrientImpactSnapshotFactory.make(
                ruleVersion: NutrientImpactSnapshot.fallbackRuleVersion,
                recordID: "fallback-rule-version",
                date: "2026-08-30",
                normalizedMenuName: "처음 보는 메뉴",
                status: .finished,
                recordUpdatedAt: updatedAt,
                nutrientIDs: []
            )
        )

        try store.install(snapshot)

        XCTAssertEqual(snapshot.ruleVersion, 0)
        XCTAssertEqual(
            try store.load(matching: fixtureRevision(
                recordID: snapshot.recordID,
                normalizedMenuName: snapshot.normalizedMenuName,
                status: snapshot.status,
                updatedAt: updatedAt
            )),
            snapshot
        )
        XCTAssertNil(
            NutrientImpactSnapshotFactory.make(
                ruleVersion: 99,
                recordID: "unsupported-rule-version",
                date: "2026-08-30",
                normalizedMenuName: "처음 보는 메뉴",
                status: .finished,
                recordUpdatedAt: updatedAt,
                nutrientIDs: []
            )
        )
    }

    func testInstallRejectsPathAndCopyMutations() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)

        assertInstallRejected(store, fixtureSnapshot(recordID: "../escape"))
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "path-menu-1", normalizedMenuName: "menu/../escape")
        )
        assertInstallRejected(store, fixtureSnapshot(recordID: #"menu\..\escape"#))
        assertInstallRejected(store, fixtureSnapshot(recordID: "opaque-null-\u{0000}id"))
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-1", headline: "단백질 12g을 먹었어요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-2", explanation: "철분 4 mg을 섭취했어요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-3", explanation: "철분 12㎎을 섭취했어요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-4", explanation: "철분 １２ｍｇ을 섭취했어요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-5", headline: "철분이 부족하니 꼭 먹어야 해요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-6", headline: "영양소가 모자라면 몸이 나빠져요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-7", headline: "의사 진단이 필요해요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-8", explanation: "이 문장에는 API token이 들어 있어요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-9", disclaimer: "알레르기가 있어도 먹어도 괜찮아요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-10", disclaimer: "알레르기가 있더라도 다시 먹어봐요.")
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "forbidden-copy-11", disclaimer: "알레르기지만 조금은 먹어보세요.")
        )
    }

    func testCanonicalCopyWorksWithOpaqueIdentifiers() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let snapshot = try XCTUnwrap(
            NutrientImpactSnapshotFactory.make(
                recordID: #"opaque/path\record:01.v1"#,
                date: "2026-08-30",
                normalizedMenuName: "현미밥·콩나물",
                status: .oneBite,
                recordUpdatedAt: Date(timeIntervalSince1970: 10),
                nutrientIDs: ["carbohydrate"]
            )
        )

        try store.install(snapshot)
        XCTAssertEqual(
            try store.load(matching: RebuildMealRecordRevision(
                recordID: snapshot.recordID,
                date: snapshot.date,
                normalizedMenuName: snapshot.normalizedMenuName,
                status: snapshot.status,
                updatedAt: snapshot.recordUpdatedAt
            )),
            snapshot
        )

        let changedDisclaimer = NutrientImpactSnapshot(
            schemaVersion: snapshot.schemaVersion,
            ruleVersion: snapshot.ruleVersion,
            recordID: "contract-disclaimer",
            date: snapshot.date,
            normalizedMenuName: snapshot.normalizedMenuName,
            status: snapshot.status,
            recordUpdatedAt: Date(timeIntervalSince1970: 11),
            nutrients: snapshot.nutrients,
            headline: snapshot.headline,
            explanation: snapshot.explanation,
            alternatives: snapshot.alternatives,
            disclaimer: "영양 정보는 교육용 참고 정보예요."
        )
        XCTAssertThrowsError(try store.install(changedDisclaimer)) { error in
            XCTAssertEqual(error as? NutrientImpactSidecarError, .invalidSnapshot)
        }
    }

    func testNonCanonicalSafetyCopyIsRejected() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let rejectedCopy = [
            "철분 12\u{200B}mg을 섭취했어요.",
            "철분 １２\u{200B}㎎을 섭취했어요.",
            "알레르기가 있는데 한 입 시도해요.",
            "알레르기가 있는데 한 입 먹어요.",
            "알레르기가 있으면 조금 먹어 보세요.",
            "알레르기가 있다면 조금 먹어 보세요.",
            "알레르기가 있는 경우 한 입 먹어요.",
            "알레르기가 있으면 소량 섭취해 보세요.",
            "알레르기가 있더라도 맛을 보세요.",
            "알레르기가 있을 때 드세요.",
            "알레르기가 있어서 먹어요.",
            "알레르기 때문에 먹어 봐요.",
            "알레르기가 있는데 먹지 않다가 한 입 시도해요.",
            "철분이 모자라요.",
            "철분이 모자랍니다.",
            "철분이 모자란 상태예요.",
            "철분이 부족해요.",
            "철분 결핍이에요.",
            "철분 결핍 상태예요.",
            "영양소 부족을 진단하지 않아요. 철분 결핍 상태예요.",
            "철분이 모자라서 몸이 나빠져요.",
            "철분 결핍이라고 진단해요.",
            "이 증상은 치료가 필요해요.",
        ]
        for (index, copy) in rejectedCopy.enumerated() {
            let snapshot = fixtureSnapshot(
                recordID: "noncanonical-copy-\(index)",
                headline: copy
            )
            XCTAssertThrowsError(try store.install(snapshot)) { error in
                XCTAssertEqual(error as? NutrientImpactSidecarError, .invalidSnapshot)
            }
        }
        XCTAssertTrue(try jsonFiles().isEmpty)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)
    }

    func testDirectorySyncFailureKeepsPublishedRevisionImmutable() throws {
        let snapshot = fixtureSnapshot(recordID: "directory-sync-failure")
        let failingStore = FileNutrientImpactSidecar(
            directoryURL: temporaryDirectory,
            directorySync: { _ in -1 }
        )

        XCTAssertThrowsError(try failingStore.install(snapshot)) { error in
            XCTAssertEqual(error as? NutrientImpactSidecarError, .writeFailed)
        }
        let file = try XCTUnwrap(singleJSONFile())
        let publishedBytes = try Data(contentsOf: file)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)

        let restartedStore = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let revision = RebuildMealRecordRevision(
            recordID: snapshot.recordID,
            date: snapshot.date,
            normalizedMenuName: snapshot.normalizedMenuName,
            status: snapshot.status,
            updatedAt: snapshot.recordUpdatedAt
        )
        XCTAssertEqual(try restartedStore.load(matching: revision), snapshot)
        XCTAssertNoThrow(try restartedStore.install(snapshot))
        XCTAssertEqual(try Data(contentsOf: file), publishedBytes)
    }

    func testExistingRevisionRetryResynchronizesPublishedDirectory() throws {
        let snapshot = fixtureSnapshot(recordID: "directory-resync")
        let firstStore = FileNutrientImpactSidecar(
            directoryURL: temporaryDirectory,
            directorySync: { _ in -1 }
        )
        XCTAssertThrowsError(try firstStore.install(snapshot))
        let file = try XCTUnwrap(singleJSONFile())
        let publishedBytes = try Data(contentsOf: file)

        let successfulSyncs = SidecarLockedCounter()
        let retryStore = FileNutrientImpactSidecar(
            directoryURL: temporaryDirectory,
            directorySync: { _ in successfulSyncs.increment(); return 0 }
        )
        XCTAssertNoThrow(try retryStore.install(snapshot))
        XCTAssertEqual(successfulSyncs.value, 1)
        XCTAssertEqual(try Data(contentsOf: file), publishedBytes)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)

        let failedSyncs = SidecarLockedCounter()
        let failingRetryStore = FileNutrientImpactSidecar(
            directoryURL: temporaryDirectory,
            directorySync: { _ in failedSyncs.increment(); return -1 }
        )
        XCTAssertThrowsError(try failingRetryStore.install(snapshot)) { error in
            XCTAssertEqual(error as? NutrientImpactSidecarError, .writeFailed)
        }
        XCTAssertEqual(failedSyncs.value, 1)
        XCTAssertEqual(try Data(contentsOf: file), publishedBytes)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)
    }

    func testUTF8ByteLimitsRejectCombiningPayloadAndOversizedFileReturnsNil() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let combiningPayload = String(
            repeating: "e\u{301}\u{302}\u{303}\u{304}\u{305}",
            count: 400
        )
        XCTAssertLessThan(combiningPayload.count, 1_000)
        XCTAssertGreaterThan(combiningPayload.utf8.count, 4_096)
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: "utf8-combining", headline: combiningPayload)
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(recordID: String(repeating: "😀", count: 257))
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(
                recordID: "utf8-too-many-nutrients",
                nutrients: (0..<33).map { "nutrient-\($0)" }
            )
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(
                recordID: "utf8-too-many-alternatives",
                status: .difficultToday,
                alternatives: (0..<9).map { "교육 문장 \($0)번을 살펴봐요." }
            )
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(
                recordID: "utf8-long-alternatives",
                status: .difficultToday,
                alternatives: Array(repeating: String(repeating: "가", count: 1_000), count: 8)
            )
        )

        let allowedMultibyte = fixtureSnapshot(
            recordID: String(repeating: "가", count: 300)
        )
        XCTAssertNoThrow(try store.install(allowedMultibyte))

        let file = try XCTUnwrap(singleJSONFile())
        try Data(repeating: 0x41, count: 65_537).write(to: file)
        XCTAssertNil(try store.load(matching: RebuildMealRecordRevision(
            recordID: allowedMultibyte.recordID,
            date: allowedMultibyte.date,
            normalizedMenuName: allowedMultibyte.normalizedMenuName,
            status: allowedMultibyte.status,
            updatedAt: allowedMultibyte.recordUpdatedAt
        )))
    }

    func testFingerprintNormalizesNFCWhileExactRevisionFieldsRemainExact() throws {
        let nfcDirectory = temporaryDirectory.appendingPathComponent("nfc", isDirectory: true)
        let nfdDirectory = temporaryDirectory.appendingPathComponent("nfd", isDirectory: true)
        let nfc = "café"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))

        let nfcSnapshot = fixtureSnapshot(recordID: nfc, normalizedMenuName: nfc)
        let nfdSnapshot = fixtureSnapshot(recordID: nfd, normalizedMenuName: nfd)
        let nfcStore = FileNutrientImpactSidecar(directoryURL: nfcDirectory)
        let nfdStore = FileNutrientImpactSidecar(directoryURL: nfdDirectory)
        try nfcStore.install(nfcSnapshot)
        try nfdStore.install(nfdSnapshot)

        XCTAssertEqual(
            try XCTUnwrap(try jsonFiles(in: nfcDirectory).first).lastPathComponent,
            try XCTUnwrap(try jsonFiles(in: nfdDirectory).first).lastPathComponent
        )
        XCTAssertEqual(
            try nfcStore.load(matching: fixtureRevision(recordID: nfc, normalizedMenuName: nfc)),
            nfcSnapshot
        )
        let canonicallyEquivalentLoad = try XCTUnwrap(
            try nfcStore.load(matching: fixtureRevision(recordID: nfd, normalizedMenuName: nfd))
        )
        XCTAssertEqual(Array(canonicallyEquivalentLoad.recordID.utf8), Array(nfc.utf8))
        XCTAssertEqual(Array(canonicallyEquivalentLoad.normalizedMenuName.utf8), Array(nfc.utf8))
    }

    func testConcurrentIdenticalInstallDoesNotCreateOrOverwriteRevision() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let snapshot = fixtureSnapshot(
            status: .difficultToday,
            updatedAt: Date(timeIntervalSince1970: 10),
            alternatives: ["브로콜리무침"]
        )

        let concurrentErrors = concurrentInstall(
            Array(repeating: snapshot, count: 8),
            into: store
        )
        XCTAssertTrue(concurrentErrors.isEmpty, "Concurrent identical installs failed: \(concurrentErrors)")
        XCTAssertEqual(try jsonFiles().count, 1)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)
        let before = try XCTUnwrap(singleJSONFile())
        let beforeBytes = try Data(contentsOf: before)

        let conflicting = fixtureSnapshot(
            status: .difficultToday,
            updatedAt: Date(timeIntervalSince1970: 10),
            alternatives: ["사과"]
        )
        XCTAssertThrowsError(try store.install(conflicting))
        XCTAssertEqual(try Data(contentsOf: before), beforeBytes)
    }

    func testConcurrentConflictingInstallsPublishExactlyOneImmutableWinner() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let candidates = (0..<8).map { index in
            fixtureSnapshot(
                status: .difficultToday,
                alternatives: ["메뉴\(index)"]
            )
        }

        let errors = concurrentInstall(candidates, into: store)

        XCTAssertEqual(errors.count, candidates.count - 1)
        XCTAssertTrue(errors.allSatisfy { ($0 as? NutrientImpactSidecarError) == .conflictingRevision })
        XCTAssertEqual(try jsonFiles().count, 1)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)
        let winner = try XCTUnwrap(
            try store.load(
                matching: fixtureRevision(status: .difficultToday)
            )
        )
        XCTAssertTrue(candidates.contains(winner))
        let winnerBytes = try Data(contentsOf: try XCTUnwrap(singleJSONFile()))
        XCTAssertThrowsError(try store.install(candidates.first { $0 != winner }!))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(singleJSONFile())), winnerBytes)
    }

    func testRestartReadBackAndOrphanOrStaleRevisionReturnNil() throws {
        let snapshot = fixtureSnapshot(status: .half, updatedAt: Date(timeIntervalSince1970: 10))
        try FileNutrientImpactSidecar(directoryURL: temporaryDirectory).install(snapshot)

        let restartedStore = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        XCTAssertEqual(
            try restartedStore.load(matching: fixtureRevision(status: .half, updatedAt: Date(timeIntervalSince1970: 10))),
            snapshot
        )
        XCTAssertNil(
            try restartedStore.load(matching: fixtureRevision(status: .half, updatedAt: Date(timeIntervalSince1970: 11)))
        )
        XCTAssertNil(
            try restartedStore.load(matching: fixtureRevision(recordID: "orphan", status: .half, updatedAt: Date(timeIntervalSince1970: 10)))
        )
    }

    func testSymlinkedSidecarDirectoryAndSnapshotAreNotFollowed() throws {
        let realDirectory = temporaryDirectory.appendingPathComponent("real", isDirectory: true)
        let linkedDirectory = temporaryDirectory.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)

        let snapshot = fixtureSnapshot(status: .half, updatedAt: Date(timeIntervalSince1970: 10))
        let linkedStore = FileNutrientImpactSidecar(directoryURL: linkedDirectory)
        XCTAssertThrowsError(try linkedStore.install(snapshot))
        XCTAssertNil(
            try linkedStore.load(matching: fixtureRevision(status: .half, updatedAt: Date(timeIntervalSince1970: 10)))
        )
        XCTAssertTrue(try jsonFiles(in: realDirectory).isEmpty)

        let realStore = FileNutrientImpactSidecar(directoryURL: realDirectory)
        try realStore.install(snapshot)
        let realFile = try XCTUnwrap(try jsonFiles(in: realDirectory).first)
        let originalBytes = try Data(contentsOf: realFile)
        let outsideFile = temporaryDirectory.appendingPathComponent("outside.json")
        try originalBytes.write(to: outsideFile)
        try FileManager.default.removeItem(at: realFile)
        try FileManager.default.createSymbolicLink(at: realFile, withDestinationURL: outsideFile)
        XCTAssertNil(
            try realStore.load(matching: fixtureRevision(status: .half, updatedAt: Date(timeIntervalSince1970: 10)))
        )
        XCTAssertThrowsError(try realStore.install(snapshot))
        XCTAssertEqual(try Data(contentsOf: outsideFile), originalBytes)
    }

    func testNoopSidecarDoesNotPersistOrReturnSnapshot() throws {
        let sidecar = NoopNutrientImpactSidecar()
        let snapshot = fixtureSnapshot(status: .finished, updatedAt: Date(timeIntervalSince1970: 10))
        XCTAssertNoThrow(try sidecar.install(snapshot))
        XCTAssertNil(
            try sidecar.load(matching: fixtureRevision(status: .finished, updatedAt: Date(timeIntervalSince1970: 10)))
        )
    }

    func testInMemorySidecarPreservesSharedValidatorErrors() throws {
        let sidecar = InMemoryNutrientImpactSidecar()
        let cases: [(NutrientImpactSnapshot, NutrientImpactSidecarError)] = [
            (
                fixtureSnapshot(schemaVersion: 99),
                .unsupportedSchemaVersion
            ),
            (
                fixtureSnapshot(ruleVersion: 99),
                .unsupportedRuleVersion
            ),
            (
                fixtureSnapshot(headline: "변조된 교육 문장이에요."),
                .invalidSnapshot
            ),
        ]

        for (snapshot, expectedError) in cases {
            XCTAssertThrowsError(try FileNutrientImpactSidecar.validate(snapshot)) { error in
                XCTAssertEqual(error as? NutrientImpactSidecarError, expectedError)
            }
            XCTAssertThrowsError(try sidecar.install(snapshot)) { error in
                XCTAssertEqual(error as? NutrientImpactSidecarError, expectedError)
            }
        }
    }

    func testInMemorySidecarRejectsConflictingRevisionLikeFileSidecar() throws {
        let sidecar = InMemoryNutrientImpactSidecar()
        let first = fixtureSnapshot(
            updatedAt: Date(timeIntervalSince1970: 10),
            nutrients: ["carbohydrate"]
        )
        let conflicting = fixtureSnapshot(
            updatedAt: Date(timeIntervalSince1970: 10),
            nutrients: ["protein"]
        )

        try sidecar.install(first)
        XCTAssertEqual(
            try sidecar.load(matching: fixtureRevision(updatedAt: Date(timeIntervalSince1970: 10))),
            first
        )
        XCTAssertThrowsError(try sidecar.install(conflicting)) { error in
            XCTAssertEqual(error as? NutrientImpactSidecarError, .conflictingRevision)
        }
        XCTAssertEqual(
            try sidecar.load(matching: fixtureRevision(updatedAt: Date(timeIntervalSince1970: 10))),
            first
        )
    }

    func testSidecarDoesNotChangeManagedModelSchema() throws {
        let model = RebuildManagedModel.make()
        XCTAssertEqual(model.entitiesByName.count, 8)
        XCTAssertNil(model.entitiesByName["NutrientImpactSnapshot"])
        XCTAssertEqual(
            model.entitiesByName[RebuildEntityName.migrationState]?.attributesByName.keys.sorted(),
            ["completedAt", "id", "sourceDigest", "version"]
        )
        XCTAssertEqual(
            model.entitiesByName[RebuildEntityName.mealRecord]?.attributesByName.keys.sorted(),
            [
                "allergyCodesJSON", "date", "deletedAt", "difficultyReasonsJSON",
                "id", "menuName", "normalizedMenuName", "parentShareEnabled",
                "photoIDsJSON", "status", "updatedAt",
            ]
        )
    }

    func testCanonicalCatalogCoversEveryStatusAndNormalizesKnownNutrients() throws {
        let statuses = RebuildEatingStatus.allCases
        let sourceNutrients = ["carbohydrate", "protein", "carbohydrate"]
        let expectedNutrients = ["protein", "carbohydrate"]
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)

        for (index, status) in statuses.enumerated() {
            let snapshot = try XCTUnwrap(
                NutrientImpactSnapshotFactory.make(
                    recordID: "canonical-status-\(index)",
                    date: "2026-08-30",
                    normalizedMenuName: "현미밥",
                    status: status,
                    recordUpdatedAt: Date(timeIntervalSince1970: TimeInterval(index + 10)),
                    nutrientIDs: sourceNutrients
                )
            )

            XCTAssertEqual(snapshot.nutrients, expectedNutrients)
            XCTAssertEqual(
                snapshot.disclaimer,
                "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요."
            )
            XCTAssertNoThrow(try store.install(snapshot))
        }

        XCTAssertEqual(try jsonFiles().count, statuses.count)
    }

    func testCanonicalCopyCatalogUsesExactStatusTable() throws {
        let expectedCopies: [(RebuildEatingStatus, NutrientImpactCopy)] = [
            (
                .finished,
                NutrientImpactCopy(
                    headline: "이 메뉴를 즐겁게 잘 마무리했어요!",
                    explanation: "이 메뉴에서는 보통 철분 같은 대표 영양소를 만날 수 있어요. 이 메뉴의 식사 경험을 멋지게 기록했어요.",
                    disclaimer: NutrientImpactCopyCatalog.educationNotice
                )
            ),
            (
                .half,
                NutrientImpactCopy(
                    headline: "절반까지 차근차근 먹어 봤어요!",
                    explanation: "절반까지 시도한 경험을 잘 기록했어요. 이 메뉴에서는 보통 철분 같은 대표 영양소를 만날 수 있어요.",
                    disclaimer: NutrientImpactCopyCatalog.educationNotice
                )
            ),
            (
                .oneBite,
                NutrientImpactCopy(
                    headline: "한 입 도전, 멋지게 해냈어요!",
                    explanation: "한 입으로 새로운 맛과 식감을 살펴봤어요. 이 메뉴에서는 보통 철분 같은 대표 영양소를 만날 수 있어요.",
                    disclaimer: NutrientImpactCopyCatalog.educationNotice
                )
            ),
            (
                .smelledOnly,
                NutrientImpactCopy(
                    headline: "냄새와 느낌을 살펴본 것도 멋진 탐색이에요!",
                    explanation: "오늘은 냄새와 느낌을 천천히 알아봤어요. 이 메뉴에서는 보통 철분 같은 대표 영양소를 만날 수 있어요.",
                    disclaimer: NutrientImpactCopyCatalog.educationNotice
                )
            ),
            (
                .difficultToday,
                NutrientImpactCopy(
                    headline: "오늘은 이 메뉴의 대표 영양소를 덜 섭취했을 수 있어요.",
                    explanation: "이 메뉴에서는 보통 철분 같은 대표 영양소를 만날 수 있어요. 그래도 괜찮아요. 솔직하게 기록한 것이 첫걸음이에요.",
                    disclaimer: NutrientImpactCopyCatalog.educationNotice
                )
            ),
            (
                .allergyAvoided,
                NutrientImpactCopy(
                    headline: "알레르기 안전을 먼저 챙긴 선택이에요!",
                    explanation: "보호자와 학교 안내를 먼저 확인해요.",
                    disclaimer: NutrientImpactCopyCatalog.educationNotice
                )
            ),
        ]
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)

        for (index, entry) in expectedCopies.enumerated() {
            let (status, expected) = entry
            XCTAssertEqual(
                NutrientImpactCopyCatalog.makeCopy(status: status, nutrientIDs: ["iron"]),
                expected,
                "Unexpected canonical copy for status index \(index)"
            )
            let snapshot = try XCTUnwrap(
                NutrientImpactSnapshotFactory.make(
                    recordID: "canonical-copy-table-\(index)",
                    date: "2026-08-30",
                    normalizedMenuName: "현미밥",
                    status: status,
                    recordUpdatedAt: Date(timeIntervalSince1970: TimeInterval(index + 10)),
                    nutrientIDs: ["iron"]
                )
            )
            XCTAssertEqual(snapshot.headline, expected.headline)
            XCTAssertEqual(snapshot.explanation, expected.explanation)
            XCTAssertEqual(snapshot.disclaimer, expected.disclaimer)
            if status == .smelledOnly || status == .allergyAvoided {
                XCTAssertFalse(expected.headline.contains("섭취"))
                XCTAssertFalse(expected.explanation.contains("섭취"))
                XCTAssertFalse(expected.explanation.contains("먹"))
            }
            if status == .difficultToday {
                XCTAssertTrue(expected.headline.contains("덜 섭취했을 수 있어요"))
                XCTAssertTrue(expected.explanation.contains("보통 철분"))
                XCTAssertTrue(expected.explanation.contains("그래도 괜찮아요"))
                XCTAssertTrue(expected.explanation.contains("솔직하게 기록한 것이 첫걸음"))
            }
            XCTAssertNoThrow(try store.install(snapshot))
        }
    }

    func testSameMealSelectorUsesProvenanceAndSharedNutrientPriority() throws {
        let current = mealItem(
            name: "현미밥",
            nutrients: ["protein", "iron"]
        )
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: "철분메뉴", nutrients: ["iron"]),
            mealItem(name: "단백질메뉴", nutrients: ["protein"]),
            mealItem(name: "복합메뉴", nutrients: ["protein", "iron"]),
            mealItem(name: "알레르기메뉴", allergyCodes: [3], nutrients: ["protein", "iron"]),
            mealItem(name: "무관메뉴", nutrients: ["carbohydrate"]),
        ])

        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: [3]
        ))

        XCTAssertEqual(selection.menuLabels, ["복합메뉴", "단백질메뉴"])
        XCTAssertEqual(selection.provenance.mealDayDate, mealDay.date)
        XCTAssertEqual(selection.provenance.currentMenuName, "현미밥")
        XCTAssertEqual(selection.provenance.targetNutrientIDs, ["protein", "iron"])
        XCTAssertTrue(selection.alternatives.allSatisfy { $0.provenance == selection.provenance })
        XCTAssertTrue(selection.alternatives.allSatisfy { !$0.nutrientIDs.isEmpty })
        XCTAssertFalse(selection.menuLabels.contains("현미밥"))
        XCTAssertEqual(selection.alternatives.count, 2)
    }

    func testSameMealSelectorReturnsProvenanceWhenNoAlternativeMatches() throws {
        let current = mealItem(name: " BBQ Chicken ", nutrients: ["단백질"])
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: "이름만비슷한메뉴", nutrients: []),
            mealItem(name: "무관메뉴", nutrients: ["탄수화물"]),
            mealItem(name: "알레르기메뉴", allergyCodes: [7], nutrients: ["단백질"]),
        ])

        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: [7]
        ))

        XCTAssertTrue(selection.alternatives.isEmpty)
        XCTAssertTrue(selection.menuLabels.isEmpty)
        XCTAssertEqual(selection.provenance.currentMenuName, "bbq chicken")
        XCTAssertEqual(selection.provenance.targetNutrientIDs, ["protein"])

        XCTAssertNotNil(NutrientImpactSnapshotFactory.make(
            recordID: "empty-selection-canonical",
            date: mealDay.date,
            normalizedMenuName: "bbq chicken",
            status: .difficultToday,
            recordUpdatedAt: Date(timeIntervalSince1970: 1),
            nutrientIDs: ["단백질"],
            alternativeSelection: selection
        ))
        XCTAssertNil(NutrientImpactSnapshotFactory.make(
            recordID: "empty-selection-wrong-date",
            date: "2026-08-31",
            normalizedMenuName: "bbq chicken",
            status: .difficultToday,
            recordUpdatedAt: Date(timeIntervalSince1970: 2),
            nutrientIDs: ["단백질"],
            alternativeSelection: selection
        ))
        XCTAssertNil(NutrientImpactSnapshotFactory.make(
            recordID: "empty-selection-wrong-menu",
            date: mealDay.date,
            normalizedMenuName: "BBQ Chicken",
            status: .difficultToday,
            recordUpdatedAt: Date(timeIntervalSince1970: 3),
            nutrientIDs: ["단백질"],
            alternativeSelection: selection
        ))
        XCTAssertNil(NutrientImpactSnapshotFactory.make(
            recordID: "empty-selection-wrong-nutrients",
            date: mealDay.date,
            normalizedMenuName: "bbq chicken",
            status: .difficultToday,
            recordUpdatedAt: Date(timeIntervalSince1970: 4),
            nutrientIDs: ["철분"],
            alternativeSelection: selection
        ))
    }

    func testNutrientCanonicalizerSharesRealParserAliasesAndStableOrder() {
        XCTAssertEqual(
            MealNutrientCanonicalizer.orderedKnownIDs(
                from: [" 탄수화물 ", "Protein", "식이섬유", "철", "칼슘", "비타민", "단백질"]
            ),
            ["fiber", "vitamin", "protein", "iron", "calcium", "carbohydrate"]
        )
        XCTAssertEqual(
            NutrientImpactCopyCatalog.canonicalNutrientIDs(
                fromRawValues: ["단백질", "철분", "protein"]
            ),
            ["protein", "iron"]
        )
        XCTAssertNil(
            NutrientImpactCopyCatalog.validatedCanonicalNutrientIDs(["단백질"])
        )
        XCTAssertEqual(
            NutrientImpactCopyCatalog.validatedCanonicalNutrientIDs(["protein", "iron"]),
            ["protein", "iron"]
        )
    }

    func testSameMealSelectorDerivesKoreanAndVisualNutrientsFromActualMembers() throws {
        let current = mealItem(name: " 닭갈비 ", nutrients: [])
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: "두부조림", nutrients: ["단백질"]),
            mealItem(name: "소고기볶음", nutrients: ["철"]),
            mealItem(name: "현미밥", nutrients: ["탄수화물"]),
        ])

        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: []
        ))

        XCTAssertEqual(selection.provenance.currentMenuName, "닭갈비")
        XCTAssertEqual(selection.provenance.targetNutrientIDs, ["protein", "iron"])
        XCTAssertEqual(selection.menuLabels, ["두부조림", "소고기볶음"])
        XCTAssertEqual(selection.alternatives.map(\.nutrientIDs), [["protein"], ["iron"]])
    }

    func testSameMealSelectorRejectsCurrentItemThatIsNotAMealDayMember() {
        let stored = mealItem(
            name: "BBQ 닭구이",
            nutrients: ["단백질"],
            sourceRawText: "BBQ 닭구이"
        )
        let detached = mealItem(
            name: "BBQ 닭구이",
            nutrients: ["단백질"],
            sourceRawText: "detached"
        )
        let mealDay = fixtureMealDay(items: [stored])

        XCTAssertNil(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: detached,
            childAllergyCodes: []
        ))
    }

    func testMealRecordIdentityNormalizerMatchesMixedCaseSelectorProvenance() throws {
        let current = mealItem(name: "  BBQ 닭구이  ", nutrients: ["단백질"])
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: "두부조림", nutrients: ["protein"]),
        ])
        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: []
        ))

        XCTAssertEqual(MealRecordIdentityNormalizer.normalizedMenuName(current.name), "bbq 닭구이")
        XCTAssertEqual(selection.provenance.currentMenuName, "bbq 닭구이")
        XCTAssertNotNil(NutrientImpactSnapshotFactory.make(
            recordID: "mixed-case-bbq",
            date: mealDay.date,
            normalizedMenuName: "bbq 닭구이",
            status: .difficultToday,
            recordUpdatedAt: Date(timeIntervalSince1970: 5),
            nutrientIDs: ["단백질"],
            alternativeSelection: selection
        ))
    }

    func testFactoryAllowsTypedSameMealAlternativesOnlyForDifficultToday() throws {
        let current = mealItem(name: "두부조림", nutrients: ["protein"])
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: "달걀찜", nutrients: ["protein"]),
        ])
        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: []
        ))
        let withAlternative = try XCTUnwrap(
            NutrientImpactSnapshotFactory.make(
                recordID: "typed-alternative-with-copy",
                date: mealDay.date,
                normalizedMenuName: current.normalizedPresentationName,
                status: .difficultToday,
                recordUpdatedAt: Date(timeIntervalSince1970: 10),
                nutrientIDs: current.nutrients,
                alternativeSelection: selection
            )
        )
        let withoutAlternative = try XCTUnwrap(
            NutrientImpactSnapshotFactory.make(
                recordID: "typed-alternative-without-copy",
                date: mealDay.date,
                normalizedMenuName: current.normalizedPresentationName,
                status: .difficultToday,
                recordUpdatedAt: Date(timeIntervalSince1970: 11),
                nutrientIDs: current.nutrients
            )
        )

        XCTAssertEqual(withAlternative.alternatives, ["달걀찜"])
        XCTAssertEqual(withoutAlternative.alternatives, [])
        XCTAssertEqual(
            NutrientImpactCopyCatalog.makeCopy(
                status: .allergyAvoided,
                nutrientIDs: ["protein"],
                hasAlternatives: false
            )?.explanation,
            "보호자와 학교 안내를 먼저 확인해요."
        )

        for status in RebuildEatingStatus.allCases where status != .difficultToday {
            XCTAssertNil(
                NutrientImpactSnapshotFactory.make(
                    recordID: "typed-alternative-rejected-\(status.rawValue)",
                    date: mealDay.date,
                    normalizedMenuName: current.normalizedPresentationName,
                    status: status,
                    recordUpdatedAt: Date(timeIntervalSince1970: 11),
                    nutrientIDs: current.nutrients,
                    alternativeSelection: selection
                ),
                status.rawValue
            )
        }

        XCTAssertNil(
            NutrientImpactSnapshotFactory.make(
                recordID: "typed-alternative-wrong-date",
                date: "2026-08-31",
                normalizedMenuName: current.normalizedPresentationName,
                status: .difficultToday,
                recordUpdatedAt: Date(timeIntervalSince1970: 12),
                nutrientIDs: current.nutrients,
                alternativeSelection: selection
            )
        )
        XCTAssertNil(
            NutrientImpactSnapshotFactory.make(
                recordID: "typed-alternative-wrong-menu",
                date: mealDay.date,
                normalizedMenuName: "다른메뉴",
                status: .difficultToday,
                recordUpdatedAt: Date(timeIntervalSince1970: 13),
                nutrientIDs: current.nutrients,
                alternativeSelection: selection
            )
        )
        XCTAssertNil(
            NutrientImpactSnapshotFactory.make(
                recordID: "typed-alternative-wrong-nutrients",
                date: mealDay.date,
                normalizedMenuName: current.normalizedPresentationName,
                status: .difficultToday,
                recordUpdatedAt: Date(timeIntervalSince1970: 14),
                nutrientIDs: ["iron"],
                alternativeSelection: selection
            )
        )
    }

    func testEmptyNutrientCopyUsesNeutralFallbackWithoutDuplicatePhrase() throws {
        for status in RebuildEatingStatus.allCases {
            let copy = try XCTUnwrap(
                NutrientImpactCopyCatalog.makeCopy(status: status, nutrientIDs: [])
            )
            XCTAssertFalse(copy.headline.contains("대표 영양소 같은 대표 영양소"))
            XCTAssertFalse(copy.explanation.contains("대표 영양소 같은 대표 영양소"))
        }
    }

    func testFinishedCopyIsMenuScoped() throws {
        let copy = try XCTUnwrap(
            NutrientImpactCopyCatalog.makeCopy(status: .finished, nutrientIDs: ["iron"])
        )
        XCTAssertTrue(copy.headline.contains("이 메뉴"))
        XCTAssertTrue(copy.explanation.contains("이 메뉴"))
    }

    func testSidecarTreatsAlternativeLabelsAsOpaqueStructuredData() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let snapshot = fixtureSnapshot(
            recordID: "opaque-alternative-labels",
            status: .difficultToday,
            alternatives: ["철분 12mg", "fake secret marker: API token"]
        )

        XCTAssertNoThrow(try store.install(snapshot))
        XCTAssertEqual(try store.load(matching: fixtureRevision(
            recordID: snapshot.recordID,
            status: snapshot.status,
            updatedAt: snapshot.recordUpdatedAt
        )), snapshot)
    }

    func testSameMealSelectorCanonicalizesRealLabelsAndExcludesCurrentMenu() throws {
        let current = mealItem(name: "현미밥", nutrients: ["carbohydrate"])
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(
                name: "\u{00A0}김치\u{00A0} ·  두부\u{00A0}",
                nutrients: ["carbohydrate"]
            ),
            mealItem(name: "고구마 (찐 것)", nutrients: ["carbohydrate"]),
            mealItem(name: "2026년산 고구마", nutrients: ["carbohydrate"]),
        ])

        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: []
        ))

        XCTAssertEqual(
            selection.menuLabels,
            ["김치 · 두부", "고구마 (찐 것)"]
        )
        XCTAssertFalse(selection.menuLabels.contains("현미밥"))
    }

    func testSameMealSelectorDeduplicatesAfterCandidateQualification() throws {
        let current = mealItem(name: "현미밥", nutrients: ["protein"])
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: " 두부 ", nutrients: ["protein"]),
            mealItem(name: "두부", nutrients: ["protein"]),
            mealItem(name: "김치", nutrients: ["protein"]),
        ])

        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: []
        ))

        XCTAssertEqual(selection.menuLabels, ["두부", "김치"])
    }

    func testSameMealSelectorPrioritizesBeforeCanonicalLabelDeduplication() throws {
        let current = mealItem(
            name: "현미밥",
            nutrients: ["protein", "iron"]
        )
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: "두부", nutrients: ["iron"]),
            mealItem(name: " 두부 ", nutrients: ["protein", "iron"]),
            mealItem(name: "달걀", nutrients: ["protein"]),
        ])

        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: []
        ))

        XCTAssertEqual(selection.menuLabels, ["두부", "달걀"])
        XCTAssertEqual(
            selection.alternatives.first?.nutrientIDs,
            ["protein", "iron"]
        )
    }

    func testSidecarRejectsOnlyNonCanonicalStructuralLabels() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let rejectedDirectLabels: [[String]] = [
            ["/tmp/file"],
            [" 두부 "],
            ["두부", " 두부 "],
            ["두부", "\u{00A0}두부\u{00A0}"],
            ["두부", "김치", "사과"],
            ["\u{0000}두부"],
            ["\u{200B}두부"],
        ]
        for (index, labels) in rejectedDirectLabels.enumerated() {
            assertInstallRejected(
                store,
                fixtureSnapshot(
                    recordID: "menu-label-direct-rejected-\(index)",
                    status: .difficultToday,
                    alternatives: labels
                )
            )
        }
    }

    func testSidecarRejectsMutatedAndPreviouslyAmbiguousSafetyCopy() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let canonical = try XCTUnwrap(
            NutrientImpactSnapshotFactory.make(
                recordID: "canonical-copy-base",
                date: "2026-08-30",
                normalizedMenuName: "현미밥",
                status: .oneBite,
                recordUpdatedAt: Date(timeIntervalSince1970: 10),
                nutrientIDs: ["iron"]
            )
        )

        let mutatedCopies = [
            "\(canonical.headline)!",
            "철분이 부족하다는 판단을 하지 않아요",
            "철분 부족을 진단하지 않으면 안 됩니다",
            "알레르기가 있으면 한 입 먹어요",
            "알레르기 반응이 있으면 한 입 먹어요",
            "알레르기가 있으면 피하지 않아요",
            "철분이 결핍된 상태예요",
            "영양소 부족을 진단하지 않아요. 철분 결핍 상태예요.",
            "안전하게 피한 선택이 가장 중요해요. 보호자와 학교 안내를 먼저 확인해요."
        ]

        for (index, copy) in mutatedCopies.enumerated() {
            let snapshot = snapshotByReplacing(
                canonical,
                recordID: "mutated-copy-\(index)",
                headline: copy
            )
            assertInstallRejected(store, snapshot)
        }

        for (index, copy) in [
            "알레르기가 있으면 맛을 보지 않아요",
            "오늘은 천천히 살펴본 것으로 충분해요",
            "영양소 정보를 알아보는 교육용 문장이에요"
        ].enumerated() {
            let snapshot = snapshotByReplacing(
                canonical,
                recordID: "safe-but-noncanonical-\(index)",
                explanation: copy
            )
            assertInstallRejected(store, snapshot)
        }

        XCTAssertTrue(try jsonFiles().isEmpty)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)
    }

    func testFactoryTreatsAlternativesAsMenuLabelsNotCopy() throws {
        let current = mealItem(name: "현미밥", nutrients: ["carbohydrate"])
        let mealDay = fixtureMealDay(items: [
            current,
            mealItem(name: "김치·두부", nutrients: ["carbohydrate"]),
            mealItem(name: "고구마 (찐 것)", nutrients: ["carbohydrate"]),
        ])
        let selection = try XCTUnwrap(SameMealAlternativeSelector.select(
            from: mealDay,
            currentItem: current,
            childAllergyCodes: []
        ))

        let snapshot = NutrientImpactSnapshotFactory.make(
            recordID: "menu-labels",
            date: mealDay.date,
            normalizedMenuName: current.normalizedPresentationName,
            status: .difficultToday,
            recordUpdatedAt: Date(timeIntervalSince1970: 10),
            nutrientIDs: current.nutrients,
            alternativeSelection: selection
        )
        XCTAssertEqual(snapshot?.alternatives, ["김치·두부", "고구마 (찐 것)"])
    }

    private func mealItem(
        name: String,
        allergyCodes: [Int] = [],
        nutrients: [String],
        tags: [String] = [],
        sourceRawText: String? = nil
    ) -> RebuildMealItem {
        RebuildMealItem(
            name: name,
            allergyCodes: allergyCodes,
            nutrients: nutrients,
            tags: tags,
            sourceRawText: sourceRawText ?? name
        )
    }

    private func fixtureMealDay(items: [RebuildMealItem]) -> RebuildMealDay {
        RebuildMealDay(
            date: "2026-08-30",
            menuItems: items,
            calorie: "600 kcal",
            nutrition: .empty
        )
    }

    private func fixtureSnapshot(
        schemaVersion: Int = 1,
        ruleVersion: Int = 1,
        recordID: String = "2026-08-30|현미밥|oneBite",
        date: String = "2026-08-30",
        normalizedMenuName: String = "현미밥",
        status: RebuildEatingStatus = .oneBite,
        updatedAt: Date = Date(timeIntervalSince1970: 10),
        nutrients: [String] = ["carbohydrate"],
        headline: String? = nil,
        explanation: String? = nil,
        alternatives: [String]? = nil,
        disclaimer: String? = nil
    ) -> NutrientImpactSnapshot {
        let persistedAlternatives = alternatives ?? []
        let canonicalCopy = NutrientImpactCopyCatalog.makeCopy(
            status: status,
            nutrientIDs: nutrients,
            hasAlternatives: !persistedAlternatives.isEmpty
        )
        return NutrientImpactSnapshot(
            schemaVersion: schemaVersion,
            ruleVersion: ruleVersion,
            recordID: recordID,
            date: date,
            normalizedMenuName: normalizedMenuName,
            status: status,
            recordUpdatedAt: updatedAt,
            nutrients: nutrients,
            headline: headline ?? canonicalCopy?.headline ?? "invalid headline",
            explanation: explanation ?? canonicalCopy?.explanation ?? "invalid explanation",
            alternatives: persistedAlternatives,
            disclaimer: disclaimer ?? canonicalCopy?.disclaimer ?? NutrientImpactCopyCatalog.educationNotice
        )
    }

    private func snapshotByReplacing(
        _ snapshot: NutrientImpactSnapshot,
        recordID: String,
        headline: String? = nil,
        explanation: String? = nil,
        disclaimer: String? = nil
    ) -> NutrientImpactSnapshot {
        NutrientImpactSnapshot(
            schemaVersion: snapshot.schemaVersion,
            ruleVersion: snapshot.ruleVersion,
            recordID: recordID,
            date: snapshot.date,
            normalizedMenuName: snapshot.normalizedMenuName,
            status: snapshot.status,
            recordUpdatedAt: snapshot.recordUpdatedAt,
            nutrients: snapshot.nutrients,
            headline: headline ?? snapshot.headline,
            explanation: explanation ?? snapshot.explanation,
            alternatives: snapshot.alternatives,
            disclaimer: disclaimer ?? snapshot.disclaimer
        )
    }

    private func fixtureRevision(
        recordID: String = "2026-08-30|현미밥|oneBite",
        date: String = "2026-08-30",
        normalizedMenuName: String = "현미밥",
        status: RebuildEatingStatus = .oneBite,
        updatedAt: Date = Date(timeIntervalSince1970: 10)
    ) -> RebuildMealRecordRevision {
        RebuildMealRecordRevision(
            recordID: recordID,
            date: date,
            normalizedMenuName: normalizedMenuName,
            status: status,
            updatedAt: updatedAt
        )
    }

    private func assertInstallRejected(
        _ store: FileNutrientImpactSidecar,
        _ snapshot: NutrientImpactSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let filesBefore = (try? jsonFiles().map(\.lastPathComponent)) ?? []
        let temporaryArtifactsBefore = (try? temporaryArtifacts().map(\.lastPathComponent)) ?? []
        XCTAssertThrowsError(try store.install(snapshot), file: file, line: line) { error in
            XCTAssertEqual(
                error as? NutrientImpactSidecarError,
                .invalidSnapshot,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            (try? jsonFiles().map(\.lastPathComponent)) ?? [],
            filesBefore,
            file: file,
            line: line
        )
        XCTAssertEqual(
            (try? temporaryArtifacts().map(\.lastPathComponent)) ?? [],
            temporaryArtifactsBefore,
            file: file,
            line: line
        )
    }

    private func jsonFiles(in directory: URL? = nil) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory ?? temporaryDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func singleJSONFile() throws -> URL? {
        try XCTUnwrap(jsonFiles().count == 1 ? jsonFiles().first : nil)
    }

    private func temporaryArtifacts() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".nutrient-impact-") }
    }

    private func concurrentInstall(
        _ snapshots: [NutrientImpactSnapshot],
        into store: FileNutrientImpactSidecar
    ) -> [Error] {
        let finished = DispatchGroup()
        let startBarrierQueue = DispatchQueue(
            label: "NutrientImpactSidecarTests.concurrentInstall",
            qos: .userInitiated,
            attributes: [.concurrent, .initiallyInactive]
        )
        let resultLock = NSLock()
        var errors: [Error] = []

        for snapshot in snapshots {
            finished.enter()
            startBarrierQueue.async {
                defer { finished.leave() }
                do {
                    try store.install(snapshot)
                } catch {
                    resultLock.lock()
                    errors.append(error)
                    resultLock.unlock()
                }
            }
        }
        startBarrierQueue.activate()
        finished.wait()
        resultLock.lock()
        defer { resultLock.unlock() }
        return errors
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func decodedSnapshot(at url: URL) throws -> NutrientImpactSnapshot {
        let envelope = try jsonObject(at: url)
        let snapshotObject = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: snapshotObject, options: [.sortedKeys])
        return try JSONDecoder().decode(NutrientImpactSnapshot.self, from: data)
    }
}

private final class SidecarLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
