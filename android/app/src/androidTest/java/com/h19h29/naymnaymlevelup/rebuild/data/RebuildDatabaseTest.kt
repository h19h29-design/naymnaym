package com.h19h29.naymnaymlevelup.rebuild.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RebuildDatabaseTest {
    private lateinit var database: RebuildDatabase

    @Before
    fun createDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
    }

    @After
    fun closeDatabase() {
        database.close()
    }

    @Test
    fun duplicateProgressEventHasOneConcurrentWinnerAndTotals18Xp() = runBlocking {
        val repository = ProgressRepository(database.progressDao())
        val event = ProgressEventEntity(
            id = "meal:2026-07-25|시금치 나물|oneBite",
            amount = 18,
            occurredAtEpochMillis = 1_785_000_000_000,
            sourceRecordId = "2026-07-25|시금치 나물|oneBite",
        )

        val appended = withContext(Dispatchers.IO) {
            listOf(
                async { repository.appendIfAbsent(event) },
                async { repository.appendIfAbsent(event) },
            ).awaitAll()
        }

        assertEquals(1, appended.count { it })
        assertEquals(1, appended.count { !it })
        assertEquals(18, repository.totalXp())
        assertEquals(event, database.progressDao().find(event.id))
    }

    @Test
    fun databaseExposesTheEightRebuildEntityAndDaoContracts() = runBlocking {
        assertEquals("naym-rebuild.db", RebuildDatabase.DATABASE_NAME)
        assertEquals(1, database.openHelper.readableDatabase.version)

        val profile = ProfileEntity(
            id = "current",
            role = "child",
            nickname = "도토리",
            officeCode = "B10",
            schoolCode = "7130166",
            allergyCodesJson = """["5","6"]""",
        )
        database.profileDao().upsert(profile)
        assertEquals(profile, database.profileDao().load())

        val mealDay = MealDayEntity(
            date = "2026-07-25",
            payloadJson = """{"menu":"현미밥"}""",
            fetchedAtEpochMillis = 1_785_000_000_000,
            source = "NEIS",
        )
        database.mealDayDao().upsert(mealDay)
        assertEquals(mealDay, database.mealDayDao().observe(mealDay.date).first())

        val mealRecord = MealRecordEntity(
            id = "2026-07-25|현미밥|finished",
            date = "2026-07-25",
            menuName = "현미밥",
            normalizedMenuName = "현미밥",
            status = "finished",
            difficultyReasonsJson = """["texture"]""",
            allergyCodesJson = """["5"]""",
            photoIdsJson = """["photo-1"]""",
            parentShareEnabled = true,
            updatedAtEpochMillis = 1_785_000_100_000,
            deletedAtEpochMillis = null,
        )
        database.mealRecordDao().upsert(mealRecord)
        assertEquals(mealRecord, database.mealRecordDao().find(mealRecord.id))

        val mealPhoto = MealPhotoEntity(
            id = "photo-1",
            recordId = mealRecord.id,
            relativePath = "meal-photos/photo-1.jpg",
            createdAtEpochMillis = 1_785_000_200_000,
        )
        database.mealPhotoDao().upsert(mealPhoto)
        assertEquals(listOf(mealPhoto), database.mealPhotoDao().forRecord(mealRecord.id))

        val laterEnvelope = SyncEnvelopeEntity(
            id = "sync-later",
            recordType = "mealRecord",
            recordId = mealRecord.id,
            state = "queued",
            retryCount = 1,
            updatedAtEpochMillis = 200,
        )
        val earlierEnvelope = SyncEnvelopeEntity(
            id = "sync-earlier",
            recordType = "profile",
            recordId = profile.id,
            state = "queued",
            retryCount = 0,
            updatedAtEpochMillis = 100,
        )
        database.syncEnvelopeDao().upsert(laterEnvelope)
        database.syncEnvelopeDao().upsert(earlierEnvelope)
        assertEquals(
            listOf(earlierEnvelope, laterEnvelope),
            database.syncEnvelopeDao().orderedBatch(limit = 10),
        )

        val parentLink = ParentLinkEntity(
            id = "current",
            inviteCode = "ABC123",
            connectionState = "connected",
            connectedAtEpochMillis = 1_785_000_300_000,
            inviteSecret = "exact-legacy-secret",
            registeredAtEpochMillis = 1_785_000_250_000,
        )
        database.parentLinkDao().upsert(parentLink)
        assertEquals(parentLink, database.parentLinkDao().load())

        val migrationDao = database.migrationStateDao()
        assertNull(migrationDao.version(MigrationStateRepository.STATE_ID))
        val migrationRepository = MigrationStateRepository(migrationDao)
        migrationRepository.markCompleted(
            version = 1,
            sourceDigest = "sha256:legacy",
            completedAtEpochMillis = 1_785_000_400_000,
        )
        assertEquals(1, migrationDao.version(MigrationStateRepository.STATE_ID))
        assertEquals(
            MigrationStateEntity(
                id = MigrationStateRepository.STATE_ID,
                version = 1,
                completedAtEpochMillis = 1_785_000_400_000,
                sourceDigest = "sha256:legacy",
            ),
            migrationDao.find(MigrationStateRepository.STATE_ID),
        )

        val daoNames = database.openHelper.readableDatabase
            .query("SELECT name FROM sqlite_master WHERE type = 'table'")
            .use { cursor ->
                buildSet {
                    while (cursor.moveToNext()) {
                        add(cursor.getString(0))
                    }
                }
            }
        assertTrue(
            daoNames.containsAll(
                setOf(
                    "profiles",
                    "meal_days",
                    "meal_records",
                    "meal_photos",
                    "progress_events",
                    "sync_envelopes",
                    "parent_links",
                    "migration_states",
                ),
            ),
        )
        assertFalse(daoNames.contains("legacy_records"))
    }
}
