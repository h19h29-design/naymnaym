import CoreFoundation
import CryptoKit
import Foundation

struct NutrientImpactSnapshot: Codable, Hashable, Sendable {
    static let supportedSchemaVersion = 1
    static let supportedRuleVersion = NutritionRuleEngine.supportedRuleVersion

    let schemaVersion: Int
    let ruleVersion: Int
    let recordID: String
    let date: String
    let normalizedMenuName: String
    let status: RebuildEatingStatus
    let recordUpdatedAt: Date
    let nutrients: [String]
    let headline: String
    let explanation: String
    let alternatives: [String]
    let disclaimer: String
}

protocol NutrientImpactSidecar: Sendable {
    func install(_ snapshot: NutrientImpactSnapshot) throws
    func load(matching record: RebuildMealRecordRevision) throws -> NutrientImpactSnapshot?
}

enum NutrientImpactSidecarError: Error, Equatable {
    case invalidSnapshot
    case unsupportedSchemaVersion
    case unsupportedRuleVersion
    case invalidRevision
    case directoryUnavailable
    case writeFailed
    case readBackFailed
    case conflictingRevision
}

struct NoopNutrientImpactSidecar: NutrientImpactSidecar, Sendable {
    static let shared = Self()

    func install(_ snapshot: NutrientImpactSnapshot) throws {}

    func load(matching record: RebuildMealRecordRevision) throws -> NutrientImpactSnapshot? {
        nil
    }
}

struct FileNutrientImpactSidecar: NutrientImpactSidecar, @unchecked Sendable {
    private static let filePrefix = "nutrient-impact-v1-"
    private static let fileExtension = "json"

    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func install(_ snapshot: NutrientImpactSnapshot) throws {
        try Self.validate(snapshot)
        try makeDirectoryIfNeeded()

        let destinationURL = try fileURL(for: snapshot)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try acceptExistingRevision(at: destinationURL, matching: snapshot)
            return
        }

