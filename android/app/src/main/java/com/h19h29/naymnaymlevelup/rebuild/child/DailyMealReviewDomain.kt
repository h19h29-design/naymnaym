package com.h19h29.naymnaymlevelup.rebuild.child

import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionRuleEngine
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class DailyMealReviewItem(
    val id: String,
    val nutrients: List<String>,
)

data class DailyMealReviewWholeMeal(
    val protein: Double? = null,
    val carbs: Double? = null,
    val fat: Double? = null,
)

data class DailyMealReviewRequest(
    val requestId: String,
    val sessionId: String,
    val items: List<DailyMealReviewItem>,
    val wholeMeal: DailyMealReviewWholeMeal,
)

data class DailyMealReviewHighlight(
    val itemId: String,
    val nutrient: String,
    val reason: String,
)

data class DailyMealReviewResponse(
    val source: String,
    val reviewId: String,
    val day: String,
    val generatedAt: String,
    val model: String,
    val policyVersion: String,
    val summary: String,
    val benefit: String,
    val highlights: List<DailyMealReviewHighlight>,
    val caution: String,
    val tip: String,
)

data class DailyMealReviewMenuSnapshot(
    val id: String,
    val name: String,
    val allergyCodes: List<Int>,
    val nutrients: List<String> = emptyList(),
)

data class SavedDailyMealReview(
    val profileKey: String,
    val schoolKey: String,
    val date: String,
    val mealType: String,
    val mealFingerprint: String,
    val menuSnapshot: List<DailyMealReviewMenuSnapshot>,
    val response: DailyMealReviewResponse,
    val requestId: String = response.reviewId,
    val wholeMeal: DailyMealReviewWholeMeal = DailyMealReviewWholeMeal(),
) {
    fun visibleHighlights(currentAllergyCodes: List<Int>): List<DailyMealReviewHighlight> {
        val current = currentAllergyCodes.toSet()
        return response.highlights.filter { highlight ->
            menuSnapshot.firstOrNull { it.id == highlight.itemId }
                ?.allergyCodes
                ?.none(current::contains) == true
        }
    }

    fun menuName(itemId: String): String? = menuSnapshot.firstOrNull { it.id == itemId }?.name
}

interface DailyMealReviewRepository {
    val deletionRevision: StateFlow<Long>? get() = null
    suspend fun load(profileKey: String, schoolKey: String, date: String): SavedDailyMealReview?
    suspend fun save(record: SavedDailyMealReview)
    suspend fun deleteAll()
}

fun interface DailyMealReviewClient {
    suspend fun generate(request: DailyMealReviewRequest): DailyMealReviewResponse
}

class DailyMealReviewRequestFactory(
    private val rules: NutritionRuleEngine,
) {
    fun create(
        meal: MealDay,
        registeredAllergyCodes: List<Int>,
        requestId: UUID,
        sessionId: UUID,
    ): DailyMealReviewRequest {
        require(requestId.version() == 4 && sessionId.version() == 4)
        require(meal.menuItems.size <= 30)
        val allergies = registeredAllergyCodes.toSet()
        val items = meal.menuItems.mapIndexedNotNull { index, item ->
            if (item.allergyCodes.any(allergies::contains)) return@mapIndexedNotNull null
            val discovered = (item.nutrients.mapNotNull(::normalizeNutrientId) +
                rules.insight(item.name).nutrients.map { it.id })
                .toSet()
            val nutrients = NUTRIENT_ORDER.filter(discovered::contains)
            nutrients.takeIf(List<String>::isNotEmpty)?.let {
                DailyMealReviewItem(id = "m$index", nutrients = it)
            }
        }
        return DailyMealReviewRequest(
            requestId = requestId.toString(),
            sessionId = sessionId.toString(),
            items = items,
            wholeMeal = dailyMealReviewWholeMeal(meal),
        )
    }

    companion object {
        val NUTRIENT_ORDER = listOf(
            "fiber", "vitamin", "protein", "iron", "calcium", "carbohydrate",
        )

        fun normalizeNutrientId(raw: String): String? =
            MealCoachRequestFactory.normalizeNutrientId(raw)
    }
}

fun dailyMealReviewWholeMeal(meal: MealDay): DailyMealReviewWholeMeal = DailyMealReviewWholeMeal(
    protein = meal.nutrition.protein.validWireAmount(),
    carbs = meal.nutrition.carbs.validWireAmount(),
    fat = meal.nutrition.fat.validWireAmount(),
)

