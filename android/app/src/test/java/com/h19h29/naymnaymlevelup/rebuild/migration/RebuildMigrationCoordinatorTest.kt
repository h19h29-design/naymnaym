package com.h19h29.naymnaymlevelup.rebuild.migration

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class RebuildMigrationCoordinatorTest {
    @Test
    fun migrationIsIdempotentAndDoesNotClearLegacySource() = runBlocking {
        val profile = """{"nickname":"냠냠이"}"""
        val source = FakeLegacySource(profileJson = profile)
        val target = FakeMigrationTarget()
        val coordinator = RebuildMigrationCoordinator(source, target)

        assertEquals(MigrationOutcome.Migrated, coordinator.runIfNeeded(1))
        assertEquals(MigrationOutcome.AlreadyCompleted, coordinator.runIfNeeded(1))
        assertEquals(profile, source.profileJson)
        assertFalse(source.wasMutated)
        assertEquals(1, target.committedPlan?.profile?.let { 1 })
        assertEquals("냠냠이", target.committedPlan?.profile?.nickname)
        assertEquals(1, target.migrateAttempts)
    }

    @Test
    fun emptySourceDoesNotWriteCompletionMarker() = runBlocking {
        val source = FakeLegacySource()
        val target = FakeMigrationTarget()

        assertEquals(
            MigrationOutcome.NoLegacyData,
            RebuildMigrationCoordinator(source, target).runIfNeeded(1),
        )
        assertEquals(0, target.completedVersion)
        assertNull(target.committedPlan)
    }

    @Test
    fun malformedOrIncompletePresentPayloadIsRejectedBeforeTargetWrites() {
        listOf(
            LegacySnapshot(profileJson = """{"nickname":""}"""),
            LegacySnapshot(mealsJson = """{"not":"an array"}"""),
            LegacySnapshot(
                mealsJson =
                    """[{"date":"20260725","menuName":"시금치","eatingStatus":"unknown"}]""",
            ),
            LegacySnapshot(
                mealsJson =
                    """
                    [{
                      "date":"20260230",
                      "menuName":"시금치",
                      "eatingStatus":"oneBite",
                      "createdAt":"2026-07-25T01:02:03Z"
                    }]
                    """.trimIndent(),
            ),
            LegacySnapshot(challengesJson = """[{"date":"20260725"}]"""),
            LegacySnapshot(parentJson = """[{"inviteCode":""}]"""),
            LegacySnapshot(childLinkJson = """{"id":"child-id"}"""),
            LegacySnapshot(mealPhotosJson = """[{"id":"photo-1"}]"""),
        ).forEach { snapshot ->
            val target = FakeMigrationTarget()

            assertThrows(LegacyMigrationException::class.java) {
                runBlocking {
                    RebuildMigrationCoordinator(
                        FakeLegacySource(snapshot = snapshot),
                        target,
                    ).runIfNeeded(1)
                }
            }
            assertEquals(0, target.migrateAttempts)
            assertEquals(0, target.completedVersion)
        }
    }

    @Test
    fun partialFailureRollsBackAndRetryCommitsOnce() = runBlocking {
        val source = FakeLegacySource(
            profileJson = """{"nickname":"재시도"}""",
            mealsJson =
                """
                [{
                  "mealId":"meal-1",
                  "date":"20260725",
                  "menuName":" 현미밥 ",
                  "eatingStatus":"finished",
                  "difficultyReasons":[],
                  "allergyCodes":[],
                  "photoIds":[],
                  "createdAt":"2026-07-25T01:02:03Z"
                }]
                """.trimIndent(),
            challengesJson =
                """
                [{
                  "challengeId":"challenge-1",
                  "date":"20260725",
                  "menuName":" 현미밥 ",
                  "eatingStatus":"finished",
                  "gainedExp":18,
                  "createdAt":"2026-07-25T01:02:03Z"
                }]
                """.trimIndent(),
        )
        val target = FakeMigrationTarget(failNextMigration = true)
        val coordinator = RebuildMigrationCoordinator(source, target)

        assertThrows(PartialWriteFailure::class.java) {
            runBlocking { coordinator.runIfNeeded(1) }
        }
        assertEquals(0, target.completedVersion)
        assertNull(target.committedPlan)
        assertEquals(MigrationOutcome.Migrated, coordinator.runIfNeeded(1))
        assertEquals(MigrationOutcome.AlreadyCompleted, coordinator.runIfNeeded(1))
        assertEquals(1, target.completedVersion)
        assertEquals(18, target.committedPlan?.expectedTotalXp)
        assertFalse(source.wasMutated)
    }

    @Test
    fun storedProgressIsAuthoritativeAndCreatesAReconciliationEvent() = runBlocking {
        val source = FakeLegacySource(
            profileJson = """{"nickname":"경험치"}""",
            progressJson =
                """{"recordExp":20,"challengeExp":15,"balanceExp":5,"safetyExp":0}""",
            challengesJson =
                """
                [{
                  "challengeId":"challenge-1",
                  "date":"20260725",
                  "menuName":"나물",
                  "eatingStatus":"oneBite",
                  "gainedExp":18,
                  "createdAt":"2026-07-25T01:02:03Z"
                }]
                """.trimIndent(),
        )
        val target = FakeMigrationTarget()

        assertEquals(
            MigrationOutcome.Migrated,
            RebuildMigrationCoordinator(source, target).runIfNeeded(1),
        )
        val plan = requireNotNull(target.committedPlan)
        assertEquals(40, plan.expectedTotalXp)
        assertEquals(40, plan.progressEvents.sumOf { it.amount })
        assertTrue(
            plan.progressEvents.any {
                it.id == "legacy:progress-reconciliation" && it.amount == 22
            },
        )
    }

    @Test
    fun allSevenLogicalPayloadsAreMappedWithoutDroppingRecords() = runBlocking {
        val source = FakeLegacySource(
            profileJson =
                """{"id":"profile-1","role":"child","nickname":"전체","allergyCodes":[5]}""",
            progressJson = """{"totalXp":9}""",
            mealsJson =
                """
                [{
                  "mealId":"meal-1",
                  "date":"2026-07-25",
                  "menuName":"시금치 나물",
                  "eatingStatus":"oneBite",
                  "photoIds":["photo-1"],
                  "createdAt":"2026-07-25T01:02:03Z"
                }]
                """.trimIndent(),
            mealPhotosJson =
                """
                [{
                  "id":"photo-1",
                  "fileName":"photo-1.jpg",
                  "createdAt":"2026-07-25T01:02:04Z"
                }]
                """.trimIndent(),
            challengesJson =
                """
                [{
                  "challengeId":"challenge-1",
                  "date":"2026-07-25",
                  "menuName":"시금치 나물",
                  "action":"oneBite",
                  "gainedExp":9,
                  "createdAt":"2026-07-25T01:02:03Z"
                }]
                """.trimIndent(),
            parentJson =
                """[{"id":"parent-child","inviteCode":" parent-1 "}]""",
            childLinkJson =
                """
                {
                  "childLinkId":"child-1",
                  "inviteCode":" child-1 ",
                  "parentConnectedAt":"2026-07-25T01:03:00Z"
                }
                """.trimIndent(),
        )
        val target = FakeMigrationTarget()

        assertEquals(
            MigrationOutcome.Migrated,
            RebuildMigrationCoordinator(source, target).runIfNeeded(1),
        )
        val plan = requireNotNull(target.committedPlan)
        assertEquals("profile-1", plan.profile?.id)
        assertEquals(1, plan.mealRecords.size)
        assertEquals("photo-1.jpg", plan.mealPhotos.single().relativePath)
        assertEquals(plan.mealRecords.single().id, plan.mealPhotos.single().recordId)
        assertEquals(1, plan.progressEvents.size)
        assertEquals(2, plan.parentLinks.size)
        assertEquals(listOf("CHILD-1", "PARENT-1"), plan.parentLinks.map { it.inviteCode })
    }

    @Test
    fun sourceDigestIsDeterministicAndSourceSensitive() {
        val first = LegacySnapshot(profileJson = """{"nickname":"첫째"}""")
        val same = LegacySnapshot(profileJson = """{"nickname":"첫째"}""")
        val changed = LegacySnapshot(profileJson = """{"nickname":"둘째"}""")

        assertEquals(LegacySourceDigest.digest(first), LegacySourceDigest.digest(same))
        assertTrue(LegacySourceDigest.digest(first).startsWith("sha256:"))
        assertEquals(71, LegacySourceDigest.digest(first).length)
        assertFalse(LegacySourceDigest.digest(first) == LegacySourceDigest.digest(changed))
    }

    @Test
    fun concurrentCallsHaveOneLogicalWinner() = runBlocking {
        val target = FakeMigrationTarget(migrationDelayMillis = 30)
        val coordinator = RebuildMigrationCoordinator(
            FakeLegacySource(profileJson = """{"nickname":"동시성"}"""),
            target,
        )

        val outcomes = listOf(
            async(Dispatchers.Default) { coordinator.runIfNeeded(1) },
            async(Dispatchers.Default) { coordinator.runIfNeeded(1) },
        ).awaitAll()

        assertEquals(1, outcomes.count { it == MigrationOutcome.Migrated })
        assertEquals(1, outcomes.count { it == MigrationOutcome.AlreadyCompleted })
        assertEquals(1, target.migrateAttempts)
    }

    @Test
    fun unsupportedVersionFailsWithoutReadingOrWriting() {
        val source = FakeLegacySource(profileJson = """{"nickname":"버전"}""")
        val target = FakeMigrationTarget()

        assertThrows(LegacyMigrationException::class.java) {
            runBlocking {
                RebuildMigrationCoordinator(source, target).runIfNeeded(2)
            }
        }
        assertEquals(0, source.readCount)
        assertEquals(0, target.migrateAttempts)
    }
}

