import CoreData
import XCTest
@testable import NaymNaymLevelUp

final class RebuildMealRepositoryTests: XCTestCase {
    func testRefreshFailureKeepsCachedMealInRetryableFailedStateWithoutRewritingStore() async throws {
        let meal = RebuildMealDay.fixture(date: "2026-07-25")
        let container = try RebuildPersistentStore.makeInMemory()
        let cache = CoreDataRebuildMealDayStore(context: container.viewContext)
        let refreshedAt = Date(timeIntervalSince1970: 1_753_401_600)
        try cache.save(meal, refreshedAt: refreshedAt, source: "neis")
        let payloadBefore = try mealPayload(
            date: meal.date,
            context: container.viewContext
        )
        let client = StubMealClient(result: .failure(NEISClientError.serverStatus(503)))
        let repository = RebuildMealRepository(store: cache, client: client)

        await repository.refresh(date: "2026-07-25", school: .fixture)
        let state = await repository.currentState(date: "2026-07-25")

        guard case let .failed(message, cached) = state else {
            return XCTFail("Expected a retryable failed state with cached content")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(cached, meal)
        XCTAssertEqual(
            try cache.load(date: "2026-07-25"),
            RebuildCachedMealDay(
                meal: meal,
                refreshedAt: refreshedAt,
                source: "neis"
            )
        )
        XCTAssertEqual(
            try mealPayload(date: meal.date, context: container.viewContext),
            payloadBefore
        )
    }

    func testObserverImmediatelyEmitsCachedStateThenRefreshStates() async throws {
        let cachedMeal = RebuildMealDay.fixture(date: "2026-07-25", menuName: "저장된 급식")
        let liveMeal = RebuildMealDay.fixture(date: "2026-07-25", menuName: "새 급식")
        let refreshedAt = Date(timeIntervalSince1970: 1_753_401_600)
        let cache = InMemoryMealDayStore(
            entries: [
                RebuildCachedMealDay(
                    meal: cachedMeal,
                    refreshedAt: refreshedAt,
                    source: "neis"
                )
            ]
        )
        let repository = RebuildMealRepository(
            store: cache,
            client: StubMealClient(result: .success(liveMeal)),
            now: { Date(timeIntervalSince1970: 1_753_405_200) }
        )
        let stream = await repository.observe(date: "2026-07-25")
        var iterator = stream.makeAsyncIterator()
        let initialState = await iterator.next()

        XCTAssertEqual(
            initialState,
            .cached(cachedMeal, refreshedAt: refreshedAt)
        )

        await repository.refresh(date: "2026-07-25", school: .fixture)
        let refreshingState = await iterator.next()
        let liveState = await iterator.next()

        XCTAssertEqual(refreshingState, .refreshing(cachedMeal))
        XCTAssertEqual(liveState, .live(liveMeal))
    }

    func testObserverImmediatelyEmitsEmptyWithoutCache() async {
        let repository = RebuildMealRepository(
            store: InMemoryMealDayStore(),
            client: StubMealClient(result: .success(nil))
        )
        let stream = await repository.observe(date: "2026-07-25")
        var iterator = stream.makeAsyncIterator()
        let state = await iterator.next()

        XCTAssertEqual(state, .empty)
    }

    func testSuccessfulRefreshPersistsMealForANewRepository() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let store = CoreDataRebuildMealDayStore(context: container.viewContext)
        let liveMeal = RebuildMealDay.fixture(date: "2026-07-25")
        let refreshedAt = Date(timeIntervalSince1970: 1_753_405_200)
        let repository = RebuildMealRepository(
            store: store,
            client: StubMealClient(result: .success(liveMeal)),
            now: { refreshedAt }
        )

        await repository.refresh(date: "2026-07-25", school: .fixture)
        let liveState = await repository.currentState(date: "2026-07-25")

        XCTAssertEqual(
            liveState,
            .live(liveMeal)
        )
        let restoredRepository = RebuildMealRepository(
            store: store,
            client: StubMealClient(result: .success(nil))
        )
        let restoredState = await restoredRepository.currentState(
            date: "2026-07-25"
        )
        XCTAssertEqual(
            restoredState,
            .cached(liveMeal, refreshedAt: refreshedAt)
        )
    }

