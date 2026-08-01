package com.h19h29.naymnaymlevelup.rebuild.growth

import com.h19h29.naymnaymlevelup.rebuild.meal.ContractLoadException
import com.h19h29.naymnaymlevelup.rebuild.meal.RebuildContractReader
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.Locale

enum class CollectionBadgeCategory {
    nutrition,
    challenge,
    streak,
}

data class CollectionRecord(
    val date: String,
    val normalizedMenuName: String,
    val status: String,
)

data class CollectionBadge(
    val id: String,
    val category: CollectionBadgeCategory,
    val metric: String,
    val threshold: Int,
    val title: String,
)

data class CollectionProgress(
    val totalXp: Int,
    val badges: List<CollectionBadge>,
    val earnedBadgeIds: Set<String>,
    val positiveRecordCount: Int,
    val activeDayCount: Int,
    val longestWeekdayStreak: Int,
) {
    val collectedCount: Int
        get() = earnedBadgeIds.size

    fun earnedCount(category: CollectionBadgeCategory): Int =
        badges.count { it.category == category && it.id in earnedBadgeIds }

    fun badges(category: CollectionBadgeCategory): List<CollectionBadge> =
        badges.filter { it.category == category }

    companion object {
        fun evaluate(
            totalXp: Int,
            records: List<CollectionRecord>,
            policyBytes: ByteArray,
        ): CollectionProgress {
            val policy = CollectionPolicy.decode(policyBytes)
            val positiveRecords = deduplicatedPositiveRecords(
                records = records,
                positiveStatuses = policy.positiveStatuses.toSet(),
            )
            val activeDates = positiveRecords.map { it.date }.toSet()
            val foodGroupCounts = policy.foodGroups.associate { group ->
                group.id to positiveRecords.count { record ->
                    group.keywords.any { keyword ->
                        record.normalizedMenuName.contains(keyword)
                    }
                }
            }
            val metrics = metrics(
                positiveRecords = positiveRecords,
                foodGroupCounts = foodGroupCounts,
                activeDates = activeDates,
            )
            val earnedIds = policy.badges
                .filter { badge -> metrics.getValueOrDefault(badge.metric, 0) >= badge.threshold }
                .mapTo(linkedSetOf()) { it.id }
            return CollectionProgress(
                totalXp = totalXp.coerceAtLeast(0),
                badges = policy.badges,
                earnedBadgeIds = earnedIds,
                positiveRecordCount = positiveRecords.size,
                activeDayCount = activeDates.size,
                longestWeekdayStreak = metrics.getValueOrDefault("weekday_streak", 0),
            )
        }

        private fun deduplicatedPositiveRecords(
            records: List<CollectionRecord>,
            positiveStatuses: Set<String>,
        ): List<CollectionRecord> {
            val bestForMeal = linkedMapOf<String, CollectionRecord>()
            records.forEach { record ->
                val menu = record.normalizedMenuName.trim().lowercase(Locale.ROOT)
                if (
                    record.status !in positiveStatuses ||
                    menu.isEmpty() ||
                    parseCanonicalDate(record.date) == null
                ) {
                    return@forEach
                }
                val normalized = record.copy(normalizedMenuName = menu)
                val identity = "${normalized.date}|${normalized.normalizedMenuName}"
                val existing = bestForMeal[identity]
                if (existing == null || statusRank(normalized.status) > statusRank(existing.status)) {
                    bestForMeal[identity] = normalized
                }
            }
            return bestForMeal.values.sortedWith(
                compareBy<CollectionRecord> { it.date }
                    .thenBy { it.normalizedMenuName }
                    .thenBy { it.status },
            )
        }

        private fun metrics(
            positiveRecords: List<CollectionRecord>,
            foodGroupCounts: Map<String, Int>,
            activeDates: Set<String>,
        ): Map<String, Int> {
            val menuCountsByDate = positiveRecords
                .groupBy { it.date }
                .mapValues { (_, records) -> records.map { it.normalizedMenuName }.toSet().size }
            return buildMap {
                put("positive_records", positiveRecords.size)
                put("one_bite_records", positiveRecords.count { it.status == "oneBite" })
                put("finished_records", positiveRecords.count { it.status == "finished" })
                put("distinct_menus", positiveRecords.map { it.normalizedMenuName }.toSet().size)
                put("three_menu_days", menuCountsByDate.values.count { it >= 3 })
                put("active_days", activeDates.size)
                put("weekday_streak", longestWeekdayStreak(activeDates))
                put("distinct_food_groups", foodGroupCounts.values.count { it > 0 })
                foodGroupCounts.forEach { (id, count) -> put("food_group_$id", count) }
            }
        }

        private fun longestWeekdayStreak(activeDates: Set<String>): Int {
            val weekdays = activeDates
                .mapNotNull(::parseCanonicalDate)
                .filter { it.dayOfWeek.value <= DayOfWeek.FRIDAY.value }
                .sorted()
            var longest = 0
            var current = 0
            var previous: LocalDate? = null
            weekdays.forEach { date ->
                current = if (previous == null) {
                    1
                } else {
                    val gap = ChronoUnit.DAYS.between(previous, date)
                    val crossesWeekend =
                        previous?.dayOfWeek == DayOfWeek.FRIDAY &&
                            date.dayOfWeek == DayOfWeek.MONDAY &&
                            gap == 3L
                    if (gap == 1L || crossesWeekend) current + 1 else 1
                }
                longest = maxOf(longest, current)
                previous = date
            }
            return longest
        }

        private fun statusRank(status: String): Int = when (status) {
            "finished" -> 3
            "half" -> 2
            "oneBite" -> 1
            else -> 0
        }
    }
}

