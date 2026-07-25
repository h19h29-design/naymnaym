package com.h19h29.naymnaymlevelup.rebuild.data

class ProgressRepository(
    private val progressDao: ProgressDao,
) {
    suspend fun appendIfAbsent(event: ProgressEventEntity): Boolean =
        progressDao.insert(event) != INSERT_IGNORED

    suspend fun totalXp(): Int = progressDao.totalXp()

    private companion object {
        const val INSERT_IGNORED = -1L
    }
}

class MigrationStateRepository(
    private val migrationStateDao: MigrationStateDao,
) {
    suspend fun currentVersion(): Int =
        migrationStateDao.version(STATE_ID) ?: 0

    suspend fun markCompleted(
        version: Int,
        sourceDigest: String?,
    ) {
        markCompleted(
            version = version,
            sourceDigest = sourceDigest,
            completedAtEpochMillis = System.currentTimeMillis(),
        )
    }

    suspend fun markCompleted(
        version: Int,
        sourceDigest: String?,
        completedAtEpochMillis: Long,
    ) {
        migrationStateDao.insert(
            MigrationStateEntity(
                id = STATE_ID,
                version = version,
                completedAtEpochMillis = completedAtEpochMillis,
                sourceDigest = sourceDigest,
            ),
        )
    }

    suspend fun load(): MigrationStateEntity? =
        migrationStateDao.find(STATE_ID)

    companion object {
        const val STATE_ID = "rebuild-migration"
    }
}