    func testDemoRefreshPersistsDemoSourceProvenance() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let store = CoreDataRebuildMealDayStore(context: container.viewContext)
        let repository = RebuildMealRepository(
            store: store,
            client: RebuildDemoMealClient(),
            now: { Date(timeIntervalSince1970: 1_753_405_200) }
        )

        await repository.refresh(date: "2026-08-30", school: .fixture)

        XCTAssertEqual(try store.load(date: "2026-08-30")?.source, "demo")
    }

    func testSuccessfulNoMealResponseBecomesEmpty() async {
        let repository = RebuildMealRepository(
            store: InMemoryMealDayStore(),
            client: StubMealClient(result: .success(nil))
        )

        await repository.refresh(date: "2026-07-25", school: .fixture)
        let state = await repository.currentState(date: "2026-07-25")

        XCTAssertEqual(
            state,
            .empty
        )
    }

    func testSuccessfulNoMealResponseRemovesStaleCache() async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let cache = CoreDataRebuildMealDayStore(
            context: container.viewContext
        )
        try cache.save(
            .fixture(date: "2026-07-25"),
            refreshedAt: Date(timeIntervalSince1970: 1_753_401_600),
            source: "neis"
        )
        let repository = RebuildMealRepository(
            store: cache,
            client: StubMealClient(result: .success(nil))
        )

        await repository.refresh(date: "2026-07-25", school: .fixture)

        let restoredRepository = RebuildMealRepository(
            store: cache,
            client: StubMealClient(result: .success(nil))
        )
        let restoredState = await restoredRepository.currentState(
            date: "2026-07-25"
        )
        XCTAssertEqual(restoredState, .empty)
    }

    func testRefreshFailureWithoutCacheBecomesFailed() async {
        let repository = RebuildMealRepository(
            store: InMemoryMealDayStore(),
            client: StubMealClient(result: .failure(NEISClientError.serverStatus(503)))
        )

        await repository.refresh(date: "2026-07-25", school: .fixture)
        let state = await repository.currentState(date: "2026-07-25")

        guard case let .failed(message, cached) = state else {
            return XCTFail("Expected a failed state")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNil(cached)
    }

    func testStaleRefreshCompletionsCannotReplaceNewerStateOrCache() async throws {
        let staleMeal = RebuildMealDay.fixture(
            date: "2026-07-25",
            menuName: "이전 급식"
        )
        let cases: [StaleRefreshCompletionCase] = [
            StaleRefreshCompletionCase(
                name: "stale meal",
                result: .success(staleMeal)
            ),
            StaleRefreshCompletionCase(
                name: "stale no-meal",
                result: .success(nil)
            ),
            StaleRefreshCompletionCase(
                name: "stale failure",
                result: .failure(NEISClientError.serverStatus(503))
            ),
        ]

        for testCase in cases {
            try await assertStaleCompletionCannotReplaceNewerMeal(testCase)
        }
    }

    private func assertStaleCompletionCannotReplaceNewerMeal(
        _ testCase: StaleRefreshCompletionCase
    ) async throws {
        let container = try RebuildPersistentStore.makeInMemory()
        let store = CoreDataRebuildMealDayStore(
            context: container.viewContext
        )
        let client = ControlledMealClient()
        let initialMeal = RebuildMealDay.fixture(
            date: "2026-07-25",
            menuName: "초기 캐시"
        )
        let newerMeal = RebuildMealDay.fixture(
            date: "2026-07-25",
            menuName: "최신 급식"
        )
        try store.save(
            initialMeal,
            refreshedAt: Date(timeIntervalSince1970: 1_753_401_600),
            source: "neis"
        )
        let refreshedAt = Date(timeIntervalSince1970: 1_753_405_200)
        let repository = RebuildMealRepository(
            store: store,
            client: client,
            now: { refreshedAt }
        )

        let olderRefresh = Task {
            await repository.refresh(
                date: "2026-07-25",
                school: .fixture
            )
        }
        await client.waitUntilRequestCount(1)

        let newerRefresh = Task {
            await repository.refresh(
                date: "2026-07-25",
                school: .fixture
            )
        }
        await client.waitUntilRequestCount(2)

        await client.complete(
            requestID: 1,
            with: .success(newerMeal)
        )
        await newerRefresh.value
        await client.complete(
            requestID: 0,
            with: testCase.result
        )
        await olderRefresh.value

        let state = await repository.currentState(date: "2026-07-25")
        XCTAssertEqual(
            state,
            .live(newerMeal),
            testCase.name
        )

        let restoredRepository = RebuildMealRepository(
            store: store,
            client: StubMealClient(result: .success(nil))
        )
        let restoredState = await restoredRepository.currentState(
            date: "2026-07-25"
        )
        XCTAssertEqual(
            restoredState,
            .cached(newerMeal, refreshedAt: refreshedAt),
            testCase.name
        )
    }

    private func mealPayload(
        date: String,
        context: NSManagedObjectContext
    ) throws -> String {
        try context.performAndWait {
            let request = NSFetchRequest<RebuildMealDayManagedObject>(
                entityName: RebuildEntityName.mealDay
            )
            request.predicate = NSPredicate(format: "date == %@", date)
            request.fetchLimit = 1
            return try XCTUnwrap(context.fetch(request).first).payloadJSON
        }
    }
}

