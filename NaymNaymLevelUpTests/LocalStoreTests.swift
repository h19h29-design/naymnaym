import XCTest
import CloudKit
import UIKit
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
        XCTAssertEqual(store.load().first?.parentShareEnabled, false)
    }

    func testLegacyChallengeRecordDefaultsToPrivateParentShare() throws {
        let json = Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "date": "20260618",
          "menuName": "콩나물무침",
          "action": "oneBite",
          "gainedExp": 18,
          "badgeName": "초록 용사",
          "nutrients": ["식이섬유"],
          "createdAt": "2026-06-18T00:00:00Z"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(ChallengeRecord.self, from: json)

        XCTAssertEqual(record.menuName, "콩나물무침")
        XCTAssertFalse(record.parentShareEnabled)
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

    func testParentPushDeviceTokenStoreSavesAndClearsToken() {
        let store = ParentPushDeviceTokenStore(defaults: defaults)

        store.save(String(repeating: "a", count: 64))

        XCTAssertEqual(store.load(), String(repeating: "a", count: 64))
        store.clear()
        XCTAssertNil(store.load())
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
        XCTAssertEqual(appState.mealMessage, "부모 모드는 아이 초대 코드를 연결해 기록과 급식 메뉴를 확인해요.")
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

        appState.addChildLink(inviteCode: " nyam abcd efgh jklm ", nickname: "지우", schoolName: "등촌고등학교", mode: .high)
        appState.addChildLink(inviteCode: "NYAM-ABCD-EFGH-JKLM", nickname: "민준", schoolName: "냠냠중학교", mode: .middle)

        XCTAssertEqual(appState.parentProfile.childLinks.count, 1)
        XCTAssertEqual(appState.parentProfile.childLinks.first?.inviteCode, "NYAM-ABCD-EFGH-JKLM")
        XCTAssertEqual(appState.parentProfile.childLinks.first?.childNickname, "민준")
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    @MainActor
    func testAppStateRejectsInvalidLocalInviteCodeChildLink() {
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

        appState.addChildLink(inviteCode: "NYAM-ABCD-EFGH-JK1M", nickname: "지우", schoolName: "등촌고등학교", mode: .high)

        XCTAssertTrue(appState.parentProfile.childLinks.isEmpty)
        XCTAssertEqual(
            appState.parentSyncMessage,
            "헷갈리는 문자 O, 0, I, 1은 초대 코드에 사용하지 않아요. 아이 기기에서 코드를 다시 확인해 주세요."
        )
        XCTAssertEqual(appState.parentSyncError, appState.parentSyncMessage)
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    @MainActor
    func testActivateParentSharingMarksInviteReadyOnlyAfterServerSave() async {
        let childShareLinkStore = ChildShareLinkStore(defaults: defaults)
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            childShareLinkStore: childShareLinkStore,
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            serverParentLinkService: ServerParentLinkService(
                registerParentLinkHandler: { childLink in
                    var registered = childLink
                    registered.registeredAt = Date()
                    return registered
                }
            ),
            automaticallyPublishesParentSharedData: false
        )
        appState.saveProfile(
            nickname: "지우",
            school: School(name: "냠냠초등학교", officeCode: "B10", schoolCode: "7010111", region: "서울", address: "서울", schoolType: "초등학교"),
            allergyCodes: []
        )

        await appState.activateParentSharing(permissions: .defaultChildSafe)

        XCTAssertTrue(appState.childShareLink?.isCloudRegistered == true)
        XCTAssertNil(appState.childShareLink?.registrationErrorMessage)
        XCTAssertTrue(childShareLinkStore.load()?.isCloudRegistered == true)
        XCTAssertEqual(appState.childShareLink?.officeCode, "B10")
        XCTAssertEqual(appState.childShareLink?.schoolCode, "7010111")
        XCTAssertNotNil(appState.childShareLink?.inviteSecret)
        XCTAssertEqual(appState.parentSyncMessage, "초대 코드가 서버에 등록됐어요. 부모에게 보내면 바로 연결할 수 있어요.")
        XCTAssertNil(appState.parentSyncError)
    }

    @MainActor
    func testActivateParentSharingKeepsFailedInviteUnshareable() async {
        let childShareLinkStore = ChildShareLinkStore(defaults: defaults)
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            childShareLinkStore: childShareLinkStore,
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            serverParentLinkService: ServerParentLinkService(
                registerParentLinkHandler: { _ in
                    throw ParentSyncServiceError.invalidResponse
                }
            ),
            automaticallyPublishesParentSharedData: false
        )
        appState.saveProfile(
            nickname: "지우",
            school: School(name: "냠냠초등학교", officeCode: "B10", schoolCode: "7010111", region: "서울", address: "서울", schoolType: "초등학교"),
            allergyCodes: []
        )

        await appState.activateParentSharing(permissions: .defaultChildSafe)

        XCTAssertFalse(appState.childShareLink?.isCloudRegistered == true)
        XCTAssertNotNil(appState.childShareLink?.registrationErrorMessage)
        XCTAssertFalse(childShareLinkStore.load()?.isCloudRegistered == true)
        XCTAssertEqual(appState.parentSyncError, appState.parentSyncMessage)
    }

    func testParentInviteShareMessageCanBePastedAsInviteCode() {
        let service = CloudKitParentLinkService()
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "냠냠초등학교",
            mode: .elementary,
            inviteCode: "NYAM-8K3P-7M2A-C9YD",
            registeredAt: Date()
        )

        XCTAssertEqual(service.normalizeInviteCode(child.parentInviteShareMessage), child.inviteCode)
        XCTAssertFalse(child.parentInviteShareMessage.contains(child.schoolName))
        XCTAssertFalse(child.parentInviteShareMessage.contains("사진"))
    }

    @MainActor
    func testRegisterParentPushDeviceTokenRegistersAllConnectedChildren() async {
        let firstChild = ChildLink(
            childNickname: "첫째",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-8K3P-7M2A-C9YD"
        )
        let secondChild = ChildLink(
            childNickname: "둘째",
            schoolName: "냠냠중학교",
            mode: .middle,
            inviteCode: "NYAM-9K3P-7M2A-C9YD"
        )
        var registered: [(UUID, String, String)] = []
        let tokenStore = ParentPushDeviceTokenStore(defaults: defaults)
        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            parentPushDeviceTokenStore: tokenStore,
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            serverParentLinkService: ServerParentLinkService(
                registerParentDeviceHandler: { child, token, environment in
                    registered.append((child.id, token, environment))
                }
            ),
            automaticallyPublishesParentSharedData: false
        )
        appState.parentProfile = ParentProfile(childLinks: [firstChild, secondChild])
        let deviceToken = String(repeating: "a", count: 64)

        await appState.registerParentPushDeviceToken(deviceToken)

        XCTAssertEqual(tokenStore.load(), deviceToken)
        XCTAssertEqual(registered.map(\.0), [firstChild.id, secondChild.id])
        XCTAssertEqual(Set(registered.map(\.1)), [deviceToken])
        XCTAssertEqual(Set(registered.map(\.2)), [ParentPushNotificationBridge.apnsEnvironment])
        XCTAssertEqual(appState.parentNotificationMessage, "아이 급식 결과 알림을 받을 준비가 됐어요.")
        XCTAssertNil(appState.parentNotificationError)
    }

    @MainActor
    func testChildSummariesOnlyExposeParentSharedRecords() {
        let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-8K3P-7M2A-C9YD"
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
            sampleProvider: SampleDataProvider()
        )
        appState.parentProfile = ParentProfile(childLinks: [child])
        appState.mealRecords = [
            MealRecord(
                date: "20260618",
                menuName: "비공유나물",
                eatingStatus: .difficultToday,
                allergyCodes: [1],
                parentShareEnabled: false,
                childLinkId: child.id
            ),
            MealRecord(
                date: "20260618",
                menuName: "공유나물",
                eatingStatus: .oneBite,
                allergyCodes: [1],
                parentShareEnabled: true,
                childLinkId: child.id
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
                childLinkId: child.id
            ),
            ChallengeRecord(
                date: "20260618",
                menuName: "공유나물",
                action: .oneBite,
                gainedExp: 18,
                badgeName: "초록 용사",
                nutrients: ["식이섬유"],
                childLinkId: child.id,
                parentShareEnabled: true
            )
        ]

        let summary = appState.childSummaries[0]

        XCTAssertEqual(summary.weeklyRecords.map(\.menuName), ["공유나물"])
        XCTAssertEqual(summary.weeklyChallengeRecords.map(\.menuName), ["공유나물"])
        XCTAssertEqual(summary.allergyWarningMenus, ["공유나물"])
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    @MainActor
    func testChildSummariesRequireConnectedChildLink() {
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
        appState.mealRecords = [
            MealRecord(date: "20260618", menuName: "공유나물", eatingStatus: .oneBite, parentShareEnabled: true)
        ]

        XCTAssertTrue(appState.childSummaries.isEmpty)
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
        XCTAssertEqual(appState.records.first?.parentShareEnabled, true)
    }

    @MainActor
    func testMealPhotoSharingRemainsLocalOnly() throws {
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
        let privatePhoto = try XCTUnwrap(appState.updateMealPhotoSharing(sharedPhoto, sharedWithParent: true))

        XCTAssertFalse(sharedPhoto.isSharedWithParent)
        XCTAssertNil(sharedPhoto.childLinkId)
        XCTAssertFalse(privatePhoto.isSharedWithParent)
        XCTAssertNil(privatePhoto.childLinkId)
        XCTAssertEqual(appState.mealPhotos.first?.isSharedWithParent, false)
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    @MainActor
    func testResetChallengeRecordsKeepsProfileParentLinkAndPhotos() throws {
        let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let photoStore = LocalPhotoStore(directoryURL: photoDirectory)
        let childShareLinkStore = ChildShareLinkStore(defaults: defaults)
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
            childShareLinkStore: childShareLinkStore,
            localPhotoStore: photoStore,
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            automaticallyPublishesParentSharedData: false
        )
        appState.saveProfile(nickname: "지우", school: releaseTestSchool, allergyCodes: [1])
        appState.addChildLink(inviteCode: "NYAM-DDDD-EEEE-FFFF", nickname: "민준", schoolName: "냠냠중학교", mode: .middle)
        appState.childShareLink = child
        childShareLinkStore.save(child)

        let photo = try appState.saveMealPhotoData(Data([0x01, 0x02, 0x03]), sharedWithParent: true)
        let photoURL = photoStore.url(for: photo)
        _ = appState.recordMealInteraction(
            item: MealItem(name: "시금치나물", allergyCodes: [], nutrients: ["식이섬유"], tags: ["채소"], sourceRawText: "시금치나물"),
            date: "20260624",
            status: .oneBite,
            photoIds: [photo.id],
            shareWithParent: true
        )
        XCTAssertFalse(appState.records.isEmpty)
        XCTAssertFalse(appState.mealRecords.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))

        appState.resetChallengeRecords()

        XCTAssertNotNil(appState.profile)
        XCTAssertEqual(appState.childShareLink?.inviteCode, child.inviteCode)
        XCTAssertEqual(appState.parentProfile.childLinks.count, 1)
        XCTAssertEqual(appState.mealPhotos.map(\.id), [photo.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertTrue(appState.records.isEmpty)
        XCTAssertTrue(appState.mealRecords.isEmpty)
        XCTAssertTrue(ChallengeStore(defaults: defaults).load().isEmpty)
        XCTAssertTrue(MealRecordStore(defaults: defaults).load().isEmpty)
        XCTAssertEqual(MealPhotoMetadataStore(defaults: defaults).load().map(\.id), [photo.id])
        XCTAssertEqual(ParentProfileStore(defaults: defaults).load().childLinks.count, 1)
        XCTAssertEqual(ChildShareLinkStore(defaults: defaults).load()?.inviteCode, child.inviteCode)
        try? FileManager.default.removeItem(at: photoDirectory)
    }

    @MainActor
    func testResetAllDataClearsProfileRecordsProgressParentLinksAndPhotoFiles() throws {
        let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let photoStore = LocalPhotoStore(directoryURL: photoDirectory)
        let childShareLinkStore = ChildShareLinkStore(defaults: defaults)
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
            childShareLinkStore: childShareLinkStore,
            localPhotoStore: photoStore,
            mealService: MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE")),
            sampleProvider: SampleDataProvider(),
            automaticallyPublishesParentSharedData: false
        )
        appState.saveProfile(nickname: "지우", school: releaseTestSchool, allergyCodes: [1])
        appState.addChildLink(inviteCode: "NYAM-DDDD-EEEE-FFFF", nickname: "민준", schoolName: "냠냠중학교", mode: .middle)
        appState.childShareLink = child
        childShareLinkStore.save(child)
        appState.parentSyncMessage = "동기화 완료"

        let photo = try appState.saveMealPhotoData(Data([0x0A, 0x0B, 0x0C]), sharedWithParent: true)
        let photoURL = photoStore.url(for: photo)
        let orphanPhotoURL = photoURL.deletingLastPathComponent().appendingPathComponent("orphan-photo.jpg")
        try Data([0x0D, 0x0E, 0x0F]).write(to: orphanPhotoURL)
        _ = appState.recordMealInteraction(
            item: MealItem(name: "콩나물무침", allergyCodes: [], nutrients: ["식이섬유"], tags: ["채소"], sourceRawText: "콩나물무침"),
            date: "20260624",
            status: .oneBite,
            photoIds: [photo.id],
            shareWithParent: true
        )
        XCTAssertGreaterThan(appState.progress.exp, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanPhotoURL.path))

        appState.resetAllData()

        XCTAssertNil(appState.profile)
        XCTAssertTrue(appState.records.isEmpty)
        XCTAssertTrue(appState.mealRecords.isEmpty)
        XCTAssertTrue(appState.mealPhotos.isEmpty)
        XCTAssertEqual(appState.progress.exp, 0)
        XCTAssertEqual(appState.progress.level, 1)
        XCTAssertTrue(appState.parentProfile.childLinks.isEmpty)
        XCTAssertNil(appState.childShareLink)
        XCTAssertNil(appState.parentSyncMessage)
        XCTAssertNil(appState.todayMeal)
        XCTAssertTrue(appState.monthlyMeals.isEmpty)
        XCTAssertEqual(appState.mealStatus, .noMeal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanPhotoURL.path))
        XCTAssertNil(UserProfileStore(defaults: defaults).load())
        XCTAssertTrue(ChallengeStore(defaults: defaults).load().isEmpty)
        XCTAssertTrue(MealRecordStore(defaults: defaults).load().isEmpty)
        XCTAssertEqual(ProgressStore(defaults: defaults).load().exp, 0)
        XCTAssertTrue(MealPhotoMetadataStore(defaults: defaults).load().isEmpty)
        XCTAssertTrue(ParentProfileStore(defaults: defaults).load().childLinks.isEmpty)
        XCTAssertNil(ChildShareLinkStore(defaults: defaults).load())
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
            service.normalizeInviteCode("nyam abcd efgh jklm"),
            "NYAM-ABCD-EFGH-JKLM"
        )
        XCTAssertEqual(
            service.normalizeInviteCode("nyamabcdefghjklm"),
            "NYAM-ABCD-EFGH-JKLM"
        )
    }

    func testCloudKitInviteCodeValidationRequiresExactShape() {
        let service = CloudKitParentLinkService()

        XCTAssertTrue(service.isValidInviteCode("nyam abcd efgh jklm"))
        XCTAssertTrue(service.isValidInviteCode("NYAM-ABCD-EFGH-JKLM"))
        XCTAssertFalse(service.isValidInviteCode(""))
        XCTAssertFalse(service.isValidInviteCode("ABCD-EFGH-IJKL"))
        XCTAssertFalse(service.isValidInviteCode("NYAM-ABCD-EFGH-IJ"))
        XCTAssertFalse(service.isValidInviteCode("NYAM-ABCD-EFGH-IJKL-EXTRA"))
    }

    func testCloudKitInviteCodeRejectsAmbiguousCharacters() {
        let service = CloudKitParentLinkService()

        XCTAssertFalse(service.isValidInviteCode("NYAM-ABCD-EFGH-JK1M"))
        XCTAssertFalse(service.isValidInviteCode("NYAM-ABCD-EFGH-JK0M"))
        XCTAssertFalse(service.isValidInviteCode("NYAM-ABCD-EFGH-JKIM"))
        XCTAssertFalse(service.isValidInviteCode("NYAM-ABCD-EFGH-JKOM"))
        XCTAssertTrue(service.hasAmbiguousInviteCharacters("NYAM-ABCD-EFGH-JK1M"))
        XCTAssertEqual(
            service.inviteCodeValidationMessage("NYAM-ABCD-EFGH-JK1M"),
            "헷갈리는 문자 O, 0, I, 1은 초대 코드에 사용하지 않아요. 아이 기기에서 코드를 다시 확인해 주세요."
        )
    }

    @MainActor
    func testParentConnectionDiagnosticsCountsSharedRecords() {
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-8K3P-7M2A-C9YD"
        )
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
        appState.childShareLink = child
        appState.parentProfile = ParentProfile(childLinks: [child])
        appState.mealRecords = [
            MealRecord(date: "20260618", menuName: "공유나물", eatingStatus: .oneBite, parentShareEnabled: true, childLinkId: child.id),
            MealRecord(date: "20260618", menuName: "비공유나물", eatingStatus: .difficultToday, parentShareEnabled: false, childLinkId: child.id)
        ]
        appState.records = [
            ChallengeRecord(date: "20260618", menuName: "공유나물", action: .oneBite, gainedExp: 18, badgeName: nil, nutrients: [], childLinkId: child.id, parentShareEnabled: true)
        ]

        let diagnostics = appState.parentConnectionDiagnostics

        XCTAssertTrue(diagnostics.hasChildShareLink)
        XCTAssertEqual(diagnostics.inviteCode, "NYAM-8K3P-7M2A-C9YD")
        XCTAssertEqual(diagnostics.parentChildLinkCount, 1)
        XCTAssertEqual(diagnostics.sharedRecordCount, 2)
        XCTAssertEqual(diagnostics.permissions.sharePhotos, false)
    }

    func testCloudKitSetupOnlyRequiresQueryableIndexes() {
        let service = CloudKitParentLinkService()
        let checklist = service.setupChecklist.joined(separator: "\n")

        XCTAssertTrue(checklist.contains("ParentLink.inviteCode"))
        XCTAssertTrue(checklist.contains("SharedMealRecord.childLinkId"))
        XCTAssertTrue(checklist.contains("SharedChallengeRecord.childLinkId"))
        XCTAssertTrue(checklist.contains("queryable index"))
        XCTAssertTrue(checklist.contains("sortable index는 필요 없음"))
    }

    func testCloudKitRecordTypesMatchConsoleRunbook() {
        let service = CloudKitParentLinkService()

        XCTAssertEqual(
            service.recordTypes,
            [
                "ParentLink",
                "SharedMealRecord",
                "SharedChallengeRecord"
            ]
        )
    }

    func testCloudKitParentLinkRecordFieldsMatchConsoleRunbook() {
        let service = CloudKitParentLinkService()
        let childId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let createdAt = Date(timeIntervalSince1970: 1_771_718_400)
        let child = ChildLink(
            id: childId,
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-JKLM",
            permissions: SharingPermission(
                shareEatingRecords: true,
                shareChallengeRecords: true,
                shareAllergyWarnings: false,
                sharePhotos: true
            ),
            createdAt: createdAt
        )

        let record = service.makeParentLinkRecord(childLink: child)

        XCTAssertEqual(record.recordType, CloudKitParentLinkService.parentLinkRecordType)
        assertRecordKeys(
            record,
            [
                "childLinkId",
                "childNickname",
                "schoolName",
                "mode",
                "inviteCode",
                "shareEatingRecords",
                "shareChallengeRecords",
                "shareAllergyWarnings",
                "sharePhotos",
                "createdAt"
            ]
        )
        XCTAssertEqual(record["childLinkId"] as? String, childId.uuidString)
        XCTAssertEqual(record["childNickname"] as? String, "지우")
        XCTAssertEqual(record["schoolName"] as? String, "등촌고등학교")
        XCTAssertEqual(record["mode"] as? String, UserMode.high.rawValue)
        XCTAssertEqual(record["inviteCode"] as? String, "NYAM-ABCD-EFGH-JKLM")
        XCTAssertEqual(boolRecordValue(record["shareEatingRecords"]), true)
        XCTAssertEqual(boolRecordValue(record["shareChallengeRecords"]), true)
        XCTAssertEqual(boolRecordValue(record["shareAllergyWarnings"]), false)
        XCTAssertEqual(boolRecordValue(record["sharePhotos"]), false)
        XCTAssertEqual(record["createdAt"] as? Date, createdAt)
    }

    func testCloudKitSharedMealRecordRequiresParentShare() {
        let service = CloudKitParentLinkService()
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-JKLM"
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

    func testCloudKitSharedMealRecordFieldsMatchConsoleRunbook() throws {
        let service = CloudKitParentLinkService()
        let childId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let mealId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let createdAt = Date(timeIntervalSince1970: 1_771_718_500)
        let child = ChildLink(
            id: childId,
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-JKLM",
            permissions: SharingPermission(
                shareEatingRecords: true,
                shareChallengeRecords: true,
                shareAllergyWarnings: true,
                sharePhotos: true
            )
        )
        let meal = MealRecord(
            id: mealId,
            date: "20260624",
            menuName: "콩나물무침",
            eatingStatus: .oneBite,
            difficultyReasons: [.smell, .texture],
            allergyCodes: [1, 2],
            photoIds: ["photo-1", "photo-2"],
            parentShareEnabled: true,
            createdAt: createdAt
        )

        let record = try XCTUnwrap(service.makeSharedMealRecord(meal, childLink: child))

        XCTAssertEqual(record.recordType, CloudKitParentLinkService.sharedMealRecordType)
        assertRecordKeys(
            record,
            [
                "mealRecordId",
                "childLinkId",
                "date",
                "menuName",
                "eatingStatus",
                "difficultyReasons",
                "allergyCodes",
                "photoIds",
                "createdAt"
            ]
        )
        XCTAssertEqual(record["mealRecordId"] as? String, mealId.uuidString)
        XCTAssertEqual(record["childLinkId"] as? String, childId.uuidString)
        XCTAssertEqual(record["date"] as? String, "20260624")
        XCTAssertEqual(record["menuName"] as? String, "콩나물무침")
        XCTAssertEqual(record["eatingStatus"] as? String, EatingStatus.oneBite.rawValue)
        XCTAssertEqual(record["difficultyReasons"] as? String, "smell,texture")
        XCTAssertEqual(record["allergyCodes"] as? String, "1,2")
        XCTAssertEqual(record["photoIds"] as? String, "")
        XCTAssertEqual(record["createdAt"] as? Date, createdAt)
    }

    func testCloudKitSharedChallengeRecordRequiresParentShare() {
        let service = CloudKitParentLinkService()
        let child = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-JKLM"
        )
        let hidden = ChallengeRecord(
            date: "20260618",
            menuName: "시금치나물",
            action: .oneBite,
            gainedExp: 18,
            badgeName: "초록 용사",
            nutrients: ["식이섬유"],
            childLinkId: nil
        )
        let shared = ChallengeRecord(
            date: "20260618",
            menuName: "콩나물무침",
            action: .oneBite,
            gainedExp: 18,
            badgeName: "초록 용사",
            nutrients: ["식이섬유"],
            childLinkId: nil,
            parentShareEnabled: true
        )

        XCTAssertNil(service.makeSharedChallengeRecord(hidden, childLink: child))
        let record = service.makeSharedChallengeRecord(shared, childLink: child)

        XCTAssertEqual(record?.recordType, CloudKitParentLinkService.sharedChallengeRecordType)
        XCTAssertEqual(record?["childLinkId"] as? String, child.id.uuidString)
        XCTAssertEqual(record?["menuName"] as? String, "콩나물무침")
    }

    func testCloudKitSharedChallengeRecordFieldsMatchConsoleRunbook() throws {
        let service = CloudKitParentLinkService()
        let childId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let challengeId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let createdAt = Date(timeIntervalSince1970: 1_771_718_600)
        let child = ChildLink(
            id: childId,
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-JKLM",
            permissions: SharingPermission(
                shareEatingRecords: true,
                shareChallengeRecords: true,
                shareAllergyWarnings: true,
                sharePhotos: true
            )
        )
        let challenge = ChallengeRecord(
            id: challengeId,
            date: "20260624",
            menuName: "콩나물무침",
            action: .oneBite,
            gainedExp: 43,
            badgeName: "초록 용사",
            nutrients: ["식이섬유", "비타민"],
            createdAt: createdAt,
            eatingStatus: .oneBite,
            difficultyReasons: [.texture],
            photoIds: ["photo-1"],
            parentShareEnabled: true
        )

        let record = try XCTUnwrap(service.makeSharedChallengeRecord(challenge, childLink: child))

        XCTAssertEqual(record.recordType, CloudKitParentLinkService.sharedChallengeRecordType)
        assertRecordKeys(
            record,
            [
                "challengeRecordId",
                "childLinkId",
                "date",
                "menuName",
                "action",
                "gainedExp",
                "badgeName",
                "nutrients",
                "createdAt"
            ]
        )
        XCTAssertEqual(record["challengeRecordId"] as? String, challengeId.uuidString)
        XCTAssertEqual(record["childLinkId"] as? String, childId.uuidString)
        XCTAssertEqual(record["date"] as? String, "20260624")
        XCTAssertEqual(record["menuName"] as? String, "콩나물무침")
        XCTAssertEqual(record["action"] as? String, ChallengeRecord.Action.oneBite.rawValue)
        XCTAssertEqual(intRecordValue(record["gainedExp"]), 43)
        XCTAssertEqual(record["badgeName"] as? String, "초록 용사")
        XCTAssertEqual(record["nutrients"] as? String, "식이섬유,비타민")
        XCTAssertEqual(record["createdAt"] as? Date, createdAt)
    }

    func testCloudKitSharedMealRecordRespectsSharingPermissions() {
        let service = CloudKitParentLinkService()
        let blockedChild = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-JKLM",
            permissions: SharingPermission(shareEatingRecords: false, shareChallengeRecords: true, shareAllergyWarnings: true, sharePhotos: true)
        )
        let allergyHiddenChild = ChildLink(
            childNickname: "지우",
            schoolName: "등촌고등학교",
            mode: .high,
            inviteCode: "NYAM-ABCD-EFGH-JKLM",
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

    func testCloudKitPhotoRecordIsDisabled() {
        let service = CloudKitParentLinkService()

        XCTAssertFalse(service.recordTypes.contains("SharedMealPhoto"))
    }

    func testCloudKitSharedPhotoRecordNeverBuildsAsset() {
        let service = CloudKitParentLinkService()

        XCTAssertFalse(service.setupChecklist.joined(separator: " ").contains("photoAsset"))
    }

    func testPrivacyManifestMatchesAppPrivacyDraftCategories() throws {
        let manifest = try loadPrivacyManifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(try XCTUnwrap(manifest["NSPrivacyTrackingDomains"] as? [String]), [])

        let accessedAPITypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaultsAPI = try XCTUnwrap(accessedAPITypes.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(
            Set(try XCTUnwrap(userDefaultsAPI["NSPrivacyAccessedAPITypeReasons"] as? [String])),
            ["CA92.1"]
        )

        let collectedDataTypes = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(
            Set(collectedDataTypes.compactMap { $0["NSPrivacyCollectedDataType"] as? String }),
            [
                "NSPrivacyCollectedDataTypeOtherUserContent",
                "NSPrivacyCollectedDataTypeHealth",
                "NSPrivacyCollectedDataTypeUserID"
            ]
        )

        for dataType in collectedDataTypes {
            XCTAssertEqual(dataType["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(dataType["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
            XCTAssertEqual(
                Set(try XCTUnwrap(dataType["NSPrivacyCollectedDataTypePurposes"] as? [String])),
                ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
            )
        }
    }

    func testIntroRequiredAssetsAreBundledForRelease() throws {
        for asset in requiredIntroAssets {
            let image = UIImage(named: asset.name)
            XCTAssertNotNil(image, "\(asset.name) must be bundled so the release intro never shows an asset placeholder")
            if let image {
                XCTAssertGreaterThanOrEqual(image.size.width * image.scale, asset.minimumPixelWidth, "\(asset.name) width is below release minimum")
                XCTAssertGreaterThanOrEqual(image.size.height * image.scale, asset.minimumPixelHeight, "\(asset.name) height is below release minimum")
            }
        }
    }

    func testIntroRequiredAssetsExistInSourceCatalog() throws {
        let catalogURL = sourceRootURL()
            .appendingPathComponent("NaymNaymLevelUp")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Assets.xcassets")

        for asset in requiredIntroAssets {
            let imageSetURL = catalogURL.appendingPathComponent("\(asset.name).imageset")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: imageSetURL.path),
                "\(asset.name).imageset must stay in the asset catalog"
            )
            let contentsURL = imageSetURL.appendingPathComponent("Contents.json")
            let contentsData = try Data(contentsOf: contentsURL)
            let contents = try XCTUnwrap(
                JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
            )
            let images = try XCTUnwrap(contents["images"] as? [[String: Any]])
            let filename = try XCTUnwrap(images.compactMap { $0["filename"] as? String }.first)
            let imageURL = imageSetURL.appendingPathComponent(filename)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: imageURL.path),
                "\(asset.name) Contents.json must reference an existing image file"
            )
        }
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
                childLinkId: firstChildId,
                parentShareEnabled: true
            ),
            ChallengeRecord(
                date: "20260618",
                menuName: "둘째나물",
                action: .skipped,
                gainedExp: 3,
                badgeName: nil,
                nutrients: ["식이섬유"],
                childLinkId: secondChildId,
                parentShareEnabled: true
            )
        ]

        let summaries = appState.childSummaries

        XCTAssertEqual(summaries.first?.weeklyRecords.map(\.menuName), ["첫째나물"])
        XCTAssertEqual(summaries.last?.weeklyRecords.map(\.menuName), ["둘째나물"])
        XCTAssertEqual(summaries.first?.weeklyChallengeRecords.map(\.menuName), ["첫째나물"])
        XCTAssertEqual(summaries.last?.weeklyChallengeRecords.map(\.menuName), ["둘째나물"])
    }

    private struct RequiredIntroAsset {
        var name: String
        var minimumPixelWidth: CGFloat
        var minimumPixelHeight: CGFloat
    }

    private var requiredIntroAssets: [RequiredIntroAsset] {
        [
            RequiredIntroAsset(name: "logo_naym_levelup", minimumPixelWidth: 320, minimumPixelHeight: 72),
            RequiredIntroAsset(name: "mascot_onboarding", minimumPixelWidth: 240, minimumPixelHeight: 240),
            RequiredIntroAsset(name: "mascot_wave_1", minimumPixelWidth: 240, minimumPixelHeight: 240),
            RequiredIntroAsset(name: "mascot_wave_2", minimumPixelWidth: 240, minimumPixelHeight: 240),
            RequiredIntroAsset(name: "mascot_jump", minimumPixelWidth: 240, minimumPixelHeight: 240),
            RequiredIntroAsset(name: "bg_soft_mint", minimumPixelWidth: 40, minimumPixelHeight: 80),
            RequiredIntroAsset(name: "icon_one_bite", minimumPixelWidth: 256, minimumPixelHeight: 256),
            RequiredIntroAsset(name: "icon_growth_report", minimumPixelWidth: 256, minimumPixelHeight: 256),
            RequiredIntroAsset(name: "icon_reward", minimumPixelWidth: 256, minimumPixelHeight: 256)
        ]
    }

    private var releaseTestSchool: School {
        School(
            name: "등촌고등학교",
            officeCode: "B10",
            schoolCode: "7010700",
            region: "서울",
            address: "서울특별시 강서구",
            schoolType: "고등학교"
        )
    }

    private func assertRecordKeys(
        _ record: CKRecord,
        _ expectedKeys: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(record.allKeys()), expectedKeys, file: file, line: line)
    }

    private func boolRecordValue(_ value: CKRecordValue?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        return (value as? NSNumber)?.boolValue
    }

    private func intRecordValue(_ value: CKRecordValue?) -> Int? {
        if let int = value as? Int {
            return int
        }
        return (value as? NSNumber)?.intValue
    }

    private func loadPrivacyManifest() throws -> [String: Any] {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NaymNaymLevelUp")
            .appendingPathComponent("PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: sourceURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: Any])
    }

    private func sourceRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
