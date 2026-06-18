import XCTest
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
}

