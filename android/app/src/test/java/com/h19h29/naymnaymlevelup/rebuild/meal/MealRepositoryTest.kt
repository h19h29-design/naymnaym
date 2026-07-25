package com.h19h29.naymnaymlevelup.rebuild.meal

import com.h19h29.naymnaymlevelup.rebuild.data.MealDayDao
import com.h19h29.naymnaymlevelup.rebuild.data.MealDayEntity
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection
import java.net.URLStreamHandler
import java.time.Instant
import java.time.LocalDate
import java.util.concurrent.CountDownLatch
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MealRepositoryTest {
    @Test
    fun refreshFailureKeepsCachedMealVisible() = runTest {
        val meal = MealDay.fixture("2026-07-25")
        val store = FakeMealDayStore(listOf(meal))
        val client = FakeMealClient(Result.failure(IOException("offline")))
        val repository = MealRepository(store, client, backgroundScope)

        repository.refresh(LocalDate.parse("2026-07-25"), School.fixture)

        assertEquals(
            MealLoadState.Cached(meal, null),
            repository.currentState("2026-07-25"),
        )
        assertEquals(
            CachedMealDay(meal, refreshedAt = null, source = "fixture"),
            store.load("2026-07-25"),
        )
    }

    @Test
    fun observerImmediatelyEmitsCachedStateThenRefreshStates() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val cachedMeal = MealDay.fixture(date.toString(), menuName = "저장된 급식")
        val liveMeal = MealDay.fixture(date.toString(), menuName = "새 급식")
        val refreshedAt = Instant.parse("2026-07-25T01:00:00Z")
        val store = FakeMealDayStore(
            entries = listOf(CachedMealDay(cachedMeal, refreshedAt, "neis")),
        )
        val repository = MealRepository(
            store = store,
            client = FakeMealClient(Result.success(liveMeal)),
            scope = backgroundScope,
            now = { Instant.parse("2026-07-25T02:00:00Z") },
        )
        val states = async(start = CoroutineStart.UNDISPATCHED) {
            repository.observe(date).take(3).toList()
        }

        repository.refresh(date, School.fixture)

        assertEquals(
            listOf(
                MealLoadState.Cached(cachedMeal, refreshedAt),
                MealLoadState.Refreshing(cachedMeal),
                MealLoadState.Live(liveMeal),
            ),
            states.await(),
        )
    }

    @Test
    fun observerImmediatelyEmitsEmptyWithoutCache() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val repository = MealRepository(
            FakeMealDayStore(),
            FakeMealClient(Result.success(null)),
            backgroundScope,
        )

        assertEquals(MealLoadState.Empty, repository.observe(date).first())
    }

    @Test
    fun successfulRefreshPersistsMealForNewRepository() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val liveMeal = MealDay.fixture(date.toString())
        val refreshedAt = Instant.parse("2026-07-25T02:00:00Z")
        val store = FakeMealDayStore()
        val repository = MealRepository(
            store = store,
            client = FakeMealClient(Result.success(liveMeal)),
            scope = backgroundScope,
            now = { refreshedAt },
        )

        repository.refresh(date, School.fixture)

        assertEquals(MealLoadState.Live(liveMeal), repository.currentState(date.toString()))
        val restoredRepository = MealRepository(
            store,
            FakeMealClient(Result.success(null)),
            backgroundScope,
        )
        assertEquals(
            MealLoadState.Cached(liveMeal, refreshedAt),
            restoredRepository.currentState(date.toString()),
        )
    }

    @Test
    fun authoritativeNoMealResponseRemovesStaleCache() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val store = FakeMealDayStore(listOf(MealDay.fixture(date.toString())))
        val repository = MealRepository(
            store,
            FakeMealClient(Result.success(null)),
            backgroundScope,
        )

        repository.refresh(date, School.fixture)

        assertEquals(MealLoadState.Empty, repository.currentState(date.toString()))
        assertNull(store.load(date.toString()))
    }

    @Test
    fun refreshFailureWithoutCacheBecomesFailed() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val repository = MealRepository(
            FakeMealDayStore(),
            FakeMealClient(Result.failure(IOException("offline"))),
            backgroundScope,
        )

        repository.refresh(date, School.fixture)

        val state = repository.currentState(date.toString())
        assertTrue(state is MealLoadState.Failed)
        state as MealLoadState.Failed
        assertTrue(state.message.contains("offline"))
        assertNull(state.cached)
    }

    @Test
    fun staleRefreshCompletionsCannotReplaceNewerStateOrCache() = runTest {
        val staleMeal = MealDay.fixture("2026-07-25", menuName = "이전 급식")
        val cases = listOf(
            StaleCompletionCase("stale meal", Result.success(staleMeal)),
            StaleCompletionCase("stale no-meal", Result.success(null)),
            StaleCompletionCase(
                "stale failure",
                Result.failure(IOException("offline")),
            ),
        )

        cases.forEach { testCase ->
            val date = LocalDate.parse("2026-07-25")
            val initialMeal = MealDay.fixture(date.toString(), menuName = "초기 캐시")
            val newerMeal = MealDay.fixture(date.toString(), menuName = "최신 급식")
            val refreshedAt = Instant.parse("2026-07-25T02:00:00Z")
            val store = FakeMealDayStore(listOf(initialMeal))
            val client = ControlledMealClient()
            val repository = MealRepository(
                store = store,
                client = client,
                scope = backgroundScope,
                now = { refreshedAt },
            )

            val olderRefresh = async { repository.refresh(date, School.fixture) }
            val olderRequest = client.awaitRequest()
            val newerRefresh = async { repository.refresh(date, School.fixture) }
            val newerRequest = client.awaitRequest()

            newerRequest.complete(Result.success(newerMeal))
            newerRefresh.await()
            olderRequest.complete(testCase.result)
            olderRefresh.await()

            assertEquals(
                testCase.name,
                MealLoadState.Live(newerMeal),
                repository.currentState(date.toString()),
            )
            assertEquals(
                testCase.name,
                CachedMealDay(newerMeal, refreshedAt, "neis"),
                store.load(date.toString()),
            )
        }
    }

    @Test
    fun neisClientBuildsRedactedRequestAndParsesMealFields() = runTest {
        var requestedUrl: URL? = null
        val logs = mutableListOf<String>()
        val response = """
            {
              "mealServiceDietInfo": [
                {"head": [{"list_total_count": 1}]},
                {"row": [{
                  "MLSV_YMD": "20260725",
                  "DDISH_NM": "현미밥<br/>닭갈비 (5.6.13.15)<br>우유 (2)",
                  "CAL_INFO": "770.7 Kcal",
                  "NTR_INFO": "탄수화물(g) : 95.9<br/>단백질(g) : 42.3<br/>지방(g) : 25.1<br/>칼슘(mg) : 152.2<br/>철분(mg) : 3.7<br/>비타민 : 12"
                }]}
              ]
            }
        """.trimIndent()
        val client = NeisMealClient(
            apiKey = "test-secret",
            transport = NeisTransport { url ->
                requestedUrl = url
                response.toByteArray()
            },
            logger = logs::add,
        )

        val meal = client.fetch("2026-07-25", School.fixture)

        val url = requireNotNull(requestedUrl)
        assertEquals("/hub/mealServiceDietInfo", url.path)
        assertTrue(url.query.contains("KEY=test-secret"))
        assertTrue(url.query.contains("ATPT_OFCDC_SC_CODE=B10"))
        assertTrue(url.query.contains("SD_SCHUL_CODE=7010700"))
        assertTrue(url.query.contains("MMEAL_SC_CODE=2"))
        assertTrue(url.query.contains("MLSV_FROM_YMD=20260725"))
        assertTrue(url.query.contains("MLSV_TO_YMD=20260725"))
        assertTrue(logs.single().contains("KEY=<redacted>"))
        assertFalse(logs.single().contains("test-secret"))
        assertEquals("2026-07-25", meal?.date)
        assertEquals(listOf("현미밥", "닭갈비", "우유"), meal?.menuItems?.map { it.name })
        assertEquals(listOf(5, 6, 13, 15), meal?.menuItems?.get(1)?.allergyCodes)
        assertEquals(42.3, meal?.nutrition?.protein ?: 0.0, 0.01)
        assertEquals(152.2, meal?.nutrition?.calcium ?: 0.0, 0.01)
        assertEquals(3.7, meal?.nutrition?.iron ?: 0.0, 0.01)
        assertEquals("770.7 Kcal", meal?.calorie)
    }

    @Test
    fun neisClientReturnsNullForNoDataResult() = runTest {
        val client = NeisMealClient(
            apiKey = "test-secret",
            transport = NeisTransport {
                """{"RESULT":{"CODE":"INFO-200","MESSAGE":"해당하는 데이터가 없습니다."}}"""
                    .toByteArray()
            },
            logger = {},
        )

        assertNull(client.fetch("2026-07-25", School.fixture))
    }

    @Test
    fun neisClientRejectsImpossibleCalendarDateBeforeTransport() = runTest {
        var transportCalled = false
        val client = NeisMealClient(
            apiKey = "test-secret",
            transport = NeisTransport {
                transportCalled = true
                ByteArray(0)
            },
            logger = {},
        )

        try {
            client.fetch("2026-02-30", School.fixture)
            fail("Expected an invalid-date failure")
        } catch (error: NeisMealClientException.InvalidDate) {
            assertEquals("2026-02-30", error.value)
        }
        assertFalse(transportCalled)
    }

    @Test
    fun presentMealContainersWithWrongTypesAreMalformed() = runTest {
        val malformedResponses = listOf(
            """{"mealServiceDietInfo":{"row":[]}}""",
            """{"mealServiceDietInfo":[{"row":{"MLSV_YMD":"20260725"}}]}""",
        )

        malformedResponses.forEach { response ->
            val client = NeisMealClient(
                apiKey = "test-secret",
                transport = NeisTransport { response.toByteArray() },
                logger = {},
            )
            try {
                client.fetch("2026-07-25", School.fixture)
                fail("Expected malformed response for $response")
            } catch (_: NeisMealClientException.MalformedResponse) {
                // Expected.
            }
        }
    }

    @Test
    fun malformedNeisResponsePreservesValidCache() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val cachedMeal = MealDay.fixture(date.toString(), "저장된 급식")
        val store = FakeMealDayStore(listOf(cachedMeal))
        val client = NeisMealClient(
            apiKey = "test-secret",
            transport = NeisTransport {
                """{"mealServiceDietInfo":{"row":[]}}""".toByteArray()
            },
            logger = {},
        )
        val repository = MealRepository(store, client, backgroundScope)

        repository.refresh(date, School.fixture)

        assertEquals(
            MealLoadState.Cached(cachedMeal, refreshedAt = null),
            repository.currentState(date.toString()),
        )
        assertEquals(
            CachedMealDay(cachedMeal, refreshedAt = null, source = "fixture"),
            store.load(date.toString()),
        )
    }

    @Test
    fun roomStoreRoundTripsMealPayloadAndEvictsByDate() = runTest {
        val dao = FakeRoomMealDayDao()
        val store = RoomMealDayStore(dao)
        val fetchedAt = Instant.parse("2026-07-25T02:00:00Z")
        val meal = MealDay(
            date = "2026-07-25",
            menuItems = listOf(
                MealItem(
                    name = "닭갈비",
                    allergyCodes = listOf(5, 6, 13, 15),
                    nutrients = listOf("단백질"),
                    tags = listOf("성장"),
                    sourceRawText = "닭갈비 (5.6.13.15)",
                ),
            ),
            calorie = "770.7 Kcal",
            nutrition = NutritionInfo(
                carbs = 95.9,
                protein = 42.3,
                fat = 25.1,
                calcium = 152.2,
                iron = 3.7,
                vitamin = 12.0,
            ),
        )

        store.save(meal, fetchedAt, "neis")

        assertEquals(
            CachedMealDay(meal, fetchedAt, "neis"),
            store.load("2026-07-25"),
        )

        store.remove("2026-07-25")

        assertNull(store.load("2026-07-25"))
    }

    @Test
    fun successfulRefreshReplacesCorruptRoomCache() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val liveMeal = MealDay.fixture(date.toString(), "새 급식")
        val refreshedAt = Instant.parse("2026-07-25T02:00:00Z")
        val dao = FakeRoomMealDayDao()
        dao.upsert(
            MealDayEntity(
                date = date.toString(),
                payloadJson = "{",
                fetchedAtEpochMillis = 1L,
                source = "corrupt",
            ),
        )
        val store = RoomMealDayStore(dao)
        val repository = MealRepository(
            store = store,
            client = FakeMealClient(Result.success(liveMeal)),
            scope = backgroundScope,
            now = { refreshedAt },
        )

        repository.refresh(date, School.fixture)

        assertEquals(
            MealLoadState.Live(liveMeal),
            repository.currentState(date.toString()),
        )
        assertEquals(
            CachedMealDay(liveMeal, refreshedAt, "neis"),
            store.load(date.toString()),
        )
    }

    @Test
    fun networkFailureAfterCorruptCacheLoadStaysFailedAndKeepsRow() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val corruptEntity = MealDayEntity(
            date = date.toString(),
            payloadJson = "{",
            fetchedAtEpochMillis = 1L,
            source = "corrupt",
        )
        val dao = FakeRoomMealDayDao()
        dao.upsert(corruptEntity)
        val repository = MealRepository(
            store = RoomMealDayStore(dao),
            client = FakeMealClient(Result.failure(IOException("offline"))),
            scope = backgroundScope,
        )

        repository.refresh(date, School.fixture)

        val state = repository.currentState(date.toString())
        assertTrue(state is MealLoadState.Failed)
        state as MealLoadState.Failed
        assertTrue(state.message.contains("offline"))
        assertNull(state.cached)
        assertEquals(corruptEntity, dao.observe(date.toString()).first())
    }

    @Test
    fun cancellingHttpTransportDisconnectsBlockedConnectionPromptly() = runTest {
        val connection = BlockingHttpURLConnection(URL("https://example.test"))
        val url = URL(
            null,
            "test://meal",
            object : URLStreamHandler() {
                override fun openConnection(url: URL): URLConnection =
                    connection
            },
        )
        val request = launch {
            HttpUrlConnectionNeisTransport().get(url)
        }
        connection.awaitReadStarted()

        request.cancel()
        val disconnectedOnCancellation = connection.disconnectCount > 0
        if (!disconnectedOnCancellation) {
            connection.forceRelease()
        }
        request.join()

        assertTrue(
            "Cancellation must disconnect the active connection immediately",
            disconnectedOnCancellation,
        )
    }

    @Test
    fun suspendedCacheReadForOneDateDoesNotBlockAnotherDate() = runTest {
        val blockedDate = "2026-07-25"
        val store = BlockingLoadMealDayStore(blockedDate)
        val repository = MealRepository(
            store,
            FakeMealClient(Result.success(null)),
            backgroundScope,
        )
        val blockedRead = async {
            repository.currentState(blockedDate)
        }
        store.awaitBlockedLoad()

        val otherState = withTimeout(1_000) {
            repository.currentState("2026-07-26")
        }

        assertEquals(MealLoadState.Empty, otherState)
        store.releaseBlockedLoad()
        assertEquals(MealLoadState.Empty, blockedRead.await())
    }

    @Test
    fun cancellingCurrentRefreshRestoresCachedState() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val cachedMeal = MealDay.fixture(date.toString(), "저장된 급식")
        val client = ControlledMealClient()
        val repository = MealRepository(
            FakeMealDayStore(listOf(cachedMeal)),
            client,
            backgroundScope,
        )
        val refresh = launch {
            repository.refresh(date, School.fixture)
        }
        client.awaitRequest()
        assertEquals(
            MealLoadState.Refreshing(cachedMeal),
            repository.currentState(date.toString()),
        )

        refresh.cancelAndJoin()

        assertEquals(
            MealLoadState.Cached(cachedMeal, refreshedAt = null),
            repository.currentState(date.toString()),
        )
    }

    @Test
    fun cancellingCurrentRefreshWithoutCacheBecomesEmpty() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val client = ControlledMealClient()
        val repository = MealRepository(
            FakeMealDayStore(),
            client,
            backgroundScope,
        )
        val refresh = launch {
            repository.refresh(date, School.fixture)
        }
        client.awaitRequest()
        assertEquals(
            MealLoadState.Refreshing(cached = null),
            repository.currentState(date.toString()),
        )

        refresh.cancelAndJoin()

        assertEquals(
            MealLoadState.Empty,
            repository.currentState(date.toString()),
        )
    }

    @Test
    fun cancellationAfterStoreMutationReconcilesPersistedMeal() = runTest {
        val date = LocalDate.parse("2026-07-25")
        val cachedMeal = MealDay.fixture(date.toString(), "저장된 급식")
        val liveMeal = MealDay.fixture(date.toString(), "새 급식")
        val refreshedAt = Instant.parse("2026-07-25T02:00:00Z")
        val store = PersistThenBlockMealDayStore(cachedMeal)
        val repository = MealRepository(
            store = store,
            client = FakeMealClient(Result.success(liveMeal)),
            scope = backgroundScope,
            now = { refreshedAt },
        )
        val refresh = launch {
            repository.refresh(date, School.fixture)
        }
        store.awaitSaveMutation()
        assertEquals(
            MealLoadState.Refreshing(cachedMeal),
            repository.currentState(date.toString()),
        )

        refresh.cancelAndJoin()

        assertEquals(
            MealLoadState.Cached(liveMeal, refreshedAt),
            repository.currentState(date.toString()),
        )
    }
}

