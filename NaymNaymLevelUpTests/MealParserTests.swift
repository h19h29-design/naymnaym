import XCTest
@testable import NaymNaymLevelUp

final class MealParserTests: XCTestCase {
    func testParseMealItemsSplitsHtmlLineBreaksAndAllergies() {
        let items = MealParser.parseMealItems(rawDishName: "현미밥<br/>닭갈비(5.6.15)<br/>우유(2)")

        XCTAssertEqual(items.map(\.name), ["현미밥", "닭갈비", "우유"])
        XCTAssertEqual(items[1].allergyCodes, [5, 6, 15])
        XCTAssertEqual(items[2].allergyCodes, [2])
    }

    func testParseNutritionExtractsNumbers() {
        let nutrition = MealParser.parseNutrition(text: "탄수화물(g) : 88.2<br/>단백질(g) : 24.1<br/>지방(g) : 15.0<br/>칼슘(mg) : 220.0<br/>철(mg) : 3.4<br/>비타민 : 42")

        XCTAssertEqual(nutrition.carbs, 88.2, accuracy: 0.01)
        XCTAssertEqual(nutrition.protein, 24.1, accuracy: 0.01)
        XCTAssertEqual(nutrition.calcium, 220.0, accuracy: 0.01)
        XCTAssertEqual(nutrition.iron, 3.4, accuracy: 0.01)
    }

    func testIntroMissionPrioritizesAllergySafety() {
        let meal = MealDay(
            date: "20260624",
            menuItems: [
                MealItem(name: "우유", allergyCodes: [2], nutrients: ["칼슘"], tags: [], sourceRawText: "우유(2)"),
                MealItem(name: "콩나물무침", allergyCodes: [], nutrients: ["식이섬유"], tags: [], sourceRawText: "콩나물무침")
            ],
            calorie: "700 Kcal",
            nutrition: .empty,
            isSample: false
        )

        let mission = IntroMissionTextFactory.make(
            todayMeal: meal,
            mealStatus: .live,
            mealMessage: nil,
            isLoading: false,
            hasRegisteredSchool: true,
            isDemoMode: false,
            isAllergyRisk: { $0.allergyCodes.contains(2) }
        )

        XCTAssertEqual(mission.title, "먼저 안전 확인")
        XCTAssertTrue(mission.message.contains("주의가 필요한 메뉴"))
        XCTAssertFalse(mission.message.contains("콩나물무침 한 입 도전"))
    }

    func testIntroMissionUsesMealMenuForOneBiteRecommendation() {
        let meal = MealDay(
            date: "20260624",
            menuItems: [
                MealItem(name: "콩나물무침", allergyCodes: [], nutrients: ["식이섬유"], tags: [], sourceRawText: "콩나물무침")
            ],
            calorie: "680 Kcal",
            nutrition: .empty,
            isSample: false
        )

        let mission = IntroMissionTextFactory.make(
            todayMeal: meal,
            mealStatus: .live,
            mealMessage: nil,
            isLoading: false,
            hasRegisteredSchool: true,
            isDemoMode: false,
            isAllergyRisk: { _ in false }
        )

        XCTAssertEqual(mission.title, "오늘의 한 입 미션")
        XCTAssertTrue(mission.message.contains("콩나물무침 한 입 도전"))
    }

    func testIntroMissionShowsSchoolRegistrationWhenSchoolIsMissing() {
        let mission = IntroMissionTextFactory.make(
            todayMeal: nil,
            mealStatus: .noMeal,
            mealMessage: nil,
            isLoading: false,
            hasRegisteredSchool: false,
            isDemoMode: false,
            isAllergyRisk: { _ in false }
        )

        XCTAssertEqual(mission.title, "학교를 등록하면 시작할 수 있어요")
        XCTAssertEqual(mission.message, "학교를 선택하면 오늘 급식과 한 입 미션을 확인할 수 있어요.")
        XCTAssertEqual(mission.primaryTitle, "오늘 급식 보러가기")
        XCTAssertEqual(mission.primarySubtitle, "학교 등록하고 시작")
    }

