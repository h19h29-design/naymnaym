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

    func testGrowthCharacterAssetsClampLevelsAndResolveEveryStage() {
        let expectedTitles = [
            "새싹",
            "꼬마 모험가",
            "한입 탐험가",
            "숲길 도전자",
            "냠냠 용사",
            "숲의 수호자",
            "레전드 냠냠러"
        ]

        for level in 1...7 {
            XCTAssertEqual(GrowthCharacterAssets.atlasCell(for: level), level - 1)
            XCTAssertEqual(GrowthCharacterAssets.stageTitle(for: level), expectedTitles[level - 1])
            XCTAssertEqual(GrowthCharacterAssets.imageName(for: level), "Squirrel_Growth_Level_\(level)")
        }

        XCTAssertEqual(GrowthCharacterAssets.atlasCell(for: 0), 0)
        XCTAssertEqual(GrowthCharacterAssets.stageTitle(for: 0), expectedTitles[0])
        XCTAssertEqual(GrowthCharacterAssets.imageName(for: 0), "Squirrel_Growth_Level_1")
        XCTAssertEqual(GrowthCharacterAssets.atlasCell(for: 99), 6)
        XCTAssertEqual(GrowthCharacterAssets.stageTitle(for: 99), expectedTitles[6])
        XCTAssertEqual(GrowthCharacterAssets.imageName(for: 99), "Squirrel_Growth_Level_7")
    }

    func testGrowthProgressPresentationResolvesNextStageAndRemainingXP() {
        let levelOne = GrowthProgressPresentation(progress: PlayerProgress(recordExp: 30))
        XCTAssertEqual(levelOne.currentLevel, 1)
        XCTAssertEqual(levelOne.nextLevel, 2)
        XCTAssertEqual(levelOne.remainingXP, 50)
        XCTAssertFalse(levelOne.isStageUnlocked(2))

        let maxLevel = GrowthProgressPresentation(progress: PlayerProgress(recordExp: 1_000))
        XCTAssertEqual(maxLevel.currentLevel, 7)
        XCTAssertNil(maxLevel.nextLevel)
        XCTAssertEqual(maxLevel.remainingXP, 0)
    }

    func testGrowthProgressPresentationCalculatesFractionWithinCurrentThreshold() {
        XCTAssertEqual(
            GrowthProgressPresentation(progress: PlayerProgress(recordExp: 30)).progressFraction,
            0.375,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            GrowthProgressPresentation(progress: PlayerProgress(recordExp: 130)).progressFraction,
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            GrowthProgressPresentation(progress: PlayerProgress(recordExp: 1_000)).progressFraction,
            1,
            accuracy: 0.000_001
        )
    }

    func testGrowthProgressPresentationResetsAtEveryExactThreshold() {
        for (index, threshold) in PlayerProgress.levelThresholds.enumerated() {
            let presentation = GrowthProgressPresentation(progress: PlayerProgress(recordExp: threshold))
            let expectedLevel = index + 1

            XCTAssertEqual(presentation.currentLevel, expectedLevel, "threshold: \(threshold)")
            XCTAssertEqual(
                presentation.progressFraction,
                expectedLevel == PlayerProgress.levelThresholds.count ? 1 : 0,
                accuracy: 0.000_001,
                "threshold: \(threshold)"
            )
            XCTAssertEqual(
                presentation.nextLevel,
                expectedLevel == PlayerProgress.levelThresholds.count ? nil : expectedLevel + 1,
                "threshold: \(threshold)"
            )
            let expectedRemaining = expectedLevel == PlayerProgress.levelThresholds.count
                ? 0
                : PlayerProgress.levelThresholds[index + 1] - threshold
            XCTAssertEqual(presentation.remainingXP, expectedRemaining, "threshold: \(threshold)")
        }
    }

    func testGrowthLevelMarkUsesStableNonDynamicTypeMetrics() {
        let mark = GrowthLevelMarkPresentation(level: 1)

        XCTAssertEqual(mark.glyph, "L1")
        XCTAssertEqual(mark.diameter, 54)
        XCTAssertEqual(mark.glyphPointSize, 17)
        XCTAssertLessThan(mark.glyphPointSize, mark.diameter / 2)
    }

    func testGrowthHomeActivityStreakUsesOnlyConsecutiveRecordedDates() throws {
        let today = try XCTUnwrap(DateUtils.apiDateFormatter.date(from: "20260712"))
        let records = [
            ChallengeRecord(date: "20260712", menuName: "현미밥", action: .alreadyEats, gainedExp: 0, badgeName: nil, nutrients: []),
            ChallengeRecord(date: "20260711", menuName: "시금치나물", action: .oneBite, gainedExp: 18, badgeName: nil, nutrients: []),
            ChallengeRecord(date: "20260710", menuName: "된장국", action: .alreadyEats, gainedExp: 0, badgeName: nil, nutrients: [])
        ]

        XCTAssertEqual(
            GrowthHomePresentation.activityStreak(challengeRecords: records, mealRecords: [], asOf: today),
            3
        )
        XCTAssertEqual(
            GrowthHomePresentation.activityStreak(challengeRecords: [], mealRecords: [], asOf: today),
            0
        )
    }

    func testGrowthHomeMissionUsesActualSafeUnrecordedMealItem() {
        let rice = MealItem(name: "현미밥", allergyCodes: [], nutrients: ["탄수화물"], tags: [], sourceRawText: "현미밥")
        let spinach = MealItem(name: "시금치나물", allergyCodes: [], nutrients: ["비타민"], tags: [], sourceRawText: "시금치나물")
        let meal = MealDay(
            date: "20260712",
            menuItems: [rice, spinach],
            calorie: "650 kcal",
            nutrition: .empty,
            isSample: false,
            notice: nil
        )
        let mealRecords = [
            MealRecord(date: meal.date, menuName: rice.name, eatingStatus: .finished)
        ]

        let mission = GrowthHomePresentation.mission(
            meal: meal,
            mealState: .live,
            isLoading: false,
            message: nil,
            challengeRecords: [],
            mealRecords: mealRecords,
            allergyRiskItemIDs: []
        )

        XCTAssertEqual(mission.title, "시금치나물 한 입 도전")
        XCTAssertEqual(mission.progressText, "오늘 기록 1/2")
        XCTAssertEqual(mission.completedCount, 1)
        XCTAssertEqual(mission.totalCount, 2)
    }

    func testGrowthHomeMissionUsesAuthoritativeMealStateCopy() {
        let loading = GrowthHomePresentation.mission(
            meal: nil,
            mealState: .noMeal,
            isLoading: true,
            message: "이전 급식 오류 메시지",
            challengeRecords: [],
            mealRecords: [],
            allergyRiskItemIDs: []
        )
        XCTAssertEqual(loading.title, "오늘 급식을 불러오는 중이에요")
        XCTAssertEqual(loading.detail, "학교 급식 정보를 확인하고 있어요.")

        let noMeal = GrowthHomePresentation.mission(
            meal: nil,
            mealState: .noMeal,
            isLoading: false,
            message: "오늘은 급식이 제공되지 않아요.",
            challengeRecords: [],
            mealRecords: [],
            allergyRiskItemIDs: []
        )
        XCTAssertEqual(noMeal.title, "오늘은 등록된 급식이 없어요")
        XCTAssertEqual(noMeal.detail, "오늘은 급식이 제공되지 않아요.")

        XCTAssertEqual(
            GrowthHomePresentation.mission(
                meal: nil,
                mealState: .error,
                isLoading: false,
                message: nil,
                challengeRecords: [],
                mealRecords: [],
                allergyRiskItemIDs: []
            ).title,
            "급식 정보를 불러오지 못했어요"
        )
        XCTAssertEqual(
            GrowthHomePresentation.mission(
                meal: nil,
                mealState: .missingAPIKey,
                isLoading: false,
                message: nil,
                challengeRecords: [],
                mealRecords: [],
                allergyRiskItemIDs: []
            ).title,
            "급식 API 설정을 확인해 주세요"
        )
        XCTAssertEqual(
            GrowthHomePresentation.mission(
                meal: nil,
                mealState: .sampleSchool,
                isLoading: false,
                message: nil,
                challengeRecords: [],
                mealRecords: [],
                allergyRiskItemIDs: []
            ).title,
            "실제 학교를 선택해 주세요"
        )
        XCTAssertEqual(
            GrowthHomePresentation.mission(
                meal: nil,
                mealState: .demo,
                isLoading: false,
                message: nil,
                challengeRecords: [],
                mealRecords: [],
                allergyRiskItemIDs: []
            ).title,
            "체험 급식이 준비되지 않았어요"
        )
        XCTAssertEqual(
            GrowthHomePresentation.mission(
                meal: nil,
                mealState: .live,
                isLoading: false,
                message: nil,
                challengeRecords: [],
                mealRecords: [],
                allergyRiskItemIDs: []
            ).title,
            "오늘 급식 정보를 확인하지 못했어요"
        )

        let demoItem = MealItem(name: "시금치나물", allergyCodes: [], nutrients: ["비타민"], tags: [], sourceRawText: "시금치나물")
        let demoMeal = MealDay(
            date: "20260712",
            menuItems: [demoItem],
            calorie: "650 kcal",
            nutrition: .empty,
            isSample: true,
            notice: nil
        )
        let demoMission = GrowthHomePresentation.mission(
            meal: demoMeal,
            mealState: .demo,
            isLoading: false,
            message: nil,
            challengeRecords: [],
            mealRecords: [],
            allergyRiskItemIDs: []
        )
        XCTAssertEqual(demoMission.title, "시금치나물 한 입 도전")
        XCTAssertEqual(demoMission.detail, "체험 급식 미션이에요. 작은 한 입을 기록하면 기본 18 XP를 얻어요.")
    }

    func testGrowthHomeMissionPrioritizesUnrecordedAllergyRisk() {
        let rice = MealItem(name: "현미밥", allergyCodes: [], nutrients: ["탄수화물"], tags: [], sourceRawText: "현미밥")
        let egg = MealItem(name: "달걀찜", allergyCodes: [1], nutrients: ["단백질"], tags: [], sourceRawText: "달걀찜(1)")
        let meal = MealDay(
            date: "20260712",
            menuItems: [rice, egg],
            calorie: "650 kcal",
            nutrition: .empty,
            isSample: false,
            notice: nil
        )
        let mealRecords = [
            MealRecord(date: meal.date, menuName: rice.name, eatingStatus: .finished)
        ]

        let mission = GrowthHomePresentation.mission(
            meal: meal,
            mealState: .live,
            isLoading: false,
            message: nil,
            challengeRecords: [],
            mealRecords: mealRecords,
            allergyRiskItemIDs: [egg.id]
        )

        XCTAssertEqual(mission.title, "알레르기 주의 메뉴를 먼저 확인해요")
        XCTAssertEqual(mission.progressText, "오늘 기록 1/2")
        XCTAssertEqual(mission.completedCount, 1)
        XCTAssertEqual(mission.totalCount, 2)
        XCTAssertNotEqual(mission.title, "오늘 급식 기록을 모두 남겼어요")
    }

    func testChallengeAddsExpBadgeAndSkin() {
        var progress = PlayerProgress()
        let item = MealItem(name: "닭갈비", allergyCodes: [15], nutrients: ["단백질"], tags: ["튼튼 파워"], sourceRawText: "닭갈비(15)")
        let outcome = progress.applyChallenge(for: item)

        XCTAssertGreaterThan(outcome.gainedExp, 0)
        XCTAssertEqual(outcome.earnedBadgeName, "단백질 파워")
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

    func testBalancedAndConsistentRecordsEarnConfiguredXPBonuses() {
        let item = MealItem(
            name: "멸치볶음",
            allergyCodes: [4],
            nutrients: ["칼슘", "단백질"],
            tags: [],
            sourceRawText: "멸치볶음(4)"
        )
        let previousMealRecord = MealRecord(date: "20260619", menuName: "현미밥", eatingStatus: .finished)
        let existingRecord = ChallengeRecord(
            date: "20260620",
            menuName: "시금치나물",
            action: .alreadyEats,
            gainedExp: 10,
            badgeName: nil,
            nutrients: ["식이섬유", "비타민"],
            createdAt: Date(timeIntervalSince1970: 1),
            eatingStatus: .finished
        )

        let grant = LevelUpXPPolicy.grant(
            for: item,
            status: .finished,
            date: "20260620",
            existingRecords: [existingRecord],
            existingMealRecords: [previousMealRecord],
            isAllergyRisk: false
        )

        XCTAssertEqual(grant.base.record, 15)
        XCTAssertEqual(grant.base.balance, 15)
        XCTAssertEqual(grant.base.safety, 10)
        XCTAssertTrue(grant.notes.contains("연속 기록 +5"))
        XCTAssertTrue(grant.notes.contains("다양한 음식군 기록 +5"))
        XCTAssertTrue(grant.notes.contains("균형 잡힌 식사 기록 +10"))
        XCTAssertTrue(grant.notes.contains("알레르기 안전 확인 +10"))
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

    @MainActor
    func testCompleteChallengeAlsoLocksAllergyRiskOneBite() {
        let appState = makeAppState()
        appState.saveProfile(
            nickname: "냠냠이",
            school: School(name: "테스트초", officeCode: "B10", schoolCode: "123", region: "서울", address: "", schoolType: "초등학교"),
            allergyCodes: [1]
        )
        let item = MealItem(name: "우유", allergyCodes: [1], nutrients: ["칼슘"], tags: [], sourceRawText: "우유(1)")

        let outcome = appState.completeChallenge(for: item, date: "20260620", eatingStatus: .oneBite)

        XCTAssertEqual(outcome.gainedExp, 8)
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

    func testCharacterSkinUnlockRequiresItsLevel() {
        XCTAssertTrue(CharacterSkin.all[0].isUnlocked(at: 1))
        XCTAssertFalse(CharacterSkin.all[1].isUnlocked(at: 1))
        XCTAssertTrue(CharacterSkin.all[1].isUnlocked(at: 2))
    }

    func testExistingBadgeIsNotReportedAsNewlyEarned() {
        let item = MealItem(name: "닭갈비", allergyCodes: [], nutrients: ["단백질"], tags: [], sourceRawText: "닭갈비")
        var progress = PlayerProgress(badges: ["단백질 파워"])

        let outcome = progress.applyChallenge(for: item)

        XCTAssertNil(outcome.earnedBadgeName)
        XCTAssertEqual(progress.badges.filter { $0 == "단백질 파워" }.count, 1)
        XCTAssertFalse(ShareCardKind.available(for: outcome).contains(.badgeEarned))
    }

    @MainActor
    func testDailyCapStillReturnsSavedRecordOutcome() {
        ChallengeStore(defaults: defaults).save([
            ChallengeRecord(
                date: "20260620",
                menuName: "오늘 기록",
                action: .oneBite,
                gainedExp: 100,
                badgeName: "한 입 도전자",
                nutrients: [],
                eatingStatus: .oneBite,
                xpBreakdown: XPBreakdown(record: 50, challenge: 50),
                baseExp: 50,
                bonusExp: 50
            )
        ])
        let appState = makeAppState()
        let item = MealItem(name: "현미밥", allergyCodes: [], nutrients: ["탄수화물"], tags: [], sourceRawText: "현미밥")

        let outcome = appState.recordMealInteraction(item: item, date: "20260620", status: .finished)

        XCTAssertNotNil(outcome)
        XCTAssertEqual(outcome?.gainedExp, 0)
        XCTAssertEqual(appState.records.first?.menuName, "현미밥")
        XCTAssertNil(appState.records.first?.badgeName)
    }

    func testEatingStatusAndMealDataStatePolicies() {
        XCTAssertEqual(EatingStatus.allergyAvoided.title, "알레르기/주의로 먹지 않았어요")
        XCTAssertTrue(MealDataState.demo.usesSample)
        XCTAssertFalse(MealDataState.error.usesSample)
        XCTAssertFalse(MealDataState.missingAPIKey.usesSample)
    }

    func testMealFeedbackActionsMapToExistingStatuses() {
        XCTAssertEqual(MealFeedbackAction.oneBite.immediateStatus(isAllergyRisk: false), .oneBite)
        XCTAssertEqual(MealFeedbackAction.enjoyed.immediateStatus(isAllergyRisk: false), .finished)
        XCTAssertNil(MealFeedbackAction.difficult.immediateStatus(isAllergyRisk: false))
        XCTAssertNil(MealFeedbackAction.oneBite.immediateStatus(isAllergyRisk: true))
    }

    @MainActor
    func testRecordAllSafeMealsFinishedSkipsAllergyRiskAndDoesNotDuplicateXP() {
        let appState = makeAppState()
        appState.saveProfile(
            nickname: "냠냠이",
            school: School(name: "테스트초", officeCode: "B10", schoolCode: "123", region: "서울", address: "", schoolType: "초등학교"),
            allergyCodes: [1]
        )
        let meal = MealDay(
            date: "20260713",
            menuItems: [
                MealItem(name: "현미밥", allergyCodes: [], nutrients: ["탄수화물"], tags: [], sourceRawText: "현미밥"),
                MealItem(name: "우유", allergyCodes: [1], nutrients: ["칼슘"], tags: [], sourceRawText: "우유(1)")
            ],
            calorie: "500 Kcal",
            nutrition: .empty,
            isSample: false,
            notice: nil
        )

        let first = appState.recordAllSafeMealsFinished(meal)
        let second = appState.recordAllSafeMealsFinished(meal)

        XCTAssertEqual(first.recordedMenuNames, ["현미밥"])
        XCTAssertEqual(first.skippedAllergyMenuNames, ["우유"])
        XCTAssertEqual(appState.mealRecords.filter { $0.date == meal.date && $0.menuName == "현미밥" }.count, 1)
        XCTAssertEqual(second.gainedExp, 0)
        XCTAssertFalse(appState.mealRecords.contains { $0.date == meal.date && $0.menuName == "우유" && $0.eatingStatus == .finished })
    }

    func testShareCardRendererKeepsPersonalDetailsOutOfCardText() {
        let outcome = ChallengeOutcome(
            menuName: "시금치나물",
            gainedExp: 43,
            badgeName: "초록 용사",
            damage: 30,
            oldLevel: 1,
            newLevel: 2,
            skin: CharacterSkin.skin(for: 2),
            xpBreakdown: XPBreakdown(challenge: 43),
            earnedBadgeName: "초록 용사"
        )

        let lines = ShareCardKind.available(for: outcome).flatMap { ShareCardRenderer.textLines(kind: $0, outcome: outcome) }
        let combined = lines.joined(separator: " ")

        XCTAssertTrue(ShareCardKind.available(for: outcome).contains(.todayRecord))
        XCTAssertTrue(ShareCardKind.available(for: outcome).contains(.oneBiteSuccess))
        XCTAssertTrue(ShareCardKind.available(for: outcome).contains(.levelUp))
        XCTAssertTrue(ShareCardKind.available(for: outcome).contains(.badgeEarned))
        XCTAssertTrue(combined.contains("시금치나물"))
        XCTAssertFalse(combined.contains("학교"))
        XCTAssertFalse(combined.contains("알레르기"))
        XCTAssertFalse(combined.contains("반/번호"))
    }

    func testShareCardRendererIncludesTodayRecordWithoutOneBiteWhenNoChallengeXP() {
        let outcome = ChallengeOutcome(
            menuName: "우유",
            gainedExp: 8,
            badgeName: "안전 확인",
            damage: 0,
            oldLevel: 1,
            newLevel: 1,
            skin: CharacterSkin.skin(for: 1),
            xpBreakdown: XPBreakdown(safety: 8)
        )

        let kinds = ShareCardKind.available(for: outcome)
        let lines = kinds.flatMap { ShareCardRenderer.textLines(kind: $0, outcome: outcome) }

        XCTAssertTrue(kinds.contains(.todayRecord))
        XCTAssertFalse(kinds.contains(.oneBiteSuccess))
        XCTAssertTrue(lines.contains("오늘의 기록"))
        XCTAssertTrue(lines.contains("우유 기록 완료!"))
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
