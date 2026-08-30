package com.h19h29.naymnaymlevelup.rebuild.meal

import com.h19h29.naymnaymlevelup.rebuild.data.MealRecordEntity
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import java.io.File
import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.json.JSONArray
import org.json.JSONObject

class RecordMealUseCaseTest {
    @Test
    fun bundledXpPolicyDecodesWithAllSixStatusesActiveAndNoLegacyStatuses() {
        RecordMealUseCase(
            store = FakeMealRecordingStore(),
            policyBytes = contractBytes("xp-policy.json"),
        )
    }

    @Test
    fun sharedSpinachFixtureAwardsOnce() = runTest {
        val store = FakeMealRecordingStore()
        val useCase = RecordMealUseCase(
            store = store,
            policyBytes = contractBytes("xp-policy.json"),
        )
        val command = command()

        val first = useCase.execute(command)
        val second = useCase.execute(command)

        assertEquals(
            listOf("fiber", "vitamin"),
            NutritionRuleEngine(contractBytes("nutrition-rules.json"))
                .insight(command.menuName)
                .nutrients
                .map { it.id },
        )
        assertEquals(
            RecordMealResult(18, 18, MotionState.MealSuccess),
            first,
        )
        assertEquals(0, second.xpGranted)
        assertEquals(18, second.totalXP)
        assertEquals(1, store.records.size)
        assertEquals(1, store.events.size)
    }

    @Test
    fun nutritionUsesContractOrderDeduplicationAndChildSafeCopy() {
        val insight = NutritionRuleEngine(contractBytes("nutrition-rules.json"))
            .insight("멸치 김치")

        assertEquals(
            listOf(
                NutritionNutrient("vitamin", "비타민", listOf("귤", "토마토")),
                NutritionNutrient("protein", "단백질", listOf("달걀", "두부")),
                NutritionNutrient("iron", "철분", listOf("소고기", "두부")),
                NutritionNutrient("calcium", "칼슘", listOf("우유", "멸치")),
            ),
            insight.nutrients,
        )
        assertEquals(1, insight.ruleVersion)
        assertEquals("영양소를 조금 놓칠 수 있어요.", insight.omissionCopy)
        assertEquals(
            "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요.",
            insight.educationNotice,
        )
    }

    @Test
    fun nutritionOutputFollowsNutrientOrderWhenRulesAreReordered() {
        val document = JSONObject(contractBytes("nutrition-rules.json").decodeToString())
        val rules = document.getJSONArray("rules")
        val reordered = JSONArray()
        for (index in rules.length() - 1 downTo 0) {
            reordered.put(rules.getJSONObject(index))
        }
        document.put("rules", reordered)

        val insight = NutritionRuleEngine(document.toString().encodeToByteArray())
            .insight("멸치 김치")

        assertEquals(
            listOf("vitamin", "protein", "iron", "calcium"),
            insight.nutrients.map { it.id },
        )
    }

    @Test
    fun nutritionRejectsUnsafeOrChangedContractCopy() {
        val document = JSONObject(contractBytes("nutrition-rules.json").decodeToString())
        document.put("omissionCopy", "반드시 먹어야 해요.")
        document.put("educationNotice", "이 음식은 병을 치료해요.")

        val error = expectFailure<ContractLoadException> {
            NutritionRuleEngine(document.toString().encodeToByteArray())
        }

        assertEquals("nutrition-rules.json", error.contractName)
    }

    @Test
    fun malformedNutritionContractFailsDeterministically() {
        val error = expectFailure<ContractLoadException> {
            NutritionRuleEngine("""{"version":1,"rules":[]}""".encodeToByteArray())
        }

        assertEquals("nutrition-rules.json", error.contractName)
    }

    @Test
    fun nutritionContractRejectsIntegralFloatingPointVersion() {
        val floatingPointVersion = contractBytes("nutrition-rules.json")
            .decodeToString()
            .replace("\"version\": 1", "\"version\": 1.0")
            .encodeToByteArray()

        val error = expectFailure<ContractLoadException> {
            NutritionRuleEngine(floatingPointVersion)
        }

        assertEquals("nutrition-rules.json", error.contractName)
    }

