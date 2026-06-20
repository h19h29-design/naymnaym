import Foundation
import CloudKit

final class CodableUserDefaultsStore<Value: Codable> {
    private let key: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

final class UserProfileStore {
    private let store: CodableUserDefaultsStore<UserProfile>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "user-profile", defaults: defaults)
    }

    func load() -> UserProfile? { store.load() }
    func save(_ profile: UserProfile) { store.save(profile) }
    func clear() { store.clear() }
}

final class ProgressStore {
    private let store: CodableUserDefaultsStore<PlayerProgress>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "player-progress", defaults: defaults)
    }

    func load() -> PlayerProgress { store.load() ?? PlayerProgress() }
    func save(_ progress: PlayerProgress) { store.save(progress) }
    func clear() { store.clear() }
}

final class ChallengeStore {
    private let store: CodableUserDefaultsStore<[ChallengeRecord]>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "challenge-records", defaults: defaults)
    }

    func load() -> [ChallengeRecord] { store.load() ?? [] }
    func save(_ records: [ChallengeRecord]) { store.save(records) }
    func clear() { store.clear() }
}

final class MealRecordStore {
    private let store: CodableUserDefaultsStore<[MealRecord]>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "meal-records", defaults: defaults)
    }

    func load() -> [MealRecord] { store.load() ?? [] }
    func save(_ records: [MealRecord]) { store.save(records) }
    func clear() { store.clear() }
}

final class MealPhotoMetadataStore {
    private let store: CodableUserDefaultsStore<[MealPhotoRecord]>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "meal-photo-records", defaults: defaults)
    }

    func load() -> [MealPhotoRecord] { store.load() ?? [] }
    func save(_ records: [MealPhotoRecord]) { store.save(records) }
    func clear() { store.clear() }
}

final class ParentProfileStore {
    private let store: CodableUserDefaultsStore<ParentProfile>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "parent-profile", defaults: defaults)
    }

    func load() -> ParentProfile { store.load() ?? ParentProfile() }
    func save(_ profile: ParentProfile) { store.save(profile) }
    func clear() { store.clear() }
}

final class ChildShareLinkStore {
    private let store: CodableUserDefaultsStore<ChildLink>

    init(defaults: UserDefaults = .standard) {
        store = CodableUserDefaultsStore(key: "child-share-link", defaults: defaults)
    }

    func load() -> ChildLink? { store.load() }
    func save(_ link: ChildLink) { store.save(link) }
    func clear() { store.clear() }
}

final class LocalPhotoStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directoryURL = documents.appendingPathComponent("MealPhotos", isDirectory: true)
        }
    }

    func savePhotoData(_ data: Data, sharedWithParent: Bool = false) throws -> MealPhotoRecord {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let fileName = "\(id).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return MealPhotoRecord(
            id: id,
            fileName: fileName,
            createdAt: Date(),
            isSharedWithParent: sharedWithParent
        )
    }

    func importSharedPhotoData(_ data: Data, id: String, createdAt: Date, childLinkId: UUID?) throws -> MealPhotoRecord {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let safeId = id.replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeId)-shared.jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return MealPhotoRecord(
            id: id,
            fileName: fileName,
            createdAt: createdAt,
            isSharedWithParent: true,
            childLinkId: childLinkId
        )
    }

    func url(for record: MealPhotoRecord) -> URL {
        directoryURL.appendingPathComponent(record.fileName)
    }

    func delete(_ record: MealPhotoRecord) {
        try? fileManager.removeItem(at: url(for: record))
    }

    func clear(records: [MealPhotoRecord]) {
        records.forEach(delete)
    }
}

struct CloudSharedPhotoPayload {
    var record: MealPhotoRecord
    var data: Data?
}

struct CloudChildShareSnapshot {
    var mealRecords: [MealRecord]
    var challengeRecords: [ChallengeRecord]
    var photoPayloads: [CloudSharedPhotoPayload]
}

struct CloudKitParentLinkService {
    static let parentLinkRecordType = "ParentLink"
    static let sharedMealRecordType = "SharedMealRecord"
    static let sharedChallengeRecordType = "SharedChallengeRecord"
    static let sharedMealPhotoRecordType = "SharedMealPhoto"

    private let container: CKContainer?

    init(container: CKContainer? = nil) {
        self.container = container
    }

    func makeInviteCode(nickname: String, nonce: String = UUID().uuidString) -> String {
        let seed = "\(nickname.trimmingCharacters(in: .whitespacesAndNewlines))|\(nonce)|\(UUID().uuidString)"
        let encoded = base32(stableHash(seed), length: 12)
        let first = encoded.prefix(4)
        let second = encoded.dropFirst(4).prefix(4)
        let third = encoded.dropFirst(8).prefix(4)
        return "NYAM-\(first)-\(second)-\(third)"
    }

