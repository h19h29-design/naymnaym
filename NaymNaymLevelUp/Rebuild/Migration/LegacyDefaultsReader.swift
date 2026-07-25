import CryptoKit
import Foundation

struct LegacySnapshot {
    let profile: UserProfile?
    let progress: PlayerProgress
    let mealRecords: [MealRecord]
    let mealPhotoRecords: [MealPhotoRecord]
    let challenges: [ChallengeRecord]
    let parentProfile: ParentProfile
    let childLink: ChildLink?

    fileprivate let sourceKeys: Set<String>

    init(
        profile: UserProfile?,
        progress: PlayerProgress,
        mealRecords: [MealRecord],
        mealPhotoRecords: [MealPhotoRecord],
        challenges: [ChallengeRecord],
        parentProfile: ParentProfile,
        childLink: ChildLink?,
        sourceKeys: Set<String> = []
    ) {
        self.profile = profile
        self.progress = progress
        self.mealRecords = mealRecords
        self.mealPhotoRecords = mealPhotoRecords
        self.challenges = challenges
        self.parentProfile = parentProfile
        self.childLink = childLink
        self.sourceKeys = sourceKeys
    }

    var hasLegacyData: Bool {
        !sourceKeys.isEmpty
    }

    var hasStoredProgress: Bool {
        sourceKeys.contains(LegacyDefaultsReader.Key.progress)
    }

    var hasStoredParentProfile: Bool {
        sourceKeys.contains(LegacyDefaultsReader.Key.parentProfile)
    }
}

struct LegacyDefaultsReader {
    enum Key {
        static let profile = "user-profile"
        static let progress = "player-progress"
        static let challenges = "challenge-records"
        static let mealRecords = "meal-records"
        static let mealPhotoRecords = "meal-photo-records"
        static let parentProfile = "parent-profile"
        static let childLink = "child-share-link"

        static let all = [
            profile,
            progress,
            challenges,
            mealRecords,
            mealPhotoRecords,
            parentProfile,
            childLink,
        ]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func readSnapshot() throws -> LegacySnapshot {
        let presentKeys = Set(Key.all.filter { defaults.object(forKey: $0) != nil })
        return LegacySnapshot(
            profile: UserProfileStore(defaults: defaults).load(),
            progress: ProgressStore(defaults: defaults).load(),
            mealRecords: MealRecordStore(defaults: defaults).load(),
            mealPhotoRecords: MealPhotoMetadataStore(defaults: defaults).load(),
            challenges: ChallengeStore(defaults: defaults).load(),
            parentProfile: ParentProfileStore(defaults: defaults).load(),
            childLink: ChildShareLinkStore(defaults: defaults).load(),
            sourceKeys: presentKeys
        )
    }

    func sourceDigest(for snapshot: LegacySnapshot) throws -> String {
        let payload = DigestPayload(
            sourceKeys: snapshot.sourceKeys.sorted(),
            profile: snapshot.sourceKeys.contains(Key.profile) ? snapshot.profile : nil,
            progress: snapshot.sourceKeys.contains(Key.progress) ? snapshot.progress : nil,
            mealRecords: snapshot.sourceKeys.contains(Key.mealRecords) ? snapshot.mealRecords : nil,
            mealPhotoRecords: snapshot.sourceKeys.contains(Key.mealPhotoRecords)
                ? snapshot.mealPhotoRecords
                : nil,
            challenges: snapshot.sourceKeys.contains(Key.challenges) ? snapshot.challenges : nil,
            parentProfile: snapshot.sourceKeys.contains(Key.parentProfile)
                ? snapshot.parentProfile
                : nil,
            childLink: snapshot.sourceKeys.contains(Key.childLink) ? snapshot.childLink : nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(payload))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct DigestPayload: Encodable {
    let sourceKeys: [String]
    let profile: UserProfile?
    let progress: PlayerProgress?
    let mealRecords: [MealRecord]?
    let mealPhotoRecords: [MealPhotoRecord]?
    let challenges: [ChallengeRecord]?
    let parentProfile: ParentProfile?
    let childLink: ChildLink?
}
