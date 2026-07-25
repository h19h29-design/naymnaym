package com.h19h29.naymnaymlevelup.rebuild.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

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
    ],
    version = 1,
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

    companion object {
        const val DATABASE_NAME = "naym-rebuild.db"

        fun open(context: Context): RebuildDatabase = Room.databaseBuilder(
            context.applicationContext,
            RebuildDatabase::class.java,
            DATABASE_NAME,
        ).build()
    }
}
