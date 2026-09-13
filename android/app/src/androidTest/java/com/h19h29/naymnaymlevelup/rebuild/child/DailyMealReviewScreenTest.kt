package com.h19h29.naymnaymlevelup.rebuild.child

import android.os.ParcelFileDescriptor
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealClient
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDayStore
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.MealRepository
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionInfo
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionRuleEngine
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingDestination
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingRole
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildUserProfile
import java.time.LocalDate
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Rule
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DailyMealReviewScreenTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun savedRecordReopensWithoutGenerateControlsAtLargeFont() {
        lateinit var session: DailyMealReviewSession
        var densityValue = 1f
        val meal = meal()
        compose.setContent {
            val context = LocalContext.current
            val density = LocalDensity.current
            densityValue = density.density
            session = DailyMealReviewSession(
                profileKey = "profile",
                schoolKey = "school",
                mealType = "lunch",
                meal = meal,
                registeredAllergyCodes = emptyList(),
                store = SavedRepository(saved()),
                client = null,
                rules = NutritionRuleEngine(context.assets),
                today = { LocalDate.parse("2026-09-13") },
            )
            CompositionLocalProvider(LocalDensity provides Density(density.density, 1.5f)) {
                DailyMealReviewScreen(session, meal, onDismiss = {})
            }
        }

        compose.waitUntil(5_000) { session.state.value.record != null }
        compose.onNodeWithText("AI가 생성한 영양 안내").assertIsDisplayed()
        compose.onNodeWithText("1. 오늘 식단의 특징").assertIsDisplayed()
        compose.onNodeWithTag("daily_meal_review_generate").assertDoesNotExist()
        val titleTop = compose.onNodeWithText("AI 영양 안내").fetchSemanticsNode().boundsInRoot.top
        assertTrue("title overlaps the status bar: $titleTop", titleTop >= 24f * densityValue)
        capture("daily-meal-review-android-saved-font-scale-1.5.png")
    }

    @Test
    fun basicScreenShowsConsentAndEducationBoundary() {
        val meal = meal()
        compose.setContent {
            val context = LocalContext.current
            DailyMealReviewScreen(
                session = DailyMealReviewSession(
                    profileKey = "profile",
                    schoolKey = "school",
                    mealType = "lunch",
                    meal = meal,
                    registeredAllergyCodes = emptyList(),
                    store = SavedRepository(null),
                    client = null,
                    rules = NutritionRuleEngine(context.assets),
                    today = { LocalDate.parse("2026-09-13") },
                ),
                meal = meal,
                onDismiss = {},
            )
        }

        compose.onNodeWithTag("daily_meal_review_consent").assertIsDisplayed()
        compose.onNodeWithText(
            "영양 교육용 참고 안내이며 실제 영양사·의료 상담을 대신하지 않아요. 실제로 먹은 양은 알 수 없어요.",
        ).assertIsDisplayed()
    }

    @Test
    fun settingsRequiresConfirmationBeforeDeletingOnlyReviewStore() {
        val store = TrackingRepository()
        compose.setContent {
            RebuildSettingsScreen(
                profile = RebuildUserProfile(
                    id = "profile",
                    role = OnboardingRole.Child,
                    nickname = "냠냠",
                    school = null,
                    allergyCodes = emptyList(),
                    destination = OnboardingDestination.Today,
                ),
                dailyMealReviewStore = store,
            )
        }

        compose.onNodeWithTag("settings_delete_daily_reviews").performScrollTo().performClick()
        compose.onNodeWithText("AI 평가 기록을 삭제할까요?").assertIsDisplayed()
        compose.onNodeWithTag("settings_confirm_delete_daily_reviews").performClick()
        compose.waitUntil(5_000) { store.deleted }
    }

    @Test
    fun emptyScheduleDateStillOpensItsStoredReview() {
        val emptyMeals = object : MealDayStore {
            override suspend fun load(date: String) = null
            override suspend fun save(meal: MealDay, refreshedAt: Instant, source: String) = Unit
            override suspend fun remove(date: String) = Unit
        }
        val viewModel = MealScheduleViewModel(
            repository = MealRepository(
                store = emptyMeals,
                client = MealClient { _, _ -> null },
                scope = CoroutineScope(Dispatchers.Main.immediate),
            ),
            school = null,
        )
        compose.setContent {
            MealScheduleScreen(
                viewModel = viewModel,
                profileKey = "profile",
                schoolKey = "school",
                dailyMealReviewStore = SavedRepository(saved()),
            )
        }

        compose.onNodeWithTag("meal_schedule_screen")
            .performScrollToNode(hasTestTag("daily_meal_review_entry"))
        compose.onNodeWithTag("daily_meal_review_entry").assertIsDisplayed().performClick()
        compose.onNodeWithText("AI가 생성한 영양 안내").assertIsDisplayed()
        compose.onNodeWithText("현재 식단과 달라요. 아래 내용은 평가 당시 식단을 기준으로 해요.")
            .assertDoesNotExist()
        val storedNutrition = "단백질 23.0g · 탄수화물 70.0g · 지방 18.0g"
        compose.onNodeWithTag("daily_meal_review_screen")
            .performScrollToNode(hasText(storedNutrition))
        compose.onNodeWithText(storedNutrition).assertIsDisplayed()
        capture("daily-meal-review-android-saved-normal.png")
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val command = instrumentation.uiAutomation.executeShellCommand(
            "screencap -p /sdcard/Download/$name",
        )
        ParcelFileDescriptor.AutoCloseInputStream(command).use {
            while (it.read() >= 0) Unit
        }
    }

    private class SavedRepository(private val saved: SavedDailyMealReview?) : DailyMealReviewRepository {
        override suspend fun load(profileKey: String, schoolKey: String, date: String) = saved
        override suspend fun save(record: SavedDailyMealReview) = Unit
        override suspend fun deleteAll() = Unit
    }

    private class TrackingRepository : DailyMealReviewRepository {
        @Volatile var deleted = false
        override suspend fun load(profileKey: String, schoolKey: String, date: String) = null
        override suspend fun save(record: SavedDailyMealReview) = Unit
        override suspend fun deleteAll() { deleted = true }
    }

    private fun meal() = MealDay(
        "2026-09-13",
        listOf(MealItem("현미밥", emptyList(), listOf("carbohydrate"), emptyList(), "현미밥")),
        "500 kcal",
        NutritionInfo(70.0, 23.0, 18.0, 120.0, 3.0, 4.0),
    )

    private fun saved() = SavedDailyMealReview(
        "profile", "school", "2026-09-13", "lunch", dailyMealFingerprint(meal()),
        listOf(DailyMealReviewMenuSnapshot("m0", "현미밥", emptyList())),
        response = DailyMealReviewResponse(
            "ai", "00000000-0000-4000-8000-000000000001", "2026-09-13",
            "2026-09-13T04:00:00.000Z", "deepseek-v4.1-flash", "daily-v1",
            "오늘 영양 구성을 살펴봤어.", "에너지원이 되는 영양소를 만날 수 있어.",
            listOf(DailyMealReviewHighlight("m0", "carbohydrate", "활동에 쓰이는 에너지원이야.")),
            "실제로 먹은 양은 알 수 없어.", "다음 식사에서도 다양한 음식을 만나 보자.",
        ),
        wholeMeal = DailyMealReviewWholeMeal(protein = 23.0, carbs = 70.0, fat = 18.0),
    )
}
