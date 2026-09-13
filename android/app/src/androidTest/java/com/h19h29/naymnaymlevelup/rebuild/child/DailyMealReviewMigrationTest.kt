package com.h19h29.naymnaymlevelup.rebuild.child

import android.content.Context
import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import java.io.IOException
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DailyMealReviewMigrationTest {
    private val databaseName = "daily-review-migration.db"
    private val context: Context = ApplicationProvider.getApplicationContext()

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        RebuildDatabase::class.java,
        emptyList(),
        FrameworkSQLiteOpenHelperFactory(),
    )

    @After
    fun cleanUp() {
        context.deleteDatabase(databaseName)
    }

    @Test
    @Throws(IOException::class)
    fun migration1To2PreservesExistingRowsAndOnlyReviewDeletionClearsReviews() = runBlocking {
        helper.createDatabase(databaseName, 1).apply {
            execSQL("INSERT INTO profiles VALUES ('profile', 'child', '냠냠', 'office', 'school', '[2]')")
            execSQL("INSERT INTO meal_days VALUES ('2026-09-13', '{}', 1, 'fixture')")
            execSQL("INSERT INTO progress_events VALUES ('xp', 7, 1, NULL)")
            close()
        }

        helper.runMigrationsAndValidate(databaseName, 2, true, RebuildDatabase.MIGRATION_1_2).close()
        val database = Room.databaseBuilder(context, RebuildDatabase::class.java, databaseName)
            .addMigrations(RebuildDatabase.MIGRATION_1_2)
            .build()
        try {
            assertEquals("냠냠", database.profileDao().find("profile")?.nickname)
            assertEquals(7L, database.progressDao().totalXp())
            database.openHelper.readableDatabase.query(
                "SELECT COUNT(*) FROM meal_days WHERE date = '2026-09-13'",
            ).use { cursor ->
                cursor.moveToFirst()
                assertEquals(1, cursor.getInt(0))
            }
            database.dailyMealReviewDao().upsert(
                com.h19h29.naymnaymlevelup.rebuild.data.DailyMealReviewEntity(
                    id = "profile|school|2026-09-13",
                    profileKey = "profile",
                    schoolKey = "school",
                    date = "2026-09-13",
                    payloadJson = "{}",
                    createdAtEpochMillis = 1,
                ),
            )
            database.dailyMealReviewDao().deleteAll()
            assertEquals(null, database.dailyMealReviewDao().find("profile", "school", "2026-09-13"))
            assertEquals("냠냠", database.profileDao().find("profile")?.nickname)
            assertEquals(7L, database.progressDao().totalXp())
            database.openHelper.readableDatabase.query(
                "SELECT COUNT(*) FROM meal_days WHERE date = '2026-09-13'",
            ).use { cursor ->
                cursor.moveToFirst()
                assertEquals(1, cursor.getInt(0))
            }
        } finally {
            database.close()
        }
    }

    @Test
    fun roomStoreSeparatesLocalScopeReloadsAndDeletesOnlyItsTable() = runBlocking {
        val database = Room.inMemoryDatabaseBuilder(context, RebuildDatabase::class.java).build()
        try {
            val store = DailyMealReviewStore(database.dailyMealReviewDao())
            val first = saved("profile-a", "school-a")
            val second = saved("profile-b", "school-a")
            store.save(first)
            store.save(second)

            val reopened = DailyMealReviewStore(database.dailyMealReviewDao())
            assertEquals(first, reopened.load("profile-a", "school-a", "2026-09-13"))
            assertEquals(second, reopened.load("profile-b", "school-a", "2026-09-13"))
            assertEquals(null, reopened.load("profile-a", "school-b", "2026-09-13"))

            database.progressDao().insert(
                com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity("keep", 9, 1, null),
            )
            reopened.deleteAll()
            assertEquals(null, reopened.load("profile-a", "school-a", "2026-09-13"))
            assertEquals(9L, database.progressDao().totalXp())
        } finally {
            database.close()
        }
    }

    private fun saved(profile: String, school: String) = SavedDailyMealReview(
        profile, school, "2026-09-13", "lunch", "fingerprint",
        listOf(DailyMealReviewMenuSnapshot("m0", "현미밥", emptyList(), listOf("carbohydrate"))),
        DailyMealReviewResponse(
            "ai", "00000000-0000-4000-8000-000000000001", "2026-09-13",
            "2026-09-13T04:00:00.000Z", "deepseek-v4.1-flash", "daily-v1",
            "오늘 영양 구성을 살펴봤어.", "에너지원이 되는 영양소를 만날 수 있어.",
            listOf(DailyMealReviewHighlight("m0", "carbohydrate", "활동에 쓰이는 에너지원이야.")),
            "실제로 먹은 양은 알 수 없어.", "다음 식사에서도 다양한 음식을 만나 보자.",
        ),
    )
}
