import CoreFoundation
import CryptoKit
import Darwin
import Foundation

struct NutrientImpactSnapshot: Codable, Hashable, Sendable {
    static let supportedSchemaVersion = 1
    static let supportedRuleVersion = NutritionRuleEngine.supportedRuleVersion
    static let fallbackRuleVersion =
        NutritionRuleEngine.unavailableFallbackRuleVersion
    static let supportedRuleVersions: Set<Int> = [
        supportedRuleVersion,
        fallbackRuleVersion,
    ]

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

struct NutrientImpactCopy: Equatable, Sendable {
    let headline: String
    let explanation: String
    let disclaimer: String
}

struct SameMealAlternativeProvenance: Equatable, Sendable {
    let mealDayDate: String
    let currentMenuName: String
    let targetNutrientIDs: [String]

    fileprivate init(
        mealDayDate: String,
        currentMenuName: String,
        targetNutrientIDs: [String]
    ) {
        self.mealDayDate = mealDayDate
        self.currentMenuName = currentMenuName
        self.targetNutrientIDs = targetNutrientIDs
    }
}

struct SameMealAlternative: Equatable, Sendable {
    let menuName: String
    let nutrientIDs: [String]
    let allergyCodes: [Int]
    let provenance: SameMealAlternativeProvenance

    fileprivate init(
        menuName: String,
        nutrientIDs: [String],
        allergyCodes: [Int],
        provenance: SameMealAlternativeProvenance
    ) {
        self.menuName = menuName
        self.nutrientIDs = nutrientIDs
        self.allergyCodes = allergyCodes
        self.provenance = provenance
    }
}

struct SameMealAlternativeSelection: Equatable, Sendable {
    let alternatives: [SameMealAlternative]
    let provenance: SameMealAlternativeProvenance

    var menuLabels: [String] {
        alternatives.map(\.menuName)
    }

    fileprivate init(
        alternatives: [SameMealAlternative],
        provenance: SameMealAlternativeProvenance
    ) {
        self.alternatives = alternatives
        self.provenance = provenance
    }

    fileprivate func isCanonical() -> Bool {
        guard alternatives.count <= 2,
              !provenance.mealDayDate.isEmpty,
              !provenance.currentMenuName.isEmpty,
              !provenance.currentMenuName.contains("|"),
              MealRecordIdentityNormalizer.normalizedMenuName(
                  provenance.currentMenuName
              ) == provenance.currentMenuName,
              let targetNutrients = NutrientImpactCopyCatalog.validatedCanonicalNutrientIDs(
                  provenance.targetNutrientIDs
              ),
              !targetNutrients.isEmpty,
              NutrientImpactCopyCatalog.validateMenuLabels(menuLabels),
              Set(menuLabels).count == menuLabels.count
        else {
            return false
        }

        let targetSet = Set(targetNutrients)
        return alternatives.allSatisfy { alternative in
            guard alternative.provenance == provenance,
                  let nutrients = NutrientImpactCopyCatalog.validatedCanonicalNutrientIDs(
                      alternative.nutrientIDs
                  ),
                  !nutrients.isEmpty,
                  !Set(nutrients).intersection(targetSet).isEmpty,
                  alternative.allergyCodes == Array(Set(alternative.allergyCodes).sorted()),
                  NutrientImpactCopyCatalog.validateMenuLabels([alternative.menuName]),
                  MealRecordIdentityNormalizer.normalizedMenuName(
                      alternative.menuName
                  ) != provenance.currentMenuName
            else {
                return false
            }
            return true
        }
    }

    fileprivate func matches(
        date: String,
        menuName: String,
        nutrientIDs: [String]
    ) -> Bool {
        guard isCanonical() else { return false }
        return exact(provenance.mealDayDate, date)
            && exact(provenance.currentMenuName, menuName)
            && provenance.targetNutrientIDs.count == nutrientIDs.count
            && zip(provenance.targetNutrientIDs, nutrientIDs).allSatisfy { lhs, rhs in
                exact(lhs, rhs)
            }
    }