    @Test
    fun nearBaseCapGrantsOnlyRemainingFiveXp() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:2026-07-25|기존|finished",
                amount = 45,
                sourceRecordId = "2026-07-25|기존|finished",
            )
        }

        val result = useCase(store).execute(command())

        assertEquals(RecordMealResult(5, 50, MotionState.MealSuccess), result)
    }

    @Test
    fun dailyTotalCapStopsBaseAfterChallengeUsage() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:2026-07-25|기존|finished",
                amount = 30,
                sourceRecordId = "2026-07-25|기존|finished",
            )
            seedEvent(
                id = "challenge:2026-07-25|기존|finished",
                amount = 70,
                sourceRecordId = "2026-07-25|기존|finished",
            )
        }

        val result = useCase(store).execute(command())

        assertEquals(RecordMealResult(0, 100, MotionState.MealSuccess), result)
    }

    @Test
    fun statusTransitionRepairsCanonicalRowsWithoutAdditionalXp() = runTest {
        val store = FakeMealRecordingStore()
        val useCase = useCase(store)

        val first = useCase.execute(command())
        val transitioned = useCase.execute(
            command(
                status = EatingStatus.Finished,
                occurredAt = Instant.ofEpochSecond(1_753_430_401),
            ),
        )

        assertEquals(18, first.xpGranted)
        assertEquals(0, transitioned.xpGranted)
        assertEquals(18, transitioned.totalXP)
        assertEquals(1, store.records.size)
        assertEquals(EatingStatus.Finished.wireValue, store.records.values.single().status)
        assertEquals(1, store.events.size)
        assertEquals(18, store.events.values.single().amount)
    }

    @Test
    fun newerRevisionCannotBeOverwrittenByAnOlderCommand() = runTest {
        val store = FakeMealRecordingStore()
        val useCase = useCase(store)
        val newer = command(
            status = EatingStatus.Finished,
            photoIDs = listOf("newer-photo"),
            parentShareEnabled = true,
            occurredAt = Instant.ofEpochSecond(1_753_430_410),
        )
        useCase.execute(newer)
        val recordsBefore = LinkedHashMap(store.records)
        val eventsBefore = LinkedHashMap(store.events)

        val error = expectFailure<RecordMealException> {
            useCase.execute(
                command(
                    status = EatingStatus.OneBite,
                    photoIDs = listOf("older-photo"),
                    parentShareEnabled = false,
                    occurredAt = Instant.ofEpochSecond(1_753_430_400),
                ),
            )
        }

        assertEquals("StaleRevision", error.failure.name)
        assertEquals(recordsBefore, store.records)
        assertEquals(eventsBefore, store.events)
    }

    @Test
    fun equalTimestampExactReplaySucceedsWithoutAdditionalXp() = runTest {
        val store = FakeMealRecordingStore()
        val useCase = useCase(store)
        val replay = command(
            photoIDs = listOf("photo-1"),
            parentShareEnabled = true,
        )

        val first = useCase.execute(replay)
        val second = useCase.execute(replay)

        assertEquals(18, first.xpGranted)
        assertEquals(0, second.xpGranted)
        assertEquals(18, second.totalXP)
        assertEquals(1, store.records.size)
        assertEquals(1, store.events.size)
        assertEquals("[\"photo-1\"]", store.records.values.single().photoIdsJson)
        assertTrue(store.records.values.single().parentShareEnabled)
    }

    @Test
    fun equalTimestampConflictingPayloadIsRejectedBeforeMutation() = runTest {
        val cases = listOf(
            "status" to (
                command() to command(status = EatingStatus.Finished)
                ),
            "difficulty reasons" to (
                command(
                    status = EatingStatus.DifficultToday,
                    difficultyReasons = listOf(DifficultyReason.Texture),
                ) to command(
                    status = EatingStatus.DifficultToday,
                    difficultyReasons = listOf(DifficultyReason.Taste),
                )
                ),
            "allergy overlap" to (
                command(
                    status = EatingStatus.AllergyAvoided,
                    allergyCodes = listOf(5),
                ) to command(
                    status = EatingStatus.AllergyAvoided,
                    allergyCodes = listOf(5, 7),
                )
                ),
            "photo" to (
                command(photoIDs = listOf("photo-1")) to
                    command(photoIDs = listOf("photo-1", "photo-2"))
                ),
            "raw menu" to (
                command(
                    recordID = "2026-07-25|spinach",
                    menuName = "spinach",
                ) to command(
                    recordID = "2026-07-25|spinach",
                    menuName = " SPINACH ",
                )
                ),
        )

        cases.forEach { (label, revisions) ->
            val store = FakeMealRecordingStore()
            val useCase = useCase(store)
            useCase.execute(revisions.first)
            val recordsBefore = LinkedHashMap(store.records)
            val eventsBefore = LinkedHashMap(store.events)

            val error = expectFailure<RecordMealException> {
                useCase.execute(revisions.second)
            }

            assertEquals(
                label,
                "ConflictingRevision",
                error.failure.name,
            )
            assertEquals(label, recordsBefore, store.records)
            assertEquals(label, eventsBefore, store.events)
        }
    }

    @Test
    fun crossStatusRecordOrEventAloneSealsAward() = runTest {
        val recordStore = FakeMealRecordingStore().apply {
            seedRecord(
                command(
                    recordID = "2026-07-25|시금치나물|finished",
                    status = EatingStatus.Finished,
                ),
            )
        }
        val recordSealed = useCase(recordStore).execute(
            command(occurredAt = Instant.ofEpochSecond(1_753_430_401)),
        )

        assertEquals(0, recordSealed.xpGranted)
        assertEquals(0, recordSealed.totalXP)
        assertEquals(1, recordStore.records.size)
        assertEquals(1, recordStore.events.size)

        val eventStore = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:2026-07-25|시금치나물|finished",
                amount = 10,
                sourceRecordId = "2026-07-25|시금치나물|finished",
            )
        }
        val eventSealed = useCase(eventStore).execute(command())

        assertEquals(0, eventSealed.xpGranted)
        assertEquals(10, eventSealed.totalXP)
        assertEquals(1, eventStore.records.size)
        assertEquals(1, eventStore.events.size)
    }

    @Test
    fun newestLegacyWinnerPreservesIdentityMetadataAndSourceEventWhileSoftDeletingDuplicates() =
        runTest {
            val store = FakeMealRecordingStore().apply {
                seedRecordEntity(
                    id = "2026-07-25|rice|finished",
                    normalizedMenuName = "rice",
                    status = EatingStatus.Finished,
                    photoIdsJson = "[\"older-photo\"]",
                    parentShareEnabled = false,
                    updatedAtEpochMillis = 1_000,
                )
                seedRecordEntity(
                    id = "2026-07-25|rice|half",
                    normalizedMenuName = "rice",
                    status = EatingStatus.Half,
                    photoIdsJson = "[\"winner-photo\"]",
                    parentShareEnabled = true,
                    updatedAtEpochMillis = 2_000,
                )
                seedEvent(
                    id = "meal:2026-07-25|rice|finished",
                    amount = 10,
                    sourceRecordId = "2026-07-25|rice|finished",
                )
            }

            val result = useCase(store).execute(
                command(
                    recordID = "2026-07-25|rice",
                    menuName = "RICE",
                    status = EatingStatus.OneBite,
                    photoIDs = listOf("winner-photo", "new-photo"),
                    parentShareEnabled = false,
                ),
            )

            assertEquals(RecordMealResult(0, 10, MotionState.MealSuccess), result)
            assertEquals(2, store.records.size)
            val winner = store.records.getValue("2026-07-25|rice|half")
            assertEquals(EatingStatus.OneBite.wireValue, winner.status)
            assertEquals(
                "[\"winner-photo\", \"older-photo\", \"new-photo\"]",
                winner.photoIdsJson,
            )
            assertTrue(winner.parentShareEnabled)
            assertNull(winner.deletedAtEpochMillis)
            assertEquals(
                Instant.ofEpochSecond(1_753_430_400).toEpochMilli(),
                store.records.getValue("2026-07-25|rice|finished")
                    .deletedAtEpochMillis,
            )
            assertEquals(1, store.records.values.count { it.deletedAtEpochMillis == null })
            assertEquals(1, store.events.size)
            assertEquals(
                "2026-07-25|rice|finished",
                store.events.values.single().sourceRecordId,
            )
        }

    @Test
    fun corruptActiveLoserPhotoJsonFailsClosedBeforeAnyMutation() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedRecordEntity(
                id = "2026-07-25|rice|oneBite",
                normalizedMenuName = "rice",
                status = EatingStatus.OneBite,
                photoIdsJson = "{",
                updatedAtEpochMillis = 1_000,
            )
            seedRecordEntity(
                id = "2026-07-25|rice|half",
                normalizedMenuName = "rice",
                status = EatingStatus.Half,
                photoIdsJson = "[\"winner-photo\"]",
                updatedAtEpochMillis = 2_000,
            )
        }
        val before = LinkedHashMap(store.records)

        val error = expectFailure<ContractLoadException> {
            useCase(store).execute(
                command(
                    recordID = "2026-07-25|rice",
                    menuName = "rice",
                    status = EatingStatus.Finished,
                ),
            )
        }

        assertEquals("meal-record.json", error.contractName)
        assertEquals(before, store.records)
        assertEquals(2, store.records.values.count { it.deletedAtEpochMillis == null })
        assertTrue(store.events.isEmpty())
    }

    @Test
    fun migratedCustomWinnerAndItsExactSourceEventArePreserved() = runTest {
        val migratedId = "550e8400-e29b-41d4-a716-446655440000"
        val store = FakeMealRecordingStore().apply {
            seedRecordEntity(
                id = "2026-07-25|rice|finished",
                normalizedMenuName = "rice",
                status = EatingStatus.Finished,
                photoIdsJson = "[\"legacy-photo\"]",
                updatedAtEpochMillis = 1_000,
            )
            seedRecordEntity(
                id = migratedId,
                normalizedMenuName = "rice",
                status = EatingStatus.Half,
                photoIdsJson = "[\"migrated-photo\"]",
                parentShareEnabled = true,
                updatedAtEpochMillis = 2_000,
            )
            seedEvent(
                id = "meal:$migratedId",
                amount = 12,
                sourceRecordId = migratedId,
            )
        }

        val result = useCase(store).execute(
            command(
                recordID = "2026-07-25|rice",
                menuName = "rice",
                status = EatingStatus.OneBite,
                photoIDs = listOf("new-photo"),
                parentShareEnabled = false,
            ),
        )

        assertEquals(RecordMealResult(0, 12, MotionState.MealSuccess), result)
        val winner = store.records.getValue(migratedId)
        assertEquals(EatingStatus.OneBite.wireValue, winner.status)
        assertEquals(
            "[\"migrated-photo\", \"legacy-photo\", \"new-photo\"]",
            winner.photoIdsJson,
        )
        assertTrue(winner.parentShareEnabled)
        assertNull(winner.deletedAtEpochMillis)
        assertEquals(1, store.records.values.count { it.deletedAtEpochMillis == null })
        assertEquals(2, store.records.size)
        assertEquals(1, store.events.size)
        assertEquals("meal:$migratedId", store.events.values.single().id)
        assertEquals(migratedId, store.events.values.single().sourceRecordId)
    }

    @Test
    fun equalTimestampLegacyWinnerUsesAscendingIdentityTieBreak() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedRecordEntity(
                id = "2026-07-25|rice|oneBite",
                normalizedMenuName = "rice",
                status = EatingStatus.OneBite,
                updatedAtEpochMillis = 2_000,
            )
            seedRecordEntity(
                id = "2026-07-25|rice|half",
                normalizedMenuName = "rice",
                status = EatingStatus.Half,
                updatedAtEpochMillis = 2_000,
            )
        }

        useCase(store).execute(
            command(
                recordID = "2026-07-25|rice",
                menuName = "rice",
                status = EatingStatus.Finished,
            ),
        )

        assertNull(store.records.getValue("2026-07-25|rice|half").deletedAtEpochMillis)
        assertEquals(
            Instant.ofEpochSecond(1_753_430_400).toEpochMilli(),
            store.records.getValue("2026-07-25|rice|oneBite").deletedAtEpochMillis,
        )
    }

    @Test
    fun exactLogicalIdentityDoesNotTreatRiceballAsRice() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:2026-07-25|riceball|finished",
                amount = 10,
                sourceRecordId = "2026-07-25|riceball|finished",
            )
        }

        val result = useCase(store).execute(
            command(
                recordID = "2026-07-25|rice",
                menuName = "rice",
            ),
        )

        assertEquals(18, result.xpGranted)
        assertEquals(28, result.totalXP)
        assertEquals(2, store.events.size)
    }

    @Test
    fun unrelatedStableIdentityCollisionFailsWithoutOverwriting() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedRecordEntity(
                id = "2026-07-25|rice",
                normalizedMenuName = "riceball",
                status = EatingStatus.Finished,
                updatedAtEpochMillis = 2_000,
            )
        }
        val original = store.records.getValue("2026-07-25|rice")

        val error = expectFailure<RecordMealException> {
            useCase(store).execute(
                command(
                    recordID = "2026-07-25|rice",
                    menuName = "rice",
                ),
            )
        }

        assertEquals(RecordMealFailure.RecordIdentityCollision, error.failure)
        assertEquals(listOf("2026-07-25|rice"), store.recordLookups)
        assertEquals(original, store.records.getValue("2026-07-25|rice"))
        assertTrue(store.events.isEmpty())
    }

    @Test
    fun migratedMealEventWithUuidSourceCountsTowardSeoulDailyBaseCap() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:migrated-uuid",
                amount = 45,
                sourceRecordId = "550e8400-e29b-41d4-a716-446655440000",
                occurredAt = Instant.ofEpochSecond(1_784_948_400),
            )
        }

        val result = useCase(store).execute(command())

        assertEquals(RecordMealResult(5, 50, MotionState.MealSuccess), result)
    }

    @Test
    fun migratedChallengeEventWithNilSourceCountsTowardSeoulDailyTotalCap() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "challenge:migrated-no-source",
                amount = 95,
                sourceRecordId = null,
                occurredAt = Instant.ofEpochSecond(1_784_948_400),
            )
        }

        val result = useCase(store).execute(command())

        assertEquals(RecordMealResult(5, 100, MotionState.MealSuccess), result)
    }

    @Test
    fun canonicalSourceDateWinsOverBackfilledOccurredAtDate() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:backfilled-canonical-source",
                amount = 100,
                sourceRecordId = "2026-07-24|기존|finished",
                occurredAt = Instant.ofEpochSecond(1_784_948_400),
            )
        }

        val result = useCase(store).execute(command())

        assertEquals(RecordMealResult(18, 118, MotionState.MealSuccess), result)
    }

    @Test
    fun negativeCorrectionsNeverCancelPositiveDailyOrLifetimeXp() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:positive",
                amount = 45,
                sourceRecordId = "2026-07-25|기존|finished",
            )
            seedEvent(
                id = "meal:negative-correction",
                amount = -40,
                sourceRecordId = "2026-07-25|교정|finished",
            )
        }

        val result = useCase(store).execute(command())

        assertEquals(RecordMealResult(5, 50, MotionState.MealSuccess), result)
    }

    @Test
    fun allSixStatusesAreActiveAndLegacyCommandIdentityIsRejected() = runTest {
        val store = FakeMealRecordingStore()
        val useCase = useCase(store)

        val half = useCase.execute(command(status = EatingStatus.Half))
        assertEquals(12, half.xpGranted)

        val legacyIdentity = expectFailure<RecordMealException> {
            useCase.execute(
                command(recordID = "2026-07-25|시금치나물|finished"),
            )
        }
        assertEquals(
            RecordMealFailure.InvalidRecordIdentity,
            legacyIdentity.failure,
        )

        val impossibleDate = expectFailure<RecordMealException> {
            useCase.execute(
                command(
                    recordID = "2026-02-30|시금치나물",
                    date = "2026-02-30",
                ),
            )
        }
        assertEquals(RecordMealFailure.InvalidRecordIdentity, impossibleDate.failure)
        assertEquals(1, store.records.size)
        assertEquals(1, store.events.size)
    }

    @Test
    fun canonicalIdentityTrimsAndLowercasesWithoutRemovingInteriorSpaces() = runTest {
        val store = FakeMealRecordingStore()
        val command = command(
            recordID = "2026-07-25|spinach 나물",
            menuName = "  SPINACH 나물 \n",
        )

        useCase(store).execute(command)

        val record = store.records.values.single()
        assertEquals("2026-07-25|spinach 나물", record.id)
        assertEquals("spinach 나물", record.normalizedMenuName)
        assertEquals("  SPINACH 나물 \n", record.menuName)
    }

    @Test
    fun allergyRiskRejectsEveryNonAvoidanceStatusAndAllowsSafetyRecord() = runTest {
        EatingStatus.entries
            .filterNot { it == EatingStatus.AllergyAvoided }
            .forEach { status ->
                val store = FakeMealRecordingStore()
                val unsafe = expectFailure<RecordMealException> {
                    useCase(store).execute(
                        command(
                            status = status,
                            allergyCodes = listOf(5),
                            childAllergyCodes = listOf(2, 5),
                            itemAllergyCodes = listOf(5, 9),
                        ),
                    )
                }
                assertEquals(
                    status.wireValue,
                    RecordMealFailure.AllergySafetyRequired,
                    unsafe.failure,
                )
                assertTrue(store.records.isEmpty())
                assertTrue(store.events.isEmpty())
            }

        val safety = useCase(FakeMealRecordingStore()).execute(
            command(
                status = EatingStatus.AllergyAvoided,
                allergyCodes = listOf(5),
                childAllergyCodes = listOf(2, 5),
                itemAllergyCodes = listOf(5, 9),
            ),
        )
        assertEquals(RecordMealResult(8, 8, MotionState.MealSuccess), safety)
    }

    @Test
    fun allergyContextMustMatchTheExactSortedIntersectionBeforeAnyWrite() = runTest {
        val commands = listOf(
            command(
                status = EatingStatus.AllergyAvoided,
                allergyCodes = emptyList(),
                childAllergyCodes = listOf(5),
                itemAllergyCodes = listOf(5),
            ),
            command(
                status = EatingStatus.AllergyAvoided,
                allergyCodes = listOf(5),
                childAllergyCodes = listOf(5, 7),
                itemAllergyCodes = listOf(7, 9),
            ),
            command(
                status = EatingStatus.AllergyAvoided,
                allergyCodes = listOf(7, 5),
                childAllergyCodes = listOf(5, 7),
                itemAllergyCodes = listOf(5, 7, 9),
            ),
        )

        commands.forEach { invalidCommand ->
            val store = FakeMealRecordingStore()

            val error = expectFailure<RecordMealException> {
                useCase(store).execute(invalidCommand)
            }

            assertEquals(
                RecordMealFailure.AllergyContextMismatch,
                error.failure,
            )
            assertTrue(store.records.isEmpty())
            assertTrue(store.events.isEmpty())
        }
    }

    @Test
    fun difficultRecordUsesComfortMotionAndNeverDeductsXp() = runTest {
        val result = useCase(FakeMealRecordingStore()).execute(
            command(
                status = EatingStatus.DifficultToday,
                difficultyReasons = listOf(DifficultyReason.Texture),
            ),
        )

        assertEquals(RecordMealResult(3, 3, MotionState.Comfort), result)
    }

    @Test
    fun updatingExistingStableRecordPreservesParentShareInBothDirections() = runTest {
        listOf(false to true, true to false).forEach { (stored, incoming) ->
            val store = FakeMealRecordingStore().apply {
                seedRecord(command(parentShareEnabled = stored))
            }

            val transition = command(
                parentShareEnabled = incoming,
                occurredAt = Instant.ofEpochSecond(1_753_430_401),
            )
            val useCase = useCase(store)
            val result = useCase.execute(transition)
            val replay = useCase.execute(transition)

            assertEquals(0, result.xpGranted)
            assertEquals(0, replay.xpGranted)
            assertEquals(0, result.totalXP)
            assertEquals(0, replay.totalXP)
            assertEquals(1, store.records.size)
            assertEquals(stored, store.records.values.single().parentShareEnabled)
            assertEquals(1, store.events.size)
            assertEquals(0, store.events.values.single().amount)
        }
    }

    @Test
    fun existingEventWithoutRecordRepairsRecordWithoutDuplicateXp() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "meal:2026-07-25|시금치나물|oneBite",
                amount = 18,
                sourceRecordId = "2026-07-25|시금치나물|oneBite",
            )
        }

        val result = useCase(store).execute(command())

        assertEquals(0, result.xpGranted)
        assertEquals(18, result.totalXP)
        assertEquals(1, store.records.size)
        assertEquals(1, store.events.size)
    }

    @Test
    fun transactionFailureRollsBackRecordAndProgressTogether() = runTest {
        val store = FakeMealRecordingStore(failProgressInsert = true)

        expectFailure<IllegalStateException> {
            useCase(store).execute(command())
        }

        assertTrue(store.records.isEmpty())
        assertTrue(store.events.isEmpty())
    }

    @Test
    fun totalOverflowRollsBackNewRecordAndEvent() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedEvent(
                id = "legacy:overflow-max",
                amount = Int.MAX_VALUE,
                sourceRecordId = "2025-07-25|legacy|finished",
            )
        }

        val error = expectFailure<RecordMealException> {
            useCase(store).execute(command())
        }

        assertEquals(RecordMealFailure.XpOverflow, error.failure)
        assertTrue(store.records.isEmpty())
        assertEquals(1, store.events.size)
    }

    @Test
    fun concurrentDuplicateCommandsHaveOneWinner() = runTest {
        val store = FakeMealRecordingStore()
        val first = useCase(store)
        val second = useCase(store)

        val results = listOf(first, second)
            .map { useCase ->
                async { useCase.execute(command()) }
            }
            .awaitAll()

        assertEquals(listOf(0, 18), results.map { it.xpGranted }.sorted())
        assertEquals(1, store.records.size)
        assertEquals(1, store.events.size)
        assertEquals(18, store.events.values.single().amount)
    }

    @Test
    fun ignoredProgressInsertNeverReportsUncommittedXp() = runTest {
        val store = FakeMealRecordingStore(forceInsertConflict = true)

        val result = useCase(store).execute(command())

        assertEquals(0, result.xpGranted)
        assertEquals(18, result.totalXP)
        assertEquals(1, store.records.size)
        assertEquals(1, store.events.size)
    }

    @Test
    fun malformedXpPolicyFailsBeforeAnyWrite() {
        val store = FakeMealRecordingStore()
        val policy = JSONObject(contractBytes("xp-policy.json").decodeToString())
        policy.getJSONObject("statusXP").put("oneBite", -18)
        val error = expectFailure<ContractLoadException> {
            RecordMealUseCase(
                store = store,
                policyBytes = policy.toString().encodeToByteArray(),
            )
        }

        assertEquals("xp-policy.json", error.contractName)
        assertTrue(store.records.isEmpty())
        assertTrue(store.events.isEmpty())
    }

    @Test
    fun xpPolicyRejectsAnyLegacyReadCompatibleStatus() {
        val policy = JSONObject(contractBytes("xp-policy.json").decodeToString())
        policy.put(
            "activeStatuses",
            JSONArray(
                listOf(
                    "finished",
                    "oneBite",
                    "smelledOnly",
                    "difficultToday",
                    "allergyAvoided",
                ),
            ),
        )
        policy.put("legacyReadCompatibleStatuses", JSONArray(listOf("half")))

        val error = expectFailure<ContractLoadException> {
            RecordMealUseCase(
                store = FakeMealRecordingStore(),
                policyBytes = policy.toString().encodeToByteArray(),
            )
        }

        assertEquals("xp-policy.json", error.contractName)
    }

    @Test
    fun xpPolicyCannotEnableStatusTransitionAwards() {
        val policy = JSONObject(contractBytes("xp-policy.json").decodeToString())
        policy.put("statusTransitionsGrantAdditionalXP", true)

        val error = expectFailure<ContractLoadException> {
            RecordMealUseCase(
                store = FakeMealRecordingStore(),
                policyBytes = policy.toString().encodeToByteArray(),
            )
        }

        assertEquals("xp-policy.json", error.contractName)
    }

    @Test
    fun xpPolicyRejectsUnknownCapKeys() {
        val policy = JSONObject(contractBytes("xp-policy.json").decodeToString())
        policy.getJSONObject("caps").put("unexpected", 0)

        val error = expectFailure<ContractLoadException> {
            RecordMealUseCase(
                store = FakeMealRecordingStore(),
                policyBytes = policy.toString().encodeToByteArray(),
            )
        }

        assertEquals("xp-policy.json", error.contractName)
    }

    @Test
    fun xpPolicyRejectsIntegralFloatingPointNumbers() {
        val canonical = contractBytes("xp-policy.json").decodeToString()
        val replacements = listOf(
            "\"version\": 1" to "\"version\": 1.0",
            "\"oneBite\": 18" to "\"oneBite\": 18.0",
            "\"base\": 50" to "\"base\": 50.0",
        )

        replacements.forEach { (source, replacement) ->
            val error = expectFailure<ContractLoadException> {
                RecordMealUseCase(
                    store = FakeMealRecordingStore(),
                    policyBytes = canonical
                        .replace(source, replacement)
                        .encodeToByteArray(),
                )
            }

            assertEquals("xp-policy.json", error.contractName)
        }
    }

    private fun contractBytes(name: String): ByteArray {
        val candidates = listOf(
            File("src/main/assets/rebuild-contracts/$name"),
            File("app/src/main/assets/rebuild-contracts/$name"),
        )
        return candidates.firstOrNull(File::isFile)?.readBytes()
            ?: throw AssertionError("Missing bundled contract $name")
    }

    private fun useCase(store: MealRecordingStore): RecordMealUseCase =
        RecordMealUseCase(
            store = store,
            policyBytes = contractBytes("xp-policy.json"),
        )

    private fun command(
        recordID: String = "2026-07-25|시금치나물",
        date: String = "2026-07-25",
        menuName: String = "시금치나물",
        status: EatingStatus = EatingStatus.OneBite,
        difficultyReasons: List<DifficultyReason> = emptyList(),
        allergyCodes: List<Int> = emptyList(),
        childAllergyCodes: List<Int> = allergyCodes,
        itemAllergyCodes: List<Int> = allergyCodes,
        photoIDs: List<String> = emptyList(),
        parentShareEnabled: Boolean = false,
        occurredAt: Instant = Instant.ofEpochSecond(1_753_430_400),
    ): RecordMealCommand = RecordMealCommand(
        recordID = recordID,
        date = date,
        menuName = menuName,
        status = status,
        difficultyReasons = difficultyReasons,
        allergyCodes = allergyCodes,
        childAllergyCodes = childAllergyCodes,
        itemAllergyCodes = itemAllergyCodes,
        photoIDs = photoIDs,
        parentShareEnabled = parentShareEnabled,
        occurredAt = occurredAt,
    )

    private inline fun <reified T : Throwable> expectFailure(
        block: () -> Unit,
    ): T {
        try {
            block()
            fail("Expected ${T::class.java.simpleName}")
        } catch (error: Throwable) {
            if (error !is T) {
                throw error
            }
            return error
        }
        error("unreachable")
    }
}