        let encoded = try Self.encode(snapshot)
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(Self.filePrefix)\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var didMove = false
        defer {
            if !didMove {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        do {
            try encoded.write(to: temporaryURL, options: [.atomic])
        } catch {
            throw NutrientImpactSidecarError.writeFailed
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            didMove = true
        } catch {
            // Another writer may have installed this exact revision between
            // the existence check and the rename. It is safe to accept only a
            // valid byte-equivalent snapshot; no existing file is replaced.
            if fileManager.fileExists(atPath: destinationURL.path) {
                try acceptExistingRevision(at: destinationURL, matching: snapshot)
                return
            }
            throw NutrientImpactSidecarError.writeFailed
        }

        guard let readBack = readValidSnapshot(at: destinationURL), readBack == snapshot else {
            throw NutrientImpactSidecarError.readBackFailed
        }
    }

    func load(matching record: RebuildMealRecordRevision) throws -> NutrientImpactSnapshot? {
        guard Self.validate(record), isRegularDirectory(directoryURL) else { return nil }

        guard let destinationURL = try? fileURL(for: record),
              let snapshot = readValidSnapshot(at: destinationURL),
              Self.matches(snapshot, record: record)
        else {
            return nil
        }
        return snapshot
    }

    private func makeDirectoryIfNeeded() throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw NutrientImpactSidecarError.directoryUnavailable
        }
        guard isRegularDirectory(directoryURL) else {
            throw NutrientImpactSidecarError.directoryUnavailable
        }
    }

    private func isRegularDirectory(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeDirectory
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeRegular
    }

    private func fileURL(for snapshot: NutrientImpactSnapshot) throws -> URL {
        guard Self.isValid(snapshot) else {
            throw NutrientImpactSidecarError.invalidSnapshot
        }
        let fingerprint = Self.fingerprint(
            recordID: snapshot.recordID,
            date: snapshot.date,
            normalizedMenuName: snapshot.normalizedMenuName,
            status: snapshot.status,
            updatedAt: snapshot.recordUpdatedAt
        )
        return directoryURL.appendingPathComponent(
            "\(Self.filePrefix)\(fingerprint).\(Self.fileExtension)",
            isDirectory: false
        )
    }

    private func fileURL(for record: RebuildMealRecordRevision) throws -> URL {
        guard Self.validate(record) else {
            throw NutrientImpactSidecarError.invalidRevision
        }
        let fingerprint = Self.fingerprint(
            recordID: record.recordID,
            date: record.date,
            normalizedMenuName: record.normalizedMenuName,
            status: record.status,
            updatedAt: record.updatedAt
        )
        return directoryURL.appendingPathComponent(
            "\(Self.filePrefix)\(fingerprint).\(Self.fileExtension)",
            isDirectory: false
        )
    }

    private func acceptExistingRevision(
        at url: URL,
        matching snapshot: NutrientImpactSnapshot
    ) throws {
        guard let existing = readValidSnapshot(at: url) else {
            throw NutrientImpactSidecarError.conflictingRevision
        }
        guard existing == snapshot else {
            throw NutrientImpactSidecarError.conflictingRevision
        }
    }

    private func readValidSnapshot(at url: URL) -> NutrientImpactSnapshot? {
        guard isRegularFile(url),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == Self.expectedJSONKeys,
              Self.hasStrictInteger(dictionary["schemaVersion"]),
              Self.hasStrictInteger(dictionary["ruleVersion"]),
              let snapshot = try? JSONDecoder().decode(
                  NutrientImpactSnapshot.self,
                  from: data
              ),
              Self.isValid(snapshot)
        else {
            return nil
        }
        return snapshot
    }

    private static let expectedJSONKeys: Set<String> = [
        "schemaVersion",
        "ruleVersion",
        "recordID",
        "date",
        "normalizedMenuName",
        "status",
        "recordUpdatedAt",
        "nutrients",
        "headline",
        "explanation",
        "alternatives",
        "disclaimer",
    ]

    private static func encode(_ snapshot: NutrientImpactSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(snapshot)
        } catch {
            throw NutrientImpactSidecarError.writeFailed
        }
    }

    private static func validate(_ snapshot: NutrientImpactSnapshot) throws {
        guard snapshot.schemaVersion == NutrientImpactSnapshot.supportedSchemaVersion else {
            throw NutrientImpactSidecarError.unsupportedSchemaVersion
        }
        guard snapshot.ruleVersion == NutrientImpactSnapshot.supportedRuleVersion else {
            throw NutrientImpactSidecarError.unsupportedRuleVersion
        }
        guard validateRevisionComponents(
            recordID: snapshot.recordID,
            date: snapshot.date,
            normalizedMenuName: snapshot.normalizedMenuName,
            status: snapshot.status,
            updatedAt: snapshot.recordUpdatedAt
        ) else {
            throw NutrientImpactSidecarError.invalidSnapshot
        }
        guard validateIdentifierList(snapshot.nutrients),
              validateCopy(snapshot.headline),
              validateCopy(snapshot.explanation),
              snapshot.alternatives.count <= 8,
              snapshot.alternatives.allSatisfy(validateCopy),
              validateCopy(snapshot.disclaimer) else {
            throw NutrientImpactSidecarError.invalidSnapshot
        }
    }

    private static func isValid(_ snapshot: NutrientImpactSnapshot) -> Bool {
        (try? validate(snapshot)) != nil
    }

    private static func validate(_ record: RebuildMealRecordRevision) -> Bool {
        validateRevisionComponents(
            recordID: record.recordID,
            date: record.date,
            normalizedMenuName: record.normalizedMenuName,
            status: record.status,
            updatedAt: record.updatedAt
        )
    }

    private static func validateRevisionComponents(
        recordID: String,
        date: String,
        normalizedMenuName: String,
        status: RebuildEatingStatus,
        updatedAt: Date
    ) -> Bool {
        _ = status
        guard validIdentifier(recordID, maximumLength: 512),
              validDate(date),
              validIdentifier(normalizedMenuName, maximumLength: 512),
              updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        return true
    }

    private static func validateIdentifierList(_ values: [String]) -> Bool {
        guard values.count <= 32, Set(values).count == values.count else {
            return false
        }
        return values.allSatisfy { validIdentifier($0, maximumLength: 128) && !containsForbiddenCopy($0) }
    }

    private static func validIdentifier(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty,
              value.count <= maximumLength,
              !containsControlCharacter(value),
              !containsPathTraversal(value) else {
            return false
        }
        return true
    }

    private static func validateCopy(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 1_000,
              !containsControlCharacter(value),
              !containsForbiddenCopy(value) else {
            return false
        }
        return true
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value < 0x20
                || (0x7F...0x9F).contains(scalar.value)
                || scalar.value == 0x2028
                || scalar.value == 0x2029
        }
    }

    private static func containsPathTraversal(_ value: String) -> Bool {
        guard !value.contains("/") && !value.contains("\\") else {
            return true
        }
        return value == "." || value == ".."
    }

    private static func containsForbiddenCopy(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let secretPatterns = [
            #"(?:^|[^a-z0-9])api[ _-]?key(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])api[ _-]?token(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])access[ _-]?token(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])refresh[ _-]?token(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])bearer(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])private[ _-]?key(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])client[ _-]?secret(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])password(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])passwd(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])secret(?:$|[^a-z0-9])"#,
            #"(?:^|[^a-z0-9])sk-[a-z0-9_-]{8,}(?:$|[^a-z0-9])"#,
            #"-----begin [a-z ]*private key-----"#,
            "비밀번호",
            "인증 토큰",
            "액세스 토큰",
            "개인키",
            "시크릿",
        ]
        guard !secretPatterns.contains(where: { pattern in
            lowercased.range(of: pattern, options: .regularExpression) != nil
        }) else {
            return true
        }

        let quantityPattern = #"\d+(?:[.,]\d+)?\s*(?:kcal|mg|g|그램|밀리그램|킬로칼로리)"#
        if lowercased.range(of: quantityPattern, options: .regularExpression) != nil {
            return true
        }

        // Remove only explicit educational disclaimers before scanning for
        // medical claims. The disclaimer itself is allowed, while a diagnosis
        // or treatment assertion elsewhere in the copy remains forbidden.
        let normalizedForMedical = lowercased.replacingOccurrences(of: " ", with: "")
        let safeDisclaimerMarkers = [
            "진단이나치료를대신하지않습니다",
            "진단이나치료를대신하지않는",
            "진단이아닙니다",
            "진단이아닌",
            "진단이아닐",
        ]
        let medicalClaimText = safeDisclaimerMarkers.reduce(normalizedForMedical) {
            $0.replacingOccurrences(of: $1, with: "")
        }
        let medicalPhrases = [
            "결핍",
            "부족",
            "진단",
            "치료",
            "처방",
            "질병",
            "의학적",
            "의료적",
            "건강 악화",
            "악화",
            "빈혈",
            "고혈압",
            "당뇨",
        ]
        guard !medicalPhrases.contains(where: medicalClaimText.contains) else {
            return true
        }

        let allergyReversalPhrases = [
            "알레르기가 있어도",
            "알레르기여도",
            "알레르기라도",
            "알레르기를 무시",
            "알레르기 무시",
            "알레르기인데 먹",
            "먹어도 괜찮",
            "괜찮으니 먹",
            "피하지 말고",
            "피할 필요 없",
        ]
        return allergyReversalPhrases.contains(where: lowercased.contains)
    }

    private static func validDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        )
        guard let date = calendar.date(from: components) else { return false }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.string(from: date) == value
    }

    private static func hasStrictInteger(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return false
        }
        let type = String(cString: number.objCType)
        return type != "f" && type != "d"
    }

    private static func matches(
        _ snapshot: NutrientImpactSnapshot,
        record: RebuildMealRecordRevision
    ) -> Bool {
        snapshot.recordID == record.recordID
            && snapshot.date == record.date
            && snapshot.normalizedMenuName == record.normalizedMenuName
            && snapshot.status == record.status
            && snapshot.recordUpdatedAt == record.updatedAt
            && fingerprint(
                recordID: snapshot.recordID,
                date: snapshot.date,
                normalizedMenuName: snapshot.normalizedMenuName,
                status: snapshot.status,
                updatedAt: snapshot.recordUpdatedAt
            ) == fingerprint(
                recordID: record.recordID,
                date: record.date,
                normalizedMenuName: record.normalizedMenuName,
                status: record.status,
                updatedAt: record.updatedAt
            )
    }

    private static func fingerprint(
        recordID: String,
        date: String,
        normalizedMenuName: String,
        status: RebuildEatingStatus,
        updatedAt: Date
    ) -> String {
        var canonical = Data("NutrientImpactRevision/v1".utf8)
        appendComponent(recordID, to: &canonical)
        appendComponent(date, to: &canonical)
        appendComponent(normalizedMenuName, to: &canonical)
        appendComponent(status.rawValue, to: &canonical)
        var timestampBits = updatedAt.timeIntervalSinceReferenceDate.bitPattern.bigEndian
        withUnsafeBytes(of: &timestampBits) { canonical.append(contentsOf: $0) }

        return SHA256.hash(data: canonical)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func appendComponent(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}