    private func exact(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }
}

enum SameMealAlternativeSelector {
    static func select(
        from mealDay: RebuildMealDay,
        currentItem: RebuildMealItem,
        childAllergyCodes: [Int]
    ) -> SameMealAlternativeSelection? {
        guard let currentIndex = mealDay.menuItems.firstIndex(of: currentItem) else {
            return nil
        }
        let currentIdentity = MealRecordIdentityNormalizer.normalizedMenuName(
            currentItem.name
        )
        guard !currentIdentity.isEmpty,
              !currentIdentity.contains("|"),
              let currentDisplayLabel = NutrientImpactCopyCatalog.canonicalMenuLabels([
                  currentItem.normalizedPresentationName
              ])?.first else {
            return nil
        }
        let targets = resolvedNutrientIDs(for: currentItem)
        guard !targets.isEmpty else {
            return nil
        }

        return buildSelection(
            from: mealDay,
            currentIndex: currentIndex,
            currentIdentity: currentIdentity,
            currentDisplayLabel: currentDisplayLabel,
            targets: targets,
            childAllergyCodes: childAllergyCodes
        )
    }

    private static func buildSelection(
        from mealDay: RebuildMealDay,
        currentIndex: Int,
        currentIdentity: String,
        currentDisplayLabel: String,
        targets: [String],
        childAllergyCodes: [Int]
    ) -> SameMealAlternativeSelection {
        precondition(
            !targets.isEmpty,
            "A same-meal selection requires canonical target nutrients."
        )
        let provenance = SameMealAlternativeProvenance(
            mealDayDate: mealDay.date,
            currentMenuName: currentIdentity,
            targetNutrientIDs: targets
        )
        let childAllergies = Set(childAllergyCodes)
        let targetSet = Set(targets)
        var candidates: [(index: Int, item: RebuildMealItem, label: String, nutrients: [String], shared: [String])] = []

        for (index, item) in mealDay.menuItems.enumerated() where index != currentIndex {
            let itemIdentity = MealRecordIdentityNormalizer.normalizedMenuName(item.name)
            guard !itemIdentity.isEmpty,
                  !itemIdentity.contains("|"),
                  itemIdentity != currentIdentity,
                  let label = NutrientImpactCopyCatalog.canonicalMenuLabels([
                      item.normalizedPresentationName
                  ])?.first,
                  label != currentDisplayLabel,
                  childAllergies.isDisjoint(with: item.allergyCodes) else {
                continue
            }
            let nutrients = resolvedNutrientIDs(for: item)
            guard !nutrients.isEmpty else { continue }
            let shared = targets.filter { targetSet.contains($0) && nutrients.contains($0) }
            guard !shared.isEmpty else { continue }
            candidates.append((index, item, label, nutrients, shared))
        }

        candidates.sort { lhs, rhs in
            if lhs.shared.count != rhs.shared.count {
                return lhs.shared.count > rhs.shared.count
            }
            let lhsPriority = targets.firstIndex(where: lhs.shared.contains) ?? targets.count
            let rhsPriority = targets.firstIndex(where: rhs.shared.contains) ?? targets.count
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.index < rhs.index
        }

        var selectedCandidates: [(
            index: Int,
            item: RebuildMealItem,
            label: String,
            nutrients: [String],
            shared: [String]
        )] = []
        var selectedLabels = Set<String>()
        for candidate in candidates
        where selectedLabels.insert(candidate.label).inserted {
            selectedCandidates.append(candidate)
            if selectedCandidates.count == 2 { break }
        }
        let selected = selectedCandidates.map { candidate in
            SameMealAlternative(
                menuName: candidate.label,
                nutrientIDs: candidate.nutrients,
                allergyCodes: Array(Set(candidate.item.allergyCodes).sorted()),
                provenance: provenance
            )
        }
        return SameMealAlternativeSelection(
            alternatives: Array(selected),
            provenance: provenance
        )
    }

    private static func resolvedNutrientIDs(
        for item: RebuildMealItem
    ) -> [String] {
        let structured = MealNutrientCanonicalizer.orderedKnownIDs(
            from: item.nutrients
        )
        guard structured.isEmpty else { return structured }

        let visual = MealVisualResolver.resolve(item: item)
        guard visual.confidence != .fallback else { return [] }
        return MealNutrientCanonicalizer.orderedKnownIDs(
            from: visual.representativeNutrientIDs
        )
    }
}

/// The sidecar is a persistence boundary, so copy is an allow-list rather
/// than a best-effort natural-language policy. Callers use this catalog to
/// build every snapshot; the sidecar accepts only the exact resulting copy.
enum NutrientImpactCopyCatalog {
    static let educationNotice =
        "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요."

