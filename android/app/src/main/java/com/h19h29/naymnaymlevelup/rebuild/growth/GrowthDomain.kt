package com.h19h29.naymnaymlevelup.rebuild.growth

import android.content.res.AssetManager
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressDao
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.meal.ContractLoadException
import com.h19h29.naymnaymlevelup.rebuild.meal.RebuildContractReader
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.time.format.DateTimeFormatter
import java.util.Locale

class GrowthPolicy private constructor(
    val thresholds: List<Int>,
    val titles: List<String>,
) {
    fun level(totalXp: Int): Int = level(totalXp.toLong())

    fun level(totalXp: Long): Int {
        val safeXp = totalXp.coerceAtLeast(0)
        return thresholds.indexOfLast { safeXp >= it }
            .coerceAtLeast(0) + 1
    }

    fun title(level: Int): String = titles[(level - 1).coerceIn(titles.indices)]

    fun currentThreshold(totalXp: Int): Int = thresholds[level(totalXp) - 1]

    fun nextThreshold(totalXp: Int): Int? = thresholds.getOrNull(level(totalXp))

    fun progress(totalXp: Int): Float {
        val current = currentThreshold(totalXp)
        val next = nextThreshold(totalXp) ?: return 1f
        return ((totalXp.coerceAtLeast(0) - current).toFloat() / (next - current))
            .coerceIn(0f, 1f)
    }

    companion object {
        fun decode(bytes: ByteArray): GrowthPolicy =
            try {
                val root = RebuildContractReader.parse(bytes)
                val version = (root["version"] as? Long)?.toInt()
                val thresholds = (root["thresholds"] as? List<*>)
                    ?.map { value ->
                        val longValue = value as? Long
                            ?: throw ContractLoadException(CONTRACT_NAME)
                        longValue.toInt().takeIf {
                            it.toLong() == longValue
                        } ?: throw ContractLoadException(CONTRACT_NAME)
                    }
                    ?: throw ContractLoadException(CONTRACT_NAME)
                val titles = (root["titles"] as? List<*>)
                    ?.map { value ->
                        (value as? String)?.takeIf(String::isNotBlank)
                            ?: throw ContractLoadException(CONTRACT_NAME)
                    }
                    ?: throw ContractLoadException(CONTRACT_NAME)
                val valid = root.keys == setOf(
                    "version",
                    "thresholds",
                    "titles",
                ) &&
                    version == 1 &&
                    thresholds.size == 7 &&
                    thresholds.firstOrNull() == 0 &&
                    thresholds.zipWithNext().all { (left, right) ->
                        left < right
                    } &&
                    titles.size == 7 &&
                    titles.toSet().size == titles.size
                if (!valid) throw ContractLoadException(CONTRACT_NAME)
                GrowthPolicy(thresholds = thresholds, titles = titles)
            } catch (error: ContractLoadException) {
                throw error
            } catch (_: Exception) {
                throw ContractLoadException(CONTRACT_NAME)
            }

        private const val CONTRACT_NAME = "growth-policy.json"
    }
}

object GrowthPolicyLoader {
    fun load(assetManager: AssetManager): GrowthPolicy = load {
        RebuildContractReader.readAsset(assetManager, CONTRACT_NAME)
    }

    internal fun load(readBytes: () -> ByteArray): GrowthPolicy =
        try {
            GrowthPolicy.decode(readBytes())
        } catch (error: ContractLoadException) {
            throw error
        } catch (_: Exception) {
            throw ContractLoadException(CONTRACT_NAME)
        }

    private const val CONTRACT_NAME = "growth-policy.json"
}

data class GrowthSnapshot(
    val totalXp: Int,
    val recentEvents: List<ProgressEventEntity>,
) {
    companion object {
        val empty = GrowthSnapshot(totalXp = 0, recentEvents = emptyList())
    }
}

interface GrowthProgressSource {
    suspend fun totalXp(): Long
    suspend fun recentPositiveEvents(limit: Int): List<ProgressEventEntity>
}

class RoomGrowthProgressSource(
    private val progressDao: ProgressDao,
) : GrowthProgressSource {
    override suspend fun totalXp(): Long = progressDao.totalXp()

    override suspend fun recentPositiveEvents(limit: Int): List<ProgressEventEntity> =
        progressDao.recentPositive(limit)
}

class GrowthRepository(
    private val source: GrowthProgressSource,
) {
    suspend fun load(limit: Int = DEFAULT_RECENT_LIMIT): GrowthSnapshot {
        val boundedLimit = limit.coerceIn(0, MAX_RECENT_LIMIT)
        val totalXp = source.totalXp()
            .coerceIn(0, Int.MAX_VALUE.toLong())
            .toInt()
        val recentEvents = source.recentPositiveEvents(boundedLimit)
            .asSequence()
            .filter { it.amount > 0 }
            .sortedWith(
                compareByDescending<ProgressEventEntity> {
                    it.occurredAtEpochMillis
                }.thenByDescending { it.id },
            )
            .take(boundedLimit)
            .toList()
        return GrowthSnapshot(
            totalXp = totalXp,
            recentEvents = recentEvents,
        )
    }

    companion object {
        const val DEFAULT_RECENT_LIMIT = 8
        const val MAX_RECENT_LIMIT = 20
    }
}

data class GrowthEventPresentation(
    val title: String,
    val xpText: String,
    val dateText: String,
) {
    companion object {
        private val dateFormatter = DateTimeFormatter.ofPattern("M월 d일")
        private val statusLabels = mapOf(
            "finished" to "다 먹었어요",
            "half" to "절반 먹었어요",
            "oneBite" to "한 입 도전",
            "smelledOnly" to "냄새 맡기",
            "difficultToday" to "오늘은 어려웠어요",
            "allergyAvoided" to "알레르기 안전 기록",
        )

        fun from(event: ProgressEventEntity): GrowthEventPresentation {
            val title = when {
                event.id == "legacy:progress-reconciliation" ->
                    "이전 성장 기록 정리"
                event.id.startsWith("meal:") ->
                    canonicalMealTitle(event.id) ?: "성장 XP 획득"
                else -> "성장 XP 획득"
            }
            val localDate = Instant.ofEpochMilli(event.occurredAtEpochMillis)
                .atZone(ZoneId.systemDefault())
                .toLocalDate()
            return GrowthEventPresentation(
                title = title,
                xpText = "+${event.amount} XP",
                dateText = dateFormatter.format(localDate),
            )
        }

        private fun canonicalMealTitle(id: String): String? {
            val components = id.removePrefix("meal:").split('|')
            if (components.size != 3) return null
            val (date, menu, status) = components
            val statusLabel = statusLabels[status] ?: return null
            val normalizedMenu = menu.trim().lowercase(Locale.ROOT)
            if (
                !isCanonicalDate(date) ||
                normalizedMenu.isEmpty() ||
                menu != normalizedMenu
            ) {
                return null
            }
            return "$normalizedMenu · $statusLabel"
        }

        private fun isCanonicalDate(value: String): Boolean =
            try {
                LocalDate.parse(value).toString() == value
            } catch (_: DateTimeParseException) {
                false
            }
    }
}