    func testIntroMissionSeparatesNoMealFromError() {
        let noMeal = IntroMissionTextFactory.make(
            todayMeal: nil,
            mealStatus: .noMeal,
            mealMessage: nil,
            isLoading: false,
            hasRegisteredSchool: true,
            isDemoMode: false,
            isAllergyRisk: { _ in false }
        )

        let error = IntroMissionTextFactory.make(
            todayMeal: nil,
            mealStatus: .error,
            mealMessage: "server down",
            isLoading: false,
            hasRegisteredSchool: true,
            isDemoMode: false,
            isAllergyRisk: { _ in false }
        )

        XCTAssertEqual(noMeal.title, "오늘은 급식 정보가 없어요")
        XCTAssertEqual(noMeal.message, "방학, 재량휴업일, 급식 미운영일일 수 있어요.")
        XCTAssertNil(noMeal.primaryTitle)
        XCTAssertEqual(error.title, "급식 정보를 불러오지 못했어요")
        XCTAssertEqual(error.message, "API 키, 학교 설정, 네트워크 상태를 확인해 주세요.")
        XCTAssertEqual(error.primaryTitle, "설정 확인하기")
    }

    func testIntroMissionShowsDemoBadgeOnlyForDemo() {
        let mission = IntroMissionTextFactory.make(
            todayMeal: nil,
            mealStatus: .demo,
            mealMessage: nil,
            isLoading: false,
            hasRegisteredSchool: true,
            isDemoMode: true,
            isAllergyRisk: { _ in false }
        )

        XCTAssertEqual(mission.title, "체험 모드예요")
        XCTAssertTrue(mission.showsDemoBadge)
        XCTAssertTrue(mission.message.contains("샘플 데이터"))
    }

    func testMealCalendarModeDefaultsToWeeklyContract() {
        XCTAssertEqual(MealCalendarMode.weekly.title, "주간")
        XCTAssertEqual(MealCalendarMode.monthly.title, "월간")
        XCTAssertEqual(MealCalendarMode.allCases.first, .weekly)
    }

    func testMealCalendarWeekPeriodUsesSevenDayWindow() throws {
        let start = try XCTUnwrap(DateUtils.apiDateFormatter.date(from: "20260624"))
        let dates = MealCalendarPeriod.weekDates(starting: start)

        XCTAssertEqual(dates.map(DateUtils.apiString(from:)), [
            "20260624",
            "20260625",
            "20260626",
            "20260627",
            "20260628",
            "20260629",
            "20260630"
        ])
        XCTAssertEqual(MealCalendarPeriod.weekTitle(starting: start), "2026.06.24 ~ 2026.06.30")
    }

    func testMealCalendarWeekNavigationMovesBySevenDays() throws {
        let start = try XCTUnwrap(DateUtils.apiDateFormatter.date(from: "20260624"))
        let previous = MealCalendarPeriod.shiftedWeekStart(start, by: -1)
        let next = MealCalendarPeriod.shiftedWeekStart(start, by: 1)

        XCTAssertEqual(DateUtils.apiString(from: previous), "20260617")
        XCTAssertEqual(DateUtils.apiString(from: next), "20260701")
    }
}

final class MealServiceTests: XCTestCase {
    private var originalHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func setUp() {
        super.setUp()
        originalHandler = MockURLProtocol.requestHandler
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = originalHandler
        super.tearDown()
    }

    func testMissingAPIKeyDoesNotUseSampleFallback() async {
        let service = MealService(client: NEISClient(apiKey: "YOUR_KEY_HERE"))
        let result = await service.fetchMonthlyMeals(school: actualSchool, year: 2026, month: 6)

        XCTAssertEqual(result.status, .missingAPIKey)
        XCTAssertTrue(result.meals.isEmpty)
        XCTAssertFalse(result.usedSample)
    }

    func testSampleSchoolRequiresExplicitDemoMode() async {
        let service = MealService(client: NEISClient(apiKey: "test-key"))
        let sampleSchool = SampleDataProvider().sampleSchools[0]

        let blocked = await service.fetchMonthlyMeals(school: sampleSchool, year: 2026, month: 6, allowsDemo: false)
        let demo = await service.fetchMonthlyMeals(school: sampleSchool, year: 2026, month: 6, allowsDemo: true)

        XCTAssertEqual(blocked.status, .sampleSchool)
        XCTAssertTrue(blocked.meals.isEmpty)
        XCTAssertFalse(blocked.usedSample)
        XCTAssertEqual(demo.status, .demo)
        XCTAssertFalse(demo.meals.isEmpty)
        XCTAssertTrue(demo.usedSample)
    }