private class FakeMealDayStore(
    meals: List<MealDay> = emptyList(),
    entries: List<CachedMealDay> = meals.map {
        CachedMealDay(it, refreshedAt = null, source = "fixture")
    },
) : MealDayStore {
    private val entries = entries.associateByTo(mutableMapOf()) { it.meal.date }

    override suspend fun load(date: String): CachedMealDay? = entries[date]

    override suspend fun save(
        meal: MealDay,
        refreshedAt: Instant,
        source: String,
    ) {
        entries[meal.date] = CachedMealDay(meal, refreshedAt, source)
    }

    override suspend fun remove(date: String) {
        entries.remove(date)
    }
}

private class FakeMealClient(
    private val result: Result<MealDay?>,
) : MealClient {
    override suspend fun fetch(date: LocalDate, school: School): MealDay? =
        result.getOrThrow()
}

private data class StaleCompletionCase(
    val name: String,
    val result: Result<MealDay?>,
)

private class ControlledMealClient : MealClient {
    class PendingRequest internal constructor(
        private val continuation:
            kotlinx.coroutines.CancellableContinuation<MealDay?>,
    ) {
        fun complete(result: Result<MealDay?>) {
            continuation.resumeWith(result)
        }
    }

    private val requests = Channel<PendingRequest>(Channel.UNLIMITED)

