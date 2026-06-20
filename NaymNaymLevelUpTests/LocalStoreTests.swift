import XCTest
import CloudKit
@testable import NaymNaymLevelUp

final class LocalStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "NaymNaymLevelUpTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testProfileStoreSavesAndLoadsProfile() {
        let store = UserProfileStore(defaults: defaults)
        let profile = UserProfile(
            nickname: "냠냠이",
            schoolName: "냠냠중학교",
            officeCode: "B10",
            schoolCode: "7010111",
            regionName: "서울",
            selectedAllergyCodes: [1, 2]
        )

        store.save(profile)

        XCTAssertEqual(store.load()?.nickname, "냠냠이")
        XCTAssertEqual(store.load()?.selectedAllergyCodes, [1, 2])
    }

    func testChallengeStoreClearsRecords() {
        let store = ChallengeStore(defaults: defaults)
        let record = ChallengeRecord(date: "20260618", menuName: "콩나물무침", action: .oneBite, gainedExp: 20, badgeName: "초록 용사", nutrients: ["식이섬유"])

        store.save([record])
        XCTAssertEqual(store.load().count, 1)

        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testChallengeStoreSavesAlreadyEatsRecord() {
        let store = ChallengeStore(defaults: defaults)
        let record = ChallengeRecord(date: "20260618", menuName: "현미밥", action: .alreadyEats, gainedExp: 0, badgeName: nil, nutrients: ["탄수화물"])

        store.save([record])

        XCTAssertEqual(store.load().first?.action, .alreadyEats)
    }

    func testMealRecordStoreSavesEatingStatusAndReasons() {
        let store = MealRecordStore(defaults: defaults)
        let record = MealRecord(
            date: "20260618",
            menuName: "시금치나물",
            eatingStatus: .smelledOnly,
            difficultyReasons: [.smell, .texture],
            allergyCodes: [],
            photoIds: ["photo-1"],
            parentShareEnabled: true
        )

        store.save([record])

        XCTAssertEqual(store.load().first?.eatingStatus, .smelledOnly)
        XCTAssertEqual(store.load().first?.difficultyReasons, [.smell, .texture])
        XCTAssertEqual(store.load().first?.photoIds, ["photo-1"])
    }

    func testParentProfileStoreSavesChildLink() {
        let store = ParentProfileStore(defaults: defaults)
        let child = ChildLink(childNickname: "지우", schoolName: "등촌고등학교", mode: .high)
        store.save(ParentProfile(nickname: "보호자", childLinks: [child]))

        XCTAssertEqual(store.load().childLinks.first?.childNickname, "지우")
        XCTAssertEqual(store.load().childLinks.first?.mode, .high)
    }

    @MainActor
    func testParentModeStartsWithoutSchoolAndSkipsMealFetch() async {
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            automaticallyPublishesParentSharedData: false
        )

        appState.saveParentProfile(nickname: " 보호자 ")
        await appState.loadMeals()

        XCTAssertTrue(appState.hasProfile)
        XCTAssertEqual(appState.profile?.nickname, "보호자")
        XCTAssertEqual(appState.profile?.effectiveMode, .parent)
        XCTAssertEqual(appState.profile?.schoolCode, "")
        XCTAssertEqual(appState.profile?.officeCode, "")
        XCTAssertEqual(appState.profile?.themeId, UserMode.parent.defaultThemeId)
        XCTAssertTrue(appState.monthlyMeals.isEmpty)
        XCTAssertNil(appState.todayMeal)
        XCTAssertEqual(appState.mealStatus, .noMeal)
        XCTAssertEqual(appState.mealMessage, "부모 모드는 아이 초대 코드를 연결해 기록을 확인해요.")
    }

    @MainActor
    func testAppStateAddsInviteCodeChildLinkWithoutDuplicates() {
        let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            localPhotoStore: LocalPhotoStore(directoryURL: photoDirectory),
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider()
        )

        appState.addChildLink(inviteCode: " nyam-123456 ", nickname: "지우", schoolName: "등촌고등학교", mode: .high)
        appState.addChildLink(inviteCode: "NYAM-123456", nickname: "민준", schoolName: "냠냠중학교", mode: .middle)

        XCTAssertEqual(appState.parentProfile.childLinks.count, 1)
        XCTAssertEqual(appState.parentProfile.childLinks.first?.inviteCode, "NYAM-123456")
        XCTAssertEqual(appState.parentProfile.childLinks.first?.childNickname, "민준")
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    @MainActor
    func testChildSummariesOnlyExposeParentSharedPhotosAndRecords() {
        let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            localPhotoStore: LocalPhotoStore(directoryURL: photoDirectory),
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider()
        )
        appState.mealPhotos = [
            MealPhotoRecord(id: "shared-photo", fileName: "shared-photo.jpg", createdAt: Date(), isSharedWithParent: true),
            MealPhotoRecord(id: "private-photo", fileName: "private-photo.jpg", createdAt: Date(), isSharedWithParent: false)
        ]
        appState.mealRecords = [
            MealRecord(
                date: "20260618",
                menuName: "비공유나물",
                eatingStatus: .difficultToday,
                allergyCodes: [1],
                photoIds: ["shared-photo"],
                parentShareEnabled: false
            ),
            MealRecord(
                date: "20260618",
                menuName: "공유나물",
                eatingStatus: .oneBite,
                allergyCodes: [1],
                photoIds: ["shared-photo", "private-photo"],
                parentShareEnabled: true
            )
        ]
        appState.records = [
            ChallengeRecord(
                date: "20260618",
                menuName: "비공유나물",
                action: .oneBite,
                gainedExp: 18,
                badgeName: "초록 용사",
                nutrients: ["식이섬유"],
                childLinkId: UUID()
            ),
            ChallengeRecord(
                date: "20260618",
                menuName: "공유나물",
                action: .oneBite,
                gainedExp: 18,
                badgeName: "초록 용사",
                nutrients: ["식이섬유"]
            )
        ]

        let summary = appState.childSummaries[0]

        XCTAssertEqual(summary.weeklyRecords.map(\.menuName), ["공유나물"])
        XCTAssertEqual(summary.weeklyChallengeRecords.map(\.menuName), ["공유나물"])
        XCTAssertEqual(summary.allergyWarningMenus, ["공유나물"])
        XCTAssertEqual(summary.recentPhotoIds, ["shared-photo"])
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    func testLocalPhotoStoreSavesAndDeletesFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LocalPhotoStore(directoryURL: directory)
        let data = Data([0x01, 0x02, 0x03])

        let record = try store.savePhotoData(data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: record).path))

        store.delete(record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: record).path))
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testMealInteractionAssignsChildLinkWhenParentSharingEnabled() {
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-AAAA-BBBB-CCCC"
        )
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            automaticallyPublishesParentSharedData: false
        )
        appState.childShareLink = child

        _ = appState.recordMealInteraction(
            item: MealItem(name: "시금치나물", allergyCodes: [], nutrients: ["식이섬유"], tags: ["채소"], sourceRawText: "시금치나물"),
            date: "20260618",
            status: .oneBite,
            shareWithParent: true
        )

        XCTAssertEqual(appState.mealRecords.first?.childLinkId, child.id)
        XCTAssertEqual(appState.records.first?.childLinkId, child.id)
        XCTAssertEqual(appState.mealRecords.first?.parentShareEnabled, true)
    }

    @MainActor
    func testUpdateMealPhotoSharingClearsChildLinkWhenDisabled() throws {
        let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-AAAA-BBBB-CCCC"
        )
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            localPhotoStore: LocalPhotoStore(directoryURL: photoDirectory),
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            automaticallyPublishesParentSharedData: false
        )
        appState.childShareLink = child

        let sharedPhoto = try appState.saveMealPhotoData(Data([0x01, 0x02]), sharedWithParent: true)
        let privatePhoto = try XCTUnwrap(appState.updateMealPhotoSharing(sharedPhoto, sharedWithParent: false))

        XCTAssertFalse(privatePhoto.isSharedWithParent)
        XCTAssertNil(privatePhoto.childLinkId)
        XCTAssertEqual(appState.mealPhotos.first?.isSharedWithParent, false)
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    func testCloudKitInviteCodeDoesNotExposeNickname() {
        let service = CloudKitParentLinkService()
        let code = service.makeInviteCode(nickname: "지우", nonce: "fixed-nonce")

        XCTAssertTrue(code.hasPrefix("NYAM-"))
        XCTAssertEqual(code.count, 19)
        XCTAssertFalse(code.contains("지우"))
        XCTAssertEqual(service.normalizeInviteCode(" \(code.lowercased()) "), code)
    }

    func testCloudKitInviteCodeNormalizationAcceptsMissingHyphens() {
        let service = CloudKitParentLinkService()

        XCTAssertEqual(
            service.normalizeInviteCode("nyam abcd efgh ijkl"),
            "NYAM-ABCD-EFGH-IJKL"
        )
        XCTAssertEqual(
            service.normalizeInviteCode("nyamabcdefghijkl"),
            "NYAM-ABCD-EFGH-IJKL"
        )
    }

    func testCloudKitSetupOnlyRequiresQueryableIndexes() {
        let service = CloudKitParentLinkService()
        let checklist = service.setupChecklist.joined(separator: "\n")

        XCTAssertTrue(checklist.contains("ParentLink.inviteCode"))
        XCTAssertTrue(checklist.contains("SharedMealRecord.childLinkId"))
        XCTAssertTrue(checklist.contains("SharedChallengeRecord.childLinkId"))
        XCTAssertTrue(checklist.contains("SharedMealPhoto.childLinkId"))
        XCTAssertTrue(checklist.contains("queryable index"))
        XCTAssertTrue(checklist.contains("sortable index는 필요 없음"))
    }

    func testCloudKitSharedMealRecordRequiresParentShare() {
        let service = CloudKitParentLinkService()
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-123456"
        )
        let hidden = MealRecord(
            date: "20260618",
            menuName: "시금치나물",
            eatingStatus: .difficultToday,
            parentShareEnabled: false
        )
        let shared = MealRecord(
            date: "20260618",
            menuName: "시금치나물",
            eatingStatus: .oneBite,
            difficultyReasons: [.texture],
            allergyCodes: [1],
            photoIds: ["photo-1"],
            parentShareEnabled: true
        )

        XCTAssertNil(service.makeSharedMealRecord(hidden, childLink: child))
        let record = service.makeSharedMealRecord(shared, childLink: child)
        XCTAssertEqual(record?.recordType, CloudKitParentLinkService.sharedMealRecordType)
        XCTAssertEqual(record?["menuName"] as? String, "시금치나물")
        XCTAssertEqual(record?["eatingStatus"] as? String, EatingStatus.oneBite.rawValue)
    }

    func testCloudKitSharedChallengeRecordUsesCurrentChildForLocalRecord() {
        let service = CloudKitParentLinkService()
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-IJKL"
        )
        let localRecord = ChallengeRecord(
            date: "20260618",
            menuName: "시금치나물",
            action: .oneBite,
            gainedExp: 18,
            badgeName: "초록 용사",
            nutrients: ["식이섬유"],
            childLinkId: nil
        )

        let record = service.makeSharedChallengeRecord(localRecord, childLink: child)

        XCTAssertEqual(record?.recordType, CloudKitParentLinkService.sharedChallengeRecordType)
        XCTAssertEqual(record?["childLinkId"] as? String, child.id.uuidString)
        XCTAssertEqual(record?["menuName"] as? String, "시금치나물")
    }

    func testCloudKitSharedMealRecordRespectsSharingPermissions() {
        let service = CloudKitParentLinkService()
        let blockedChild = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-IJKL",
            permissions: SharingPermission(shareEatingRecords: false, shareChallengeRecords: true, shareAllergyWarnings: true, sharePhotos: true)
        )
        let allergyHiddenChild = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-IJKL",
            permissions: SharingPermission(shareEatingRecords: true, shareChallengeRecords: true, shareAllergyWarnings: false, sharePhotos: true)
        )
        let shared = MealRecord(
            date: "20260618",
            menuName: "우유",
            eatingStatus: .oneBite,
            allergyCodes: [2],
            parentShareEnabled: true
        )

        XCTAssertNil(service.makeSharedMealRecord(shared, childLink: blockedChild))
        let record = service.makeSharedMealRecord(shared, childLink: allergyHiddenChild)
        XCTAssertEqual(record?["allergyCodes"] as? String, "")
    }

    func testCloudKitPhotoRecordRequiresBothPermissions() {
        let service = CloudKitParentLinkService()
        let blockedChild = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-123456",
            permissions: SharingPermission(shareEatingRecords: true, shareChallengeRecords: true, shareAllergyWarnings: true, sharePhotos: false)
        )
        let photo = MealPhotoRecord(id: "photo-1", fileName: "photo-1.jpg", createdAt: Date(), isSharedWithParent: true)

        XCTAssertNil(service.makeSharedPhotoRecord(photo, childLink: blockedChild))

        let allowedChild = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-123456",
            permissions: SharingPermission(shareEatingRecords: true, shareChallengeRecords: true, shareAllergyWarnings: true, sharePhotos: true)
        )
        XCTAssertEqual(service.makeSharedPhotoRecord(photo, childLink: allowedChild)?.recordType, CloudKitParentLinkService.sharedMealPhotoRecordType)
    }

    @MainActor
    func testChildSummariesSeparateRecordsByChildLinkId() {
        let firstChildId = UUID()
        let secondChildId = UUID()
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider()
        )
        appState.parentProfile = ParentProfile(
            childLinks: [
                ChildLink(id: firstChildId, childNickname: "첫째", schoolName: "등촌고등학교", mode: .high, inviteCode: "NYAM-AAAA-BBBB-CCCC"),
                ChildLink(id: secondChildId, childNickname: "둘째", schoolName: "냠냠중학교", mode: .middle, inviteCode: "NYAM-DDDD-EEEE-FFFF")
            ]
        )
        appState.mealRecords = [
            MealRecord(
                date: "20260618",
                menuName: "첫째나물",
                eatingStatus: .oneBite,
                parentShareEnabled: true,
                childLinkId: firstChildId
            ),
            MealRecord(
                date: "20260618",
                menuName: "둘째나물",
                eatingStatus: .difficultToday,
                parentShareEnabled: true,
                childLinkId: secondChildId
            )
        ]
        appState.records = [
            ChallengeRecord(
                date: "20260618",
                menuName: "첫째나물",
                action: .oneBite,
                gainedExp: 18,
                badgeName: "초록 용사",
                nutrients: ["식이섬유"],
                childLinkId: firstChildId
            ),
            ChallengeRecord(
                date: "20260618",
                menuName: "둘째나물",
                action: .skipped,
                gainedExp: 3,
                badgeName: nil,
                nutrients: ["식이섬유"],
                childLinkId: secondChildId
            )
        ]

        let summaries = appState.childSummaries

        XCTAssertEqual(summaries.first?.weeklyRecords.map(\.menuName), ["첫째나물"])
        XCTAssertEqual(summaries.last?.weeklyRecords.map(\.menuName), ["둘째나물"])
        XCTAssertEqual(summaries.first?.weeklyChallengeRecords.map(\.menuName), ["첫째나물"])
        XCTAssertEqual(summaries.last?.weeklyChallengeRecords.map(\.menuName), ["둘째나물"])
    }
}
