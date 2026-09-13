package com.h19h29.naymnaymlevelup.rebuild.child

import com.h19h29.naymnaymlevelup.rebuild.data.DailyMealReviewDao
import com.h19h29.naymnaymlevelup.rebuild.data.DailyMealReviewEntity
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class DailyMealReviewStore(
    private val dao: DailyMealReviewDao,
    private val now: () -> Instant = Instant::now,
) : DailyMealReviewRepository {
    private val mutableDeletionRevision = MutableStateFlow(0L)
    override val deletionRevision: StateFlow<Long> = mutableDeletionRevision.asStateFlow()
    override suspend fun load(
        profileKey: String,
        schoolKey: String,
        date: String,
    ): SavedDailyMealReview? = dao.find(profileKey, schoolKey, date)?.let { entity ->
        DailyMealReviewJson.decodeStored(entity.payloadJson).also { record ->
            if (record.profileKey != profileKey || record.schoolKey != schoolKey || record.date != date) {
                throw DailyMealReviewCorruptRecordException()
            }
        }
    }

    override suspend fun save(record: SavedDailyMealReview) {
        require(record.response.source == "ai")
        dao.upsert(
            DailyMealReviewEntity(
                id = record.storageId(),
                profileKey = record.profileKey,
                schoolKey = record.schoolKey,
                date = record.date,
                payloadJson = DailyMealReviewJson.encodeStored(record),
                createdAtEpochMillis = now().toEpochMilli(),
            ),
        )
    }

    override suspend fun deleteAll() {
        dao.deleteAll()
        mutableDeletionRevision.value += 1
    }
}

private fun SavedDailyMealReview.storageId(): String =
    listOf(profileKey, schoolKey, date).joinToString(separator = "|")
