package com.h19h29.naymnaymlevelup.rebuild.child

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionInfo
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

/** Explicit manual opt-in only: one paid provider request, synthetic food data. */
class MealNutritionCoachLiveTest {
    @get:Rule val compose = createComposeRule()

    @Test fun syntheticMealReachesAiOnlyAfterExplicitConsent() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("mealCoachLive") == "1")
        compose.setContent {
            RebuildTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    MealNutritionCoach(
                        meal = MealDay(
                            date = "2026-09-14",
                            menuItems = listOf(MealItem("현미밥", emptyList(), listOf("carbohydrate"), emptyList(), "")),
                            calorie = "",
                            nutrition = NutritionInfo.empty,
                        ),
                        registeredAllergyCodes = emptyList(),
                    )
                }
            }
        }
        compose.onNodeWithTag("meal_coach_ai_toggle").performScrollTo().performClick()
        compose.onNodeWithTag("meal_coach_consent").performScrollTo().performClick()
        compose.onNodeWithTag("meal_coach_question_benefits").performScrollTo().performClick()
        compose.waitUntil(20000) {
            compose.onAllNodesWithTag("meal_coach_ai_connected").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("meal_coach_ai_connected").assertExists()
        compose.onNodeWithTag("meal_coach_answer_ai").performScrollTo().assertExists()
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val screenshot=requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        File(requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)),"meal-coach-android-live.png")
            .outputStream().use { screenshot.compress(Bitmap.CompressFormat.PNG,100,it) }
        screenshot.recycle()
    }
}