    static let nutrientOrder = MealNutrientCanonicalizer.orderedIDs

    private static let nutrientNames: [String: String] = [
        "fiber": "식이섬유",
        "vitamin": "비타민",
        "protein": "단백질",
        "iron": "철분",
        "calcium": "칼슘",
        "carbohydrate": "탄수화물",
    ]

    private static let maximumMenuLabelBytes = 256
    private static let maximumMenuLabelCharacters = 80

    static func canonicalNutrientIDs(
        fromRawValues values: [String]
    ) -> [String]? {
        MealNutrientCanonicalizer.canonicalizedIfAllKnown(values)
    }

    static func validatedCanonicalNutrientIDs(
        _ values: [String]
    ) -> [String]? {
        MealNutrientCanonicalizer.validatedCanonicalIDs(values)
    }

    static func makeCopy(
        status: RebuildEatingStatus,
        nutrientIDs: [String],
        hasAlternatives: Bool = false
    ) -> NutrientImpactCopy? {
        guard !hasAlternatives || status == .difficultToday,
              let normalized = validatedCanonicalNutrientIDs(nutrientIDs) else {
            return nil
        }
        let headline: String
        let explanation: String

        switch status {
        case .finished:
            headline = "이 메뉴를 즐겁게 잘 마무리했어요!"
            explanation = "\(commonNutritionSentence(for: normalized)) 이 메뉴의 식사 경험을 멋지게 기록했어요."
        case .half:
            headline = "절반까지 차근차근 먹어 봤어요!"
            explanation = "절반까지 시도한 경험을 잘 기록했어요. \(commonNutritionSentence(for: normalized))"
        case .oneBite:
            headline = "한 입 도전, 멋지게 해냈어요!"
            explanation = "한 입으로 새로운 맛과 식감을 살펴봤어요. \(commonNutritionSentence(for: normalized))"
        case .smelledOnly:
            headline = "냄새와 느낌을 살펴본 것도 멋진 탐색이에요!"
            explanation = "오늘은 냄새와 느낌을 천천히 알아봤어요. \(commonNutritionSentence(for: normalized))"
        case .difficultToday:
            headline = "오늘은 이 메뉴의 대표 영양소를 덜 섭취했을 수 있어요."
            explanation = "\(commonNutritionSentence(for: normalized)) 그래도 괜찮아요. 솔직하게 기록한 것이 첫걸음이에요."
        case .allergyAvoided:
            headline = "알레르기 안전을 먼저 챙긴 선택이에요!"
            explanation = "보호자와 학교 안내를 먼저 확인해요."
        }

        return NutrientImpactCopy(
            headline: headline,
            explanation: explanation,
            disclaimer: educationNotice
        )
    }

    static func isCanonical(
        status: RebuildEatingStatus,
        nutrientIDs: [String],
        headline: String,
        explanation: String,
        disclaimer: String,
        hasAlternatives: Bool = false
    ) -> Bool {
        guard let copy = makeCopy(
            status: status,
            nutrientIDs: nutrientIDs,
            hasAlternatives: hasAlternatives
        ) else {
            return false
        }
        return exact(copy.headline, headline)
            && exact(copy.explanation, explanation)
            && exact(copy.disclaimer, disclaimer)
    }

    static func validateMenuLabels(_ values: [String]) -> Bool {
        guard let canonical = canonicalMenuLabels(values) else { return false }
        guard canonical.count == values.count else { return false }
        return zip(canonical, values).allSatisfy { expected, actual in
            expected.utf8.elementsEqual(actual.utf8)
        }
    }

    /// Canonicalize menu labels at the factory boundary. The sidecar itself
    /// accepts only this exact representation, so whitespace/NFC variants and
    /// duplicates cannot be smuggled into persisted snapshots.
    static func canonicalMenuLabels(_ values: [String]) -> [String]? {
        guard values.count <= 2 else { return nil }

        var canonical: [String] = []
        canonical.reserveCapacity(values.count)
        for value in values {
            guard let label = canonicalMenuLabel(value), !canonical.contains(label) else {
                return nil
            }
            canonical.append(label)
        }
        return canonical
    }

