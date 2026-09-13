package com.h19h29.naymnaymlevelup.rebuild.child

import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionRuleEngine
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class MealCoachQuestion(
    val wireValue: String,
    private val wholeMealTitle: String,
) {
    Overview("overview", "이 식단 어때?"),
    Benefits("benefits", "먹으면 어떤 도움이 돼?"),
    Omission("omission", "남기면 어떻게 보완해?"),

    ;

    fun title(isWholeMealSelected: Boolean): String =
        if (this == Overview && !isWholeMealSelected) {
            "이 메뉴 어때?"
        } else {
            wholeMealTitle
        }
}

internal const val MEAL_COACH_CONSENT_COPY =
    "선택한 질문 종류·대표 영양소 ID·임시 세션 ID를 전송해요. 모든 메뉴를 선택했을 때만 전체 급식 수치(단백질·탄수화물·지방)를 함께 전송해요. 메뉴 이름·학교·날짜·개인 식사 기록·등록 알레르기는 전송하지 않아요."

data class MealCoachWholeMeal(
    val protein: Double? = null,
    val carbs: Double? = null,
    val fat: Double? = null,
)

data class MealCoachRequest(
    val question: MealCoachQuestion,
    val nutrients: List<String>,
    val wholeMeal: MealCoachWholeMeal,
    val sessionId: String,
)

data class MealCoachResponse(
    val source: String,
    val summary: String,
    val benefit: String,
    val caution: String,
    val tip: String,
)

fun interface MealCoachClient {
    suspend fun ask(request: MealCoachRequest): MealCoachResponse
}

class MealCoachRequestFactory(
    private val rules: NutritionRuleEngine,
) {
    fun create(
        question: MealCoachQuestion,
        meal: MealDay,
        selectedMenuIndices: Set<Int>,
        sessionId: String,
    ): MealCoachRequest {
        require(UUID.fromString(sessionId).toString() == sessionId.lowercase(Locale.ROOT))
        val selectedItems = selectedMenuIndices.sorted().mapNotNull(meal.menuItems::getOrNull)
        val discovered = selectedItems.flatMap { item ->
            val metadata = item.nutrients.mapNotNull(::normalizeNutrientId)
            metadata.ifEmpty {
                rules.insight(item.name).nutrients.map { it.id }
            }
        }.toSet()
        val isWholeMealSelected = meal.menuItems.isNotEmpty() &&
            selectedMenuIndices == meal.menuItems.indices.toSet()
        return MealCoachRequest(
            question = question,
            nutrients = NUTRIENT_ORDER.filter(discovered::contains),
            wholeMeal = if (isWholeMealSelected) {
                MealCoachWholeMeal(
                    protein = meal.nutrition.protein.validAmount(),
                    carbs = meal.nutrition.carbs.validAmount(),
                    fat = meal.nutrition.fat.validAmount(),
                )
            } else {
                MealCoachWholeMeal()
            },
            sessionId = sessionId,
        )
    }

    companion object {
        val NUTRIENT_ORDER = listOf(
            "fiber",
            "vitamin",
            "protein",
            "iron",
            "calcium",
            "carbohydrate",
        )

        fun normalizeNutrientId(raw: String): String? = when (
            raw.trim().lowercase(Locale.ROOT).replace("_", "").replace("-", "")
        ) {
            "fiber", "dietaryfiber", "식이섬유" -> "fiber"
            "vitamin", "vitamins", "비타민" -> "vitamin"
            "protein", "단백질" -> "protein"
            "iron", "철", "철분" -> "iron"
            "calcium", "칼슘" -> "calcium"
            "carbohydrate", "carbohydrates", "carb", "carbs", "탄수화물" ->
                "carbohydrate"
            else -> null
        }
    }
}

private fun Double.validAmount(): Double? = takeIf { it.isFinite() && it > 0.0 }

enum class MealCoachAnswerSource {
    Local,
    Ai,
}

data class MealCoachAnswer(
    val source: MealCoachAnswerSource,
    val summary: String,
    val benefit: String,
    val caution: String,
    val tip: String,
)

data class MealCoachUiState(
    val selectedMenuIndices: Set<Int>,
    val useAi: Boolean = false,
    val consent: Boolean = false,
    val isLoading: Boolean = false,
    val answer: MealCoachAnswer? = null,
    val notice: String? = null,
    val aiConnected: Boolean = false,
)

