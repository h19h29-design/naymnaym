package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.unit.Density
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.h19h29.naymnaymlevelup.rebuild.data.MealRecordEntity
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.MealLoadState
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionInfo
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealCommand
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealResult
import com.h19h29.naymnaymlevelup.rebuild.meal.School
import com.h19h29.naymnaymlevelup.rebuild.growth.GrowthPolicyLoader
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import java.time.LocalDate
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class TodayForestScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun mealHeaderReflowsAndPrimaryActionRemainsReachableAtTwoHundredPercentText() {
        val meal = MealDay(
            date = "2026-07-25",
            menuItems = listOf(
                MealItem(
                    name = "아주 길어도 줄바꿈되어 모두 읽을 수 있는 오늘의 학교 급식 메뉴",
                    allergyCodes = emptyList(),
                    nutrients = emptyList(),
                    tags = emptyList(),
                    sourceRawText = "급식",
                ),
            ),
            calorie = "650 Kcal",
            nutrition = NutritionInfo.empty,
        )
        val viewModel = TodayForestViewModel(
            repository = object : TodayMealRepository {
                override suspend fun currentState(date: String) = MealLoadState.Live(meal)
                override suspend fun refresh(date: LocalDate, school: School) = Unit
            },
            recorder = object : TodayMealRecorder {
                override suspend fun execute(command: RecordMealCommand): RecordMealResult {
                    error("Not used")
                }
            },
            school = null,
            allergyCodes = emptyList(),
            date = LocalDate.of(2026, 7, 25),
        )

        composeRule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = 2f),
            ) {
                RebuildTheme {
                    TodayForestScreen(
                        viewModel = viewModel,
                        growthPolicy = GrowthPolicyLoader.load(
                            ApplicationProvider.getApplicationContext<
                                android.content.Context
                            >().assets,
                        ),
                    )
                }
            }
        }

        val headingBounds = composeRule.onNodeWithText("오늘의 점심")
            .fetchSemanticsNode()
            .boundsInRoot
        val sourceBounds = composeRule.onNodeWithText("학교 급식")
            .fetchSemanticsNode()
            .boundsInRoot
        assertTrue(sourceBounds.top >= headingBounds.bottom)

        composeRule.onNodeWithTag("today_forest_list")
            .performScrollToIndex(3)
        composeRule.onNodeWithTag("today_primary_action")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun freshViewModelReadsPersistedRoomXpTruthfully() {
        runBlocking {
            val context = ApplicationProvider.getApplicationContext<android.content.Context>()
            val database = Room.inMemoryDatabaseBuilder(
                context,
                RebuildDatabase::class.java,
            ).build()
            try {
                database.progressDao().insert(
                    ProgressEventEntity(
                        id = "persisted-positive",
                        amount = 734,
                        occurredAtEpochMillis = 1,
                        sourceRecordId = null,
                    ),
                )
                database.progressDao().insert(
                    ProgressEventEntity(
                        id = "persisted-negative",
                        amount = -500,
                        occurredAtEpochMillis = 2,
                        sourceRecordId = null,
                    ),
                )
                val viewModel = TodayForestViewModel(
                    repository = object : TodayMealRepository {
                        override suspend fun currentState(date: String) = MealLoadState.Empty
                        override suspend fun refresh(date: LocalDate, school: School) = Unit
                    },
                    recorder = TodayMealRecorder { error("Not used") },
                    progressProvider = RoomTodayProgressProvider(database),
                    school = null,
                    allergyCodes = emptyList(),
                    date = LocalDate.of(2026, 7, 25),
                )

                viewModel.load()

                assertEquals(734, viewModel.state.value.totalXP)
                composeRule.setContent {
                    RebuildTheme {
                        TodayForestScreen(
                            viewModel = viewModel,
                            growthPolicy = GrowthPolicyLoader.load(context.assets),
                        )
                    }
                }
                composeRule.onNodeWithContentDescription("레벨 6 냠냠 다람쥐")
                    .assertIsDisplayed()
            } finally {
                database.close()
            }
        }
    }

    @Test
    fun roomPhotoMetadataPreservesOrderedUniqueIdsAcrossStatusChanges() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        try {
            listOf(
                Triple("finished", "[\"photo-1\",\"photo-2\"]", 1L),
                Triple("oneBite", "[\"photo-2\",\"photo-3\"]", 2L),
            ).forEach { (status, photos, updatedAt) ->
                database.mealRecordDao().upsert(
                    MealRecordEntity(
                        id = "2026-07-25|김치 볶음밥|$status",
                        date = "2026-07-25",
                        menuName = "김치 볶음밥",
                        normalizedMenuName = "김치 볶음밥",
                        status = status,
                        difficultyReasonsJson = "[]",
                        allergyCodesJson = "[]",
                        photoIdsJson = photos,
                        updatedAtEpochMillis = updatedAt,
                        deletedAtEpochMillis = null,
                    ),
                )
            }

            val photoIDs = RoomTodayPhotoMetadataStore(database).photoIDs(
                "2026-07-25",
                "김치 볶음밥",
            )

            assertEquals(listOf("photo-1", "photo-2", "photo-3"), photoIDs)
        } finally {
            database.close()
        }
    }
}