    private static func nutrientPhrase(for nutrientIDs: [String]) -> String? {
        let names = nutrientIDs.compactMap { nutrientNames[$0] }
        guard !names.isEmpty else { return nil }
        guard names.count > 1 else { return names[0] }
        return names.joined(separator: " · ")
    }

    private static func exact(_ expected: String, _ actual: String) -> Bool {
        expected.utf8.elementsEqual(actual.utf8)
    }

    private static func commonNutritionSentence(for nutrientIDs: [String]) -> String {
        guard let phrase = nutrientPhrase(for: nutrientIDs) else {
            return "이 메뉴의 대표 영양소 정보는 아직 자세히 확인하지 못했어요."
        }
        return "이 메뉴에서는 보통 \(phrase) 같은 대표 영양소를 만날 수 있어요."
    }

    private static func canonicalMenuLabel(_ value: String) -> String? {
        let normalized = value.precomposedStringWithCanonicalMapping
        guard normalized.utf8.count <= maximumMenuLabelBytes,
              normalized.count <= maximumMenuLabelCharacters,
              !containsControlCharacter(normalized),
              !containsFormatCharacter(normalized),
              !containsPathSeparator(normalized)
        else {
            return nil
        }

        var result = String()
        result.reserveCapacity(normalized.count)
        var pendingSpace = false
        for scalar in normalized.unicodeScalars {
            if scalar.properties.generalCategory == .spaceSeparator {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.unicodeScalars.append(scalar)
        }

        guard !result.isEmpty,
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return result
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value < 0x20
                || (0x7F...0x9F).contains(scalar.value)
                || scalar.value == 0x2028
                || scalar.value == 0x2029
        }
    }

    private static func containsFormatCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .format
        }
    }

    private static func containsPathSeparator(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value == 0x2F || scalar.value == 0x5C
        }
    }

}

enum NutrientImpactSnapshotFactory {
    static func make(
        schemaVersion: Int = NutrientImpactSnapshot.supportedSchemaVersion,
        ruleVersion: Int = NutrientImpactSnapshot.supportedRuleVersion,
        recordID: String,
        date: String,
        normalizedMenuName: String,
        status: RebuildEatingStatus,
        recordUpdatedAt: Date,
        nutrientIDs: [String]
    ) -> NutrientImpactSnapshot? {
        guard schemaVersion == NutrientImpactSnapshot.supportedSchemaVersion,
              NutrientImpactSnapshot.supportedRuleVersions.contains(ruleVersion) else {
            return nil
        }
        guard let nutrients = NutrientImpactCopyCatalog.canonicalNutrientIDs(
            fromRawValues: nutrientIDs
        ) else { return nil }
        return makeSnapshot(
            schemaVersion: schemaVersion,
            ruleVersion: ruleVersion,
            recordID: recordID,
            date: date,
            normalizedMenuName: normalizedMenuName,
            status: status,
            recordUpdatedAt: recordUpdatedAt,
            nutrients: nutrients,
            alternatives: []
        )
    }

    static func make(
        schemaVersion: Int = NutrientImpactSnapshot.supportedSchemaVersion,
        ruleVersion: Int = NutrientImpactSnapshot.supportedRuleVersion,
        recordID: String,
        date: String,
        normalizedMenuName: String,
        status: RebuildEatingStatus,
        recordUpdatedAt: Date,
        nutrientIDs: [String],
        alternativeSelection: SameMealAlternativeSelection
    ) -> NutrientImpactSnapshot? {
        guard schemaVersion == NutrientImpactSnapshot.supportedSchemaVersion,
              NutrientImpactSnapshot.supportedRuleVersions.contains(ruleVersion),
              status == .difficultToday else {
            return nil
        }
        guard let nutrients = NutrientImpactCopyCatalog.canonicalNutrientIDs(
            fromRawValues: nutrientIDs
        ), !nutrients.isEmpty,
              alternativeSelection.matches(
                  date: date,
                  menuName: normalizedMenuName,
                  nutrientIDs: nutrients
              )
        else {
            return nil
        }
        return makeSnapshot(
            schemaVersion: schemaVersion,
            ruleVersion: ruleVersion,
            recordID: recordID,
            date: date,
            normalizedMenuName: normalizedMenuName,
            status: status,
            recordUpdatedAt: recordUpdatedAt,
            nutrients: nutrients,
            alternatives: alternativeSelection.menuLabels
        )
    }

