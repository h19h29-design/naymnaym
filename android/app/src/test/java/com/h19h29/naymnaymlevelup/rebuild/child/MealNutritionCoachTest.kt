package com.h19h29.naymnaymlevelup.rebuild.child

import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionInfo
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionRuleEngine
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection
import java.net.URLStreamHandler
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MealNutritionCoachTest {
    private val rules by lazy {
        NutritionRuleEngine(contractBytes("nutrition-rules.json"))
    }

    @Test
    fun requestNormalizesCanonicalAndRuleNutrientsInContractOrder() {
        val meal = meal(
            date = "2026-09-14",
            items = listOf(
                item("시금치나물", nutrients = listOf("PROTEIN", "탄수화물")),
                item("우유", nutrients = listOf("calcium", "unknown")),
            ),
        )

        val request = MealCoachRequestFactory(rules).create(
            question = MealCoachQuestion.Overview,
            meal = meal,
            selectedMenuIndices = setOf(0, 1),
            sessionId = "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )

        assertEquals(
            listOf("protein", "calcium", "carbohydrate"),
            request.nutrients,
        )
    }

    @Test
    fun requestJsonContainsOnlyAnonymousContractFieldsAndWholeMealNumbers() {
        val meal = meal(
            date = "2026-09-14",
            items = listOf(
                item("현미밥", allergyCodes = listOf(1, 2)),
            ),
            nutrition = NutritionInfo(
                carbs = 88.4,
                protein = 22.0,
                fat = 12.5,
                calcium = 100.0,
                iron = 2.0,
                vitamin = 3.0,
            ),
        )
        val request = MealCoachRequestFactory(rules).create(
            MealCoachQuestion.Benefits,
            meal,
            setOf(0),
            "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )

        val root = JSONObject(MealCoachJson.encodeRequest(request))

        assertEquals(
            setOf("question", "nutrients", "wholeMeal", "sessionId"),
            root.keys().asSequence().toSet(),
        )
        assertEquals(
            setOf("protein", "carbs", "fat"),
            root.getJSONObject("wholeMeal").keys().asSequence().toSet(),
        )
        assertEquals("benefits", root.getString("question"))
        assertFalse(root.toString().contains("현미밥"))
        assertFalse(root.toString().contains("2026-09-14"))
        assertFalse(root.toString().contains("allergy", ignoreCase = true))
        assertFalse(root.toString().contains("school", ignoreCase = true))
        assertFalse(root.toString().contains("record", ignoreCase = true))
    }

    @Test
    fun requestOmitsZeroNegativeAndNonFiniteWholeMealNumbers() {
        val meal = meal(
            nutrition = NutritionInfo(
                carbs = Double.NaN,
                protein = 0.0,
                fat = -3.0,
                calcium = 0.0,
                iron = 0.0,
                vitamin = 0.0,
            ),
        )

        val request = MealCoachRequestFactory(rules).create(
            MealCoachQuestion.Omission,
            meal,
            setOf(0),
            "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )

        assertEquals(
            0,
            JSONObject(MealCoachJson.encodeRequest(request)).getJSONObject("wholeMeal").length(),
        )
    }

    @Test
    fun requestOmitsWholeMealNumbersWhenOnlySomeMenusAreSelected() {
        val meal = meal(
            items = listOf(item("현미밥"), item("두부조림")),
            nutrition = NutritionInfo(
                carbs = 88.4,
                protein = 22.0,
                fat = 12.5,
                calcium = 0.0,
                iron = 0.0,
                vitamin = 0.0,
            ),
        )

        val request = MealCoachRequestFactory(rules).create(
            MealCoachQuestion.Overview,
            meal,
            setOf(0),
            "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )

        assertEquals(MealCoachWholeMeal(), request.wholeMeal)
        assertEquals(
            0,
            JSONObject(MealCoachJson.encodeRequest(request)).getJSONObject("wholeMeal").length(),
        )
    }

    @Test
    fun overviewLabelAndConsentCopyExplainTheActualAnonymousPayload() {
        assertEquals("이 식단 어때?", MealCoachQuestion.Overview.title(isWholeMealSelected = true))
        assertEquals("이 메뉴 어때?", MealCoachQuestion.Overview.title(isWholeMealSelected = false))
        listOf(
            "선택한 질문 종류",
            "대표 영양소 ID",
            "전체 급식 수치",
            "임시 세션 ID",
            "메뉴 이름",
            "식사 기록",
            "알레르기",
        ).forEach { phrase ->
            assertTrue(MEAL_COACH_CONSENT_COPY.contains(phrase))
        }
    }

    @Test
    fun responseRequiresExactKeysAiSourceAndBoundedNonBlankStrings() {
        val valid = """{
          "source":"ai",
          "summary":"균형을 살펴봤어요.",
          "benefit":"여러 영양소를 공급받을 수 있어요.",
          "caution":"정확한 섭취량은 알 수 없어요.",
          "tip":"천천히 살펴봐요."
        }""".trimIndent().encodeToByteArray()

        assertEquals("균형을 살펴봤어요.", MealCoachJson.decodeResponse(valid).summary)

        val invalid = listOf(
            valid.decodeToString().replace("\"source\":\"ai\",", ""),
            valid.decodeToString().replace("\"source\":\"ai\"", "\"source\":\"local\""),
            valid.decodeToString().replace("\"tip\":\"천천히 살펴봐요.\"", "\"tip\":\"천천히 살펴봐요.\",\"extra\":true"),
            valid.decodeToString().replace("\"summary\":\"균형을 살펴봤어요.\"", "\"summary\":\"   \""),
            valid.decodeToString().replace("균형을 살펴봤어요.", "가".repeat(241)),
        )
        invalid.forEach { raw ->
            assertThrows(MealCoachProtocolException::class.java) {
                MealCoachJson.decodeResponse(raw.encodeToByteArray())
            }
        }
    }

    @Test
    fun responseRejectsBodiesLargerThanSixteenKilobytes() {
        assertThrows(MealCoachProtocolException.ResponseTooLarge::class.java) {
            MealCoachJson.decodeResponse(ByteArray(16 * 1024 + 1))
        }
    }

    @Test
    fun httpTransportUsesPostBearerJsonTimeoutsAndNoRedirects() = runTest {
        val connection = RecordingMealCoachConnection(
            URL("http://127.0.0.1:64918/v1/meal-coach"),
        )
        val url = testUrl(connection)

        val response = HttpUrlConnectionMealCoachTransport().post(
            endpoint = url,
            accessToken = "s".repeat(32),
            body = "{}".encodeToByteArray(),
        )

        assertEquals("POST", connection.requestMethod)
        assertEquals(15_000, connection.connectTimeout)
        assertEquals(15_000, connection.readTimeout)
        assertFalse(connection.instanceFollowRedirects)
        assertEquals("Bearer ${"s".repeat(32)}", connection.getRequestProperty("Authorization"))
        assertEquals("application/json", connection.getRequestProperty("Content-Type"))
        assertEquals("{}", connection.written.toString(Charsets.UTF_8.name()))
        assertTrue(connection.disconnected)
        assertEquals("ai", MealCoachJson.decodeResponse(response).source)
    }

    @Test
    fun cancellingHttpTransportDisconnectsTheActiveRequest() = runTest {
        val connection = BlockingMealCoachConnection(
            URL("http://127.0.0.1:64918/v1/meal-coach"),
        )
        val request = backgroundScope.launch(Dispatchers.Default) {
            HttpUrlConnectionMealCoachTransport().post(
                endpoint = testUrl(connection),
                accessToken = "s".repeat(32),
                body = "{}".encodeToByteArray(),
            )
        }
        assertTrue(connection.readStarted.await(1, TimeUnit.SECONDS))

        request.cancel()
        assertTrue(connection.disconnected.await(1, TimeUnit.SECONDS))
        request.join()

        assertTrue(request.isCancelled)
    }

    @Test
    fun developmentConfigIsDebugOnlyAndAcceptsOnlyExactLoopbackRoutes() {
        val directory = createTempDirectory("meal-coach-config").toFile()
        val file = File(directory, "meal-coach-development.json")
        file.writeText(
            """{"endpoint":"http://10.0.2.2:64918/v1/meal-coach","accessToken":"${"t".repeat(32)}"}""",
        )

        assertNull(MealCoachDevelopmentConfig.load(directory, isDebug = false))
        assertEquals(
            "http://10.0.2.2:64918/v1/meal-coach",
            MealCoachDevelopmentConfig.load(directory, isDebug = true)?.endpoint?.toString(),
        )

        listOf(
            "http://10.0.2.2:64918/v1/other",
            "http://localhost:64918/v1/meal-coach",
            "https://10.0.2.2:64918/v1/meal-coach",
        ).forEach { endpoint ->
            file.writeText(
                """{"endpoint":"$endpoint","accessToken":"${"t".repeat(32)}"}""",
            )
            assertNull(MealCoachDevelopmentConfig.load(directory, isDebug = true))
        }
        file.writeText(
            """{"endpoint":"http://127.0.0.1:64918/v1/meal-coach","accessToken":"short"}""",
        )
        assertNull(MealCoachDevelopmentConfig.load(directory, isDebug = true))
        file.writeBytes(ByteArray(4_097) { 'x'.code.toByte() })
        assertNull(MealCoachDevelopmentConfig.load(directory, isDebug = true))
        directory.deleteRecursively()
    }

    @Test
    fun aiQuestionRequiresConsentAndAllergyRiskStaysLocal() = runTest {
        val client = RecordingMealCoachClient()
        val session = MealCoachSession(
            initialMeal = meal(items = listOf(item("우유", allergyCodes = listOf(7)))),
            rules = rules,
            client = client,
            scope = backgroundScope,
            sessionId = "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )
        session.setUseAi(true)

        session.ask(MealCoachQuestion.Benefits, registeredAllergyCodes = listOf(7))
        assertEquals(0, client.requests.size)
        assertEquals(MealCoachAnswerSource.Local, session.state.value.answer?.source)
        assertTrue(session.state.value.answer?.caution.orEmpty().contains("먹도록 권하지"))
        assertTrue(session.state.value.answer?.summary.orEmpty().contains("먹도록 권하지"))
        assertFalse(session.state.value.answer?.summary.orEmpty().contains("안전한"))

        session.ask(MealCoachQuestion.Omission, registeredAllergyCodes = listOf(7))
        assertFalse(session.state.value.answer?.tip.orEmpty().contains("안전한"))
        assertTrue(session.state.value.answer?.tip.orEmpty().contains("보호자나 선생님"))

        session.bindMeal(meal(date = "2026-09-15", items = listOf(item("두부"))))
        session.setUseAi(true)
        session.ask(MealCoachQuestion.Benefits, registeredAllergyCodes = emptyList())
        assertEquals(0, client.requests.size)
        assertTrue(session.state.value.notice.orEmpty().contains("동의"))

        session.setConsent(true)
        session.ask(MealCoachQuestion.Benefits, registeredAllergyCodes = emptyList())
        assertEquals(1, client.requests.size)
    }

    @Test
    fun changingSelectedMealCancelsInflightAnswerAndRestoresAllMenuSelections() = runTest {
        val client = BlockingMealCoachClient()
        val session = MealCoachSession(
            initialMeal = meal(
                date = "2026-09-14",
                items = listOf(item("밥"), item("나물")),
            ),
            rules = rules,
            client = client,
            scope = backgroundScope,
            sessionId = "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )
        session.toggleMenu(1)
        session.setUseAi(true)
        session.setConsent(true)
        session.ask(MealCoachQuestion.Overview, registeredAllergyCodes = emptyList())
        client.started.await()

        session.bindMeal(
            meal(
                date = "2026-09-15",
                items = listOf(item("국"), item("두부"), item("김치")),
            ),
        )

        assertTrue(client.cancelled.await())
        assertEquals(setOf(0, 1, 2), session.state.value.selectedMenuIndices)
        assertNull(session.state.value.answer)
        assertFalse(session.state.value.isLoading)
    }

    @Test
    fun changingConsentCancelsInflightAnswerAndClearsResult() = runTest {
        val client = BlockingMealCoachClient()
        val session = MealCoachSession(
            initialMeal = meal(items = listOf(item("두부"))),
            rules = rules,
            client = client,
            scope = backgroundScope,
            sessionId = "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )
        session.setUseAi(true)
        session.setConsent(true)
        session.ask(MealCoachQuestion.Overview, registeredAllergyCodes = emptyList())
        client.started.await()

        session.setConsent(false)

        assertTrue(client.cancelled.await())
        assertNull(session.state.value.answer)
        assertFalse(session.state.value.isLoading)
        assertFalse(session.state.value.aiConnected)
    }

    @Test
    fun changingRegisteredAllergiesCancelsInflightAnswerAndClearsResult() = runTest {
        val client = BlockingMealCoachClient()
        val session = MealCoachSession(
            initialMeal = meal(items = listOf(item("두부"))),
            rules = rules,
            client = client,
            scope = backgroundScope,
            sessionId = "9b0a70a3-89f2-4c81-a87e-87a2df675ee2",
        )
        session.setUseAi(true)
        session.setConsent(true)
        session.ask(MealCoachQuestion.Overview, registeredAllergyCodes = emptyList())
        client.started.await()

        session.bindRegisteredAllergyCodes(listOf(5))

        assertTrue(client.cancelled.await())
        assertNull(session.state.value.answer)
        assertFalse(session.state.value.isLoading)
        assertFalse(session.state.value.aiConnected)
    }

    private fun contractBytes(name: String): ByteArray {
        val candidates = listOf(
            File("src/main/assets/rebuild-contracts/$name"),
            File("app/src/main/assets/rebuild-contracts/$name"),
        )
        return candidates.firstOrNull(File::isFile)?.readBytes()
            ?: throw AssertionError("Missing bundled contract $name")
    }

    private fun meal(
        date: String = "2026-09-14",
        items: List<MealItem> = listOf(item("현미밥")),
        nutrition: NutritionInfo = NutritionInfo.empty,
    ) = MealDay(date, items, "700 Kcal", nutrition)

    private fun item(
        name: String,
        nutrients: List<String> = emptyList(),
        allergyCodes: List<Int> = emptyList(),
    ) = MealItem(name, allergyCodes, nutrients, emptyList(), name)

    private fun testUrl(connection: URLConnection): URL = URL(
        null,
        "test://meal-coach",
        object : URLStreamHandler() {
            override fun openConnection(url: URL): URLConnection = connection
        },
    )
}

private class RecordingMealCoachClient : MealCoachClient {
    val requests = mutableListOf<MealCoachRequest>()

    override suspend fun ask(request: MealCoachRequest): MealCoachResponse {
        requests += request
        return MealCoachResponse("ai", "요약", "도움", "주의", "팁")
    }
}

private class BlockingMealCoachClient : MealCoachClient {
    val started = CompletableDeferred<Unit>()
    val cancelled = CompletableDeferred<Boolean>()

    override suspend fun ask(request: MealCoachRequest): MealCoachResponse {
        started.complete(Unit)
        try {
            CompletableDeferred<Unit>().await()
        } finally {
            cancelled.complete(true)
        }
        error("unreachable")
    }
}

private open class RecordingMealCoachConnection(url: URL) : HttpURLConnection(url) {
    val written = ByteArrayOutputStream()
    var disconnected = false

    override fun connect() = Unit
    override fun disconnect() {
        disconnected = true
    }
    override fun usingProxy(): Boolean = false
    override fun getOutputStream() = written
    override fun getResponseCode(): Int = HTTP_OK
    override fun getInputStream(): InputStream = ByteArrayInputStream(
        """{"source":"ai","summary":"요약","benefit":"도움","caution":"주의","tip":"팁"}"""
            .encodeToByteArray(),
    )
}

private class BlockingMealCoachConnection(url: URL) : HttpURLConnection(url) {
    val readStarted = CountDownLatch(1)
    val disconnected = CountDownLatch(1)
    private val release = CountDownLatch(1)

    override fun connect() = Unit
    override fun disconnect() {
        disconnected.countDown()
        release.countDown()
    }
    override fun usingProxy(): Boolean = false
    override fun getOutputStream() = ByteArrayOutputStream()
    override fun getResponseCode(): Int = HTTP_OK
    override fun getInputStream(): InputStream = object : InputStream() {
        override fun read(): Int {
            readStarted.countDown()
            release.await()
            return -1
        }
    }
}