private class FakeMealRecordingStore(
    private val failProgressInsert: Boolean = false,
    private val forceInsertConflict: Boolean = false,
) : MealRecordingStore {
    private val mutex = Mutex()
    val records = linkedMapOf<String, MealRecordEntity>()
    val events = linkedMapOf<String, ProgressEventEntity>()
    val recordLookups = mutableListOf<String>()

    override suspend fun <T> withTransaction(
        block: suspend MealRecordingTransaction.() -> T,
    ): T = mutex.withLock {
        val workingRecords = LinkedHashMap(records)
        val workingEvents = LinkedHashMap(events)
        val transaction = object : MealRecordingTransaction {
            override suspend fun findRecord(id: String): MealRecordEntity? =
                workingRecords[id].also { recordLookups += id }

            override suspend fun findLogicalRecords(
                date: String,
                normalizedMenuName: String,
            ): List<MealRecordEntity> =
                workingRecords.values.filter {
                    it.date == date &&
                        it.normalizedMenuName == normalizedMenuName
                }.sortedWith(
                    compareByDescending<MealRecordEntity> {
                        it.updatedAtEpochMillis
                    }.thenBy { it.id },
                )

            override suspend fun upsertRecord(record: MealRecordEntity) {
                workingRecords[record.id] = record
            }

            override suspend fun findLogicalMealEvents(
                recordIds: List<String>,
                eventIds: List<String>,
            ): List<ProgressEventEntity> =
                workingEvents.values.filter {
                    it.id.startsWith("meal:") &&
                        (
                            it.id in eventIds ||
                                it.sourceRecordId in recordIds
                            )
                }.sortedWith(
                    compareBy<ProgressEventEntity> {
                        it.occurredAtEpochMillis
                    }.thenBy { it.id },
                )

            override suspend fun insertProgressEvent(event: ProgressEventEntity): Boolean {
                if (failProgressInsert) {
                    throw IllegalStateException("forced progress failure")
                }
                if (forceInsertConflict) {
                    workingEvents[event.id] = event.copy(amount = 18)
                    return false
                }
                if (workingEvents.containsKey(event.id)) {
                    return false
                }
                workingEvents[event.id] = event
                return true
            }

            override suspend fun dailyBaseXp(
                date: String,
                dayStartEpochMillis: Long,
                nextDayStartEpochMillis: Long,
            ): Long =
                workingEvents.values
                    .filter { event ->
                        event.id.startsWith("meal:") &&
                            countsForDate(
                                event,
                                date,
                                dayStartEpochMillis,
                                nextDayStartEpochMillis,
                            )
                    }
                    .sumOf { it.amount.coerceAtLeast(0).toLong() }

            override suspend fun dailyTotalXp(
                date: String,
                dayStartEpochMillis: Long,
                nextDayStartEpochMillis: Long,
            ): Long =
                workingEvents.values
                    .filter { event ->
                        countsForDate(
                            event,
                            date,
                            dayStartEpochMillis,
                            nextDayStartEpochMillis,
                        )
                    }
                    .sumOf { it.amount.coerceAtLeast(0).toLong() }

            override suspend fun totalXp(): Long =
                workingEvents.values.sumOf {
                    it.amount.coerceAtLeast(0).toLong()
                }
        }

        val result = transaction.block()
        records.clear()
        records.putAll(workingRecords)
        events.clear()
        events.putAll(workingEvents)
        result
    }

    private fun countsForDate(
        event: ProgressEventEntity,
        date: String,
        dayStartEpochMillis: Long,
        nextDayStartEpochMillis: Long,
    ): Boolean {
        val sourceDate = canonicalSourceDate(event.sourceRecordId)
        return if (sourceDate != null) {
            sourceDate == date
        } else {
            event.occurredAtEpochMillis in
                dayStartEpochMillis..<nextDayStartEpochMillis
        }
    }

    private fun canonicalSourceDate(sourceRecordId: String?): String? {
        if (
            sourceRecordId == null ||
            sourceRecordId.length < 12 ||
            sourceRecordId[4] != '-' ||
            sourceRecordId[7] != '-' ||
            sourceRecordId[10] != '|'
        ) {
            return null
        }
        val date = sourceRecordId.substring(0, 10)
        return date
            .filterIndexed { index, _ -> index != 4 && index != 7 }
            .takeIf { digits -> digits.all(Char::isDigit) }
            ?.let { date }
    }

    fun seedRecord(command: RecordMealCommand) {
        records[command.recordID] = MealRecordEntity(
            id = command.recordID,
            date = command.date,
            menuName = command.menuName,
            normalizedMenuName = command.menuName,
            status = command.status.wireValue,
            difficultyReasonsJson = "[]",
            allergyCodesJson = "[]",
            photoIdsJson = "[]",
            parentShareEnabled = command.parentShareEnabled,
            updatedAtEpochMillis = command.occurredAt.toEpochMilli(),
            deletedAtEpochMillis = null,
        )
    }

    fun seedRecordEntity(
        id: String,
        normalizedMenuName: String,
        status: EatingStatus,
        photoIdsJson: String = "[]",
        parentShareEnabled: Boolean = false,
        updatedAtEpochMillis: Long,
        deletedAtEpochMillis: Long? = null,
    ) {
        records[id] = MealRecordEntity(
            id = id,
            date = "2026-07-25",
            menuName = normalizedMenuName,
            normalizedMenuName = normalizedMenuName,
            status = status.wireValue,
            difficultyReasonsJson = "[]",
            allergyCodesJson = "[]",
            photoIdsJson = photoIdsJson,
            parentShareEnabled = parentShareEnabled,
            updatedAtEpochMillis = updatedAtEpochMillis,
            deletedAtEpochMillis = deletedAtEpochMillis,
        )
    }

    fun seedEvent(
        id: String,
        amount: Int,
        sourceRecordId: String?,
        occurredAt: Instant = Instant.ofEpochSecond(1_753_430_400),
    ) {
        events[id] = ProgressEventEntity(
            id = id,
            amount = amount,
            occurredAtEpochMillis = occurredAt.toEpochMilli(),
            sourceRecordId = sourceRecordId,
        )
    }
}