private data class CollectionFoodGroup(
    val id: String,
    val keywords: List<String>,
)

private data class CollectionPolicy(
    val positiveStatuses: List<String>,
    val foodGroups: List<CollectionFoodGroup>,
    val badges: List<CollectionBadge>,
) {
    companion object {
        fun decode(bytes: ByteArray): CollectionPolicy = try {
            val root = RebuildContractReader.parse(bytes)
            val positiveStatuses = root.stringList("positiveStatuses")
            val foodGroups = (root["foodGroups"] as? List<*>)
                ?.map { value ->
                    val group = value as? Map<*, *> ?: throw ContractLoadException(CONTRACT_NAME)
                    val id = group["id"] as? String ?: throw ContractLoadException(CONTRACT_NAME)
                    val keywords = (group["keywords"] as? List<*>)
                        ?.map { (it as? String)?.trim()?.lowercase(Locale.ROOT)
                            ?: throw ContractLoadException(CONTRACT_NAME) }
                        ?: throw ContractLoadException(CONTRACT_NAME)
                    CollectionFoodGroup(id = id, keywords = keywords)
                }
                ?: throw ContractLoadException(CONTRACT_NAME)
            val badges = (root["badges"] as? List<*>)
                ?.map { value ->
                    val badge = value as? Map<*, *> ?: throw ContractLoadException(CONTRACT_NAME)
                    val threshold = (badge["threshold"] as? Long)?.toInt()
                        ?: throw ContractLoadException(CONTRACT_NAME)
                    val category = (badge["category"] as? String)
                        ?.let { raw -> CollectionBadgeCategory.entries.firstOrNull { it.name == raw } }
                        ?: throw ContractLoadException(CONTRACT_NAME)
                    CollectionBadge(
                        id = badge["id"] as? String ?: throw ContractLoadException(CONTRACT_NAME),
                        category = category,
                        metric = badge["metric"] as? String ?: throw ContractLoadException(CONTRACT_NAME),
                        threshold = threshold,
                        title = badge["title"] as? String ?: throw ContractLoadException(CONTRACT_NAME),
                    )
                }
                ?: throw ContractLoadException(CONTRACT_NAME)
            val groupIds = foodGroups.map { it.id }.toSet()
            val standardMetrics = setOf(
                "positive_records",
                "one_bite_records",
                "finished_records",
                "distinct_menus",
                "three_menu_days",
                "active_days",
                "weekday_streak",
                "distinct_food_groups",
            )
            val valid = root.keys == setOf("version", "positiveStatuses", "foodGroups", "badges") &&
                (root["version"] as? Long)?.toInt() == 1 &&
                positiveStatuses.isNotEmpty() &&
                positiveStatuses.toSet().size == positiveStatuses.size &&
                foodGroups.isNotEmpty() &&
                groupIds.size == foodGroups.size &&
                foodGroups.all { it.id.isNotBlank() && it.keywords.isNotEmpty() && it.keywords.all(String::isNotBlank) } &&
                badges.isNotEmpty() &&
                badges.map { it.id }.toSet().size == badges.size &&
                badges.all { badge ->
                    badge.id.isNotBlank() &&
                        badge.title.isNotBlank() &&
                        badge.threshold > 0 &&
                        (badge.metric in standardMetrics ||
                            (badge.metric.startsWith("food_group_") &&
                                badge.metric.removePrefix("food_group_") in groupIds))
                }
            if (!valid) throw ContractLoadException(CONTRACT_NAME)
            CollectionPolicy(positiveStatuses, foodGroups, badges)
        } catch (error: ContractLoadException) {
            throw error
        } catch (_: Exception) {
            throw ContractLoadException(CONTRACT_NAME)
        }

        private fun Map<String, Any?>.stringList(key: String): List<String> =
            (this[key] as? List<*>)?.map { it as? String ?: throw ContractLoadException(CONTRACT_NAME) }
                ?: throw ContractLoadException(CONTRACT_NAME)

        private const val CONTRACT_NAME = "collection-policy.json"
    }
}

private fun parseCanonicalDate(value: String): LocalDate? = try {
    LocalDate.parse(value).takeIf { it.toString() == value }
} catch (_: DateTimeParseException) {
    null
}
