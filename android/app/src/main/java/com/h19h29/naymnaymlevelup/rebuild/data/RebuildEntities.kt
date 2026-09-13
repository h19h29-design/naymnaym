package com.h19h29.naymnaymlevelup.rebuild.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "profiles")
data class ProfileEntity(
    @PrimaryKey val id: String,
    val role: String,
    val nickname: String,
    val officeCode: String?,
    val schoolCode: String?,
    val allergyCodesJson: String,
)

@Entity(tableName = "meal_days")
data class MealDayEntity(
    @PrimaryKey val date: String,
    val payloadJson: String,
    val fetchedAtEpochMillis: Long,
    val source: String,
)

@Entity(tableName = "meal_records")
data class MealRecordEntity(
    @PrimaryKey val id: String,
    val date: String,
    val menuName: String,
    val normalizedMenuName: String,
    val status: String,
    val difficultyReasonsJson: String,
    val allergyCodesJson: String,
    val photoIdsJson: String,
    @ColumnInfo(defaultValue = "0") val parentShareEnabled: Boolean = false,
    val updatedAtEpochMillis: Long,
    val deletedAtEpochMillis: Long?,
)

@Entity(tableName = "meal_photos")
data class MealPhotoEntity(
    @PrimaryKey val id: String,
    val recordId: String,
    val relativePath: String,
    val createdAtEpochMillis: Long,
)

@Entity(tableName = "progress_events")
data class ProgressEventEntity(
    @PrimaryKey val id: String,
    val amount: Int,
    val occurredAtEpochMillis: Long,
    val sourceRecordId: String?,
)

@Entity(tableName = "sync_envelopes")
data class SyncEnvelopeEntity(
    @PrimaryKey val id: String,
    val recordType: String,
    val recordId: String,
    val state: String,
    val retryCount: Int,
    val updatedAtEpochMillis: Long,
)

@Entity(tableName = "parent_links")
data class ParentLinkEntity(
    @PrimaryKey val id: String,
    val inviteCode: String,
    val connectionState: String,
    val connectedAtEpochMillis: Long?,
    val inviteSecret: String? = null,
    val registeredAtEpochMillis: Long? = null,
)

@Entity(tableName = "migration_states")
data class MigrationStateEntity(
    @PrimaryKey val id: String,
    val version: Int,
    val completedAtEpochMillis: Long,
    val sourceDigest: String?,
)

@Entity(tableName = "daily_meal_reviews")
data class DailyMealReviewEntity(
    @PrimaryKey val id: String,
    val profileKey: String,
    val schoolKey: String,
    val date: String,
    val payloadJson: String,
    val createdAtEpochMillis: Long,
)