private fun Double.validWireAmount(): Double? = takeIf { isFinite() && this > 0.0 && this <= 1_000.0 }

fun dailyMealReviewSourceLabel(source: String): String = when (source) {
    "ai" -> "AI가 생성한 영양 안내"
    else -> "기본 영양 안내"
}

fun dailyMealReviewNutrientRole(nutrient: String): String = when (nutrient) {
    "fiber" -> "식이섬유는 다양한 식재료를 경험하는 데 도움을 줘요."
    "vitamin" -> "비타민은 몸이 제 역할을 하는 데 필요한 영양소예요."
    "protein" -> "단백질은 몸을 이루는 재료로 쓰여요."
    "iron" -> "철분은 몸속에서 산소를 나르는 일을 도와요."
    "calcium" -> "칼슘은 뼈와 치아를 이루는 데 쓰여요."
    "carbohydrate" -> "탄수화물은 활동에 쓰이는 에너지원이에요."
    else -> "메뉴에서 확인된 대표 영양소예요."
}

fun dailyMealFingerprint(meal: MealDay): String {
    val value = buildString {
        append(meal.date)
        meal.menuItems.forEachIndexed { index, item ->
            append('|').append(index).append(':').append(item.name.trim())
            append(':').append(item.allergyCodes.sorted().joinToString(","))
            append(':').append(item.nutrients.sorted().joinToString(","))
        }
        append('|').append(meal.nutrition.protein)
        append('|').append(meal.nutrition.carbs)
        append('|').append(meal.nutrition.fat)
    }
    return MessageDigest.getInstance("SHA-256")
        .digest(value.encodeToByteArray())
        .joinToString("") { "%02x".format(Locale.ROOT, it) }
}

enum class DailyMealReviewError {
    PastOrFuture,
    NoMeal,
    NoCandidates,
    ConsentRequired,
    DailyUsed,
    RequestConflict,
    RecoveryUnavailable,
    InProgress,
    AttemptLimit,
    UsageLimit,
    StorageUnavailable,
    NotConfigured,
    AnswerUnavailable,
    Unauthorized,
    InvalidRequest,
    Network,
    Timeout,
    SaveFailed,
    CorruptRecord,
}

data class DailyMealReviewUiState(
    val isLoading: Boolean = false,
    val consent: Boolean = false,
    val record: SavedDailyMealReview? = null,
    val unsavedRecord: SavedDailyMealReview? = null,
    val error: DailyMealReviewError? = null,
    val notice: String? = null,
    val mealChangedSinceReview: Boolean = false,
    val generationAvailable: Boolean = false,
    val generationLockedForDay: Boolean = false,
)

class DailyMealReviewPendingRequestCache(
    private val maxEntries: Int = 16,
) {
    private data class Key(
        val profileKey: String,
        val schoolKey: String,
        val mealType: String,
        val date: String,
    )

    private data class Entry(
        val request: DailyMealReviewRequest,
        val createdAt: Instant,
    )

    private val entries = LinkedHashMap<Key, Entry>()

    init {
        require(maxEntries > 0)
    }

    @Synchronized
    internal fun recover(
        profileKey: String,
        schoolKey: String,
        mealType: String,
        date: String,
        at: Instant,
    ): DailyMealReviewRequest? {
        removeExpired(at)
        return entries[Key(profileKey, schoolKey, mealType, date)]?.request
    }

    @Synchronized
    internal fun retain(
        profileKey: String,
        schoolKey: String,
        mealType: String,
        date: String,
        request: DailyMealReviewRequest,
        at: Instant,
    ) {
        removeExpired(at)
        val key = Key(profileKey, schoolKey, mealType, date)
        val retainedAt = entries[key]
            ?.takeIf { it.request == request }
            ?.createdAt
            ?: at
        entries[key] = Entry(request, retainedAt)
        while (entries.size > maxEntries) {
            entries.entries.iterator().run {
                next()
                remove()
            }
        }
    }

    @Synchronized
    internal fun remove(
        profileKey: String,
        schoolKey: String,
        mealType: String,
        date: String,
        requestId: String? = null,
    ) {
        val key = Key(profileKey, schoolKey, mealType, date)
        if (requestId == null || entries[key]?.request?.requestId == requestId) entries.remove(key)
    }

    private fun removeExpired(at: Instant) {
        entries.entries.removeAll { (_, entry) -> at.isAfter(entry.createdAt.plusSeconds(90)) }
    }
}

