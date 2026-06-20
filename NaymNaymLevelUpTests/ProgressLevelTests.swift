import XCTest
@testable import NaymNaymLevelUp

final class ProgressLevelTests: XCTestCase {
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
        XCTAssertTrue(progress.badges.contains("단백질 파워"))
        XCTAssertEqual(progress.currentSkinId, CharacterSkin.skin(for: progress.level).id)
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
}
