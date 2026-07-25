package com.h19h29.naymnaymlevelup.rebuild.migration

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.h19h29.naymnaymlevelup.rebuild.data.MigrationStateRepository
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RebuildMigrationIntegrationTest {
    private lateinit var context: Context
    private lateinit var preferences: SharedPreferences
    private lateinit var database: RebuildDatabase

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        preferences = context.getSharedPreferences(
            LegacyPreferencesReader.PREFERENCES_FILE_NAME,
            Context.MODE_PRIVATE,
        )
        preferences.edit().clear().commit()
        database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
    }

    @After
    fun tearDown() {
        database.close()
        preferences.edit().clear().commit()
    }

    @Test
    fun readerProjectsExactTest7KeysAndMigrationPreservesTheSource() = runBlocking {
        seedCompleteLegacyPreferences()
        val before = HashMap(preferences.all)
        val reader = LegacyPreferencesReader(context)
        val snapshot = reader.readSnapshot()

        assertNotNull(snapshot.profileJson)
        assertEquals("""{"totalXp":18}""", snapshot.progressJson)
        assertTrue(requireNotNull(snapshot.mealsJson).contains("\"mealId\":\"meal-1\""))
        assertTrue(requireNotNull(snapshot.challengesJson).contains("\"gainedExp\":18"))
        assertNull(snapshot.mealPhotosJson)
        assertTrue(requireNotNull(snapshot.parentJson).contains("\"inviteCode\":\"PARENT-1\""))
        assertTrue(requireNotNull(snapshot.childLinkJson).contains("\"childLinkId\":\"child-1\""))
        assertTrue(snapshot.sourceKeys.contains("mealSnapshotLedger"))
        assertTrue(snapshot.sourceKeys.contains("dailyBaseXp-20260725"))

        val outcome = RebuildMigrationCoordinator(
            source = reader,
            target = RoomMigrationTarget(
                database = database,
                nowEpochMillis = { 1234L },
            ),
        ).runIfNeeded(1)

        assertEquals(MigrationOutcome.Migrated, outcome)
        assertEquals("냠냠 도전자", database.profileDao().find("legacy-android-profile")?.nickname)
        val identity = "2026-07-25|현미밥|finished"
        assertEquals(identity, database.mealRecordDao().find(identity)?.id)
        assertEquals(18, database.progressDao().totalXp())
        assertEquals("meal:$identity", database.progressDao().find("meal:$identity")?.id)
        assertEquals("child-1", database.parentLinkDao().find("child-1")?.id)
        val state = database.migrationStateDao().find(MigrationStateRepository.STATE_ID)
        assertEquals(1, state?.version)
        assertEquals(1234L, state?.completedAtEpochMillis)
        assertTrue(requireNotNull(state?.sourceDigest).startsWith("sha256:"))
        assertEquals(before, preferences.all)
    }

    @Test
    fun corruptPresentJsonOrWrongPreferenceTypeWritesNothingAndPreservesSource() {
        preferences.edit()
            .putString(LegacyPreferencesReader.MEAL_SNAPSHOT_LEDGER, """{"latestMeals":{}}""")
            .putBoolean("unrelated", true)
            .commit()
        val beforeCorrupt = HashMap(preferences.all)

        assertThrows(LegacyMigrationException::class.java) {
            runBlocking {
                RebuildMigrationCoordinator(
                    LegacyPreferencesReader(context),
                    RoomMigrationTarget(database),
                ).runIfNeeded(1)
            }
        }
        assertNull(
            runBlocking {
                database.migrationStateDao().find(MigrationStateRepository.STATE_ID)
            },
        )
        assertEquals(beforeCorrupt, preferences.all)

        preferences.edit().clear()
            .putInt(LegacyPreferencesReader.SCHOOL_NAME, 7)
            .commit()
        val beforeWrongType = HashMap(preferences.all)
        assertThrows(LegacyMigrationException::class.java) {
            LegacyPreferencesReader(context).readSnapshot()
        }
        assertEquals(beforeWrongType, preferences.all)
    }

    @Test
    fun verificationFailureRollsBackAllRoomRowsAndRetryMigratesOnce() = runBlocking {
        seedCompleteLegacyPreferences()
        val before = HashMap(preferences.all)
        var shouldFail = true
        val coordinator = RebuildMigrationCoordinator(
            source = LegacyPreferencesReader(context),
            target = RoomMigrationTarget(database) {
                if (shouldFail) {
                    shouldFail = false
                    throw ForcedVerificationFailure()
                }
            },
        )

        assertThrows(ForcedVerificationFailure::class.java) {
            runBlocking { coordinator.runIfNeeded(1) }
        }
        assertNull(database.profileDao().find("legacy-android-profile"))
        assertNull(database.mealRecordDao().find("2026-07-25|현미밥|finished"))
        assertNull(database.progressDao().find("meal:2026-07-25|현미밥|finished"))
        assertNull(database.parentLinkDao().find("child-1"))
        assertNull(database.migrationStateDao().find(MigrationStateRepository.STATE_ID))
        assertEquals(before, preferences.all)

        assertEquals(MigrationOutcome.Migrated, coordinator.runIfNeeded(1))
        assertEquals(MigrationOutcome.AlreadyCompleted, coordinator.runIfNeeded(1))
        assertEquals(18, database.progressDao().totalXp())
        assertEquals(1, database.migrationStateDao().version(MigrationStateRepository.STATE_ID))
        assertEquals(before, preferences.all)
    }

    @Test
    fun concurrentCoordinatorsAgainstOneRoomDatabaseHaveOneWinner() = runBlocking {
        seedCompleteLegacyPreferences()
        val reader = LegacyPreferencesReader(context)
        val outcomes = listOf(
            async(Dispatchers.IO) {
                RebuildMigrationCoordinator(reader, RoomMigrationTarget(database)).runIfNeeded(1)
            },
            async(Dispatchers.IO) {
                RebuildMigrationCoordinator(reader, RoomMigrationTarget(database)).runIfNeeded(1)
            },
        ).awaitAll()

        assertEquals(1, outcomes.count { it == MigrationOutcome.Migrated })
        assertEquals(1, outcomes.count { it == MigrationOutcome.AlreadyCompleted })
        assertEquals(1, database.migrationStateDao().version(MigrationStateRepository.STATE_ID))
        assertEquals(18, database.progressDao().totalXp())
        assertFalse(preferences.all.isEmpty())
    }

    @Test
    fun verificationReadsRoomXpAndRollsBackWhenTargetContainsUnexpectedXp() = runBlocking {
        seedCompleteLegacyPreferences()
        val existing = ProgressEventEntity(
            id = "existing-unrelated-xp",
            amount = 1,
            occurredAtEpochMillis = 1L,
            sourceRecordId = null,
        )
        database.progressDao().insert(existing)

        assertThrows(LegacyMigrationException.VerificationMismatch::class.java) {
            runBlocking {
                RebuildMigrationCoordinator(
                    LegacyPreferencesReader(context),
                    RoomMigrationTarget(database),
                ).runIfNeeded(1)
            }
        }

        assertEquals(existing, database.progressDao().find(existing.id))
        assertNull(database.progressDao().find("meal:2026-07-25|현미밥|finished"))
        assertNull(database.profileDao().find("legacy-android-profile"))
        assertNull(database.migrationStateDao().find(MigrationStateRepository.STATE_ID))
        assertEquals(1, database.progressDao().totalXp())
    }

    private fun seedCompleteLegacyPreferences() {
        val entry =
            """
            {
              "mealId":"meal-1",
              "challengeId":"challenge-1",
              "date":"20260725",
              "menuName":"현미밥",
              "eatingStatus":"finished",
              "difficultyReasons":[],
              "allergyCodes":[],
              "gainedExp":18,
              "nutrients":["탄수화물"],
              "createdAt":"2026-07-25T01:02:03Z"
            }
            """.trimIndent()
        preferences.edit()
            .putString(LegacyPreferencesReader.SCHOOL_NAME, "테스트 학교")
            .putString(LegacyPreferencesReader.OFFICE_CODE, "B10")
            .putString(LegacyPreferencesReader.SCHOOL_CODE, "7130166")
            .putString(LegacyPreferencesReader.REGION, "서울")
            .putString(LegacyPreferencesReader.ADDRESS, "서울")
            .putString(LegacyPreferencesReader.SCHOOL_TYPE, "고등학교")
            .putInt("dailyBaseXp-20260725", 18)
            .putString(
                LegacyPreferencesReader.MEAL_SNAPSHOT_LEDGER,
                """{"latestMeals":[$entry],"actions":[$entry]}""",
            )
            .putString(
                LegacyPreferencesReader.PARENT_CHILDREN,
                """[{"inviteCode":"PARENT-1","childName":"아이","schoolName":"학교"}]""",
            )
            .putString(LegacyPreferencesReader.CHILD_LINK_ID, "child-1")
            .putString(LegacyPreferencesReader.INVITE_CODE, "CHILD-1")
            .putString(LegacyPreferencesReader.INVITE_SECRET, "secret")
            .putString(LegacyPreferencesReader.REGISTERED_AT, "2026-07-25T00:00:00Z")
            .putString(LegacyPreferencesReader.PARENT_CONNECTED_AT, "2026-07-25T00:01:00Z")
            .putBoolean("unrelated", true)
            .commit()
    }
}

private class ForcedVerificationFailure : RuntimeException()
