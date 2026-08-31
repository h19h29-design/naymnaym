package com.h19h29.naymnaymlevelup.rebuild.child

import com.h19h29.naymnaymlevelup.rebuild.meal.DifficultyReason
import com.h19h29.naymnaymlevelup.rebuild.meal.EatingStatus
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.MealLoadState
import com.h19h29.naymnaymlevelup.rebuild.meal.MotionState
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionInfo
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealCommand
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealResult
import com.h19h29.naymnaymlevelup.rebuild.meal.School
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayForestViewModelTest {
    @Test
    fun cachedMealKeepsPrimaryActionAvailableOffline() = runTest {
        val viewModel = viewModel(
            repository = FakeMealRepository(MealLoadState.Cached(MEAL, null)),
        )

        viewModel.load()

        assertTrue(viewModel.state.value.primaryActionEnabled)
        assertEquals("저장된 급식", viewModel.state.value.sourceLabel)
        assertEquals(MEAL, viewModel.state.value.meal)
    }

    @Test
    fun mealStatesTellTheTruthAndOnlyMealsEnablePrimaryAction() = runTest {
        val cases = listOf(
            MealLoadState.Live(MEAL) to Triple("학교 급식", true, null),
            MealLoadState.Empty to Triple("급식 정보 없음", false, "오늘 등록된 급식이 없어요."),
            MealLoadState.Failed("offline", null) to Triple(
                "급식을 불러오지 못했어요",
                false,
                "인터넷 연결을 확인하고 다시 시도해 주세요.",
            ),
        )

        cases.forEach { (mealState, expected) ->
            val viewModel = viewModel(repository = FakeMealRepository(mealState))
            viewModel.load()
            assertEquals(expected.first, viewModel.state.value.sourceLabel)
            assertEquals(expected.second, viewModel.state.value.primaryActionEnabled)
            assertEquals(expected.third, viewModel.state.value.message)
        }
    }

    @Test
    fun freshViewModelLoadsPersistedTotalXp() = runTest {
        val viewModel = viewModel(progressProvider = TodayProgressProvider { 734 })

        viewModel.load()

        assertEquals(734, viewModel.state.value.totalXP)
    }

    @Test
    fun latePersistedTotalCannotOverwriteNewlyRecordedTotal() = runTest {
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Int>()
        val recorder = CapturingRecorder(result = RESULT.copy(totalXP = 742))
        val viewModel = viewModel(
            recorder = recorder,
            progressProvider = TodayProgressProvider {
                started.complete(Unit)
                release.await()
            },
        )

        val loading = async { viewModel.load() }
        started.await()
        viewModel.record(MEAL.menuItems.first(), EatingStatus.Finished)
        release.complete(734)
        loading.await()

        assertEquals(742, viewModel.state.value.totalXP)
    }

    @Test
    fun allergyRiskDisablesOneBiteAndPrioritizesSafetyActions() {
        val viewModel = viewModel(allergyCodes = listOf(5))
        val risky = MEAL.menuItems.first()

        assertTrue(viewModel.isAllergyRisk(risky))
        assertFalse(viewModel.isStatusEnabled(EatingStatus.OneBite, risky))
        assertEquals(
            listOf(TodaySafetyAction.AllergyAvoided, TodaySafetyAction.GuardianCheck),
            viewModel.prioritizedSafetyActions(risky),
        )
        assertEquals(
            listOf(
                EatingStatus.Finished,
                EatingStatus.OneBite,
                EatingStatus.SmelledOnly,
                EatingStatus.DifficultToday,
                EatingStatus.AllergyAvoided,
            ),
            TodayForestViewModel.activeStatuses,
        )
    }

    @Test
    fun difficultRecordUsesFiveReasonOrderAndPreservesPhotoMetadata() = runTest {
        val recorder = CapturingRecorder()
        val viewModel = viewModel(
            recorder = recorder,
            photoStore = TodayPhotoMetadataStore { _, _ -> listOf("photo-1", "photo-2") },
        )
        viewModel.load()

        viewModel.record(
            item = MEAL.menuItems.first(),
            status = EatingStatus.DifficultToday,
            difficultyReasons = listOf(
                DifficultyReason.Other,
                DifficultyReason.Appearance,
                DifficultyReason.Smell,
                DifficultyReason.Taste,
                DifficultyReason.Texture,
                DifficultyReason.Smell,
            ),
        )

        val command = recorder.commands.single()
        assertEquals(
            listOf(
                DifficultyReason.Smell,
                DifficultyReason.Texture,
                DifficultyReason.Taste,
                DifficultyReason.Appearance,
                DifficultyReason.Other,
            ),
            command.difficultyReasons,
        )
        assertEquals(listOf("photo-1", "photo-2"), command.photoIDs)
        assertEquals(
            "2026-07-25|김치 볶음밥|difficultToday",
            command.recordID,
        )
    }

    @Test
    fun smelledAndAllergyAvoidedSkipDifficultyReasons() = runTest {
        val recorder = CapturingRecorder()
        val viewModel = viewModel(recorder = recorder, allergyCodes = listOf(5))
        viewModel.load()

        viewModel.record(
            MEAL.menuItems.first(),
            EatingStatus.SmelledOnly,
            listOf(DifficultyReason.Smell),
        )
        viewModel.record(
            MEAL.menuItems.first(),
            EatingStatus.AllergyAvoided,
            listOf(DifficultyReason.Texture),
        )

        assertTrue(recorder.commands[0].difficultyReasons.isEmpty())
        assertTrue(recorder.commands[1].difficultyReasons.isEmpty())
        assertEquals(listOf(5), recorder.commands[1].allergyCodes)
    }

    @Test
    fun consecutiveMealSuccessRecordsAdvanceTheMotionRevision() = runTest {
        val viewModel = viewModel()
        viewModel.load()

        viewModel.record(MEAL.menuItems.first(), EatingStatus.Finished)
        val first = viewModel.state.value
        viewModel.record(MEAL.menuItems.first(), EatingStatus.Finished)
        val second = viewModel.state.value

        assertEquals(MotionState.MealSuccess, first.motion)
        assertEquals(MotionState.MealSuccess, second.motion)
        assertEquals(first.motionRevision + 1, second.motionRevision)
    }

    private fun viewModel(
        repository: TodayMealRepository = FakeMealRepository(MealLoadState.Live(MEAL)),
        recorder: CapturingRecorder = CapturingRecorder(),
        photoStore: TodayPhotoMetadataStore = TodayPhotoMetadataStore { _, _ -> emptyList() },
        progressProvider: TodayProgressProvider = TodayProgressProvider { 0 },
        allergyCodes: List<Int> = emptyList(),
    ) = TodayForestViewModel(
        repository = repository,
        recorder = recorder,
        photoMetadataStore = photoStore,
        progressProvider = progressProvider,
        school = null,
        allergyCodes = allergyCodes,
        date = LocalDate.of(2026, 7, 25),
        now = { Instant.parse("2026-07-25T03:00:00Z") },
    )

    private class FakeMealRepository(
        var mealState: MealLoadState,
    ) : TodayMealRepository {
        override suspend fun currentState(date: String): MealLoadState = mealState

        override suspend fun refresh(date: LocalDate, school: School) = Unit
    }

    private class CapturingRecorder(
        private val result: RecordMealResult = RESULT,
    ) : TodayMealRecorder {
        val commands = mutableListOf<RecordMealCommand>()

        override suspend fun execute(command: RecordMealCommand): RecordMealResult {
            commands += command
            return result
        }
    }

    private companion object {
        val MEAL = MealDay(
            date = "2026-07-25",
            menuItems = listOf(
                MealItem(
                    name = "김치 볶음밥",
                    allergyCodes = listOf(5),
                    nutrients = listOf("탄수화물"),
                    tags = emptyList(),
                    sourceRawText = "김치 볶음밥(5)",
                ),
            ),
            calorie = "650 Kcal",
            nutrition = NutritionInfo.empty,
        )
        val RESULT = RecordMealResult(
            xpGranted = 10,
            totalXP = 10,
            motion = MotionState.MealSuccess,
        )
    }
}