    override suspend fun fetch(date: LocalDate, school: School): MealDay? =
        suspendCancellableCoroutine { continuation ->
            check(requests.trySend(PendingRequest(continuation)).isSuccess)
        }

    suspend fun awaitRequest(): PendingRequest = requests.receive()
}

private class FakeRoomMealDayDao : MealDayDao {
    private val rows = mutableMapOf<String, MutableStateFlow<MealDayEntity?>>()

    override fun observe(date: String): Flow<MealDayEntity?> =
        rows.getOrPut(date) { MutableStateFlow(null) }

    override suspend fun upsert(mealDay: MealDayEntity) {
        rows.getOrPut(mealDay.date) { MutableStateFlow(null) }.value = mealDay
    }

    override suspend fun delete(date: String) {
        rows.getOrPut(date) { MutableStateFlow(null) }.value = null
    }
}

private class BlockingLoadMealDayStore(
    private val blockedDate: String,
) : MealDayStore {
    private val loadStarted = CompletableDeferred<Unit>()
    private val releaseLoad = CompletableDeferred<Unit>()

    override suspend fun load(date: String): CachedMealDay? {
        if (date == blockedDate) {
            loadStarted.complete(Unit)
            releaseLoad.await()
        }
        return null
    }

    override suspend fun save(
        meal: MealDay,
        refreshedAt: Instant,
        source: String,
    ) = Unit

    override suspend fun remove(date: String) = Unit

    suspend fun awaitBlockedLoad() {
        loadStarted.await()
    }

    fun releaseBlockedLoad() {
        releaseLoad.complete(Unit)
    }
}

