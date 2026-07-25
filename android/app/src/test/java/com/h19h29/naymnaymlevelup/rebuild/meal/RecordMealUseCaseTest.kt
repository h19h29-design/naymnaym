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
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.json.JSONArray
import org.json.JSONObject

class RecordMealUseCaseTest {
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
    fun legacyHalfAndMismatchedCanonicalIdentityAreRejectedWithoutWrites() = runTest {
        val store = FakeMealRecordingStore()
        val useCase = useCase(store)

        val legacy = expectFailure<RecordMealException> {
            useCase.execute(
                command(
                    recordID = "2026-07-25|시금치나물|half",
                    status = EatingStatus.Half,
                ),
            )
        }
        assertEquals(RecordMealFailure.InactiveStatus, legacy.failure)

        val mismatch = expectFailure<RecordMealException> {
            useCase.execute(command(recordID = "not-canonical"))
        }
        assertEquals(RecordMealFailure.InvalidRecordIdentity, mismatch.failure)

        val impossibleDate = expectFailure<RecordMealException> {
            useCase.execute(
                command(
                    recordID = "2026-02-30|시금치나물|oneBite",
                    date = "2026-02-30",
                ),
            )
        }
        assertEquals(RecordMealFailure.InvalidRecordIdentity, impossibleDate.failure)
        assertTrue(store.records.isEmpty())
        assertTrue(store.events.isEmpty())
    }

    @Test
    fun canonicalIdentityTrimsAndLowercasesWithoutRemovingInteriorSpaces() = runTest {
        val store = FakeMealRecordingStore()
        val command = command(
            recordID = "2026-07-25|spinach 나물|oneBite",
            menuName = "  SPINACH 나물 \n",
        )

        useCase(store).execute(command)

        val record = store.records.values.single()
        assertEquals("2026-07-25|spinach 나물|oneBite", record.id)
        assertEquals("spinach 나물", record.normalizedMenuName)
        assertEquals("  SPINACH 나물 \n", record.menuName)
    }

    @Test
    fun allergyRiskCannotBeRecordedAsChallengeAndSafetyRecordWins() = runTest {
        val store = FakeMealRecordingStore()
        val useCase = useCase(store)

        val unsafe = expectFailure<RecordMealException> {
            useCase.execute(command(allergyCodes = listOf(5)))
        }
        assertEquals(RecordMealFailure.AllergySafetyRequired, unsafe.failure)

        val safety = useCase.execute(
            command(
                recordID = "2026-07-25|시금치나물|allergyAvoided",
                status = EatingStatus.AllergyAvoided,
                allergyCodes = listOf(5),
            ),
        )
        assertEquals(RecordMealResult(8, 8, MotionState.MealSuccess), safety)
    }

    @Test
    fun difficultRecordUsesComfortMotionAndNeverDeductsXp() = runTest {
        val result = useCase(FakeMealRecordingStore()).execute(
            command(
                recordID = "2026-07-25|시금치나물|difficultToday",
                status = EatingStatus.DifficultToday,
                difficultyReasons = listOf(DifficultyReason.Texture),
            ),
        )

        assertEquals(RecordMealResult(3, 3, MotionState.Comfort), result)
    }

    @Test
    fun updatingExistingCanonicalRecordCannotCreateMissingXp() = runTest {
        val store = FakeMealRecordingStore().apply {
            seedRecord(command(parentShareEnabled = false))
        }

        val result = useCase(store).execute(command(parentShareEnabled = true))

        assertEquals(0, result.xpGranted)
        assertEquals(0, result.totalXP)
        assertEquals(1, store.records.size)
        assertEquals(true, store.records.values.single().parentShareEnabled)
        assertEquals(1, store.events.size)
        assertEquals(0, store.events.values.single().amount)
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
    fun xpPolicyCannotPromoteLegacyHalfToActive() {
        val policy = JSONObject(contractBytes("xp-policy.json").decodeToString())
        policy.put(
            "activeStatuses",
            JSONArray(
                listOf(
                    "half",
                    "finished",
                    "smelledOnly",
                    "difficultToday",
                    "allergyAvoided",
                ),
            ),
        )
        policy.put("legacyReadCompatibleStatuses", JSONArray(listOf("oneBite")))

        val error = expectFailure<ContractLoadException> {
            RecordMealUseCase(
                store = FakeMealRecordingStore(),
                policyBytes = policy.toString().encodeToByteArray(),
            )
        }

        assertEquals("xp-policy.json", error.contractName)
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
        recordID: String = "2026-07-25|시금치나물|oneBite",
        date: String = "2026-07-25",
        menuName: String = "시금치나물",
        status: EatingStatus = EatingStatus.OneBite,
        difficultyReasons: List<DifficultyReason> = emptyList(),
        allergyCodes: List<Int> = emptyList(),
        photoIDs: List<String> = emptyList(),
        parentShareEnabled: Boolean = false,
    ): RecordMealCommand = RecordMealCommand(
        recordID = recordID,
        date = date,
        menuName = menuName,
        status = status,
        difficultyReasons = difficultyReasons,
        allergyCodes = allergyCodes,
        photoIDs = photoIDs,
        parentShareEnabled = parentShareEnabled,
        occurredAt = Instant.ofEpochSecond(1_753_430_400),
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

    override suspend fun <T> withTransaction(
        block: suspend MealRecordingTransaction.() -> T,
    ): T = mutex.withLock {
        val workingRecords = LinkedHashMap(records)
        val workingEvents = LinkedHashMap(events)
        val transaction = object : MealRecordingTransaction {
            override suspend fun findRecord(id: String): MealRecordEntity? =
                workingRecords[id]

            override suspend fun upsertRecord(record: MealRecordEntity) {
                workingRecords[record.id] = record
            }

            override suspend fun findProgressEvent(id: String): ProgressEventEntity? =
                workingEvents[id]

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

            override suspend fun dailyBaseXp(date: String): Int =
                workingEvents.values
                    .filter { event ->
                        event.id.startsWith("meal:") &&
                            event.sourceRecordId?.startsWith("$date|") == true
                    }
                    .sumOf { it.amount }

            override suspend fun dailyTotalXp(date: String): Int =
                workingEvents.values
                    .filter { it.sourceRecordId?.startsWith("$date|") == true }
                    .sumOf { it.amount }

            override suspend fun totalXp(): Int =
                workingEvents.values.sumOf { it.amount }
        }

        val result = transaction.block()
        records.clear()
        records.putAll(workingRecords)
        events.clear()
        events.putAll(workingEvents)
        result
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

    fun seedEvent(
        id: String,
        amount: Int,
        sourceRecordId: String,
    ) {
        events[id] = ProgressEventEntity(
            id = id,
            amount = amount,
            occurredAtEpochMillis = Instant.ofEpochSecond(1_753_430_400).toEpochMilli(),
            sourceRecordId = sourceRecordId,
        )
    }
}