    func testNoMealResultIsDistinctFromAPIError() async throws {
        let service = try makeService(responseJSON: #"{"RESULT":{"CODE":"INFO-200","MESSAGE":"해당하는 데이터가 없습니다."}}"#)

        let result = await service.fetchMonthlyMeals(school: actualSchool, year: 2026, month: 6)

        XCTAssertEqual(result.status, .noMeal)
        XCTAssertTrue(result.meals.isEmpty)
        XCTAssertFalse(result.usedSample)
    }

    func testNEISErrorResultDoesNotLookLikeNoMeal() async throws {
        let service = try makeService(responseJSON: #"{"RESULT":{"CODE":"ERROR-336","MESSAGE":"데이터요청은 한번에 최대 1000건을 넘을 수 없습니다."}}"#)

        let result = await service.fetchMonthlyMeals(school: actualSchool, year: 2026, month: 6)

        XCTAssertEqual(result.status, .error)
        XCTAssertTrue(result.meals.isEmpty)
        XCTAssertFalse(result.usedSample)
        XCTAssertTrue(result.message?.contains("ERROR-336") == true)
    }

    func testMealRowsConvertToLiveMealDay() async throws {
        let service = try makeService(responseJSON: """
        {
          "mealServiceDietInfo": [
            {"head": [{"list_total_count": 1}]},
            {"row": [
              {
                "MLSV_YMD": "20260618",
                "DDISH_NM": "현미밥<br/>닭갈비 (5.6.13.15)<br/>우유 (2)",
                "CAL_INFO": "770.7 Kcal",
                "NTR_INFO": "탄수화물(g) : 95.9<br/>단백질(g) : 42.3<br/>지방(g) : 25.1<br/>칼슘(mg) : 152.2<br/>철분(mg) : 3.7"
              }
            ]}
          ]
        }
        """)

        let result = await service.fetchMonthlyMeals(school: actualSchool, year: 2026, month: 6)

        XCTAssertEqual(result.status, .live)
        XCTAssertEqual(result.meals.count, 1)
        XCTAssertEqual(result.meals[0].date, "20260618")
        XCTAssertEqual(result.meals[0].calorie, "770.7 Kcal")
        XCTAssertFalse(result.meals[0].isSample)
        XCTAssertEqual(result.meals[0].menuItems.map(\.name), ["현미밥", "닭갈비", "우유"])
        XCTAssertEqual(result.meals[0].menuItems[1].allergyCodes, [5, 6, 13, 15])
        XCTAssertEqual(result.meals[0].nutrition.protein, 42.3, accuracy: 0.01)
    }

    @MainActor
    func testAppStateDoesNotFallbackToFirstMonthlyMealWhenTodayIsMissing() async throws {
        let service = try makeService(responseJSON: """
        {
          "mealServiceDietInfo": [
            {"head": [{"list_total_count": 1}]},
            {"row": [
              {
                "MLSV_YMD": "20260618",
                "DDISH_NM": "현미밥<br/>닭갈비 (5.6.13.15)",
                "CAL_INFO": "770.7 Kcal",
                "NTR_INFO": "탄수화물(g) : 95.9<br/>단백질(g) : 42.3"
              }
            ]}
          ]
        }
        """)
        let suiteName = "AppStateMealFallbackTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: photoDirectory)
        }

        let appState = AppState(
            profileStore: UserProfileStore(defaults: defaults),
            progressStore: ProgressStore(defaults: defaults),
            challengeStore: ChallengeStore(defaults: defaults),
            mealRecordStore: MealRecordStore(defaults: defaults),
            mealPhotoMetadataStore: MealPhotoMetadataStore(defaults: defaults),
            parentProfileStore: ParentProfileStore(defaults: defaults),
            childShareLinkStore: ChildShareLinkStore(defaults: defaults),
            localPhotoStore: LocalPhotoStore(directoryURL: photoDirectory),
            mealService: service,
            automaticallyPublishesParentSharedData: false
        )
        appState.saveProfile(nickname: "냠냠이", school: actualSchool, allergyCodes: [])

        let date = try XCTUnwrap(DateUtils.apiDateFormatter.date(from: "20260624"))
        await appState.loadMeals(for: date)

        XCTAssertNil(appState.todayMeal)
        XCTAssertEqual(appState.mealStatus, .noMeal)
        XCTAssertEqual(appState.monthlyMeals.first?.date, "20260618")
        XCTAssertFalse(appState.monthlyMeals.first?.isSample ?? true)
    }

    private var actualSchool: School {
        School(
            name: "등촌고등학교",
            officeCode: "B10",
            schoolCode: "7010700",
            region: "서울",
            address: "서울특별시 강서구",
            schoolType: "고등학교"
        )
    }

    private func makeService(responseJSON: String) throws -> MealService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertTrue(url.absoluteString.contains("mealServiceDietInfo"))
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJSON.utf8))
        }
        return MealService(client: NEISClient(apiKey: "test-key", session: session))
    }
}

