import XCTest
@testable import NaymNaymLevelUp

final class ProgressLevelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var photoDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "ProgressLevelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        if let defaults, let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let photoDirectory {
            try? FileManager.default.removeItem(at: photoDirectory)
        }
        defaults = nil
        suiteName = nil
        photoDirectory = nil
        super.tearDown()
    }

    func testLevelThresholdsResolveExpectedLevels() {
        XCTAssertEqual(PlayerProgress.level(forExp: 0), 1)
        XCTAssertEqual(PlayerProgress.level(forExp: 80), 2)
        XCTAssertEqual(PlayerProgress.level(forExp: 320), 4)
        XCTAssertEqual(PlayerProgress.level(forExp: 1000), 7)
    }

    func testChallengeAddsExpBadgeAndSkin() {
        var progress = PlayerProgress()
        let item = MealItem(name: "닭갈비", allergyCodes: [15], nutrients: ["단백질"], tags: ["튼튼 파워"], sourceRawText: "닭갈비(15)")
        let outcome = progress.applyChallenge(for: item)

        XCTAssertGreaterThan(outcome.gainedExp, 0)
        XCTAssertEqual(progress.challengeExp, 18)
        XCTAssertTrue(progress.badges.contains("단백질 파워"))
        XCTAssertEqual(progress.currentSkinId, CharacterSkin.skin(for: progress.level).id)
    }

    func testEatingStatusBaseXPBreakdowns() {
        XCTAssertEqual(LevelUpXPPolicy.baseBreakdown(for: .finished).record, 10)
        XCTAssertEqual(LevelUpXPPolicy.baseBreakdown(for: .half).record, 12)
        XCTAssertEqual(LevelUpXPPolicy.baseBreakdown(for: .oneBite).challenge, 18)
        XCTAssertEqual(LevelUpXPPolicy.baseBreakdown(for: .smelledOnly).challenge, 10)
        XCTAssertEqual(LevelUpXPPolicy.baseBreakdown(for: .difficultToday).record, 3)
        XCTAssertEqual(LevelUpXPPolicy.baseBreakdown(for: .allergyAvoided).safety, 8)
    }

    func testRetryingPreviouslyDifficultFoodAddsChallengeBonus() {
        let item = MealItem(name: "시금치나물", allergyCodes: [], nutrients: ["식이섬유", "비타민"], tags: [], sourceRawText: "시금치나물")
        let previous = ChallengeRecord(
            date: "20260619",
            menuName: "시금치나물",
            action: .skipped,
            gainedExp: 3,
            badgeName: nil,
            nutrients: item.nutrients,
            createdAt: Date(timeIntervalSince1970: 1),
            eatingStatus: .difficultToday
        )

        let grant = LevelUpXPPolicy.grant(
            for: item,
            status: .oneBite,
            date: "20260620",
            existingRecords: [previous],
            existingMealRecords: [],
            isAllergyRisk: false
        )

        XCTAssertEqual(grant.base.challenge, 18)
        XCTAssertEqual(grant.bonus.challenge, 25)
        XCTAssertTrue(grant.notes.contains { $0.contains("한 입 도전 +25") })
    }

    func testDailyCapsLimitBaseBonusAndTotalXP() {
        let grant = LevelUpXPPolicy.applyDailyCaps(
            XPGrant(base: XPBreakdown(record: 80), bonus: XPBreakdown(challenge: 90)),
            existingRecords: [],
            date: "20260620"
        )

        XCTAssertEqual(grant.base.total, 50)
        XCTAssertEqual(grant.bonus.total, 50)
        XCTAssertEqual(grant.total, 100)

        let bonusOnly = LevelUpXPPolicy.applyDailyCaps(
            XPGrant(base: XPBreakdown(record: 20), bonus: XPBreakdown(challenge: 90)),
            existingRecords: [],
            date: "20260621"
        )

        XCTAssertEqual(bonusOnly.base.total, 20)
        XCTAssertEqual(bonusOnly.bonus.total, 70)
        XCTAssertEqual(bonusOnly.total, 90)
    }

    @MainActor
    func testAllergyRiskConvertsOneBiteToSafetyXP() {
        let appState = makeAppState()
        appState.saveProfile(
            nickname: "냠냠이",
            school: School(name: "테스트초", officeCode: "B10", schoolCode: "123", region: "서울", address: "", schoolType: "초등학교"),
            allergyCodes: [1]
        )
        let item = MealItem(name: "우유", allergyCodes: [1], nutrients: ["칼슘"], tags: [], sourceRawText: "우유(1)")

        let outcome = appState.recordMealInteraction(item: item, date: "20260620", status: .oneBite)

        XCTAssertEqual(outcome?.gainedExp, 8)
        XCTAssertEqual(appState.progress.safetyExp, 8)
        XCTAssertEqual(appState.progress.challengeExp, 0)
        XCTAssertEqual(appState.records.first?.eatingStatus, .allergyAvoided)
        XCTAssertEqual(appState.records.first?.action, .skipped)
    }

    func testModeSpecificCharacterSkinsResolve() {
        XCTAssertEqual(CharacterSkin.skin(for: 3, mode: .middle).targetMode, .middle)
        XCTAssertEqual(CharacterSkin.skin(for: 4, mode: .high).name, "엑스퍼트")
        XCTAssertEqual(CharacterSkin.skin(for: 1, mode: .elementary).name, "냠냠 새싹")
    }

    func testEatingStatusAndMealDataStatePolicies() {
        XCTAssertEqual(EatingStatus.allergyAvoided.title, "알레르기/주의로 먹지 않았어요")
        XCTAssertTrue(MealDataState.demo.usesSample)
        XCTAssertFalse(MealDataState.error.usesSample)
        XCTAssertFalse(MealDataState.missingAPIKey.usesSample)
    }

    @MainActor
    private func makeAppState() -> AppState {
        AppState(
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
    }
}
