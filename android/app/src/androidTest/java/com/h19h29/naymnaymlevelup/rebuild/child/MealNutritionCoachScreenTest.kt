package com.h19h29.naymnaymlevelup.rebuild.child

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionInfo
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import java.io.File
import org.junit.Rule
import org.junit.Test

class MealNutritionCoachScreenTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun startsWithEveryMenuSelectedAndLocalQuestionsDoNotShowAiLabel() {
        compose.setContent {
            RebuildTheme {
                MealNutritionCoach(
                    meal = MealDay(
                        date = "2026-09-14",
                        menuItems = listOf(item("현미밥"), item("시금치나물")),
                        calorie = "700 Kcal",
                        nutrition = NutritionInfo.empty,
                    ),
                    registeredAllergyCodes = emptyList(),
                    developmentConfigEnabled = false,
                )
            }
        }

        compose.onNodeWithTag("meal_nutrition_coach").assertExists()
        compose.onNodeWithTag("meal_coach_menu_0").assertIsSelected()
        compose.onNodeWithTag("meal_coach_menu_1").assertIsSelected()
        MealCoachQuestion.entries.forEach { question ->
            compose.onNodeWithTag("meal_coach_question_${question.wireValue}").assertExists()
        }
        compose.onNodeWithTag("meal_coach_question_overview").assertTextContains("이 식단 어때?")
        compose.onNodeWithTag("meal_coach_consent").assertDoesNotExist()
        capture("meal-coach-android-initial.png")

        compose.onNodeWithTag("meal_coach_menu_1").performClick()
        compose.onNodeWithTag("meal_coach_question_overview").assertTextContains("이 메뉴 어때?")
        compose.onNodeWithTag("meal_coach_question_overview").performClick()
        compose.onNodeWithTag("meal_coach_answer_local").assertExists()
        compose.onNodeWithTag("meal_coach_ai_connected").assertDoesNotExist()
        capture("meal-coach-android-answer.png")
    }

    @Test
    fun largeFontKeepsCoreCoachChoicesInTheSemanticsTree() {
        compose.setContent {
            RebuildTheme {
                MealNutritionCoach(
                    meal = MealDay(
                        date = "2026-09-14",
                        menuItems = listOf(item("현미밥"), item("시금치나물")),
                        calorie = "700 Kcal",
                        nutrition = NutritionInfo.empty,
                    ),
                    registeredAllergyCodes = emptyList(),
                    developmentConfigEnabled = false,
                )
            }
        }

        compose.onNodeWithTag("meal_coach_menu_0").assertExists()
        MealCoachQuestion.entries.forEach { question ->
            compose.onNodeWithTag("meal_coach_question_${question.wireValue}").assertExists()
        }
        capture("meal-coach-android-font-scale-1.5.png")
    }

    private fun item(name: String) = MealItem(
        name = name,
        allergyCodes = emptyList(),
        nutrients = emptyList(),
        tags = emptyList(),
        sourceRawText = name,
    )

    private fun capture(name: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val screenshot = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        val outputDirectory = requireNotNull(
            instrumentation.targetContext.getExternalFilesDir(null),
        )
        File(outputDirectory, name).outputStream().use {
            screenshot.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        screenshot.recycle()
    }
}
