package com.h19h29.naymnaymlevelup.rebuild.meal

import java.time.Instant
import java.time.LocalDate

data class School(
    val name: String,
    val officeCode: String,
    val schoolCode: String,
) {
    companion object
}

data class MealItem(
    val name: String,
    val allergyCodes: List<Int>,
    val nutrients: List<String>,
    val tags: List<String>,
    val sourceRawText: String,
)

data class NutritionInfo(
    val carbs: Double,
    val protein: Double,
    val fat: Double,
    val calcium: Double,
    val iron: Double,
    val vitamin: Double,
) {
    companion object {
        val empty = NutritionInfo(
            carbs = 0.0,
            protein = 0.0,
            fat = 0.0,
            calcium = 0.0,
            iron = 0.0,
            vitamin = 0.0,
        )
    }
}

data class MealDay(
    val date: String,
    val menuItems: List<MealItem>,
    val calorie: String,
    val nutrition: NutritionInfo,
) {
    companion object
}

sealed interface MealLoadState {
    data class Cached(
        val meal: MealDay,
        val refreshedAt: Instant?,
    ) : MealLoadState

    data class Refreshing(val cached: MealDay?) : MealLoadState

    data class Live(val meal: MealDay) : MealLoadState

    data object Empty : MealLoadState

    data class Failed(
        val message: String,
        val cached: MealDay?,
    ) : MealLoadState
}

data class CachedMealDay(
    val meal: MealDay,
    val refreshedAt: Instant?,
    val source: String,
)

interface MealDayStore {
    suspend fun load(date: String): CachedMealDay?

    suspend fun save(
        meal: MealDay,
        refreshedAt: Instant,
        source: String,
    )

    suspend fun remove(date: String)
}

fun interface MealClient {
    suspend fun fetch(date: LocalDate, school: School): MealDay?
}
