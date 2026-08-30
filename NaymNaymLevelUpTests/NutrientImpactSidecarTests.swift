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

    func testInstallRejectsPathTraversalAndForbiddenQuantities() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)

        assertInstallRejected(store, fixtureSnapshot(recordID: "../escape"))
        assertInstallRejected(store, fixtureSnapshot(normalizedMenuName: "menu/../escape"))
        assertInstallRejected(store, fixtureSnapshot(recordID: #"menu\..\escape"#))
        assertInstallRejected(store, fixtureSnapshot(recordID: "opaque\u{0000}id"))
        assertInstallRejected(store, fixtureSnapshot(headline: "단백질 12g을 먹었어요."))
        assertInstallRejected(store, fixtureSnapshot(explanation: "철분 4 mg을 섭취했어요."))
        assertInstallRejected(store, fixtureSnapshot(explanation: "철분 12㎎을 섭취했어요."))
        assertInstallRejected(store, fixtureSnapshot(explanation: "철분 １２ｍｇ을 섭취했어요."))
        assertInstallRejected(store, fixtureSnapshot(alternatives: ["이 메뉴는 230kcal예요."]))
        assertInstallRejected(store, fixtureSnapshot(headline: "철분이 부족하니 꼭 먹어야 해요."))
        assertInstallRejected(store, fixtureSnapshot(headline: "영양소가 모자라면 몸이 나빠져요."))
        assertInstallRejected(store, fixtureSnapshot(headline: "의사 진단이 필요해요."))
        assertInstallRejected(store, fixtureSnapshot(explanation: "이 문장에는 API token이 들어 있어요."))
        assertInstallRejected(store, fixtureSnapshot(disclaimer: "알레르기가 있어도 먹어도 괜찮아요."))
        assertInstallRejected(store, fixtureSnapshot(disclaimer: "알레르기가 있더라도 다시 먹어봐요."))
        assertInstallRejected(store, fixtureSnapshot(disclaimer: "알레르기지만 조금은 먹어보세요."))
    }

    func testOpaqueIdentifiersAndOrdinaryKoreanEducationAreAllowed() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let snapshot = fixtureSnapshot(
            recordID: #"opaque/path\record:01.v1"#,
            normalizedMenuName: "현미밥·콩나물",
            headline: "한 입으로 곡물의 맛과 식감을 알아봤어요.",
            explanation: "여러 재료를 천천히 살펴보며 나에게 맞는 식사를 배워요.",
            alternatives: ["다음에는 익숙한 반찬과 함께 살펴봐요."],
            disclaimer: "영양 정보는 의학 진단이 아닌 교육용 참고 정보예요."
        )

        XCTAssertNoThrow(try store.install(snapshot))
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

        let contractDisclaimer = fixtureSnapshot(
            recordID: "contract-disclaimer",
            disclaimer: "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요."
        )
        XCTAssertNoThrow(try store.install(contractDisclaimer))
    }

    func testUTF8ByteLimitsRejectCombiningPayloadAndOversizedFileReturnsNil() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let combiningPayload = String(
            repeating: "e\u{301}\u{302}\u{303}\u{304}\u{305}",
            count: 400
        )
        XCTAssertLessThan(combiningPayload.count, 1_000)
        XCTAssertGreaterThan(combiningPayload.utf8.count, 4_096)
        assertInstallRejected(store, fixtureSnapshot(headline: combiningPayload))
        assertInstallRejected(store, fixtureSnapshot(recordID: String(repeating: "😀", count: 257)))
        assertInstallRejected(
            store,
            fixtureSnapshot(nutrients: (0..<33).map { "nutrient-\($0)" })
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(alternatives: (0..<9).map { "교육 문장 \($0)번을 살펴봐요." })
        )
        assertInstallRejected(
            store,
            fixtureSnapshot(alternatives: Array(repeating: String(repeating: "가", count: 1_000), count: 8))
        )

        let allowedMultibyte = fixtureSnapshot(
            recordID: "multibyte-record",
            headline: String(repeating: "가", count: 1_000)
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
        let snapshot = fixtureSnapshot(status: .oneBite, updatedAt: Date(timeIntervalSince1970: 10))

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
            status: .oneBite,
            updatedAt: Date(timeIntervalSince1970: 10),
            headline: "다른 교육 문장으로 바뀌었어요."
        )
        XCTAssertThrowsError(try store.install(conflicting))
        XCTAssertEqual(try Data(contentsOf: before), beforeBytes)
    }

    func testConcurrentConflictingInstallsPublishExactlyOneImmutableWinner() throws {
        let store = FileNutrientImpactSidecar(directoryURL: temporaryDirectory)
        let candidates = (0..<8).map { index in
            fixtureSnapshot(headline: "교육 문장 \(index)번을 살펴봐요.")
        }

        let errors = concurrentInstall(candidates, into: store)

        XCTAssertEqual(errors.count, candidates.count - 1)
        XCTAssertTrue(errors.allSatisfy { ($0 as? NutrientImpactSidecarError) == .conflictingRevision })
        XCTAssertEqual(try jsonFiles().count, 1)
        XCTAssertTrue(try temporaryArtifacts().isEmpty)
        let winner = try XCTUnwrap(
            try store.load(matching: fixtureRevision())
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

    private func fixtureSnapshot(
        schemaVersion: Int = 1,
        ruleVersion: Int = 1,
        recordID: String = "2026-08-30|현미밥|oneBite",
        date: String = "2026-08-30",
        normalizedMenuName: String = "현미밥",
        status: RebuildEatingStatus = .oneBite,
        updatedAt: Date = Date(timeIntervalSince1970: 10),
        nutrients: [String] = ["carbohydrate"],
        headline: String = "한 입으로 곡물의 에너지를 경험했어요.",
        explanation: String = "곡물 메뉴를 천천히 살펴보며 식사를 알아가요.",
        alternatives: [String] = ["다음에는 익숙한 반찬과 함께 살펴봐요."],
        disclaimer: String = "영양 정보는 교육용 참고 정보예요."
    ) -> NutrientImpactSnapshot {
        NutrientImpactSnapshot(
            schemaVersion: schemaVersion,
            ruleVersion: ruleVersion,
            recordID: recordID,
            date: date,
            normalizedMenuName: normalizedMenuName,
            status: status,
            recordUpdatedAt: updatedAt,
            nutrients: nutrients,
            headline: headline,
            explanation: explanation,
            alternatives: alternatives,
            disclaimer: disclaimer
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
        XCTAssertThrowsError(try store.install(snapshot), file: file, line: line)
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
