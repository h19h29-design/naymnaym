package com.h19h29.naymnaymlevelup.rebuild.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface ProfileDao {
    @Upsert
    suspend fun upsert(profile: ProfileEntity)

    @Query("SELECT * FROM profiles ORDER BY id ASC LIMIT 1")
    suspend fun load(): ProfileEntity?

    @Query("SELECT * FROM profiles WHERE id = :id LIMIT 1")
    suspend fun find(id: String): ProfileEntity?

    @Query("DELETE FROM profiles")
    suspend fun deleteAll()

    @Query("DELETE FROM profiles WHERE id = :id")
    suspend fun delete(id: String)
}

@Dao
interface MealDayDao {
    @Query("SELECT * FROM meal_days WHERE date = :date LIMIT 1")
    fun observe(date: String): Flow<MealDayEntity?>

    @Upsert
    suspend fun upsert(mealDay: MealDayEntity)

    @Query("DELETE FROM meal_days WHERE date = :date")
    suspend fun delete(date: String)
}

@Dao
interface MealRecordDao {
    @Upsert
    suspend fun upsert(record: MealRecordEntity)

    @Query("SELECT * FROM meal_records WHERE id = :id LIMIT 1")
    suspend fun find(id: String): MealRecordEntity?

    @Query(
        """
        SELECT * FROM meal_records
        WHERE date = :date
          AND normalizedMenuName = :normalizedMenuName
        LIMIT 1
        """,
    )
    suspend fun findAwardRecord(
        date: String,
        normalizedMenuName: String,
    ): MealRecordEntity?

    @Query(
        """
        SELECT * FROM meal_records
        WHERE date = :date
          AND normalizedMenuName = :normalizedMenuName
          AND deletedAtEpochMillis IS NULL
        ORDER BY updatedAtEpochMillis ASC, id ASC
        """,
    )
    suspend fun recordsForMenu(
        date: String,
        normalizedMenuName: String,
    ): List<MealRecordEntity>

    @Query("SELECT COUNT(*) FROM meal_records WHERE id IN (:ids)")
    suspend fun count(ids: List<String>): Int
}

@Dao
interface MealPhotoDao {
    @Upsert
    suspend fun upsert(photo: MealPhotoEntity)

    @Query("SELECT * FROM meal_photos WHERE id = :id LIMIT 1")
    suspend fun find(id: String): MealPhotoEntity?

    @Query(
        """
        SELECT * FROM meal_photos
        WHERE recordId = :recordId
        ORDER BY createdAtEpochMillis ASC, id ASC
        """,
    )
    suspend fun forRecord(recordId: String): List<MealPhotoEntity>
}

@Dao
interface ProgressDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(event: ProgressEventEntity): Long

    @Query(
        """
        SELECT COALESCE(
            SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END),
            0
        )
        FROM progress_events
        """,
    )
    suspend fun totalXp(): Long

    @Query("SELECT COALESCE(SUM(amount), 0) FROM progress_events")
    suspend fun signedTotalXp(): Long

    @Query(
        """
        SELECT COALESCE(
            SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END),
            0
        )
        FROM progress_events
        WHERE id LIKE 'meal:%'
          AND (
            sourceRecordId LIKE :datePrefix || '%'
            OR (
              (
                sourceRecordId IS NULL
                OR sourceRecordId NOT GLOB
                  '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]|?*'
              )
              AND occurredAtEpochMillis >= :dayStartEpochMillis
              AND occurredAtEpochMillis < :nextDayStartEpochMillis
            )
          )
        """,
    )
    suspend fun dailyBaseXp(
        datePrefix: String,
        dayStartEpochMillis: Long,
        nextDayStartEpochMillis: Long,
    ): Long

    @Query(
        """
        SELECT COALESCE(
            SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END),
            0
        )
        FROM progress_events
        WHERE sourceRecordId LIKE :datePrefix || '%'
           OR (
             (
               sourceRecordId IS NULL
               OR sourceRecordId NOT GLOB
                 '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]|?*'
             )
             AND occurredAtEpochMillis >= :dayStartEpochMillis
             AND occurredAtEpochMillis < :nextDayStartEpochMillis
           )
        """,
    )
    suspend fun dailyTotalXp(
        datePrefix: String,
        dayStartEpochMillis: Long,
        nextDayStartEpochMillis: Long,
    ): Long

    @Query(
        """
        SELECT * FROM progress_events
        WHERE id LIKE 'meal:%'
          AND (
            substr(
              id,
              1,
              length('meal:' || :awardPrefix)
            ) = 'meal:' || :awardPrefix
            OR substr(
              sourceRecordId,
              1,
              length(:awardPrefix)
            ) = :awardPrefix
          )
        LIMIT 1
        """,
    )
    suspend fun findAwardEvent(
        awardPrefix: String,
    ): ProgressEventEntity?

    @Query("SELECT * FROM progress_events WHERE id = :id LIMIT 1")
    suspend fun find(id: String): ProgressEventEntity?

    @Query("SELECT COUNT(*) FROM progress_events WHERE id IN (:ids)")
    suspend fun count(ids: List<String>): Int
}

@Dao
interface SyncEnvelopeDao {
    @Upsert
    suspend fun upsert(envelope: SyncEnvelopeEntity)

    @Query(
        """
        SELECT * FROM sync_envelopes
        ORDER BY updatedAtEpochMillis ASC, id ASC
        LIMIT :limit
        """,
    )
    suspend fun orderedBatch(limit: Int): List<SyncEnvelopeEntity>
}

@Dao
interface ParentLinkDao {
    @Upsert
    suspend fun upsert(link: ParentLinkEntity)

    @Query("SELECT * FROM parent_links ORDER BY id ASC LIMIT 1")
    suspend fun load(): ParentLinkEntity?

    @Query("SELECT * FROM parent_links WHERE id = :id LIMIT 1")
    suspend fun find(id: String): ParentLinkEntity?
}

@Dao
interface MigrationStateDao {
    @Query("SELECT version FROM migration_states WHERE id = :id LIMIT 1")
    suspend fun version(id: String): Int?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(state: MigrationStateEntity)

    @Query("SELECT * FROM migration_states WHERE id = :id LIMIT 1")
    suspend fun find(id: String): MigrationStateEntity?
}