private val processDailyMealReviewPendingRequests = DailyMealReviewPendingRequestCache()

class DailyMealReviewSession(
    private val profileKey: String,
    private val schoolKey: String,
    private val mealType: String,
    private val meal: MealDay,
    private val registeredAllergyCodes: List<Int>,
    private val store: DailyMealReviewRepository,
    private val client: DailyMealReviewClient?,
    private val rules: NutritionRuleEngine,
    private val today: () -> LocalDate = { LocalDate.now(ZoneId.of("Asia/Seoul")) },
    private val now: () -> Instant = Instant::now,
    private val sessionId: UUID = UUID.randomUUID(),
    private val pendingRequestCache: DailyMealReviewPendingRequestCache = processDailyMealReviewPendingRequests,
) {
    private val mutableState = MutableStateFlow(DailyMealReviewUiState())
    val state: StateFlow<DailyMealReviewUiState> = mutableState.asStateFlow()
    private var loaded = false

    suspend fun load() {
        if (loaded) return
        val saved = try {
            store.load(profileKey, schoolKey, meal.date)
        } catch (_: DailyMealReviewCorruptRecordException) {
            mutableState.value = mutableState.value.copy(
                error = DailyMealReviewError.CorruptRecord,
                notice = "저장된 AI 평가를 읽을 수 없어요.",
            )
            loaded = true
            return
        }
        loaded = true
        if (saved != null) removePending(saved.requestId)
        mutableState.value = mutableState.value.copy(
            record = saved,
            unsavedRecord = null,
            error = null,
            notice = if (saved == null && LocalDate.parse(meal.date) != today()) {
                "저장된 AI 평가가 없어요."
            } else {
                null
            },
            mealChangedSinceReview = meal.menuItems.isNotEmpty() &&
                saved?.mealFingerprint?.let { it != dailyMealFingerprint(meal) } == true,
            generationAvailable = saved == null &&
                runCatching { LocalDate.parse(meal.date) == today() }.getOrDefault(false) &&
                meal.menuItems.isNotEmpty(),
        )
    }

    suspend fun reload() {
        loaded = false
        load()
    }

    fun setConsent(value: Boolean) {
        mutableState.value = mutableState.value.copy(consent = value, error = null, notice = null)
    }

    suspend fun generate() {
        if (!loaded) load()
        val state = mutableState.value
        if (state.record != null || state.isLoading) return
        if (state.generationLockedForDay) return
        state.unsavedRecord?.let {
            retrySave()
            return
        }
        val mealDate = runCatching { LocalDate.parse(meal.date) }.getOrNull()
        if (mealDate == null || mealDate != today()) {
            fail(DailyMealReviewError.PastOrFuture, "오늘 급식만 새 AI 해설을 만들 수 있어요.")
            return
        }
        if (meal.menuItems.isEmpty()) {
            fail(DailyMealReviewError.NoMeal, "오늘 등록된 급식이 없어요.")
            return
        }
        if (!state.consent) {
            fail(DailyMealReviewError.ConsentRequired, "전송 항목 안내에 먼저 동의해 주세요.")
            return
        }
        if (client == null) {
            fail(DailyMealReviewError.NotConfigured, "개발 AI 연결 설정이 없어요.")
            return
        }
        val requestTime = now()
        val cached = pendingRequestCache.recover(profileKey, schoolKey, mealType, meal.date, requestTime)
        val request = cached?.takeIf(::matchesCurrentMeal) ?: createRequest().also {
            if (cached != null) removePending(cached.requestId)
        }
        if (request.items.isEmpty()) {
            fail(
                DailyMealReviewError.NoCandidates,
                "알레르기 주의 또는 정보가 불명확한 메뉴만 있어 AI에 보내지 않았어요.",
            )
            return
        }
        pendingRequestCache.retain(profileKey, schoolKey, mealType, meal.date, request, requestTime)
        mutableState.value = state.copy(isLoading = true, error = null, notice = null)
        val response = try {
            client.generate(request)
        } catch (error: CancellationException) {
            mutableState.value = mutableState.value.copy(isLoading = false)
            throw error
        } catch (error: DailyMealReviewClientException) {
            if (!error.canRetry) {
                removePending(request.requestId)
                mutableState.value = mutableState.value.copy(
                    isLoading = false,
                    error = error.uiError,
                    notice = error.userMessage,
                    generationAvailable = false,
                    generationLockedForDay = true,
                )
            } else {
                fail(error.uiError, error.userMessage)
            }
            return
        } catch (_: Exception) {
            fail(DailyMealReviewError.Network, "연결을 확인한 뒤 90초 안에 같은 요청으로 다시 시도해 주세요.")
            return
        }
        if (
            response.source != "ai" ||
            response.day != meal.date ||
            response.reviewId != request.requestId
        ) {
            fail(DailyMealReviewError.AnswerUnavailable, "AI 답변 날짜를 확인하지 못해 기본 안내를 보여드려요.")
            return
        }
        val record = SavedDailyMealReview(
            profileKey = profileKey,
            schoolKey = schoolKey,
            date = meal.date,
            mealType = mealType,
            mealFingerprint = dailyMealFingerprint(meal),
            menuSnapshot = meal.menuItems.mapIndexed { index, item ->
                DailyMealReviewMenuSnapshot(
                    "m$index",
                    item.name,
                    item.allergyCodes.distinct().sorted(),
                    request.items.firstOrNull { it.id == "m$index" }?.nutrients.orEmpty(),
                )
            },
            response = response,
            requestId = request.requestId,
            wholeMeal = request.wholeMeal,
        )
        try {
            store.save(record)
            removePending(request.requestId)
            mutableState.value = mutableState.value.copy(
                isLoading = false,
                record = record,
                unsavedRecord = null,
                error = null,
                notice = null,
            )
        } catch (error: CancellationException) {
            mutableState.value = mutableState.value.copy(
                isLoading = false,
                record = null,
                unsavedRecord = record,
                error = DailyMealReviewError.SaveFailed,
                notice = "AI 응답의 기기 저장이 완료되지 않았어요. 저장을 다시 시도해 주세요.",
            )
            throw error
        } catch (_: Exception) {
            mutableState.value = mutableState.value.copy(
                isLoading = false,
                record = null,
                unsavedRecord = record,
                error = DailyMealReviewError.SaveFailed,
                notice = "AI 응답을 기기에 저장하지 못했어요. 저장을 다시 시도해 주세요.",
            )
        }
    }

    suspend fun retrySave() {
        val unsaved = mutableState.value.unsavedRecord ?: return
        try {
            store.save(unsaved)
            removePending(unsaved.requestId)
            mutableState.value = mutableState.value.copy(
                record = unsaved,
                unsavedRecord = null,
                error = null,
                notice = null,
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            fail(DailyMealReviewError.SaveFailed, "AI 응답을 기기에 저장하지 못했어요. 저장을 다시 시도해 주세요.")
        }
    }

    fun visibleHighlights(): List<DailyMealReviewHighlight> =
        (mutableState.value.record ?: mutableState.value.unsavedRecord)
            ?.visibleHighlights(registeredAllergyCodes)
            .orEmpty()

    private fun createRequest(
        requestId: UUID = UUID.randomUUID(),
        requestSessionId: UUID = sessionId,
    ): DailyMealReviewRequest = DailyMealReviewRequestFactory(rules).create(
        meal = meal,
        registeredAllergyCodes = registeredAllergyCodes,
        requestId = requestId,
        sessionId = requestSessionId,
    )

    private fun matchesCurrentMeal(cached: DailyMealReviewRequest): Boolean {
        val requestId = runCatching { UUID.fromString(cached.requestId) }.getOrNull() ?: return false
        val cachedSessionId = runCatching { UUID.fromString(cached.sessionId) }.getOrNull() ?: return false
        return runCatching { createRequest(requestId, cachedSessionId) == cached }.getOrDefault(false)
    }

    private fun removePending(requestId: String? = null) {
        pendingRequestCache.remove(profileKey, schoolKey, mealType, meal.date, requestId)
    }

    private fun fail(error: DailyMealReviewError, message: String) {
        mutableState.value = mutableState.value.copy(
            isLoading = false,
            error = error,
            notice = message,
        )
    }
}

class DailyMealReviewCorruptRecordException(cause: Throwable? = null) :
    IllegalStateException("Corrupt daily meal review", cause)

open class DailyMealReviewClientException(
    val uiError: DailyMealReviewError,
    val userMessage: String,
    val canRetry: Boolean = true,
) : Exception(userMessage)
