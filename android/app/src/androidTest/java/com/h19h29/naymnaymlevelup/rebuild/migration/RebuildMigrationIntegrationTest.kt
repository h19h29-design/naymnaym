package com.h19h29.naymnaymlevelup.rebuild.migration

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.h19h29.naymnaymlevelup.rebuild.data.MealPhotoEntity
import com.h19h29.naymnaymlevelup.rebuild.data.MealRecordEntity
import com.h19h29.naymnaymlevelup.rebuild.data.MigrationStateRepository
import com.h19h29.naymnaymlevelup.rebuild.data.ParentLinkEntity
import com.h19h29.naymnaymlevelup.rebuild.data.ProfileEntity
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
        val progressJson = org.json.JSONObject(requireNotNull(snapshot.progressJson))
        assertEquals(18, progressJson.getInt("totalXp"))
        val dailyXp = progressJson.getJSONArray("dailyXpEntries").getJSONObject(0)
        assertEquals("dailyBaseXp-20260725", dailyXp.getString("key"))
        assertEquals(18, dailyXp.getInt("value"))
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
        assertEquals(18L, database.progressDao().totalXp())
        assertEquals("meal:$identity", database.progressDao().find("meal:$identity")?.id)
        val migratedChildLink = database.parentLinkDao().find("child-1")
        assertEquals("child-1", migratedChildLink?.id)
        assertEquals("secret", migratedChildLink?.inviteSecret)
        assertEquals(1_784_937_600_000L, migratedChildLink?.registeredAtEpochMillis)
        val state = database.migrationStateDao().find(MigrationStateRepository.STATE_ID)
        assertEquals(1, state?.version)
        assertEquals(1234L, state?.completedAtEpochMillis)
        assertTrue(requireNotNull(state?.sourceDigest).startsWith("sha256:"))
        assertEquals(before, preferences.all)
    }

    @Test
    fun signedReconciliationVerifiesMigrationWhileRuntimeTotalStaysPositiveOnly() = runBlocking {
        val positive = ProgressEventEntity(
            id = "legacy:positive",
            amount = 18,
            occurredAtEpochMillis = 100,
            sourceRecordId = null,
        )
        val reconciliation = ProgressEventEntity(
            id = "legacy:progress-reconciliation",
            amount = -8,
            occurredAtEpochMillis = 200,
            sourceRecordId = null,
        )
        val plan = MigrationPlan(
            profile = null,
            mealRecords = emptyList(),
            mealPhotos = emptyList(),
            progressEvents = listOf(positive, reconciliation),
            parentLinks = emptyList(),
            expectedTotalXp = 10,
        )

        val outcome = RoomMigrationTarget(database).migrate(
            plan = plan,
            targetVersion = 1,
            sourceDigest = "sha256:signed-reconciliation",
        )

        assertEquals(MigrationOutcome.Migrated, outcome)
        assertEquals(reconciliation, database.progressDao().find(reconciliation.id))
        assertEquals(18L, database.progressDao().totalXp())
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
    fun ledgerRequiresStrictJsonAndBothNamedArrays() {
        listOf(
            "{}",
            """{"latestMeals":[],"actions":[],"actions":[]}""",
            """{/*comment*/"latestMeals":[],"actions":[]}""",
            """{latestMeals:[],actions:[]}""",
            """{'latestMeals':[],'actions':[]}""",
            """{"latestMeals":[];"actions":[]}""",
            """{"latestMeals":[],"actions":[]} trailing""",
            """{"latestMeals":[]}""",
            """{"actions":[]}""",
        ).forEach { raw ->
            preferences.edit().clear()
                .putString(LegacyPreferencesReader.MEAL_SNAPSHOT_LEDGER, raw)
                .commit()
            val before = HashMap(preferences.all)

            assertThrows(LegacyMigrationException::class.java) {
                LegacyPreferencesReader(context).readSnapshot()
            }
            assertEquals(before, preferences.all)
        }
    }

    @Test
    fun dailyXpDigestIncludesEachDateAndValueNotOnlyTheAggregate() {
        preferences.edit()
            .putInt("dailyBaseXp-20260724", 10)
            .putInt("dailyBaseXp-20260725", 20)
            .commit()
        val reader = LegacyPreferencesReader(context)
        val firstSnapshot = reader.readSnapshot()
        val firstDigest = reader.sourceDigest(firstSnapshot)

        preferences.edit()
            .putInt("dailyBaseXp-20260724", 20)
            .putInt("dailyBaseXp-20260725", 10)
            .commit()
        val secondSnapshot = reader.readSnapshot()
        val secondDigest = reader.sourceDigest(secondSnapshot)

        assertEquals(30, org.json.JSONObject(firstSnapshot.progressJson!!).getInt("totalXp"))
        assertEquals(30, org.json.JSONObject(secondSnapshot.progressJson!!).getInt("totalXp"))
        assertFalse(firstDigest == secondDigest)
    }

    @Test
    fun invalidChildLinkAuthCombinationsAreRejectedWithoutSourceMutation() {
        listOf(
            mapOf(
                LegacyPreferencesReader.CHILD_LINK_ID to "missing-secret",
                LegacyPreferencesReader.INVITE_CODE to "CODE-1",
            ),
            mapOf(
                LegacyPreferencesReader.CHILD_LINK_ID to "blank-secret",
                LegacyPreferencesReader.INVITE_CODE to "CODE-2",
                LegacyPreferencesReader.INVITE_SECRET to "   ",
            ),
            mapOf(
                LegacyPreferencesReader.CHILD_LINK_ID to "connected-first",
                LegacyPreferencesReader.INVITE_CODE to "CODE-3",
                LegacyPreferencesReader.INVITE_SECRET to "valid-secret",
                LegacyPreferencesReader.PARENT_CONNECTED_AT to "2026-07-25T01:03:00Z",
            ),
        ).forEach { values ->
            preferences.edit().clear().apply {
                values.forEach { (key, value) -> putString(key, value) }
            }.commit()
            val before = HashMap(preferences.all)

            assertThrows(LegacyMigrationException.InvalidPayload::class.java) {
                runBlocking {
                    RebuildMigrationCoordinator(
                        LegacyPreferencesReader(context),
                        RoomMigrationTarget(database),
                    ).runIfNeeded(1)
                }
            }
            assertEquals(before, preferences.all)
            assertNull(
                runBlocking {
                    database.migrationStateDao()
                        .find(MigrationStateRepository.STATE_ID)
                },
            )
        }
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
        assertEquals(18L, database.progressDao().totalXp())
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
        assertEquals(18L, database.progressDao().totalXp())
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
        assertEquals(1L, database.progressDao().totalXp())
    }

    @Test
    fun differingTargetRowsCausePreflightRollbackAndPreserveUnrelatedRows() = runBlocking {
        val plan = collisionTestPlan()
        listOf("profile", "meal", "photo", "parent").forEach { collisionType ->
            val targetDatabase = Room.inMemoryDatabaseBuilder(
                context,
                RebuildDatabase::class.java,
            ).build()
            try {
                val unrelated = ProfileEntity(
                    id = "unrelated-profile",
                    role = "parent",
                    nickname = "그대로",
                    officeCode = null,
                    schoolCode = null,
                    allergyCodesJson = "[]",
                )
                targetDatabase.profileDao().upsert(unrelated)
                when (collisionType) {
                    "profile" -> targetDatabase.profileDao().upsert(
                        requireNotNull(plan.profile).copy(nickname = "충돌"),
                    )
                    "meal" -> targetDatabase.mealRecordDao().upsert(
                        plan.mealRecords.single().copy(menuName = "충돌"),
                    )
                    "photo" -> targetDatabase.mealPhotoDao().upsert(
                        plan.mealPhotos.single().copy(relativePath = "different.jpg"),
                    )
                    "parent" -> targetDatabase.parentLinkDao().upsert(
                        plan.parentLinks.single().copy(inviteSecret = "different-secret"),
                    )
                }

                assertThrows(LegacyMigrationException.TargetCollision::class.java) {
                    runBlocking {
                        RoomMigrationTarget(targetDatabase).migrate(
                            plan = plan,
                            targetVersion = 1,
                            sourceDigest = "sha256:collision",
                        )
                    }
                }
                assertEquals(unrelated, targetDatabase.profileDao().find(unrelated.id))
                assertNull(
                    targetDatabase.migrationStateDao()
                        .find(MigrationStateRepository.STATE_ID),
                )
            } finally {
                targetDatabase.close()
            }
        }
    }

    @Test
    fun exactEqualTargetRowsAreAccepted() = runBlocking {
        val plan = collisionTestPlan()
        database.profileDao().upsert(requireNotNull(plan.profile))
        plan.mealRecords.forEach { database.mealRecordDao().upsert(it) }
        plan.mealPhotos.forEach { database.mealPhotoDao().upsert(it) }
        plan.parentLinks.forEach { database.parentLinkDao().upsert(it) }

        assertEquals(
            MigrationOutcome.Migrated,
            RoomMigrationTarget(database).migrate(
                plan = plan,
                targetVersion = 1,
                sourceDigest = "sha256:equal",
            ),
        )
        assertEquals(1, database.migrationStateDao().version(MigrationStateRepository.STATE_ID))
    }

    private fun collisionTestPlan(): MigrationPlan {
        val profile = ProfileEntity(
            id = "planned-profile",
            role = "child",
            nickname = "계획",
            officeCode = "B10",
            schoolCode = "123",
            allergyCodesJson = "[]",
        )
        val meal = MealRecordEntity(
            id = "2026-07-25|나물|oneBite",
            date = "2026-07-25",
            menuName = "나물",
            normalizedMenuName = "나물",
            status = "oneBite",
            difficultyReasonsJson = "[]",
            allergyCodesJson = "[]",
            photoIdsJson = """["planned-photo"]""",
            updatedAtEpochMillis = 1L,
            deletedAtEpochMillis = null,
        )
        val photo = MealPhotoEntity(
            id = "planned-photo",
            recordId = meal.id,
            relativePath = "planned-photo.jpg",
            createdAtEpochMillis = 2L,
        )
        val parent = ParentLinkEntity(
            id = "planned-parent",
            inviteCode = "PLAN-1",
            connectionState = "invitePending",
            connectedAtEpochMillis = null,
            inviteSecret = "exact-secret",
            registeredAtEpochMillis = 3L,
        )
        return MigrationPlan(
            profile = profile,
            mealRecords = listOf(meal),
            mealPhotos = listOf(photo),
            progressEvents = emptyList(),
            parentLinks = listOf(parent),
            expectedTotalXp = 0,
        )
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
            .putString(
                LegacyPreferencesReader.REGISTERED_AT,
                "Sat Jul 25 09:00:00 GMT+09:00 2026",
            )
            .putString(LegacyPreferencesReader.PARENT_CONNECTED_AT, "2026-07-25T00:01:00Z")
            .putBoolean("unrelated", true)
            .commit()
    }
}

private class ForcedVerificationFailure : RuntimeException()
