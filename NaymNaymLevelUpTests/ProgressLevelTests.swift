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
}