    func normalizeInviteCode(_ code: String) -> String {
        let trimmed = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")

        let compact = trimmed.unicodeScalars
            .filter { $0.value <= 127 && CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()

        guard compact.hasPrefix("NYAM") else {
            return trimmed
        }

        let body = String(compact.dropFirst(4))
        guard body.count == 12 else {
            return trimmed
        }

        let first = body.prefix(4)
        let second = body.dropFirst(4).prefix(4)
        let third = body.dropFirst(8).prefix(4)
        return "NYAM-\(first)-\(second)-\(third)"
    }

    func makeChildLink(profile: UserProfile, permissions: SharingPermission = .defaultChildSafe) -> ChildLink {
        ChildLink(
            childNickname: profile.nickname,
            schoolName: profile.schoolName,
            mode: profile.effectiveMode,
            inviteCode: makeInviteCode(nickname: profile.nickname),
            permissions: permissions
        )
    }

    func makeParentLinkRecord(childLink: ChildLink) -> CKRecord {
        let record = CKRecord(
            recordType: Self.parentLinkRecordType,
            recordID: CKRecord.ID(recordName: "parentlink-\(childLink.id.uuidString)")
        )
        record["childLinkId"] = childLink.id.uuidString as CKRecordValue
        record["childNickname"] = childLink.childNickname as CKRecordValue
        record["schoolName"] = childLink.schoolName as CKRecordValue
        record["mode"] = childLink.mode.rawValue as CKRecordValue
        record["inviteCode"] = childLink.inviteCode as CKRecordValue
        record["shareEatingRecords"] = childLink.permissions.shareEatingRecords as CKRecordValue
        record["shareChallengeRecords"] = childLink.permissions.shareChallengeRecords as CKRecordValue
        record["shareAllergyWarnings"] = childLink.permissions.shareAllergyWarnings as CKRecordValue
        record["sharePhotos"] = childLink.permissions.sharePhotos as CKRecordValue
        record["createdAt"] = childLink.createdAt as CKRecordValue
        return record
    }

    func makeSharedMealRecord(_ mealRecord: MealRecord, childLink: ChildLink) -> CKRecord? {
        guard childLink.permissions.shareEatingRecords, mealRecord.parentShareEnabled else { return nil }
        let record = CKRecord(
            recordType: Self.sharedMealRecordType,
            recordID: CKRecord.ID(recordName: "meal-\(childLink.id.uuidString)-\(mealRecord.id.uuidString)")
        )
        record["mealRecordId"] = mealRecord.id.uuidString as CKRecordValue
        record["childLinkId"] = childLink.id.uuidString as CKRecordValue
        record["date"] = mealRecord.date as CKRecordValue
        record["menuName"] = mealRecord.menuName as CKRecordValue
        record["eatingStatus"] = mealRecord.eatingStatus.rawValue as CKRecordValue
        record["difficultyReasons"] = mealRecord.difficultyReasons.map(\.rawValue).joined(separator: ",") as CKRecordValue
        record["allergyCodes"] = childLink.permissions.shareAllergyWarnings ? mealRecord.allergyCodes.map(String.init).joined(separator: ",") as CKRecordValue : "" as CKRecordValue
        record["photoIds"] = mealRecord.photoIds.joined(separator: ",") as CKRecordValue
        record["createdAt"] = mealRecord.createdAt as CKRecordValue
        return record
    }

    func makeSharedChallengeRecord(_ challengeRecord: ChallengeRecord, childLink: ChildLink) -> CKRecord? {
        guard childLink.permissions.shareChallengeRecords else { return nil }
        let record = CKRecord(
            recordType: Self.sharedChallengeRecordType,
            recordID: CKRecord.ID(recordName: "challenge-\(childLink.id.uuidString)-\(challengeRecord.id.uuidString)")
        )
        record["challengeRecordId"] = challengeRecord.id.uuidString as CKRecordValue
        record["childLinkId"] = childLink.id.uuidString as CKRecordValue
        record["date"] = challengeRecord.date as CKRecordValue
        record["menuName"] = challengeRecord.menuName as CKRecordValue
        record["action"] = challengeRecord.action.rawValue as CKRecordValue
        record["gainedExp"] = challengeRecord.gainedExp as CKRecordValue
        record["badgeName"] = (challengeRecord.badgeName ?? "") as CKRecordValue
        record["nutrients"] = challengeRecord.nutrients.joined(separator: ",") as CKRecordValue
        record["createdAt"] = challengeRecord.createdAt as CKRecordValue
        return record
    }

    func makeSharedPhotoRecord(_ photoRecord: MealPhotoRecord, childLink: ChildLink, photoURL: URL? = nil) -> CKRecord? {
        guard childLink.permissions.sharePhotos, photoRecord.isSharedWithParent else { return nil }
        let record = CKRecord(
            recordType: Self.sharedMealPhotoRecordType,
            recordID: CKRecord.ID(recordName: "photo-\(childLink.id.uuidString)-\(photoRecord.id)")
        )
        record["childLinkId"] = childLink.id.uuidString as CKRecordValue
        record["photoId"] = photoRecord.id as CKRecordValue
        record["fileName"] = photoRecord.fileName as CKRecordValue
        record["createdAt"] = photoRecord.createdAt as CKRecordValue
        if let photoURL {
            record["photoAsset"] = CKAsset(fileURL: photoURL)
        }
        return record
    }

    func saveParentLink(_ childLink: ChildLink) async throws -> CKRecord.ID {
        let record = makeParentLinkRecord(childLink: childLink)
        let saved = try await saveOrUpdate(record)
        return saved.recordID
    }

    func saveSharedRecords(_ records: [CKRecord]) async throws {
        for record in records {
            _ = try await saveOrUpdate(record)
        }
    }

    func fetchParentLink(inviteCode: String) async throws -> ChildLink {
        let normalizedCode = normalizeInviteCode(inviteCode)
        let predicate = NSPredicate(format: "inviteCode == %@", normalizedCode)
        let query = CKQuery(recordType: Self.parentLinkRecordType, predicate: predicate)
        let links = try await perform(query)
            .compactMap { makeChildLink(from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
        guard let link = links.first else {
            throw CloudKitParentLinkError.inviteCodeNotFound
        }
        return link
    }

    func fetchSharedSnapshot(childLink: ChildLink) async throws -> CloudChildShareSnapshot {
        let childLinkId = childLink.id.uuidString
        let predicate = NSPredicate(format: "childLinkId == %@", childLinkId)

        let mealQuery = CKQuery(recordType: Self.sharedMealRecordType, predicate: predicate)
        let meals = try await perform(mealQuery)
            .compactMap { makeMealRecord(from: $0, childLink: childLink) }
            .sorted { $0.createdAt > $1.createdAt }

        let challengeQuery = CKQuery(recordType: Self.sharedChallengeRecordType, predicate: predicate)
        let challenges = try await perform(challengeQuery)
            .compactMap { makeChallengeRecord(from: $0, childLink: childLink) }
            .sorted { $0.createdAt > $1.createdAt }

        let photoQuery = CKQuery(recordType: Self.sharedMealPhotoRecordType, predicate: predicate)
        let photos = try await perform(photoQuery)
            .compactMap { makePhotoPayload(from: $0, childLink: childLink) }
            .sorted { $0.record.createdAt > $1.record.createdAt }

        return CloudChildShareSnapshot(mealRecords: meals, challengeRecords: challenges, photoPayloads: photos)
    }

    var recordTypes: [String] {
        [
            Self.parentLinkRecordType,
            Self.sharedMealRecordType,
            Self.sharedChallengeRecordType,
            Self.sharedMealPhotoRecordType
        ]
    }

    var setupChecklist: [String] {
        [
            "iCloud capability와 CloudKit container 연결",
            "초대 코드로 public CloudKit ParentLink record 생성",
            "ParentLink.inviteCode, SharedMealRecord.childLinkId, SharedChallengeRecord.childLinkId, SharedMealPhoto.childLinkId queryable index 구성",
            "createdAt 최신순 정렬은 앱 내부에서 처리하므로 CloudKit sortable index는 필요 없음",
            "먹은 정도, 한 입 도전, 알레르기 주의, 선택 사진만 공유",
            "자유 채팅, 공개 피드, 학교 통계 record는 만들지 않음"
        ]
    }

    private var database: CKDatabase {
        (container ?? CKContainer.default()).publicCloudDatabase
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: CloudKitParentLinkError.emptyResponse)
                }
            }
        }
    }

    private func saveOrUpdate(_ record: CKRecord) async throws -> CKRecord {
        do {
            let existing = try await fetch(record.recordID)
            for key in record.allKeys() {
                existing[key] = record[key]
            }
            return try await save(existing)
        } catch let error as CKError where error.code == .unknownItem {
            return try await save(record)
        }
    }

    private func fetch(_ recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CloudKitParentLinkError.emptyResponse)
                }
            }
        }
    }

    private func perform(_ query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var operation: CKQueryOperation? = CKQueryOperation(query: query)

        while let currentOperation = operation {
            let page = try await run(currentOperation)
            records.append(contentsOf: page.records)

            if let cursor = page.cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = nil
            }
        }

        return records
    }

    private func run(_ operation: CKQueryOperation) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var records: [CKRecord] = []
            var recordError: Error?

            operation.resultsLimit = 100
            operation.recordMatchedBlock = { _, result in
                lock.lock()
                defer { lock.unlock() }

                switch result {
                case .success(let record):
                    records.append(record)
                case .failure(let error):
                    recordError = error
                }
            }
            operation.queryResultBlock = { result in
                lock.lock()
                let finalRecords = records
                let finalRecordError = recordError
                lock.unlock()

                switch result {
                case .success(let cursor):
                    if let finalRecordError {
                        continuation.resume(throwing: finalRecordError)
                    } else {
                        continuation.resume(returning: (finalRecords, cursor))
                    }
                case .failure(let error):
                    continuation.resume(throwing: finalRecordError ?? error)
                }
            }
            database.add(operation)
        }
    }

    private func makeChildLink(from record: CKRecord) -> ChildLink? {
        guard let childLinkIdText = record["childLinkId"] as? String,
              let childLinkId = UUID(uuidString: childLinkIdText),
              let childNickname = record["childNickname"] as? String,
              let schoolName = record["schoolName"] as? String,
              let modeText = record["mode"] as? String,
              let mode = UserMode(rawValue: modeText),
              let inviteCode = record["inviteCode"] as? String
        else {
            return nil
        }

        return ChildLink(
            id: childLinkId,
            childNickname: childNickname,
            schoolName: schoolName,
            mode: mode,
            inviteCode: inviteCode,
            permissions: SharingPermission(
                shareEatingRecords: record["shareEatingRecords"] as? Bool ?? true,
                shareChallengeRecords: record["shareChallengeRecords"] as? Bool ?? true,
                shareAllergyWarnings: record["shareAllergyWarnings"] as? Bool ?? true,
                sharePhotos: record["sharePhotos"] as? Bool ?? false
            ),
            createdAt: record["createdAt"] as? Date ?? Date()
        )
    }

    private func makeMealRecord(from record: CKRecord, childLink: ChildLink) -> MealRecord? {
        guard let date = record["date"] as? String,
              let menuName = record["menuName"] as? String,
              let statusText = record["eatingStatus"] as? String,
              let status = EatingStatus(rawValue: statusText)
        else {
            return nil
        }

        let id = (record["mealRecordId"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        return MealRecord(
            id: id,
            date: date,
            menuName: menuName,
            eatingStatus: status,
            difficultyReasons: split(record["difficultyReasons"] as? String).compactMap(DifficultyReason.init(rawValue:)),
            allergyCodes: split(record["allergyCodes"] as? String).compactMap(Int.init),
            photoIds: split(record["photoIds"] as? String),
            parentShareEnabled: true,
            createdAt: record["createdAt"] as? Date ?? Date(),
            childLinkId: childLink.id
        )
    }

    private func makeChallengeRecord(from record: CKRecord, childLink: ChildLink) -> ChallengeRecord? {
        guard let date = record["date"] as? String,
              let menuName = record["menuName"] as? String,
              let actionText = record["action"] as? String,
              let action = ChallengeRecord.Action(rawValue: actionText)
        else {
            return nil
        }

        let id = (record["challengeRecordId"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let badgeName = (record["badgeName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ChallengeRecord(
            id: id,
            date: date,
            menuName: menuName,
            action: action,
            gainedExp: record["gainedExp"] as? Int ?? 0,
            badgeName: badgeName,
            nutrients: split(record["nutrients"] as? String),
            createdAt: record["createdAt"] as? Date ?? Date(),
            childLinkId: childLink.id
        )
    }

    private func makePhotoPayload(from record: CKRecord, childLink: ChildLink) -> CloudSharedPhotoPayload? {
        guard let photoId = record["photoId"] as? String,
              let fileName = record["fileName"] as? String
        else {
            return nil
        }

        var data: Data?
        if let asset = record["photoAsset"] as? CKAsset,
           let fileURL = asset.fileURL {
            data = try? Data(contentsOf: fileURL)
        }

        let photo = MealPhotoRecord(
            id: photoId,
            fileName: fileName,
            createdAt: record["createdAt"] as? Date ?? Date(),
            isSharedWithParent: true,
            childLinkId: childLink.id
        )
        return CloudSharedPhotoPayload(record: photo, data: data)
    }

    private func split(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text.split(separator: ",").map { String($0) }
    }

    private func base32(_ value: UInt64, length: Int) -> String {
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var number = value
        var characters: [Character] = []
        repeat {
            characters.append(alphabet[Int(number % UInt64(alphabet.count))])
            number /= UInt64(alphabet.count)
        } while number > 0

        while characters.count < length {
            characters.append(alphabet[Int(stableHash(String(characters)) % UInt64(alphabet.count))])
        }

        return String(characters.prefix(length))
    }

    private func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

enum CloudKitParentLinkError: LocalizedError {
    case inviteCodeNotFound
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .inviteCodeNotFound:
            return "초대 코드를 찾지 못했어요."
        case .emptyResponse:
            return "CloudKit 응답이 비어 있어요."
        }
    }
}