    private static func makeSnapshot(
        schemaVersion: Int,
        ruleVersion: Int,
        recordID: String,
        date: String,
        normalizedMenuName: String,
        status: RebuildEatingStatus,
        recordUpdatedAt: Date,
        nutrients: [String],
        alternatives: [String]
    ) -> NutrientImpactSnapshot? {
        guard let copy = NutrientImpactCopyCatalog.makeCopy(
            status: status,
            nutrientIDs: nutrients,
            hasAlternatives: !alternatives.isEmpty
        ) else {
            return nil
        }
        return NutrientImpactSnapshot(
            schemaVersion: schemaVersion,
            ruleVersion: ruleVersion,
            recordID: recordID,
            date: date,
            normalizedMenuName: normalizedMenuName,
            status: status,
            recordUpdatedAt: recordUpdatedAt,
            nutrients: nutrients,
            headline: copy.headline,
            explanation: copy.explanation,
            alternatives: alternatives,
            disclaimer: copy.disclaimer
        )
    }
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

final class InMemoryNutrientImpactSidecar:
    NutrientImpactSidecar,
    @unchecked Sendable {
    private struct RevisionKey: Hashable {
        let recordID: String
        let date: String
        let normalizedMenuName: String
        let status: RebuildEatingStatus
        let updatedAt: Date

        init(snapshot: NutrientImpactSnapshot) {
            self.init(
                recordID: snapshot.recordID,
                date: snapshot.date,
                normalizedMenuName: snapshot.normalizedMenuName,
                status: snapshot.status,
                updatedAt: snapshot.recordUpdatedAt
            )
        }

        init(revision: RebuildMealRecordRevision) {
            self.init(
                recordID: revision.recordID,
                date: revision.date,
                normalizedMenuName: revision.normalizedMenuName,
                status: revision.status,
                updatedAt: revision.updatedAt
            )
        }

        private init(
            recordID: String,
            date: String,
            normalizedMenuName: String,
            status: RebuildEatingStatus,
            updatedAt: Date
        ) {
            self.recordID = recordID
            self.date = date
            self.normalizedMenuName = normalizedMenuName
            self.status = status
            self.updatedAt = updatedAt
        }
    }

    private let lock = NSLock()
    private var snapshots: [RevisionKey: NutrientImpactSnapshot] = [:]

    func install(_ snapshot: NutrientImpactSnapshot) throws {
        guard (try? FileNutrientImpactSidecar.validate(snapshot)) != nil else {
            throw NutrientImpactSidecarError.invalidSnapshot
        }
        let key = RevisionKey(snapshot: snapshot)
        lock.lock()
        defer { lock.unlock() }
        if let existing = snapshots[key] {
            guard existing == snapshot else {
                throw NutrientImpactSidecarError.conflictingRevision
            }
            return
        }
        snapshots[key] = snapshot
    }

    func load(
        matching revision: RebuildMealRecordRevision
    ) throws -> NutrientImpactSnapshot? {
        guard FileNutrientImpactSidecar.validate(revision) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return snapshots[RevisionKey(revision: revision)]
    }
}

struct FileNutrientImpactSidecar: NutrientImpactSidecar, @unchecked Sendable {
    private struct Envelope: Codable {
        let envelopeVersion: Int
        let revisionFingerprint: String
        let snapshotDigest: String
        let snapshot: NutrientImpactSnapshot
    }

    private static let supportedEnvelopeVersion = 1
    private static let maximumSidecarBytes = 64 * 1_024
    private static let maximumIdentifierBytes = 1_024
    private static let maximumNutrientIdentifierBytes = 256
    private static let maximumAggregateStringBytes = 20 * 1_024
    private static let filePrefix = "nutrient-impact-v1-"
    private static let fileExtension = "json"

    private let directoryURL: URL
    private let fileManager: FileManager
    private let directorySync: @Sendable (Int32) -> Int32

