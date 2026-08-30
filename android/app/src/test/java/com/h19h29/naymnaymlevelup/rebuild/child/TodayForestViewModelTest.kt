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
    fun allergyRiskAllowsOnlyAllergyAvoidedAcrossAllSixStatuses() {
        val viewModel = viewModel(allergyCodes = listOf(5))
        val risky = MEAL.menuItems.first()

        assertTrue(viewModel.isAllergyRisk(risky))
        assertEquals(
            listOf(
                EatingStatus.Finished to false,
                EatingStatus.Half to false,
                EatingStatus.OneBite to false,
                EatingStatus.SmelledOnly to false,
                EatingStatus.DifficultToday to false,
                EatingStatus.AllergyAvoided to true,
            ),
            TodayForestViewModel.activeStatuses.map { status ->
                status to viewModel.isStatusEnabled(status, risky)
            },
        )
        assertEquals(
            listOf(TodaySafetyAction.AllergyAvoided, TodaySafetyAction.GuardianCheck),
            viewModel.prioritizedSafetyActions(risky),
        )
        assertEquals(
            listOf(
                EatingStatus.Finished,
                EatingStatus.Half,
                EatingStatus.OneBite,
                EatingStatus.SmelledOnly,
                EatingStatus.DifficultToday,
                EatingStatus.AllergyAvoided,
            ),
            TodayForestViewModel.activeStatuses,
        )
    }

    @Test
    fun safeMenuAllowsAllSixStatuses() {
        val viewModel = viewModel(allergyCodes = listOf(5))
        val safe = MEAL.menuItems.first().copy(allergyCodes = listOf(7, 9))

        assertFalse(viewModel.isAllergyRisk(safe))
        assertEquals(
            TodayForestViewModel.activeStatuses,
            TodayForestViewModel.activeStatuses.filter { status ->
                viewModel.isStatusEnabled(status, safe)
            },
        )
    }

    @Test
    fun allSixStatusLabelsMatchTheChildContract() {
        assertEquals(
            listOf(
                "finished" to "다 먹었어요",
                "half" to "반 정도 먹었어요",
                "oneBite" to "한 입 도전",
                "smelledOnly" to "냄새만 맡았어요",
                "difficultToday" to "오늘은 안 먹어요",
                "allergyAvoided" to "알레르기로 피했어요",
            ),
            TodayForestViewModel.activeStatuses.map { status ->
                status.wireValue to status.childTitle
            },
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
            "2026-07-25|김치 볶음밥",
            command.recordID,
        )
    }

    @Test
    fun riskyNonAvoidanceStatusesAreRejectedBeforeRecorder() = runTest {
        val recorder = CapturingRecorder()
        val viewModel = viewModel(recorder = recorder, allergyCodes = listOf(5))
        viewModel.load()

        TodayForestViewModel.activeStatuses
            .filterNot { it == EatingStatus.AllergyAvoided }
            .forEach { status ->
                val error = expectTodayFailure {
                    viewModel.record(
                        MEAL.menuItems.first(),
                        status,
                        listOf(DifficultyReason.Smell),
                    )
                }
                assertEquals(
                    status.wireValue,
                    TodayForestError.AllergySafetyRequired,
                    error.reason,
                )
            }

        assertTrue(recorder.commands.isEmpty())
    }

    @Test
    fun allergyAvoidedPersistsExactSortedOverlapAndSkipsDifficultyReasons() = runTest {
        val recorder = CapturingRecorder()
        val viewModel = viewModel(
            recorder = recorder,
            allergyCodes = listOf(7, 5, 2, 5),
        )
        viewModel.load()
        val risky = MEAL.menuItems.first().copy(
            allergyCodes = listOf(9, 7, 5, 7),
        )

        viewModel.record(
            risky,
            EatingStatus.AllergyAvoided,
            listOf(DifficultyReason.Texture),
        )

        val command = recorder.commands.single()
        assertTrue(command.difficultyReasons.isEmpty())
        assertEquals(listOf(5, 7), command.allergyCodes)
        assertEquals(listOf(2, 5, 7), command.childAllergyCodes)
        assertEquals(listOf(5, 7, 9), command.itemAllergyCodes)
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

    private suspend fun expectTodayFailure(
        block: suspend () -> Unit,
    ): TodayForestException {
        try {
            block()
        } catch (error: TodayForestException) {
            return error
        }
        throw AssertionError("Expected TodayForestException")
    }

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