final class RebuildMealClientTests: XCTestCase {
    override func tearDown() {
        RebuildMealMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testNEISDebugURLRedactionHidesEveryQueryValue() throws {
        let rawURL = "https://open.neis.go.kr/hub/schoolInfo?KEY=fixture-key-value&ATPT_OFCDC_SC_CODE=B10&SD_SCHUL_CODE=7010700&SCHUL_NM=냠냠초&pIndex=1"

        let redacted = NEISDebugLog.redactedURLString(rawURL)

        let components = try XCTUnwrap(URLComponents(string: redacted))
        XCTAssertEqual(components.path, "/hub/schoolInfo")
        XCTAssertEqual(
            components.queryItems?.map(\.name),
            [
                "KEY",
                "ATPT_OFCDC_SC_CODE",
                "SD_SCHUL_CODE",
                "SCHUL_NM",
                "pIndex",
            ]
        )
        XCTAssertTrue(
            components.queryItems?.allSatisfy { $0.value == "<redacted>" }
                == true
        )
        for privateValue in [
            "fixture-key-value", "B10", "7010700", "냠냠초", "=1",
        ] {
            XCTAssertFalse(redacted.contains(privateValue))
        }
    }

    func testNEISDebugURLRedactionDoesNotEchoMalformedInput() {
        let malformed = "not a valid URL?KEY=fixture-key-value&query=냠냠초"

        let redacted = NEISDebugLog.redactedURLString(malformed)

        XCTAssertEqual(redacted, "<invalid-url>")
        XCTAssertFalse(redacted.contains(malformed))
        XCTAssertFalse(redacted.contains("fixture-key-value"))
        XCTAssertFalse(redacted.contains("냠냠초"))
    }

    func testNEISDebugQueryMessageRedactsLegacySchoolAndDateValues() {
        let query = [
            "ATPT_OFCDC_SC_CODE": "fixture-office-code",
            "SD_SCHUL_CODE": "fixture-school-code",
            "MMEAL_SC_CODE": "2",
            "MLSV_FROM_YMD": "20260701",
            "MLSV_TO_YMD": "20260731",
        ]

        let message = NEISDebugLog.redactedQueryMessage(
            path: "mealServiceDietInfo",
            query: query
        )

        XCTAssertTrue(message.hasPrefix("mealServiceDietInfo params "))
        for field in query.keys {
            XCTAssertTrue(message.contains("\(field)=<redacted>"))
        }
        for privateValue in query.values {
            XCTAssertFalse(message.contains("=\(privateValue)"))
        }
    }

    func testNEISDebugErrorMessageDoesNotExposeFailingURLValues() throws {
        let failingURL = try XCTUnwrap(
            URL(
                string: "https://example.invalid/meal?KEY=fake-private-key"
                    + "&ATPT_OFCDC_SC_CODE=fake-office"
                    + "&SD_SCHUL_CODE=fake-school"
                    + "&MLSV_FROM_YMD=20991231"
            )
        )
        let error = URLError(
            .badServerResponse,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        let message = NEISDebugLog.redactedErrorMessage(
            path: "mealServiceDietInfo",
            error: error
        )

        XCTAssertTrue(message.hasPrefix("mealServiceDietInfo error "))
        XCTAssertTrue(message.contains("code=\(error.errorCode)"))
        for privateFragment in [
            failingURL.absoluteString,
            "fake-private-key",
            "fake-office",
            "fake-school",
            "20991231",
            "KEY=",
        ] {
            XCTAssertFalse(message.contains(privateFragment))
        }
    }

    func testExplicitDemoReturnsSampleMealForWeekendWithRebuildMetadata() async throws {
        let client = RebuildMealClientFactory.make(isDemoMode: true)
        let school = RebuildSchool(
            name: "냠냠중학교",
            officeCode: "B10",
            schoolCode: "7010111"
        )

        let meal = try await client.fetch(
            date: "2026-08-30",
            school: school
        )

        let sample = try XCTUnwrap(meal)
        XCTAssertEqual(sample.date, "2026-08-30")
        XCTAssertEqual(sample.menuItems.map(\.name), [
            "현미밥",
            "미역국",
            "닭갈비",
            "콩나물무침",
            "배추김치",
        ])
        XCTAssertEqual(sample.menuItems[2].allergyCodes, [5, 6, 15])
        XCTAssertEqual(sample.menuItems[2].nutrients, ["단백질", "철분"])
        XCTAssertEqual(sample.menuItems[2].tags, ["튼튼 파워", "성장 에너지"])
        XCTAssertEqual(sample.menuItems[2].sourceRawText, "닭갈비(5.6.15)")
        XCTAssertEqual(sample.calorie, "610 kcal")
        XCTAssertEqual(sample.nutrition.carbs, 78, accuracy: 0.001)
        XCTAssertEqual(sample.nutrition.protein, 23, accuracy: 0.001)
        XCTAssertEqual(sample.nutrition.fat, 14, accuracy: 0.001)
        XCTAssertEqual(sample.nutrition.calcium, 190, accuracy: 0.001)
        XCTAssertEqual(sample.nutrition.iron, 2.6, accuracy: 0.001)
        XCTAssertEqual(sample.nutrition.vitamin, 36, accuracy: 0.001)
        XCTAssertEqual(
            sample.nutrition.sourceFields,
            [.carbs, .protein, .fat, .calcium, .iron, .vitamin]
        )
        XCTAssertEqual(sample.nutrition.sourceUnits, [:])
    }

    func testExplicitDemoReturnsSampleMealForTheSelectedCurrentDate() async throws {
        let client = RebuildMealClientFactory.make(isDemoMode: true)
        let selectedDate = MealScheduleCalendar.key(for: Date())

        let meal = try await client.fetch(
            date: selectedDate,
            school: .fixture
        )

        XCTAssertEqual(meal?.date, selectedDate)
        XCTAssertFalse(meal?.menuItems.isEmpty ?? true)
    }

    func testDemoSelectionUsesSeoulCalendarAcrossAdjacentMonthBoundary() async throws {
        let client = RebuildMealClientFactory.make(isDemoMode: true)
        let school = RebuildSchool(
            name: "냠냠중학교",
            officeCode: "B10",
            schoolCode: "7010111"
        )
        let expectedMenus: [(date: String, names: [String])] = [
            (
                "2026-08-27",
                ["잡곡밥", "닭곰탕", "두부조림", "오이무침", "배추김치"]
            ),
            (
                "2026-08-31",
                ["귀리밥", "소고기무국", "계란말이", "김치볶음", "사과"]
            ),
            (
                "2026-09-01",
                ["현미밥", "미역국", "닭갈비", "콩나물무침", "배추김치"]
            ),
        ]

        for expected in expectedMenus {
            let fetched = try await client.fetch(
                date: expected.date,
                school: school
            )
            let meal = try XCTUnwrap(fetched)

            XCTAssertEqual(meal.date, expected.date)
            XCTAssertEqual(meal.menuItems.map(\.name), expected.names, expected.date)
        }
    }

    func testNonDemoUsesNEISForSchoolWithSampleIdentifiers() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RebuildMealMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RebuildMealMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
                    item in item.value.map { (item.name, $0) }
                }
            )
            XCTAssertEqual(query["ATPT_OFCDC_SC_CODE"], "B10")
            XCTAssertEqual(query["SD_SCHUL_CODE"], "7010111")

