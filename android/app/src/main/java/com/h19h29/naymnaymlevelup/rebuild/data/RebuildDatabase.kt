package com.h19h29.naymnaymlevelup.rebuild.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        ProfileEntity::class,
        MealDayEntity::class,
        MealRecordEntity::class,
        MealPhotoEntity::class,
        ProgressEventEntity::class,
        SyncEnvelopeEntity::class,
        ParentLinkEntity::class,
        MigrationStateEntity::class,
        DailyMealReviewEntity::class,
    ],
    version = 2,
    exportSchema = true,
)
abstract class RebuildDatabase : RoomDatabase() {
    abstract fun profileDao(): ProfileDao
    abstract fun mealDayDao(): MealDayDao
    abstract fun mealRecordDao(): MealRecordDao
    abstract fun mealPhotoDao(): MealPhotoDao
    abstract fun progressDao(): ProgressDao
    abstract fun syncEnvelopeDao(): SyncEnvelopeDao
    abstract fun parentLinkDao(): ParentLinkDao
    abstract fun migrationStateDao(): MigrationStateDao
    abstract fun dailyMealReviewDao(): DailyMealReviewDao

    companion object {
        const val DATABASE_NAME = "naym-rebuild.db"

        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `daily_meal_reviews` (
                        `id` TEXT NOT NULL,
                        `profileKey` TEXT NOT NULL,
                        `schoolKey` TEXT NOT NULL,
                        `date` TEXT NOT NULL,
                        `payloadJson` TEXT NOT NULL,
                        `createdAtEpochMillis` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                    """.trimIndent(),
                )
            }
        }

        fun open(context: Context): RebuildDatabase = Room.databaseBuilder(
            context.applicationContext,
            RebuildDatabase::class.java,
            DATABASE_NAME,
        ).addMigrations(MIGRATION_1_2).build()
    }
}