    init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        directorySync: @escaping @Sendable (Int32) -> Int32 = { Darwin.fsync($0) }
    ) {
        // The injected parent chain is a trusted Application Support root.
        // The final sidecar directory and every file within it are opened
        // descriptor-relative with no-follow semantics.
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.directorySync = directorySync
    }

    func install(_ snapshot: NutrientImpactSnapshot) throws {
        try Self.validate(snapshot)
        try makeDirectoryIfNeeded()
        let directoryDescriptor = try openDirectoryDescriptor()
        defer { Darwin.close(directoryDescriptor) }

        let destinationName = try fileName(for: snapshot)
        let encoded = try Self.encodeEnvelope(snapshot)
        let temporaryName = ".\(Self.filePrefix)\(UUID().uuidString).tmp"
        let temporaryDescriptor = Self.openAt(
            directoryDescriptor,
            name: temporaryName,
            flags: O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode: mode_t(0o600)
        )
        guard temporaryDescriptor >= 0 else {
            throw NutrientImpactSidecarError.writeFailed
        }
        var didPublish = false
        var temporaryIsOpen = true
        defer {
            if temporaryIsOpen {
                Darwin.close(temporaryDescriptor)
            }
            if !didPublish {
                Self.unlinkAt(directoryDescriptor, name: temporaryName)
            }
        }

        guard Darwin.fchmod(temporaryDescriptor, mode_t(0o600)) == 0,
              Self.writeAll(encoded, to: temporaryDescriptor),
              Darwin.fsync(temporaryDescriptor) == 0 else {
            throw NutrientImpactSidecarError.writeFailed
        }
        guard Darwin.close(temporaryDescriptor) == 0 else {
            temporaryIsOpen = false
            throw NutrientImpactSidecarError.writeFailed
        }
        temporaryIsOpen = false

        let publishResult = Self.renameExclusive(
            directoryDescriptor,
            from: temporaryName,
            to: destinationName
        )
        let publishError = errno
        if publishResult != 0 {
            guard publishError == EEXIST else {
                throw NutrientImpactSidecarError.writeFailed
            }
            try acceptExistingRevision(
                directoryDescriptor: directoryDescriptor,
                name: destinationName,
                matching: snapshot
            )
            guard directorySync(directoryDescriptor) == 0 else {
                // The immutable winner may originate from a prior publication
                // whose directory sync failed. A successful retry must make
                // that directory entry durable before it can report success.
                throw NutrientImpactSidecarError.writeFailed
            }
            return
        }
        didPublish = true
        guard directorySync(directoryDescriptor) == 0 else {
            // Publication already succeeded. Preserve the immutable final
            // inode so a retry can observe and validate the same winner.
            throw NutrientImpactSidecarError.writeFailed
        }

        guard let readBack = readValidSnapshot(
            directoryDescriptor: directoryDescriptor,
            name: destinationName
        ), readBack == snapshot else {
            throw NutrientImpactSidecarError.readBackFailed
        }
    }