            let body = """
            {
              "mealServiceDietInfo": [
                {"row": [{
                  "MLSV_YMD": "20260830",
                  "DDISH_NM": "보리밥<br/>김치찌개(5.9.10)",
                  "CAL_INFO": "700 Kcal",
                  "NTR_INFO": "단백질(g) : 31.5"
                }]}
              ]
            }
            """
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, Data(body.utf8))
        }
        let client = RebuildMealClientFactory.make(
            isDemoMode: false,
            neisClient: NEISClient(
                apiKey: "fixture-key",
                session: session
            )
        )
        let school = RebuildSchool(
            name: "냠냠중학교",
            officeCode: "B10",
            schoolCode: "7010111"
        )

        let meal = try await client.fetch(date: "2026-08-30", school: school)

        let live = try XCTUnwrap(meal)
        XCTAssertEqual(live.date, "2026-08-30")
        XCTAssertEqual(live.menuItems.map(\.name), ["보리밥", "김치찌개"])
        XCTAssertEqual(live.nutrition.protein, 31.5, accuracy: 0.001)
    }

    func testFetchUsesCurrentNEISEndpointAndParsesMeal() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RebuildMealMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RebuildMealMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false)
            )
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
                    item in item.value.map { (item.name, $0) }
                }
            )
            XCTAssertEqual(url.path, "/hub/mealServiceDietInfo")
            XCTAssertEqual(query["KEY"], "test-secret")
            XCTAssertEqual(query["ATPT_OFCDC_SC_CODE"], "B10")
            XCTAssertEqual(query["SD_SCHUL_CODE"], "7010700")
            XCTAssertEqual(query["MMEAL_SC_CODE"], "2")
            XCTAssertEqual(query["MLSV_FROM_YMD"], "20260725")
            XCTAssertEqual(query["MLSV_TO_YMD"], "20260725")

            let body = """
            {
              "mealServiceDietInfo": [
                {"head": [{"list_total_count": 1}]},
                {"row": [{
                  "MLSV_YMD": "20260725",
                  "DDISH_NM": "현미밥<br/>닭갈비 (5.6.13.15)",
                  "CAL_INFO": "770.7 Kcal",
                  "NTR_INFO": "탄수화물(g) : 95.9<br/>단백질(g) : 42.3"
                }]}
              ]
            }
            """
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, Data(body.utf8))
        }
        let client = RebuildMealClient(
            neisClient: NEISClient(apiKey: "test-secret", session: session)
        )

        let meal = try await client.fetch(date: "2026-07-25", school: .fixture)

        XCTAssertEqual(meal?.date, "2026-07-25")
        XCTAssertEqual(meal?.menuItems.map(\.name), ["현미밥", "닭갈비"])
        XCTAssertEqual(meal?.menuItems[1].allergyCodes, [5, 6, 13, 15])
        XCTAssertEqual(
            try XCTUnwrap(meal).nutrition.protein,
            42.3,
            accuracy: 0.01
        )
        XCTAssertEqual(meal?.calorie, "770.7 Kcal")
    }

    func testFetchReturnsNilForNEISNoDataResult() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RebuildMealMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RebuildMealMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            let body = #"{"RESULT":{"CODE":"INFO-200","MESSAGE":"해당하는 데이터가 없습니다."}}"#
            return (response, Data(body.utf8))
        }
        let client = RebuildMealClient(
            neisClient: NEISClient(apiKey: "test-secret", session: session)
        )

        let meal = try await client.fetch(date: "2026-07-25", school: .fixture)

        XCTAssertNil(meal)
    }

    func testFetchRejectsImpossibleCalendarDateBeforeNetwork() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RebuildMealMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RebuildMealMockURLProtocol.requestHandler = { request in
            XCTFail("An invalid date must be rejected before a request")
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            let body = #"{"RESULT":{"CODE":"INFO-200"}}"#
            return (response, Data(body.utf8))
        }
        let client = RebuildMealClient(
            neisClient: NEISClient(apiKey: "test-secret", session: session)
        )

        do {
            _ = try await client.fetch(
                date: "2026-02-30",
                school: .fixture
            )
            XCTFail("Expected invalidDate")
        } catch let error as RebuildMealClientError {
            XCTAssertEqual(error, .invalidDate("2026-02-30"))
        } catch {
            XCTFail("Expected invalidDate, got \(error)")
        }
    }
}

