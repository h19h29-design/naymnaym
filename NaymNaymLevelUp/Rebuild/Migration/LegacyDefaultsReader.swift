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
    private let persistentDomainName: String?

    init(
        defaults: UserDefaults = .standard,
        persistentDomainName: String? = nil
    ) {
        self.defaults = defaults
        self.persistentDomainName = persistentDomainName
            ?? (defaults === UserDefaults.standard ? Bundle.main.bundleIdentifier : nil)
    }

    func readSnapshot() throws -> LegacySnapshot {
        let profile = try UserProfileStore(defaults: defaults)
            .readPersisted(domainName: persistentDomainName)
        let progress = try ProgressStore(defaults: defaults)
            .readPersisted(domainName: persistentDomainName)
        let mealRecords = try MealRecordStore(defaults: defaults)
            .readPersisted(domainName: persistentDomainName)
        let mealPhotoRecords = try MealPhotoMetadataStore(defaults: defaults)
            .readPersisted(domainName: persistentDomainName)
        let challenges = try ChallengeStore(defaults: defaults)
            .readPersisted(domainName: persistentDomainName)
        let parentProfile = try ParentProfileStore(defaults: defaults)
            .readPersisted(domainName: persistentDomainName)
        let childLink = try ChildShareLinkStore(defaults: defaults)
            .readPersisted(domainName: persistentDomainName)
        let presentKeys = Set([
            profile.isPresent ? Key.profile : nil,
            progress.isPresent ? Key.progress : nil,
            mealRecords.isPresent ? Key.mealRecords : nil,
            mealPhotoRecords.isPresent ? Key.mealPhotoRecords : nil,
            challenges.isPresent ? Key.challenges : nil,
            parentProfile.isPresent ? Key.parentProfile : nil,
            childLink.isPresent ? Key.childLink : nil,
        ].compactMap { $0 })
        return LegacySnapshot(
            profile: profile.value,
            progress: progress.value ?? PlayerProgress(),
            mealRecords: mealRecords.value ?? [],
            mealPhotoRecords: mealPhotoRecords.value ?? [],
            challenges: challenges.value ?? [],
            parentProfile: parentProfile.value ?? ParentProfile(),
            childLink: childLink.value,
            sourceKeys: presentKeys
        )
    }

    func sourceDigest(for snapshot: LegacySnapshot) throws -> String {
        let payload = DigestPayload(
            sourceKeys: snapshot.sourceKeys.sorted(),
            profile: snapshot.sourceKeys.contains(Key.profile) ? snapshot.profile : nil,
            progress: snapshot.sourceKeys.contains(Key.progress)
                ? DigestProgress(snapshot.progress)
                : nil,
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
    let progress: DigestProgress?
    let mealRecords: [MealRecord]?
    let mealPhotoRecords: [MealPhotoRecord]?
    let challenges: [ChallengeRecord]?
    let parentProfile: ParentProfile?
    let childLink: ChildLink?
}

private struct DigestProgress: Encodable {
    let level: Int
    let recordExp: Int
    let challengeExp: Int
    let balanceExp: Int
    let safetyExp: Int
    let totalChallenges: Int
    let badges: [String]
    let currentSkinId: String

    init(_ progress: PlayerProgress) {
        level = progress.level
        recordExp = progress.recordExp
        challengeExp = progress.challengeExp
        balanceExp = progress.balanceExp
        safetyExp = progress.safetyExp
        totalChallenges = progress.totalChallenges
        badges = progress.badges
        currentSkinId = progress.currentSkinId
    }
}
