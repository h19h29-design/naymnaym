package com.h19h29.naymnaymlevelup.rebuild.child

import com.fasterxml.jackson.core.JsonFactory
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.meal.DifficultyReason
import com.h19h29.naymnaymlevelup.rebuild.meal.EatingStatus
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.MealLoadState
import com.h19h29.naymnaymlevelup.rebuild.meal.MealRepository
import com.h19h29.naymnaymlevelup.rebuild.meal.MealSafetyPolicy
import com.h19h29.naymnaymlevelup.rebuild.meal.MotionState
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealCommand
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealResult
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealUseCase
import com.h19h29.naymnaymlevelup.rebuild.meal.School
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

interface TodayMealRepository {
    suspend fun currentState(date: String): MealLoadState
    suspend fun refresh(date: LocalDate, school: School)
}

class LiveTodayMealRepository(
    private val repository: MealRepository,
) : TodayMealRepository {
    override suspend fun currentState(date: String): MealLoadState =
        repository.currentState(date)

    override suspend fun refresh(date: LocalDate, school: School) {
        repository.refresh(date, school)
    }
}

fun interface TodayMealRecorder {
    suspend fun execute(command: RecordMealCommand): RecordMealResult
}

class LiveTodayMealRecorder(
    private val useCase: RecordMealUseCase,
) : TodayMealRecorder {
    override suspend fun execute(command: RecordMealCommand): RecordMealResult =
        useCase.execute(command)
}

fun interface TodayPhotoMetadataStore {
    suspend fun photoIDs(date: String, normalizedMenuName: String): List<String>
}

fun interface TodayProgressProvider {
    suspend fun totalXP(): Int
}

class RoomTodayPhotoMetadataStore(
    private val database: RebuildDatabase,
) : TodayPhotoMetadataStore {
    override suspend fun photoIDs(
        date: String,
        normalizedMenuName: String,
    ): List<String> {
        val seen = linkedSetOf<String>()
        database.mealRecordDao()
            .recordsForMenu(date, normalizedMenuName)
            .flatMap { StringArrayJson.decode(it.photoIdsJson) }
            .forEach(seen::add)
        return seen.toList()
    }
}

class RoomTodayProgressProvider(
    private val database: RebuildDatabase,
) : TodayProgressProvider {
    override suspend fun totalXP(): Int {
        val value = database.progressDao().totalXp()
        require(value in 0L..Int.MAX_VALUE.toLong()) {
            "Persisted XP is outside the supported range"
        }
        return value.toInt()
    }
}

enum class TodaySafetyAction {
    AllergyAvoided,
    GuardianCheck,
}

enum class TodayForestError {
    MealUnavailable,
    AllergySafetyRequired,
}

class TodayForestException(
    val reason: TodayForestError,
) : IllegalStateException(reason.name)

data class TodayForestUiState(
    val meal: MealDay? = null,
    val sourceLabel: String = "급식을 확인하고 있어요",
    val primaryActionEnabled: Boolean = false,
    val isLoading: Boolean = false,
    val totalXP: Int = 0,
    val lastGrantedXP: Int = 0,
    val motion: MotionState = MotionState.Idle,
    val motionRevision: Long = 0,
    val message: String? = null,
)