private final class InMemoryMealDayStore: RebuildMealDayStore {
    private let lock = NSLock()
    private var entries: [String: RebuildCachedMealDay]

    init(meals: [RebuildMealDay] = []) {
        entries = Dictionary(
            uniqueKeysWithValues: meals.map {
                (
                    $0.date,
                    RebuildCachedMealDay(
                        meal: $0,
                        refreshedAt: nil,
                        source: "fixture"
                    )
                )
            }
        )
    }

    init(entries: [RebuildCachedMealDay]) {
        self.entries = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.meal.date, $0) }
        )
    }

    func load(date: String) throws -> RebuildCachedMealDay? {
        lock.lock()
        defer { lock.unlock() }
        return entries[date]
    }

    func save(
        _ meal: RebuildMealDay,
        refreshedAt: Date,
        source: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        entries[meal.date] = RebuildCachedMealDay(
            meal: meal,
            refreshedAt: refreshedAt,
            source: source
        )
    }

    func remove(date: String) throws {
        lock.lock()
        defer { lock.unlock() }
        entries[date] = nil
    }
}

private struct StubMealClient: RebuildMealClientProtocol {
    let result: Result<RebuildMealDay?, Error>

    func fetch(
        date: String,
        school: RebuildSchool
    ) async throws -> RebuildMealDay? {
        try result.get()
    }
}