final class SchoolSearchServiceTests: XCTestCase {
    private var originalHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override func setUp() {
        super.setUp()
        originalHandler = MockURLProtocol.requestHandler
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = originalHandler
        super.tearDown()
    }

    func testEmptyKeywordDoesNotSearchOrUseSample() async {
        let service = SchoolSearchService(client: NEISClient(apiKey: "test-key"))

        let result = await service.searchSchools(keyword: "   ")

        XCTAssertTrue(result.schools.isEmpty)
        XCTAssertFalse(result.usedSample)
        XCTAssertEqual(result.message, "학교 이름을 입력하면 검색할 수 있어요.")
    }

    func testMissingAPIKeyDoesNotReturnSampleSchools() async {
        let service = SchoolSearchService(client: NEISClient(apiKey: "YOUR_KEY_HERE"))

        let result = await service.searchSchools(keyword: "등촌고")

        XCTAssertTrue(result.schools.isEmpty)
        XCTAssertFalse(result.usedSample)
        XCTAssertTrue(result.message?.contains("NEIS API 키") == true)
    }

    func testSchoolInfoRowsConvertToSchoolCodes() async throws {
        let service = try makeSchoolSearchService(responseJSON: """
        {
          "schoolInfo": [
            {"head": [{"list_total_count": 1}]},
            {"row": [
              {
                "ATPT_OFCDC_SC_CODE": "B10",
                "ATPT_OFCDC_SC_NM": "서울특별시교육청",
                "SD_SCHUL_CODE": "7010700",
                "SCHUL_NM": "등촌고등학교",
                "SCHUL_KND_SC_NM": "고등학교",
                "LCTN_SC_NM": "서울특별시",
                "ORG_RDNMA": "서울특별시 강서구"
              }
            ]}
          ]
        }
        """)

        let result = await service.searchSchools(keyword: "등촌고등학교")

        XCTAssertEqual(result.schools.count, 1)
        XCTAssertFalse(result.usedSample)
        XCTAssertNil(result.message)
        XCTAssertEqual(result.schools[0].officeCode, "B10")
        XCTAssertEqual(result.schools[0].schoolCode, "7010700")
        XCTAssertEqual(result.schools[0].name, "등촌고등학교")
    }

    func testSchoolInfoNoRowsDoesNotFallbackToSample() async throws {
        let service = try makeSchoolSearchService(responseJSON: #"{"schoolInfo":[{"head":[{"list_total_count":0}]}]}"#)

        let result = await service.searchSchools(keyword: "없는학교")

        XCTAssertTrue(result.schools.isEmpty)
        XCTAssertFalse(result.usedSample)
        XCTAssertTrue(result.message?.contains("검색 결과가 없어요") == true)
    }

    func testDemoSchoolsAreExplicitlyMarkedAsSample() {
        let service = SchoolSearchService(client: NEISClient(apiKey: "YOUR_KEY_HERE"))

        let result = service.demoSchools(keyword: "냠냠")

        XCTAssertFalse(result.schools.isEmpty)
        XCTAssertTrue(result.usedSample)
        XCTAssertTrue(result.message?.contains("체험 모드") == true)
    }

    private func makeSchoolSearchService(responseJSON: String) throws -> SchoolSearchService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertTrue(url.absoluteString.contains("schoolInfo"))
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJSON.utf8))
        }
        return SchoolSearchService(client: NEISClient(apiKey: "test-key", session: session))
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
