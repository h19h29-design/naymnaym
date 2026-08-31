package com.h19h29.naymnaymlevelup.rebuild.growth

import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.data.MealRecordEntity
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class GrowthRepositoryTest {
    @Test
    fun recentEventsArePositiveNewestFirstAndDeterministicallyOrdered() = runTest {
        val source = FakeGrowthProgressSource(
            totalXp = 734,
            events = listOf(
                event("meal:older", 7, 100),
                event("meal:same-a", 8, 200),
                event("meal:same-z", 9, 200),
                event("meal:zero", 0, 300),
                event("legacy:negative", -99, 400),
            ),
        )

        val snapshot = GrowthRepository(source).load(limit = 10)

        assertEquals(734, snapshot.totalXp)
        assertEquals(
            listOf("meal:same-z", "meal:same-a", "meal:older"),
            snapshot.recentEvents.map { it.id },
        )
    }

    @Test
    fun requestedLimitIsClampedBeforeTheStoreIsRead() = runTest {
        val source = FakeGrowthProgressSource(
            totalXp = 0,
            events = (0 until 25).map { index ->
                event("event:${index.toString().padStart(2, '0')}", 1, index.toLong())
            },
        )
        val repository = GrowthRepository(source)

        assertEquals(3, repository.load(limit = 3).recentEvents.size)
        assertEquals(3, source.requestedLimit)

        assertEquals(20, repository.load(limit = 10_000).recentEvents.size)
        assertEquals(20, source.requestedLimit)

        assertEquals(emptyList<ProgressEventEntity>(), repository.load(limit = 0).recentEvents)
        assertEquals(0, source.requestedLimit)
    }

    @Test
    fun canonicalMealCopyComesOnlyFromTheEventId() {
        val presentation = GrowthEventPresentation.from(
            event(
                id = "meal:2026-07-25|시금치 나물|oneBite",
                amount = 18,
                occurredAt = 100,
                sourceRecordId = "550e8400-e29b-41d4-a716-446655440000",
            ),
        )

        assertEquals("시금치 나물 · 한 입 도전", presentation.title)
        assertEquals("+18 XP", presentation.xpText)
    }

    @Test
    fun canonicalMealPresentationRejectsNoncanonicalIdentityAndSupportsHalf() {
        val cases = listOf(
            "meal:2026-07-25|오이|half" to "오이 · 절반 먹었어요",
            "meal:2026-02-30|오이|finished" to "성장 XP 획득",
            "meal:2026-07-25| 오이 |finished" to "성장 XP 획득",
            "meal:2026-07-25|SPINACH|finished" to "성장 XP 획득",
            "meal:2026-07-25|spinach|finished" to
                "spinach · 다 먹었어요",
        )

        cases.forEach { (id, expectedTitle) ->
            assertEquals(
                id,
                expectedTitle,
                GrowthEventPresentation.from(
                    event(
                        id = id,
                        amount = 12,
                        occurredAt = 100,
                    ),
                ).title,
            )
        }
    }

    @Test
    fun legacySourceRecordIdNeverInventsMealCopy() {
        val presentation = GrowthEventPresentation.from(
            event(
                id = "legacy:550e8400-e29b-41d4-a716-446655440000",
                amount = 12,
                occurredAt = 100,
                sourceRecordId = "2026-07-25|시금치 나물|finished",
            ),
        )

        assertEquals("성장 XP 획득", presentation.title)
        assertEquals("+12 XP", presentation.xpText)
    }

    @Test
    fun malformedMealAndReconciliationEventsUseTruthfulLabels() {
        assertEquals(
            "성장 XP 획득",
            GrowthEventPresentation.from(
                event(
                    id = "meal:migrated-uuid",
                    amount = 9,
                    occurredAt = 100,
                    sourceRecordId = "2026-07-25|김치|finished",
                ),
            ).title,
        )
        assertEquals(
            "이전 성장 기록 정리",
            GrowthEventPresentation.from(
                event(
                    id = "legacy:progress-reconciliation",
                    amount = 40,
                    occurredAt = 100,
                ),
            ).title,
        )
    }

    @Test
    fun collectionSnapshotUsesOnlyTheActiveRecordsExposedByItsSource() = runTest {
        val snapshot = CollectionRepository(
            object : CollectionSnapshotSource {
                override suspend fun totalXp(): Long = 18

                override suspend fun activeRecords(): List<MealRecordEntity> = listOf(
                    meal("2026-07-30|시금치나물|oneBite", "2026-07-30", "시금치나물", "oneBite"),
                    meal("2026-07-31|현미밥|finished", "2026-07-31", "현미밥", "finished"),
                )
            },
        ).loadCollection()

        assertEquals(18, snapshot.totalXp)
        assertEquals(
            listOf(
                CollectionRecord("2026-07-30", "시금치나물", "oneBite"),
                CollectionRecord("2026-07-31", "현미밥", "finished"),
            ),
            snapshot.records,
        )
    }

    private fun event(
        id: String,
        amount: Int,
        occurredAt: Long,
        sourceRecordId: String? = null,
    ) = ProgressEventEntity(
        id = id,
        amount = amount,
        occurredAtEpochMillis = occurredAt,
        sourceRecordId = sourceRecordId,
    )

    private fun meal(id: String, date: String, name: String, status: String) =
        MealRecordEntity(
            id = id,
            date = date,
            menuName = name,
            normalizedMenuName = name,
            status = status,
            difficultyReasonsJson = "[]",
            allergyCodesJson = "[]",
            photoIdsJson = "[]",
            updatedAtEpochMillis = 1,
            deletedAtEpochMillis = null,
        )
}

private class FakeGrowthProgressSource(
    private val totalXp: Long,
    private val events: List<ProgressEventEntity>,
) : GrowthProgressSource {
    var requestedLimit: Int? = null

    override suspend fun totalXp(): Long = totalXp

    override suspend fun recentPositiveEvents(limit: Int): List<ProgressEventEntity> {
        requestedLimit = limit
        return events
    }
}