private class PersistThenBlockMealDayStore(
    meal: MealDay,
) : MealDayStore {
    private var entry: CachedMealDay? = CachedMealDay(
        meal = meal,
        refreshedAt = null,
        source = "fixture",
    )
    private val saveMutated = CompletableDeferred<Unit>()

    override suspend fun load(date: String): CachedMealDay? = entry

    override suspend fun save(
        meal: MealDay,
        refreshedAt: Instant,
        source: String,
    ) {
        entry = CachedMealDay(meal, refreshedAt, source)
        saveMutated.complete(Unit)
        awaitCancellation()
    }

    override suspend fun remove(date: String) {
        entry = null
    }

    suspend fun awaitSaveMutation() {
        saveMutated.await()
    }
}

private class BlockingHttpURLConnection(
    url: URL,
) : HttpURLConnection(url) {
    private val readStarted = CompletableDeferred<Unit>()
    private val releaseRead = CountDownLatch(1)

    @Volatile
    var disconnectCount: Int = 0
        private set

    override fun connect() = Unit

    override fun disconnect() {
        disconnectCount += 1
        releaseRead.countDown()
    }

    override fun usingProxy(): Boolean = false

    override fun getResponseCode(): Int = HTTP_OK

    override fun getInputStream(): InputStream = object : InputStream() {
        override fun read(): Int {
            readStarted.complete(Unit)
            releaseRead.await()
            return -1
        }
    }

    suspend fun awaitReadStarted() {
        readStarted.await()
    }

    fun forceRelease() {
        releaseRead.countDown()
    }
}

private val School.Companion.fixture: School
    get() = School(
        name = "등촌고등학교",
        officeCode = "B10",
        schoolCode = "7010700",
    )

private fun MealDay.Companion.fixture(
    date: String,
    menuName: String = "현미밥",
): MealDay = MealDay(
    date = date,
    menuItems = listOf(
        MealItem(
            name = menuName,
            allergyCodes = emptyList(),
            nutrients = emptyList(),
            tags = emptyList(),
            sourceRawText = menuName,
        ),
    ),
    calorie = "770 Kcal",
    nutrition = NutritionInfo.empty,
)