class MealCoachSession(
    initialMeal: MealDay,
    private val rules: NutritionRuleEngine,
    private val client: MealCoachClient?,
    private val scope: CoroutineScope,
    private val sessionId: String = UUID.randomUUID().toString(),
    initialRegisteredAllergyCodes: List<Int> = emptyList(),
) {
    private var meal = initialMeal
    private var registeredAllergyCodes = initialRegisteredAllergyCodes.distinct().sorted()
    private var requestVersion = 0L
    private var activeRequest: Job? = null
    private val mutableState = MutableStateFlow(
        MealCoachUiState(initialMeal.menuItems.indices.toSet()),
    )
    val state: StateFlow<MealCoachUiState> = mutableState.asStateFlow()
    val aiAvailable: Boolean get() = client != null

    fun bindMeal(nextMeal: MealDay) {
        if (meal == nextMeal) return
        cancelActiveRequest()
        meal = nextMeal
        mutableState.value = mutableState.value.copy(
            selectedMenuIndices = nextMeal.menuItems.indices.toSet(),
            isLoading = false,
            answer = null,
            notice = null,
            aiConnected = false,
        )
    }

    fun toggleMenu(index: Int) {
        if (index !in meal.menuItems.indices) return
        cancelActiveRequest()
        val current = mutableState.value.selectedMenuIndices
        val updated = if (index in current) current - index else current + index
        mutableState.value = mutableState.value.copy(
            selectedMenuIndices = updated,
            isLoading = false,
            answer = null,
            notice = null,
            aiConnected = false,
        )
    }

    fun setUseAi(enabled: Boolean) {
        cancelActiveRequest()
        mutableState.value = mutableState.value.copy(
            useAi = enabled && client != null,
            consent = if (enabled && client != null) {
                mutableState.value.consent
            } else {
                false
            },
            isLoading = false,
            answer = null,
            notice = if (enabled && client == null) {
                "개발 AI 연결 설정이 없어 로컬 안내를 사용해요."
            } else {
                null
            },
            aiConnected = false,
        )
    }

    fun setConsent(consent: Boolean) {
        val current = mutableState.value
        if (!current.useAi || current.consent == consent) return
        cancelActiveRequest()
        mutableState.value = mutableState.value.copy(
            consent = consent,
            isLoading = false,
            answer = null,
            notice = null,
            aiConnected = false,
        )
    }

    fun bindRegisteredAllergyCodes(codes: List<Int>) {
        val normalized = codes.distinct().sorted()
        if (registeredAllergyCodes == normalized) return
        registeredAllergyCodes = normalized
        cancelActiveRequest()
        mutableState.value = mutableState.value.copy(
            isLoading = false,
            answer = null,
            notice = null,
            aiConnected = false,
        )
    }

    fun ask(
        question: MealCoachQuestion,
        registeredAllergyCodes: List<Int>,
    ) {
        bindRegisteredAllergyCodes(registeredAllergyCodes)
        val snapshot = mutableState.value
        if (snapshot.selectedMenuIndices.isEmpty()) {
            mutableState.value = snapshot.copy(notice = "메뉴를 하나 이상 골라 주세요.")
            return
        }
        val allergyRisk = selectedItems(snapshot).any { item ->
            item.allergyCodes.any(this.registeredAllergyCodes::contains)
        }
        if (!snapshot.useAi || allergyRisk || client == null) {
            cancelActiveRequest()
            mutableState.value = snapshot.copy(
                isLoading = false,
                answer = localAnswer(question, snapshot.selectedMenuIndices, allergyRisk),
                notice = if (allergyRisk && snapshot.useAi) {
                    "등록 알레르기 주의 메뉴는 전송하지 않고 로컬에서만 안내해요."
                } else {
                    null
                },
                aiConnected = false,
            )
            return
        }
        if (!snapshot.consent) {
            mutableState.value = snapshot.copy(
                notice = "영양소 ID와 전체 식단 수치 전송에 먼저 동의해 주세요.",
                aiConnected = false,
            )
            return
        }

        cancelActiveRequest()
        val version = requestVersion
        val request = MealCoachRequestFactory(rules).create(
            question = question,
            meal = meal,
            selectedMenuIndices = snapshot.selectedMenuIndices,
            sessionId = sessionId,
        )
        mutableState.value = snapshot.copy(
            isLoading = true,
            answer = null,
            notice = null,
            aiConnected = false,
        )
        activeRequest = scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                val response = client.ask(request)
                if (requestVersion == version) {
                    mutableState.value = mutableState.value.copy(
                        isLoading = false,
                        answer = MealCoachAnswer(
                            source = MealCoachAnswerSource.Ai,
                            summary = response.summary,
                            benefit = response.benefit,
                            caution = response.caution,
                            tip = response.tip,
                        ),
                        notice = null,
                        aiConnected = true,
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                if (requestVersion == version) {
                    mutableState.value = mutableState.value.copy(
                        isLoading = false,
                        answer = localAnswer(
                            question,
                            mutableState.value.selectedMenuIndices,
                            allergyRisk = false,
                        ),
                        notice = "AI 연결에 실패해 로컬 안내를 보여 드려요. 자동으로 다시 시도하지 않아요.",
                        aiConnected = false,
                    )
                }
            }
        }
    }

    fun close() {
        cancelActiveRequest()
    }

    private fun cancelActiveRequest() {
        requestVersion += 1
        activeRequest?.cancel()
        activeRequest = null
    }

    private fun selectedItems(state: MealCoachUiState): List<MealItem> =
        state.selectedMenuIndices.sorted().mapNotNull(meal.menuItems::getOrNull)

    private fun localAnswer(
        question: MealCoachQuestion,
        selectedIndices: Set<Int>,
        allergyRisk: Boolean,
    ): MealCoachAnswer {
        val request = MealCoachRequestFactory(rules).create(
            question,
            meal,
            selectedIndices,
            sessionId,
        )
        val names = request.nutrients.map(::nutrientName)
        val nutrientCopy = names.takeIf(List<String>::isNotEmpty)
            ?.joinToString(", ")
            ?: "대표 영양소"
        val allergyCaution = if (allergyRisk) {
            "등록한 알레르기와 관련된 메뉴는 먹도록 권하지 않아요. 보호자나 선생님에게 먼저 확인해 주세요."
        } else {
            "정확한 섭취량이나 알레르기 안전을 보장할 수는 없어요."
        }
        val summary = when (question) {
            MealCoachQuestion.Overview ->
                "고른 메뉴에서는 $nutrientCopy 같은 영양소를 살펴볼 수 있어요."
            MealCoachQuestion.Benefits -> if (allergyRisk) {
                "알레르기와 관련된 메뉴라 먹도록 권하지 않아요. 다른 음식으로 보완할지는 보호자나 선생님과 확인해 주세요."
            } else {
                "$nutrientCopy 같은 영양소를 공급받을 수 있어요."
            }
            MealCoachQuestion.Omission ->
                "한 끼를 남겼다고 영양 결핍을 단정할 수는 없어요."
        }
        return MealCoachAnswer(
            source = MealCoachAnswerSource.Local,
            summary = summary,
            benefit = request.nutrients.firstOrNull()?.let(::nutrientRole)
                ?: "음식마다 들어 있는 영양소가 달라요.",
            caution = allergyCaution,
            tip = if (allergyRisk) {
                "다른 음식으로 보완할지는 보호자나 선생님과 확인해 주세요."
            } else if (question == MealCoachQuestion.Omission) {
                "다른 식사에서 여러 음식을 다양하게 골라 보완해요. 알레르기가 걱정되면 보호자나 선생님에게 먼저 확인해 주세요."
            } else {
                "몸의 느낌을 살피고, 궁금하거나 불편하면 가까운 어른에게 알려 주세요."
            },
        )
    }
}

internal fun nutrientName(id: String): String = when (id) {
    "fiber" -> "식이섬유"
    "vitamin" -> "비타민"
    "protein" -> "단백질"
    "iron" -> "철분"
    "calcium" -> "칼슘"
    "carbohydrate" -> "탄수화물"
    else -> "영양소"
}

private fun nutrientRole(id: String): String = when (id) {
    "fiber" -> "식이섬유는 배변 활동과 건강한 식사 구성을 돕는 영양소예요."
    "vitamin" -> "비타민은 몸이 여러 기능을 원활하게 쓰도록 도와요."
    "protein" -> "단백질은 몸의 조직을 만들고 유지하는 데 쓰여요."
    "iron" -> "철분은 몸속 산소 운반에 필요한 영양소예요."
    "calcium" -> "칼슘은 뼈와 치아를 만드는 데 필요한 영양소예요."
    "carbohydrate" -> "탄수화물은 몸이 활동할 에너지를 얻는 주요 영양소예요."
    else -> "음식마다 들어 있는 영양소가 달라요."
}
