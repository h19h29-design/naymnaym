package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
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
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ChildNavigationTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun inactiveRouteVisibilityBlocksPointerInputForItsButton() {
        val isActive = mutableStateOf(true)
        var clickCount = 0
        composeRule.setContent {
            Button(
                onClick = { clickCount += 1 },
                modifier = Modifier
                    .fillMaxSize()
                    .routeVisibility(isActive.value)
                    .testTag("route_button"),
            ) {
                Text("Route action")
            }
        }
        val actionCenter = composeRule.onNodeWithTag("route_button")
            .fetchSemanticsNode()
            .boundsInRoot
            .center
        composeRule.onRoot().performTouchInput {
            click(actionCenter)
        }
        composeRule.runOnIdle {
            assertEquals(1, clickCount)
            isActive.value = false
        }

        composeRule.onRoot().performTouchInput {
            click(actionCenter)
        }

        composeRule.runOnIdle {
            assertEquals(1, clickCount)
        }
    }

    @Test
    fun inactiveTodayCannotOpenRecorderThroughOtherTabs() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        try {
            val today = LocalDate.now(ZoneId.of("Asia/Seoul")).toString()
            runBlocking {
                RoomMealDayStore(database.mealDayDao()).save(
                    meal = MealDay(
                        date = today,
                        menuItems = listOf(
                            MealItem(
                                name = "테스트 급식",
                                allergyCodes = emptyList(),
                                nutrients = emptyList(),
                                tags = emptyList(),
                                sourceRawText = "테스트 급식",
                            ),
                        ),
                        calorie = "500 Kcal",
                        nutrition = NutritionInfo.empty,
                    ),
                    refreshedAt = Instant.EPOCH,
                    source = "test",
                )
            }
            composeRule.setContent {
                RebuildTheme {
                    ChildNavigation(
                        profile = RebuildUserProfile(
                            id = "child",
                            role = OnboardingRole.Child,
                            nickname = "냠냠이",
                            school = null,
                            allergyCodes = emptyList(),
                            destination = OnboardingDestination.Today,
                        ),
                        database = database,
                        isAppActive = true,
                    )
                }
            }
            composeRule.waitUntil(timeoutMillis = 10_000) {
                runCatching {
                    composeRule.onNodeWithTag("today_primary_action")
                        .assertIsEnabled()
                }.isSuccess
            }
            composeRule.onNodeWithTag("today_forest_list")
                .performScrollToIndex(3)
            val primaryActionCenter = composeRule
                .onNodeWithTag("today_primary_action")
                .assertIsDisplayed()
                .fetchSemanticsNode()
                .boundsInRoot
                .center
            composeRule.onRoot().performTouchInput {
                click(primaryActionCenter)
            }
            composeRule.onNodeWithText("급식 기록").assertIsDisplayed()
            composeRule.onNodeWithText("닫기").performClick()
            composeRule.onNodeWithText("급식 기록").assertDoesNotExist()

            listOf("meals", "growth", "collection").forEach { route ->
                composeRule.onNodeWithTag("child_route_$route").performClick()
                composeRule.waitForIdle()
                composeRule.onRoot().performTouchInput {
                    click(primaryActionCenter)
                }

                composeRule.onNodeWithText("급식 기록").assertDoesNotExist()
            }
        } finally {
            database.close()
        }
    }

    @Test
    fun growthReloadsPersistedXpWheneverItsTabBecomesActive() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        try {
            insertProgress(database, id = "initial", amount = 80, occurredAt = 1)
            composeRule.setContent {
                RebuildTheme {
                    ChildNavigation(
                        profile = RebuildUserProfile(
                            id = "child",
                            role = OnboardingRole.Child,
                            nickname = "냠냠이",
                            school = null,
                            allergyCodes = emptyList(),
                            destination = OnboardingDestination.Today,
                        ),
                        database = database,
                        isAppActive = true,
                    )
                }
            }

            composeRule.onNodeWithTag("child_route_growth").performClick()
            waitForText("한 입 탐험가")

            composeRule.onNodeWithTag("child_route_today").performClick()
            insertProgress(database, id = "new-record", amount = 500, occurredAt = 2)
            composeRule.onNodeWithTag("child_route_growth").performClick()

            waitForText("급식 히어로")
        } finally {
            database.close()
        }
    }

    @Test
    fun collectionReloadsPersistedXpWheneverItsTabBecomesActive() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        try {
            insertProgress(database, id = "initial", amount = 80, occurredAt = 1)
            composeRule.setContent {
                RebuildTheme {
                    ChildNavigation(
                        profile = RebuildUserProfile(
                            id = "child",
                            role = OnboardingRole.Child,
                            nickname = "냠냠이",
                            school = null,
                            allergyCodes = emptyList(),
                            destination = OnboardingDestination.Today,
                        ),
                        database = database,
                        isAppActive = true,
                    )
                }
            }

            composeRule.onNodeWithTag("child_route_collection").performClick()
            waitForTag("collection_screen")
            composeRule.onNodeWithTag("collection_screen").performScrollToIndex(2)
            waitForTag("collection_level_2_unlocked")

            composeRule.onNodeWithTag("child_route_today").performClick()
            insertProgress(database, id = "new-record", amount = 500, occurredAt = 2)
            composeRule.onNodeWithTag("child_route_collection").performClick()
            waitForTag("collection_screen")
            composeRule.onNodeWithTag("collection_screen").performScrollToIndex(5)

            waitForTag("collection_level_5_unlocked")
        } finally {
            database.close()
        }
    }

    private fun insertProgress(
        database: RebuildDatabase,
        id: String,
        amount: Int,
        occurredAt: Long,
    ) {
        runBlocking {
            database.progressDao().insert(
                ProgressEventEntity(
                    id = id,
                    amount = amount,
                    occurredAtEpochMillis = occurredAt,
                    sourceRecordId = null,
                ),
            )
        }
    }

    private fun waitForText(text: String) {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithText(text)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }

    private fun waitForTag(tag: String) {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithTag(tag)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }
}
