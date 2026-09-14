package com.h19h29.naymnaymlevelup.rebuild.child

import android.os.ParcelFileDescriptor
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.printToLog
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionInfo
import com.h19h29.naymnaymlevelup.rebuild.meal.RoomMealDayStore
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingDestination
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingRole
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildUserProfile
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Debug-only, synthetic-data captures for the Google Play phone listing.
 *
 * The test deliberately refuses to touch real school, child, or allergy data: the child
 * profile, meal days, and growth events all come from the literals below. PNG files are
 * written to /sdcard/Download/nyam-store-new, and the semantics tree of every captured
 * frame is written to logcat under the NYAMCAP tag so a reviewer can confirm which screen
 * each file holds without opening the image.
 */
@RunWith(AndroidJUnit4::class)
class StoreScreenshotCaptureTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun captureChildScreens() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        try {
            seedMealsAndProgress(database)
            prepareCaptureDirectory()
            compose.setContent {
                RebuildTheme {
                    ChildNavigation(
                        profile = screenshotProfile(),
                        database = database,
                        isAppActive = true,
                    )
                }
            }

            waitForTag("today_forest_list")
            capture("01-today-forest.png")

            compose.onNodeWithTag("child_route_meals").performClick()
            waitForTag("meal_schedule_screen")
            capture("02-meal-schedule-daily.png")

            compose.onNodeWithTag("meal_schedule_mode_weekly").performClick()
            waitForTag("meal_schedule_weekly")
            capture("03-meal-schedule-weekly.png")

            compose.onNodeWithTag("meal_schedule_mode_monthly").performClick()
            waitForTag("meal_schedule_monthly")
            capture("04-meal-schedule-monthly.png")

            compose.onNodeWithTag("child_route_growth").performClick()
            waitForTag("growth_screen")
            capture("05-growth.png")

            compose.onNodeWithTag("child_route_collection").performClick()
            waitForTag("collection_screen")
            capture("06-growth-collection.png")

            compose.onNodeWithTag("child_route_settings").performClick()
            waitForTag("settings_screen")
            capture("07-settings.png")
        } finally {
            database.close()
        }
    }

    @Test
    fun captureCharacterConversation() {
        prepareCaptureDirectory()
        compose.setContent {
            RebuildTheme {
                CompanionConversationSheet(level = 3, onDismiss = {})
            }
        }
        waitForTag("companion_topic_allergy")
        capture("08-character-conversation.png")
    }

    private fun screenshotProfile() = RebuildUserProfile(
        id = "store-preview-child",
        role = OnboardingRole.Child,
        nickname = "냠냠이",
        school = null,
        allergyCodes = listOf(2, 5),
        destination = OnboardingDestination.Today,
    )

    private fun seedMealsAndProgress(database: RebuildDatabase) = runBlocking {
        val today = LocalDate.now(ZoneId.of("Asia/Seoul"))
        val store = RoomMealDayStore(database.mealDayDao())
        (-18L..18L).forEach { offset ->
            val date = today.plusDays(offset)
            store.save(
                meal = MealDay(
                    date = date.toString(),
                    menuItems = listOf(
                        MealItem("현미밥", emptyList(), listOf("carbohydrate"), emptyList(), "현미밥"),
                        MealItem("미역국", listOf(5), listOf("mineral"), emptyList(), "미역국(5)"),
                        MealItem("닭갈비", emptyList(), listOf("protein", "iron"), emptyList(), "닭갈비"),
                        MealItem("브로콜리무침", emptyList(), listOf("vitamin"), emptyList(), "브로콜리무침"),
                        MealItem("배추김치", emptyList(), listOf("fiber"), emptyList(), "배추김치"),
                    ),
                    calorie = "612 kcal",
                    nutrition = NutritionInfo(
                        carbs = 87.0,
                        protein = 24.0,
                        fat = 18.0,
                        calcium = 110.0,
                        iron = 4.2,
                        vitamin = 32.0,
                    ),
                ),
                refreshedAt = Instant.EPOCH,
                source = "store-preview",
            )
        }
        database.progressDao().insert(
            ProgressEventEntity(
                id = "store-preview-progress",
                amount = 500,
                occurredAtEpochMillis = Instant.now().toEpochMilli(),
                sourceRecordId = null,
            ),
        )
    }

    private fun waitForTag(tag: String) {
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
        compose.waitForIdle()
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        logSemantics()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val command = instrumentation.uiAutomation.executeShellCommand(
            "screencap -p $CAPTURE_DIR/$name",
        )
        ParcelFileDescriptor.AutoCloseInputStream(command).use {
            while (it.read() >= 0) Unit
        }
    }

    private fun prepareCaptureDirectory() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val command = instrumentation.uiAutomation.executeShellCommand("mkdir -p $CAPTURE_DIR")
        ParcelFileDescriptor.AutoCloseInputStream(command).use {
            while (it.read() >= 0) Unit
        }
    }

    private fun logSemantics() {
        val roots = compose.onAllNodes(isRoot())
        repeat(roots.fetchSemanticsNodes().size) { index ->
            roots[index].printToLog("$CAPTURE_LOG_TAG-$index")
        }
    }

    private companion object {
        const val CAPTURE_DIR = "/sdcard/Download/nyam-store-new"
        const val CAPTURE_LOG_TAG = "NYAMCAP"
    }
}