class TodayForestViewModel(
    private val repository: TodayMealRepository,
    private val recorder: TodayMealRecorder,
    private val photoMetadataStore: TodayPhotoMetadataStore =
        TodayPhotoMetadataStore { _, _ -> emptyList() },
    private val progressProvider: TodayProgressProvider =
        TodayProgressProvider { 0 },
    private val school: School?,
    allergyCodes: List<Int>,
    val date: LocalDate = LocalDate.now(ZoneId.of("Asia/Seoul")),
    private val now: () -> Instant = Instant::now,
) {
    val title = "오늘 급식"
    val primaryActionTitle = "오늘 급식 기록하기"
    val dateKey: String = date.toString()
    val dateText: String = date.format(
        DateTimeFormatter.ofPattern("M월 d일 EEEE", Locale.KOREAN),
    )
    val allergyCodes: List<Int> = allergyCodes.distinct().sorted()

    private val mutableState = MutableStateFlow(TodayForestUiState())
    val state: StateFlow<TodayForestUiState> = mutableState.asStateFlow()
    private var progressRevision = 0L

    suspend fun load() = coroutineScope {
        mutableState.value = mutableState.value.copy(isLoading = true)
        val revisionAtStart = progressRevision
        val persistedTotal = async {
            runCatching { progressProvider.totalXP() }.getOrNull()
        }
        apply(repository.currentState(dateKey))
        school?.let {
            repository.refresh(date, it)
            apply(repository.currentState(dateKey))
        }
        persistedTotal.await()?.let { total ->
            if (progressRevision == revisionAtStart) {
                mutableState.value = mutableState.value.copy(totalXP = total)
            }
        }
        mutableState.value = mutableState.value.copy(isLoading = false)
    }

    fun isAllergyRisk(item: MealItem): Boolean =
        item.allergyCodes.any(allergyCodes::contains)

    fun isStatusEnabled(status: EatingStatus, item: MealItem): Boolean =
        status in MealSafetyPolicy.allowedStatuses(
            childAllergyCodes = allergyCodes.toSet(),
            itemAllergyCodes = item.allergyCodes.toSet(),
        )

    fun prioritizedSafetyActions(item: MealItem): List<TodaySafetyAction> =
        if (isAllergyRisk(item)) {
            listOf(
                TodaySafetyAction.AllergyAvoided,
                TodaySafetyAction.GuardianCheck,
            )
        } else {
            emptyList()
        }

    suspend fun record(
        item: MealItem,
        status: EatingStatus,
        difficultyReasons: List<DifficultyReason> = emptyList(),
        parentShareEnabled: Boolean = false,
    ): RecordMealResult {
        if (mutableState.value.meal == null) {
            throw TodayForestException(TodayForestError.MealUnavailable)
        }
        if (!isStatusEnabled(status, item)) {
            throw TodayForestException(TodayForestError.AllergySafetyRequired)
        }
        val normalizedName = item.name.trim().lowercase(Locale.ROOT)
        val photoIDs = photoMetadataStore.photoIDs(dateKey, normalizedName)
        val reasons = if (status == EatingStatus.DifficultToday) {
            orderedDifficultyReasons(difficultyReasons)
        } else {
            emptyList()
        }
        val childAllergyCodes = allergyCodes.toSet().sorted()
        val itemAllergyCodes = item.allergyCodes.toSet().sorted()
        val matchedAllergies = childAllergyCodes
            .intersect(itemAllergyCodes.toSet())
            .sorted()
        val result = recorder.execute(
            RecordMealCommand(
                recordID = "$dateKey|$normalizedName",
                date = dateKey,
                menuName = item.name,
                status = status,
                difficultyReasons = reasons,
                allergyCodes = matchedAllergies,
                childAllergyCodes = childAllergyCodes,
                itemAllergyCodes = itemAllergyCodes,
                photoIDs = photoIDs,
                parentShareEnabled = parentShareEnabled,
                occurredAt = now(),
            ),
        )
        progressRevision += 1
        mutableState.value = mutableState.value.copy(
            totalXP = result.totalXP,
            lastGrantedXP = result.xpGranted,
            motion = result.motion,
            motionRevision = progressRevision,
            message = if (result.xpGranted > 0) {
                "${result.xpGranted} XP를 얻었어요!"
            } else {
                "오늘 기록을 저장했어요."
            },
        )
        return result
    }

    private fun apply(mealState: MealLoadState) {
        mutableState.value = when (mealState) {
            is MealLoadState.Cached -> mutableState.value.copy(
                meal = mealState.meal,
                sourceLabel = "저장된 급식",
                primaryActionEnabled = mealState.meal.menuItems.isNotEmpty(),
                message = "인터넷이 없어도 저장된 급식을 기록할 수 있어요.",
            )
            is MealLoadState.Refreshing -> mutableState.value.copy(
                meal = mealState.cached,
                sourceLabel = if (mealState.cached == null) {
                    "급식을 확인하고 있어요"
                } else {
                    "저장된 급식"
                },
                primaryActionEnabled = mealState.cached?.menuItems?.isNotEmpty() == true,
            )
            is MealLoadState.Live -> mutableState.value.copy(
                meal = mealState.meal,
                sourceLabel = "학교 급식",
                primaryActionEnabled = mealState.meal.menuItems.isNotEmpty(),
                message = null,
            )
            MealLoadState.Empty -> mutableState.value.copy(
                meal = null,
                sourceLabel = "급식 정보 없음",
                primaryActionEnabled = false,
                message = "오늘 등록된 급식이 없어요.",
            )
            is MealLoadState.Failed -> mutableState.value.copy(
                meal = mealState.cached,
                sourceLabel = if (mealState.cached == null) {
                    "급식을 불러오지 못했어요"
                } else {
                    "저장된 급식"
                },
                primaryActionEnabled = mealState.cached?.menuItems?.isNotEmpty() == true,
                message = if (mealState.cached == null) {
                    "인터넷 연결을 확인하고 다시 시도해 주세요."
                } else {
                    "인터넷이 없어 저장된 급식을 보여드려요."
                },
            )
        }
    }

    companion object {
        val activeStatuses = listOf(
            EatingStatus.Finished,
            EatingStatus.Half,
            EatingStatus.OneBite,
            EatingStatus.SmelledOnly,
            EatingStatus.DifficultToday,
            EatingStatus.AllergyAvoided,
        )
        val difficultyReasonOrder = listOf(
            DifficultyReason.Smell,
            DifficultyReason.Texture,
            DifficultyReason.Taste,
            DifficultyReason.Appearance,
            DifficultyReason.Other,
        )

        fun orderedDifficultyReasons(
            reasons: List<DifficultyReason>,
        ): List<DifficultyReason> {
            val selected = reasons.toSet()
            return difficultyReasonOrder.filter(selected::contains)
        }
    }
}

private object StringArrayJson {
    private val factory = JsonFactory()

    fun decode(raw: String): List<String> =
        factory.createParser(raw).use { parser ->
            val result = mutableListOf<String>()
            if (parser.nextToken() == com.fasterxml.jackson.core.JsonToken.START_ARRAY) {
                while (
                    parser.nextToken() !=
                    com.fasterxml.jackson.core.JsonToken.END_ARRAY
                ) {
                    parser.valueAsString?.let(result::add)
                }
            }
            result
        }
}