private class FakeLegacySource(
    var profileJson: String? = null,
    private val progressJson: String? = null,
    private val mealsJson: String? = null,
    private val mealPhotosJson: String? = null,
    private val challengesJson: String? = null,
    private val parentJson: String? = null,
    private val childLinkJson: String? = null,
    private val snapshot: LegacySnapshot? = null,
) : LegacyMigrationSource {
    var readCount = 0
    var wasMutated = false

    override fun readSnapshot(): LegacySnapshot {
        readCount += 1
        return snapshot ?: LegacySnapshot(
            profileJson = profileJson,
            progressJson = progressJson,
            mealsJson = mealsJson,
            mealPhotosJson = mealPhotosJson,
            challengesJson = challengesJson,
            parentJson = parentJson,
            childLinkJson = childLinkJson,
        )
    }
}

private class FakeMigrationTarget(
    var failNextMigration: Boolean = false,
    private val migrationDelayMillis: Long = 0,
) : MigrationTarget {
    var completedVersion = 0
    var committedPlan: MigrationPlan? = null
    var migrateAttempts = 0

    override suspend fun completedVersion(): Int = completedVersion

    override suspend fun migrate(
        plan: MigrationPlan,
        targetVersion: Int,
        sourceDigest: String,
    ): MigrationOutcome {
        if (completedVersion >= targetVersion) {
            return MigrationOutcome.AlreadyCompleted
        }
        migrateAttempts += 1
        if (migrationDelayMillis > 0) {
            delay(migrationDelayMillis)
        }
        if (failNextMigration) {
            failNextMigration = false
            throw PartialWriteFailure()
        }
        committedPlan = plan
        completedVersion = targetVersion
        return MigrationOutcome.Migrated
    }
}

private class PartialWriteFailure : RuntimeException()