    func load(matching record: RebuildMealRecordRevision) throws -> NutrientImpactSnapshot? {
        guard Self.validate(record), let directoryDescriptor = try? openDirectoryDescriptor() else {
            return nil
        }
        defer { Darwin.close(directoryDescriptor) }

        guard let destinationName = try? fileName(for: record),
              let snapshot = readValidSnapshot(
                  directoryDescriptor: directoryDescriptor,
                  name: destinationName
              ),
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
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw NutrientImpactSidecarError.directoryUnavailable
        }
        guard (try? openDirectoryDescriptor()).map({ descriptor in
            Darwin.close(descriptor)
            return true
        }) == true else {
            throw NutrientImpactSidecarError.directoryUnavailable
        }
    }

    private func openDirectoryDescriptor() throws -> Int32 {
        let descriptor = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw NutrientImpactSidecarError.directoryUnavailable
        }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            Darwin.close(descriptor)
            throw NutrientImpactSidecarError.directoryUnavailable
        }
        return descriptor
    }

    private func fileName(for snapshot: NutrientImpactSnapshot) throws -> String {
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
        return "\(Self.filePrefix)\(fingerprint).\(Self.fileExtension)"
    }

    private func fileName(for record: RebuildMealRecordRevision) throws -> String {
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
        return "\(Self.filePrefix)\(fingerprint).\(Self.fileExtension)"
    }

    private func acceptExistingRevision(
        directoryDescriptor: Int32,
        name: String,
        matching snapshot: NutrientImpactSnapshot
    ) throws {
        guard let existing = readValidSnapshot(
            directoryDescriptor: directoryDescriptor,
            name: name
        ) else {
            throw NutrientImpactSidecarError.conflictingRevision
        }
        guard existing == snapshot else {
            throw NutrientImpactSidecarError.conflictingRevision
        }
    }

    private func readValidSnapshot(
        directoryDescriptor: Int32,
        name: String
    ) -> NutrientImpactSnapshot? {
        guard let data = Self.readBoundedFile(
            directoryDescriptor: directoryDescriptor,
            name: name
        ),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == Self.expectedEnvelopeJSONKeys,
              Self.hasStrictInteger(dictionary["envelopeVersion"]),
              let snapshotDictionary = dictionary["snapshot"] as? [String: Any],
              Set(snapshotDictionary.keys) == Self.expectedSnapshotJSONKeys,
              Self.hasStrictInteger(snapshotDictionary["schemaVersion"]),
              Self.hasStrictInteger(snapshotDictionary["ruleVersion"]),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.envelopeVersion == Self.supportedEnvelopeVersion,
              Self.isValid(envelope.snapshot),
              envelope.revisionFingerprint == Self.fingerprint(for: envelope.snapshot),
              envelope.snapshotDigest == Self.snapshotDigest(envelope.snapshot)
        else {
            return nil
        }
        return envelope.snapshot
    }

    private static func openAt(
        _ directoryDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t? = nil
    ) -> Int32 {
        name.withCString { pointer in
            if let mode {
                return Darwin.openat(directoryDescriptor, pointer, flags, mode)
            }
            return Darwin.openat(directoryDescriptor, pointer, flags)
        }
    }

    private static func unlinkAt(_ directoryDescriptor: Int32, name: String) {
        name.withCString { pointer in
            _ = Darwin.unlinkat(directoryDescriptor, pointer, 0)
        }
    }

    private static func renameExclusive(
        _ directoryDescriptor: Int32,
        from sourceName: String,
        to destinationName: String
    ) -> Int32 {
        sourceName.withCString { sourcePointer in
            destinationName.withCString { destinationPointer in
                Darwin.renameatx_np(
                    directoryDescriptor,
                    sourcePointer,
                    directoryDescriptor,
                    destinationPointer,
                    UInt32(RENAME_EXCL)
                )
            }
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return data.isEmpty }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                if result > 0 {
                    written += result
                } else if result < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private static func readBoundedFile(
        directoryDescriptor: Int32,
        name: String
    ) -> Data? {
        let descriptor = openAt(
            directoryDescriptor,
            name: name,
            flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0,
              info.st_size <= off_t(maximumSidecarBytes) else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: maximumSidecarBytes + 1)
        var total = 0
        while total < buffer.count {
            let result = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(
                    descriptor,
                    rawBuffer.baseAddress!.advanced(by: total),
                    rawBuffer.count - total
                )
            }
            if result > 0 {
                total += result
            } else if result == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                return nil
            }
        }
        guard total <= maximumSidecarBytes else { return nil }
        return Data(buffer.prefix(total))
    }

    private static let expectedEnvelopeJSONKeys: Set<String> = [
        "envelopeVersion",
        "revisionFingerprint",
        "snapshotDigest",
        "snapshot",
    ]

    private static let expectedSnapshotJSONKeys: Set<String> = [
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

    private static func encodeEnvelope(_ snapshot: NutrientImpactSnapshot) throws -> Data {
        let envelope = Envelope(
            envelopeVersion: supportedEnvelopeVersion,
            revisionFingerprint: fingerprint(for: snapshot),
            snapshotDigest: snapshotDigest(snapshot),
            snapshot: snapshot
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let encoded = try encoder.encode(envelope)
            guard encoded.count <= maximumSidecarBytes else {
                throw NutrientImpactSidecarError.invalidSnapshot
            }
            return encoded
        } catch let error as NutrientImpactSidecarError {
            throw error
        } catch {
            throw NutrientImpactSidecarError.writeFailed
        }
    }

    private static func canonicalSnapshotBytes(_ snapshot: NutrientImpactSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(snapshot)
    }

    private static func snapshotDigest(_ snapshot: NutrientImpactSnapshot) -> String {
        guard let bytes = canonicalSnapshotBytes(snapshot) else { return "" }
        return hexDigest(bytes)
    }

    private static func fingerprint(for snapshot: NutrientImpactSnapshot) -> String {
        fingerprint(
            recordID: snapshot.recordID,
            date: snapshot.date,
            normalizedMenuName: snapshot.normalizedMenuName,
            status: snapshot.status,
            updatedAt: snapshot.recordUpdatedAt
        )
    }

    static func validate(_ snapshot: NutrientImpactSnapshot) throws {
        guard snapshot.schemaVersion == NutrientImpactSnapshot.supportedSchemaVersion else {
            throw NutrientImpactSidecarError.unsupportedSchemaVersion
        }
        guard NutrientImpactSnapshot.supportedRuleVersions.contains(
            snapshot.ruleVersion
        ) else {
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
              NutrientImpactCopyCatalog.isCanonical(
                  status: snapshot.status,
                  nutrientIDs: snapshot.nutrients,
                  headline: snapshot.headline,
                  explanation: snapshot.explanation,
                  disclaimer: snapshot.disclaimer,
                  hasAlternatives: !snapshot.alternatives.isEmpty
              ),
              NutrientImpactCopyCatalog.validateMenuLabels(snapshot.alternatives),
              snapshot.status == .difficultToday
                || snapshot.alternatives.isEmpty,
              hasBoundedAggregateStrings(snapshot) else {
            throw NutrientImpactSidecarError.invalidSnapshot
        }
    }

    private static func isValid(_ snapshot: NutrientImpactSnapshot) -> Bool {
        (try? validate(snapshot)) != nil
    }

    static func validate(_ record: RebuildMealRecordRevision) -> Bool {
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
        guard validIdentifier(recordID, maximumBytes: maximumIdentifierBytes),
              validDate(date),
              validIdentifier(normalizedMenuName, maximumBytes: maximumIdentifierBytes),
              updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        return true
    }

    private static func validateIdentifierList(_ values: [String]) -> Bool {
        guard values.count <= 32,
              values.allSatisfy({ validIdentifier($0, maximumBytes: maximumNutrientIdentifierBytes) }),
              NutrientImpactCopyCatalog.validatedCanonicalNutrientIDs(values) != nil else {
            return false
        }
        return true
    }

    private static func hasBoundedAggregateStrings(_ snapshot: NutrientImpactSnapshot) -> Bool {
        var total = snapshot.recordID.utf8.count
            + snapshot.date.utf8.count
            + snapshot.normalizedMenuName.utf8.count
            + snapshot.status.rawValue.utf8.count
            + snapshot.headline.utf8.count
            + snapshot.explanation.utf8.count
            + snapshot.disclaimer.utf8.count
        for value in snapshot.nutrients where total <= maximumAggregateStringBytes {
            total += value.utf8.count
        }
        for value in snapshot.alternatives where total <= maximumAggregateStringBytes {
            total += value.utf8.count
        }
        return total <= maximumAggregateStringBytes
    }

    private static func validIdentifier(_ value: String, maximumBytes: Int) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              !containsControlCharacter(value),
              !containsPathTraversal(value) else {
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
        value.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "/" || $0 == "\\" }
        ).contains { $0 == "." || $0 == ".." }
    }

    private static func validDate(_ value: String) -> Bool {
        guard value.utf8.count == 10,
              value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
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
        appendComponent(recordID.precomposedStringWithCanonicalMapping, to: &canonical)
        appendComponent(date.precomposedStringWithCanonicalMapping, to: &canonical)
        appendComponent(normalizedMenuName.precomposedStringWithCanonicalMapping, to: &canonical)
        appendComponent(status.rawValue.precomposedStringWithCanonicalMapping, to: &canonical)
        var timestampBits = updatedAt.timeIntervalSinceReferenceDate.bitPattern.bigEndian
        withUnsafeBytes(of: &timestampBits) { canonical.append(contentsOf: $0) }

        return hexDigest(canonical)
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data)
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