private struct StaleRefreshCompletionCase {
    let name: String
    let result: Result<RebuildMealDay?, Error>
}

private actor ControlledMealClient: RebuildMealClientProtocol {
    private struct RequestWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var nextRequestID = 0
    private var continuations:
        [Int: CheckedContinuation<RebuildMealDay?, Error>] = [:]
    private var requestCount = 0
    private var waiters: [RequestWaiter] = []

    func fetch(
        date: String,
        school: RebuildSchool
    ) async throws -> RebuildMealDay? {
        let requestID = nextRequestID
        nextRequestID += 1
        return try await withCheckedThrowingContinuation {
            continuation in
            continuations[requestID] = continuation
            requestCount += 1
            resumeReadyWaiters()
        }
    }

    func waitUntilRequestCount(_ count: Int) async {
        guard requestCount < count else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(
                RequestWaiter(
                    count: count,
                    continuation: continuation
                )
            )
        }
    }

    func complete(
        requestID: Int,
        with result: Result<RebuildMealDay?, Error>
    ) {
        guard let continuation = continuations.removeValue(forKey: requestID)
        else {
            preconditionFailure("Unknown request ID \(requestID)")
        }
        continuation.resume(with: result)
    }

    private func resumeReadyWaiters() {
        let ready = waiters.filter { $0.count <= requestCount }
        waiters.removeAll { $0.count <= requestCount }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}

private extension RebuildSchool {
    static let fixture = RebuildSchool(
        name: "등촌고등학교",
        officeCode: "B10",
        schoolCode: "7010700"
    )
}

private extension RebuildMealDay {
    static func fixture(
        date: String,
        menuName: String = "현미밥"
    ) -> RebuildMealDay {
        RebuildMealDay(
            date: date,
            menuItems: [
                RebuildMealItem(
                    name: menuName,
                    allergyCodes: [],
                    nutrients: [],
                    tags: [],
                    sourceRawText: menuName
                )
            ],
            calorie: "770 Kcal",
            nutrition: .empty
        )
    }
}

private final class RebuildMealMockURLProtocol: URLProtocol {
    static var requestHandler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

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
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
