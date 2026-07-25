package com.h19h29.naymnaymlevelup.rebuild.migration

import androidx.room.withTransaction
import com.h19h29.naymnaymlevelup.rebuild.data.MealPhotoEntity
import com.h19h29.naymnaymlevelup.rebuild.data.MealRecordEntity
import com.h19h29.naymnaymlevelup.rebuild.data.MigrationStateEntity
import com.h19h29.naymnaymlevelup.rebuild.data.MigrationStateRepository
import com.h19h29.naymnaymlevelup.rebuild.data.ParentLinkEntity
import com.h19h29.naymnaymlevelup.rebuild.data.ProfileEntity
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

enum class MigrationOutcome {
    NoLegacyData,
    Migrated,
    AlreadyCompleted,
}

sealed class LegacyMigrationException(
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause) {
    class UnsupportedTargetVersion(
        val version: Int,
    ) : LegacyMigrationException("unsupported migration target version: $version")

    class InvalidSourcePreference(
        val key: String,
        val reason: String,
        cause: Throwable? = null,
    ) : LegacyMigrationException("invalid legacy preference '$key': $reason", cause)

    class InvalidPayload(
        val payload: String,
        val reason: String,
        cause: Throwable? = null,
    ) : LegacyMigrationException("invalid legacy $payload payload: $reason", cause)

    class VerificationMismatch(
        val field: String,
        val expected: String,
        val actual: String,
    ) : LegacyMigrationException(
        "migration verification failed for $field: expected $expected, got $actual",
    )

    class TargetCollision(
        val table: String,
        val id: String,
    ) : LegacyMigrationException("migration target collision in $table for id '$id'")
}

data class MigrationPlan(
    val profile: ProfileEntity?,
    val mealRecords: List<MealRecordEntity>,
    val mealPhotos: List<MealPhotoEntity>,
    val progressEvents: List<ProgressEventEntity>,
    val parentLinks: List<ParentLinkEntity>,
    val expectedTotalXp: Int,
)

data class MigrationVerification(
    val profileCount: Int,
    val mealRecordCount: Int,
    val progressEventCount: Int,
    val totalXp: Int,
)

interface MigrationTarget {
    suspend fun completedVersion(): Int

    /**
     * Implementations must atomically recheck completion, write and verify the
     * plan, then write the completion marker last.
     */
    suspend fun migrate(
        plan: MigrationPlan,
        targetVersion: Int,
        sourceDigest: String,
    ): MigrationOutcome
}

class RebuildMigrationCoordinator(
    private val source: LegacyMigrationSource,
    private val target: MigrationTarget,
) {
    private val attemptMutex = Mutex()

    suspend fun runIfNeeded(targetVersion: Int = SUPPORTED_TARGET_VERSION): MigrationOutcome =
        attemptMutex.withLock {
            if (targetVersion != SUPPORTED_TARGET_VERSION) {
                throw LegacyMigrationException.UnsupportedTargetVersion(targetVersion)
            }
            if (target.completedVersion() >= targetVersion) {
                return@withLock MigrationOutcome.AlreadyCompleted
            }

            val snapshot = source.readSnapshot()
            if (!snapshot.hasLegacyData) {
                return@withLock MigrationOutcome.NoLegacyData
            }
            val plan = LegacySnapshotMapper.map(snapshot)
            target.migrate(
                plan = plan,
                targetVersion = targetVersion,
                sourceDigest = source.sourceDigest(snapshot),
            )
        }

    companion object {
        const val SUPPORTED_TARGET_VERSION = 1
    }
}

class RoomMigrationTarget(
    private val database: RebuildDatabase,
    private val nowEpochMillis: () -> Long = System::currentTimeMillis,
    private val afterVerification: suspend (MigrationVerification) -> Unit = {},
) : MigrationTarget {
    override suspend fun completedVersion(): Int =
        database.migrationStateDao().version(MigrationStateRepository.STATE_ID) ?: 0

    override suspend fun migrate(
        plan: MigrationPlan,
        targetVersion: Int,
        sourceDigest: String,
    ): MigrationOutcome = database.withTransaction {
        val migrationDao = database.migrationStateDao()
        if ((migrationDao.version(MigrationStateRepository.STATE_ID) ?: 0) >= targetVersion) {
            return@withTransaction MigrationOutcome.AlreadyCompleted
        }

        preflight(plan)
        plan.profile?.let { database.profileDao().upsert(it) }
        plan.mealRecords.forEach { database.mealRecordDao().upsert(it) }
        plan.mealPhotos.forEach { database.mealPhotoDao().upsert(it) }
        plan.progressEvents.forEach { database.progressDao().insert(it) }
        plan.parentLinks.forEach { database.parentLinkDao().upsert(it) }

        val verification = verify(plan)
        afterVerification(verification)
        migrationDao.insert(
            MigrationStateEntity(
                id = MigrationStateRepository.STATE_ID,
                version = targetVersion,
                completedAtEpochMillis = nowEpochMillis(),
                sourceDigest = sourceDigest,
            ),
        )
        MigrationOutcome.Migrated
    }

    private suspend fun preflight(plan: MigrationPlan) {
        plan.profile?.let { incoming ->
            requireCompatible(
                table = "profiles",
                id = incoming.id,
                existing = database.profileDao().find(incoming.id),
                incoming = incoming,
            )
        }
        plan.mealRecords.forEach { incoming ->
            requireCompatible(
                table = "meal_records",
                id = incoming.id,
                existing = database.mealRecordDao().find(incoming.id),
                incoming = incoming,
            )
        }
        plan.mealPhotos.forEach { incoming ->
            requireCompatible(
                table = "meal_photos",
                id = incoming.id,
                existing = database.mealPhotoDao().find(incoming.id),
                incoming = incoming,
            )
        }
        plan.parentLinks.forEach { incoming ->
            requireCompatible(
                table = "parent_links",
                id = incoming.id,
                existing = database.parentLinkDao().find(incoming.id),
                incoming = incoming,
            )
        }
    }

    private fun <T> requireCompatible(
        table: String,
        id: String,
        existing: T?,
        incoming: T,
    ) {
        if (existing != null && existing != incoming) {
            throw LegacyMigrationException.TargetCollision(table, id)
        }
    }

    private suspend fun verify(plan: MigrationPlan): MigrationVerification {
        val profileCount = if (plan.profile == null) {
            0
        } else {
            val actual = database.profileDao().find(plan.profile.id)
            requireMatch("profile", plan.profile.toString(), actual.toString())
            1
        }

        plan.mealRecords.forEach { expected ->
            requireMatch(
                field = "mealRecord:${expected.id}",
                expected = expected.toString(),
                actual = database.mealRecordDao().find(expected.id).toString(),
            )
        }
        val mealCount = countMealRecords(plan.mealRecords)
        requireMatch(
            field = "mealRecordCount",
            expected = plan.mealRecords.size.toString(),
            actual = mealCount.toString(),
        )

        plan.mealPhotos.forEach { expected ->
            val actual = database.mealPhotoDao()
                .forRecord(expected.recordId)
                .firstOrNull { it.id == expected.id }
            requireMatch(
                field = "mealPhoto:${expected.id}",
                expected = expected.toString(),
                actual = actual.toString(),
            )
        }
        plan.parentLinks.forEach { expected ->
            if (database.parentLinkDao().find(expected.id) != expected) {
                throw LegacyMigrationException.VerificationMismatch(
                    field = "parentLink:${expected.id}",
                    expected = "matching parent-link row",
                    actual = "missing or different parent-link row",
                )
            }
        }

        plan.progressEvents.forEach { expected ->
            requireMatch(
                field = "progressEvent:${expected.id}",
                expected = expected.toString(),
                actual = database.progressDao().find(expected.id).toString(),
            )
        }
        val progressCount = countProgressEvents(plan.progressEvents)
        requireMatch(
            field = "progressEventCount",
            expected = plan.progressEvents.size.toString(),
            actual = progressCount.toString(),
        )
        val totalXp = database.progressDao().totalXp()
        requireMatch(
            field = "totalXp",
            expected = plan.expectedTotalXp.toString(),
            actual = totalXp.toString(),
        )
        return MigrationVerification(
            profileCount = profileCount,
            mealRecordCount = mealCount,
            progressEventCount = progressCount,
            totalXp = totalXp,
        )
    }

    private suspend fun countMealRecords(records: List<MealRecordEntity>): Int =
        if (records.isEmpty()) 0 else database.mealRecordDao().count(records.map { it.id })

    private suspend fun countProgressEvents(events: List<ProgressEventEntity>): Int =
        if (events.isEmpty()) 0 else database.progressDao().count(events.map { it.id })

    private fun requireMatch(field: String, expected: String, actual: String) {
        if (expected != actual) {
            throw LegacyMigrationException.VerificationMismatch(field, expected, actual)
        }
    }
}

private object LegacySnapshotMapper {
    private const val RECONCILIATION_EVENT_ID = "legacy:progress-reconciliation"
    private val validRoles = setOf("child", "parent")
    private val validStatuses = setOf(
        "oneBite",
        "finished",
        "half",
        "smelledOnly",
        "difficultToday",
        "allergyAvoided",
    )

    fun map(snapshot: LegacySnapshot): MigrationPlan {
        var profile = snapshot.profileJson?.let(::parseProfile)
        val meals = snapshot.mealsJson?.let(::parseMeals).orEmpty()
        val mealPhotos = snapshot.mealPhotosJson
            ?.let { parseMealPhotos(it, meals) }
            .orEmpty()
        val challenges = snapshot.challengesJson?.let(::parseChallenges).orEmpty()
        val parent = snapshot.parentJson?.let(::parseParent)
        if (profile == null) {
            profile = parent?.profile
        }
        val childLink = snapshot.childLinkJson?.let(::parseChildLink)
        val parentLinks = mergeParentLinks(parent?.links.orEmpty(), childLink)
        val storedProgress = snapshot.progressJson?.let(::parseProgress)
        val progressEvents = makeProgressEvents(
            challenges = challenges,
            expectedTotalXp = storedProgress ?: sumXp(challenges.map { it.amount }, "progress"),
            hasStoredProgress = snapshot.progressJson != null,
        )
        val expectedTotalXp = storedProgress ?: sumXp(
            challenges.map { it.amount },
            "progress",
        )
        return MigrationPlan(
            profile = profile,
            mealRecords = meals,
            mealPhotos = mealPhotos,
            progressEvents = progressEvents,
            parentLinks = parentLinks,
            expectedTotalXp = expectedTotalXp,
        )
    }

    private fun parseProfile(raw: String): ProfileEntity {
        val objectValue = parseObject(raw, "profile")
        val nickname = objectValue.requiredNonBlankString("nickname", "profile")
        val role = objectValue.optionalString("role", "profile") ?: "child"
        if (role !in validRoles) {
            invalid("profile", "role must be child or parent")
        }
        return ProfileEntity(
            id = objectValue.optionalString("id", "profile")?.ifBlank {
                invalid("profile", "id must not be blank")
            } ?: "legacy-android-profile",
            role = role,
            nickname = nickname,
            officeCode = objectValue.optionalString("officeCode", "profile")?.ifBlank { null },
            schoolCode = objectValue.optionalString("schoolCode", "profile")?.ifBlank { null },
            allergyCodesJson = objectValue.optionalArray("allergyCodes", "profile")
                ?.also { it.requireIntegers("profile.allergyCodes") }
                ?.toString()
                ?: "[]",
        )
    }

    private fun parseProgress(raw: String): Int {
        val objectValue = parseObject(raw, "progress")
        if (objectValue.has("totalXp")) {
            return objectValue.requiredInt("totalXp", "progress")
        }
        return sumXp(
            listOf("recordExp", "challengeExp", "balanceExp", "safetyExp").map {
                objectValue.optionalInt(it, "progress") ?: 0
            },
            "progress",
        )
    }

    private fun parseMeals(raw: String): List<MealRecordEntity> {
        val array = parseArray(raw, "meals")
        val records = array.objects("meals").mapIndexed { index, objectValue ->
            val path = "meals[$index]"
            val date = normalizedDate(objectValue.requiredNonBlankString("date", path), path)
            val menuName = objectValue.requiredNonBlankString("menuName", path)
            val status = (
                objectValue.optionalString("eatingStatus", path)
                    ?: objectValue.optionalString("status", path)
                    ?: invalid(path, "missing eatingStatus")
                )
            requireStatus(status, path)
            val normalizedName = menuName.trim().lowercase(Locale.ROOT)
            val identity = "$date|$normalizedName|$status"
            val difficultyReasons = objectValue.optionalArray("difficultyReasons", path)
                ?.also { it.requireStrings("$path.difficultyReasons") }
                ?: JSONArray()
            val allergyCodes = objectValue.optionalArray("allergyCodes", path)
                ?.also { it.requireIntegers("$path.allergyCodes") }
                ?: JSONArray()
            val photoIds = objectValue.optionalArray("photoIds", path)
                ?.also { it.requireStrings("$path.photoIds") }
                ?: JSONArray()
            MealRecordEntity(
                id = identity,
                date = date,
                menuName = menuName,
                normalizedMenuName = normalizedName,
                status = status,
                difficultyReasonsJson = difficultyReasons.toString(),
                allergyCodesJson = allergyCodes.toString(),
                photoIdsJson = photoIds.toString(),
                parentShareEnabled = objectValue.optionalBoolean(
                    "parentShareEnabled",
                    path,
                ) ?: false,
                updatedAtEpochMillis = objectValue.requiredTimestamp("createdAt", path),
                deletedAtEpochMillis = null,
            )
        }
        requireUnique(records.map { it.id }, "meals", "record identity")
        return records
    }

    private fun parseMealPhotos(
        raw: String,
        meals: List<MealRecordEntity>,
    ): List<MealPhotoEntity> {
        val photoRecordIds = mutableMapOf<String, String>()
        meals.forEach { meal ->
            JSONArray(meal.photoIdsJson).strings("meal photo IDs").forEach { photoId ->
                val previous = photoRecordIds.put(photoId, meal.id)
                if (previous != null && previous != meal.id) {
                    invalid("mealPhotos", "photo '$photoId' is referenced by multiple meals")
                }
            }
        }
        val photos = parseArray(raw, "mealPhotos").objects("mealPhotos")
            .mapIndexed { index, objectValue ->
                val path = "mealPhotos[$index]"
                val id = objectValue.requiredNonBlankString("id", path)
                val relativePath = (
                    objectValue.optionalString("relativePath", path)
                        ?: objectValue.optionalString("fileName", path)
                        ?: invalid(path, "missing relativePath or fileName")
                    ).also {
                    if (it.isBlank() || it.startsWith("/") || it.contains("..")) {
                        invalid(path, "unsafe relative path")
                    }
                }
                MealPhotoEntity(
                    id = id,
                    recordId = objectValue.optionalString("recordId", path)
                        ?: photoRecordIds[id]
                        ?: "legacy-orphan-photo:$id",
                    relativePath = relativePath,
                    createdAtEpochMillis = objectValue.requiredTimestamp("createdAt", path),
                )
            }
        requireUnique(photos.map { it.id }, "mealPhotos", "photo ID")
        return photos
    }

    private fun parseChallenges(raw: String): List<ChallengeMigrationRecord> {
        val challenges = parseArray(raw, "challenges").objects("challenges")
            .mapIndexed { index, objectValue ->
                val path = "challenges[$index]"
                val sourceId = (
                    objectValue.optionalString("challengeId", path)
                        ?: objectValue.optionalString("id", path)
                        ?: invalid(path, "missing challengeId")
                    ).ifBlank { invalid(path, "challengeId must not be blank") }
                val date = normalizedDate(
                    objectValue.requiredNonBlankString("date", path),
                    path,
                )
                val menuName = objectValue.requiredNonBlankString("menuName", path)
                val status = objectValue.optionalString("eatingStatus", path)
                    ?: statusForAction(objectValue.requiredNonBlankString("action", path), path)
                requireStatus(status, path)
                val components = listOf(
                    "recordExp",
                    "challengeExp",
                    "balanceExp",
                    "safetyExp",
                )
                val hasComponents = components.any(objectValue::has)
                val amount = if (hasComponents) {
                    sumXp(
                        components.map { objectValue.optionalInt(it, path) ?: 0 },
                        path,
                    )
                } else {
                    objectValue.requiredInt("gainedExp", path)
                }
                val normalizedName = menuName.trim().lowercase(Locale.ROOT)
                ChallengeMigrationRecord(
                    eventId = "meal:$date|$normalizedName|$status",
                    amount = amount,
                    occurredAtEpochMillis = objectValue.requiredTimestamp("createdAt", path),
                    sourceRecordId = sourceId,
                )
            }
        requireUnique(challenges.map { it.eventId }, "challenges", "progress event identity")
        requireUnique(challenges.map { it.sourceRecordId }, "challenges", "challenge ID")
        return challenges
    }

    private fun parseParent(raw: String): ParsedParent {
        val trimmed = raw.trimStart()
        return if (trimmed.startsWith("[")) {
            val links = parseArray(raw, "parent").objects("parent")
                .mapIndexed { index, child ->
                    parentReceipt(child, "parent[$index]")
                }
            ParsedParent(profile = null, links = links)
        } else {
            val objectValue = parseObject(raw, "parent")
            val profile = if (objectValue.has("nickname")) {
                ProfileEntity(
                    id = objectValue.optionalString("id", "parent")
                        ?.ifBlank { invalid("parent", "id must not be blank") }
                        ?: "legacy-android-parent",
                    role = "parent",
                    nickname = objectValue.requiredNonBlankString("nickname", "parent"),
                    officeCode = null,
                    schoolCode = null,
                    allergyCodesJson = "[]",
                )
            } else {
                null
            }
            val links = objectValue.optionalArray("childLinks", "parent")
                ?.objects("parent.childLinks")
                ?.mapIndexed { index, child ->
                    parentReceipt(child, "parent.childLinks[$index]")
                }
                .orEmpty()
            if (profile == null && !objectValue.has("childLinks")) {
                invalid("parent", "missing nickname and childLinks")
            }
            ParsedParent(profile = profile, links = links)
        }
    }

    private fun parentReceipt(value: JSONObject, path: String): ParentLinkEntity {
        val inviteCode = value.requiredNonBlankString("inviteCode", path)
        val id = value.optionalString("id", path)
            ?: value.optionalString("childLinkId", path)
            ?: stableId("legacy-parent", inviteCode)
        return ParentLinkEntity(
            id = id.ifBlank { invalid(path, "id must not be blank") },
            inviteCode = inviteCode,
            connectionState = "connected",
            connectedAtEpochMillis = value.optionalTimestamp("connectedAt", path),
            inviteSecret = value.optionalString("inviteSecret", path),
            registeredAtEpochMillis = value.optionalTimestamp("registeredAt", path),
        )
    }

    private fun parseChildLink(raw: String): ParentLinkEntity {
        val objectValue = parseObject(raw, "childLink")
        val id = objectValue.optionalString("id", "childLink")
            ?: objectValue.requiredNonBlankString("childLinkId", "childLink")
        val inviteCode = objectValue.requiredNonBlankString("inviteCode", "childLink")
        val connectedAt = objectValue.optionalTimestamp(
            "parentConnectedAt",
            "childLink",
        )
        val inviteSecret = objectValue.optionalString("inviteSecret", "childLink")
        val registeredAt = objectValue.optionalTimestamp("registeredAt", "childLink")
        return ParentLinkEntity(
            id = id.ifBlank { invalid("childLink", "id must not be blank") },
            inviteCode = inviteCode,
            connectionState = if (connectedAt == null) "invitePending" else "connected",
            connectedAtEpochMillis = connectedAt,
            inviteSecret = inviteSecret,
            registeredAtEpochMillis = registeredAt,
        )
    }

    private fun mergeParentLinks(
        parentLinks: List<ParentLinkEntity>,
        childLink: ParentLinkEntity?,
    ): List<ParentLinkEntity> {
        val byId = linkedMapOf<String, ParentLinkEntity>()
        val idByInvite = mutableMapOf<String, String>()
        (parentLinks + listOfNotNull(childLink)).forEach { link ->
            val normalizedInvite = link.inviteCode.trim().uppercase(Locale.ROOT)
            val normalizedLink = link.copy(inviteCode = normalizedInvite)
            val existingById = byId[link.id]
            if (existingById != null) {
                if (existingById != normalizedLink) {
                    invalid("parentLinks", "id '${link.id}' has conflicting records")
                }
                return@forEach
            }
            val existingIdForInvite = idByInvite[normalizedInvite]
            if (existingIdForInvite != null && existingIdForInvite != link.id) {
                invalid(
                    "parentLinks",
                    "invite code '$normalizedInvite' belongs to multiple IDs",
                )
            }
            byId[link.id] = normalizedLink
            idByInvite[normalizedInvite] = link.id
        }
        return byId.values.sortedBy { it.id }
    }

    private fun makeProgressEvents(
        challenges: List<ChallengeMigrationRecord>,
        expectedTotalXp: Int,
        hasStoredProgress: Boolean,
    ): List<ProgressEventEntity> {
        val events = challenges.map {
            ProgressEventEntity(
                id = it.eventId,
                amount = it.amount,
                occurredAtEpochMillis = it.occurredAtEpochMillis,
                sourceRecordId = it.sourceRecordId,
            )
        }.toMutableList()
        val challengeTotal = sumXp(events.map { it.amount }, "progress")
        val remainder = try {
            Math.subtractExact(expectedTotalXp, challengeTotal)
        } catch (error: ArithmeticException) {
            invalid("progress", "XP total overflow", error)
        }
        if (remainder != 0 || (hasStoredProgress && events.isEmpty())) {
            events += ProgressEventEntity(
                id = RECONCILIATION_EVENT_ID,
                amount = remainder,
                occurredAtEpochMillis = challenges.maxOfOrNull {
                    it.occurredAtEpochMillis
                } ?: 0L,
                sourceRecordId = null,
            )
        }
        return events
    }

    private fun statusForAction(action: String, path: String): String = when (action) {
        "oneBite" -> "oneBite"
        "alreadyEats" -> "finished"
        "skipped" -> "difficultToday"
        else -> invalid(path, "unsupported challenge action '$action'")
    }

    private fun requireStatus(status: String, path: String) {
        if (status !in validStatuses) {
            invalid(path, "unsupported eating status '$status'")
        }
    }

    private fun normalizedDate(value: String, path: String): String = when {
        value.matches(Regex("""\d{8}""")) -> {
            val normalized =
                "${value.substring(0, 4)}-${value.substring(4, 6)}-${value.substring(6, 8)}"
            requireCalendarDate(normalized, path)
            normalized
        }
        value.matches(Regex("""\d{4}-\d{2}-\d{2}""")) -> {
            requireCalendarDate(value, path)
            value
        }
        else -> invalid(path, "date must be yyyyMMdd or yyyy-MM-dd")
    }

    private fun requireCalendarDate(value: String, path: String) {
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            isLenient = false
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val position = ParsePosition(0)
        if (formatter.parse(value, position) == null || position.index != value.length) {
            invalid(path, "invalid calendar date")
        }
    }

    private fun sumXp(values: List<Int>, path: String): Int =
        try {
            values.fold(0, Math::addExact)
        } catch (error: ArithmeticException) {
            invalid(path, "XP total overflow", error)
        }

    private fun requireUnique(values: List<String>, payload: String, name: String) {
        val duplicate = values.groupingBy { it }.eachCount().entries
            .firstOrNull { it.value > 1 }
            ?.key
        if (duplicate != null) {
            invalid(payload, "duplicate $name '$duplicate'")
        }
    }

    private fun stableId(prefix: String, value: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return "$prefix:" + bytes.take(16).joinToString("") { "%02x".format(it) }
    }

    private data class ChallengeMigrationRecord(
        val eventId: String,
        val amount: Int,
        val occurredAtEpochMillis: Long,
        val sourceRecordId: String,
    )

    private data class ParsedParent(
        val profile: ProfileEntity?,
        val links: List<ParentLinkEntity>,
    )
}

private fun parseObject(raw: String, payload: String): JSONObject =
    try {
        StrictJsonValidator.validate(raw)
        JSONObject(raw)
    } catch (error: Exception) {
        invalid(payload, "expected a JSON object", error)
    }

private fun parseArray(raw: String, payload: String): JSONArray =
    try {
        StrictJsonValidator.validate(raw)
        JSONArray(raw)
    } catch (error: Exception) {
        invalid(payload, "expected a JSON array", error)
    }

private fun JSONArray.objects(path: String): List<JSONObject> =
    (0 until length()).map { index ->
        opt(index) as? JSONObject ?: invalid(path, "item $index must be an object")
    }

private fun JSONArray.strings(path: String): List<String> =
    (0 until length()).map { index ->
        opt(index) as? String ?: invalid(path, "item $index must be a string")
    }

private fun JSONArray.requireStrings(path: String) {
    strings(path)
}

private fun JSONArray.requireIntegers(path: String) {
    (0 until length()).forEach { index ->
        val value = opt(index)
        if (value !is Number || value.toLong().toDouble() != value.toDouble()) {
            invalid(path, "item $index must be an integer")
        }
    }
}

private fun JSONObject.requiredNonBlankString(name: String, path: String): String {
    val value = optionalString(name, path)
        ?: invalid(path, "missing $name")
    if (value.isBlank()) {
        invalid(path, "$name must not be blank")
    }
    return value
}

private fun JSONObject.optionalString(name: String, path: String): String? {
    if (!has(name) || isNull(name)) {
        return null
    }
    return opt(name) as? String ?: invalid(path, "$name must be a string")
}

private fun JSONObject.requiredInt(name: String, path: String): Int =
    optionalInt(name, path) ?: invalid(path, "missing $name")

private fun JSONObject.optionalInt(name: String, path: String): Int? {
    if (!has(name) || isNull(name)) {
        return null
    }
    val value = opt(name)
    if (value !is Number || value.toLong().toDouble() != value.toDouble()) {
        invalid(path, "$name must be an integer")
    }
    val longValue = value.toLong()
    if (longValue !in Int.MIN_VALUE..Int.MAX_VALUE) {
        invalid(path, "$name is outside Int range")
    }
    return longValue.toInt()
}

private fun JSONObject.optionalBoolean(name: String, path: String): Boolean? {
    if (!has(name) || isNull(name)) {
        return null
    }
    return opt(name) as? Boolean ?: invalid(path, "$name must be a boolean")
}

private fun JSONObject.optionalArray(name: String, path: String): JSONArray? {
    if (!has(name) || isNull(name)) {
        return null
    }
    return opt(name) as? JSONArray ?: invalid(path, "$name must be an array")
}

private fun JSONObject.requiredTimestamp(name: String, path: String): Long =
    optionalTimestamp(name, path) ?: invalid(path, "missing $name")

private fun JSONObject.optionalTimestamp(name: String, path: String): Long? {
    if (!has(name) || isNull(name)) {
        return null
    }
    return when (val value = opt(name)) {
        is Number -> {
            if (value.toLong().toDouble() != value.toDouble()) {
                invalid(path, "$name epoch milliseconds must be an integer")
            }
            value.toLong()
        }
        is String -> parseIsoTimestamp(value, "$path.$name")
        else -> invalid(path, "$name must be an ISO-8601 string or epoch milliseconds")
    }
}

private fun parseIsoTimestamp(value: String, path: String): Long {
    val normalized = value
        .replace(Regex("""Z$"""), "+0000")
        .replace(Regex("""([+-]\d{2}):(\d{2})$"""), "$1$2")
    val patterns = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
    )
    patterns.forEach { pattern ->
        val formatter = SimpleDateFormat(pattern, Locale.US).apply {
            isLenient = false
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val position = ParsePosition(0)
        val date = formatter.parse(normalized, position)
        if (date != null && position.index == normalized.length) {
            return date.time
        }
    }
    val legacyFormatter = SimpleDateFormat(
        "EEE MMM dd HH:mm:ss zzz yyyy",
        Locale.US,
    ).apply {
        isLenient = false
    }
    val legacyPosition = ParsePosition(0)
    val legacyDate = legacyFormatter.parse(value, legacyPosition)
    if (legacyDate != null && legacyPosition.index == value.length) {
        return legacyDate.time
    }
    invalid(path, "invalid ISO-8601 timestamp")
}

private fun invalid(
    payload: String,
    reason: String,
    cause: Throwable? = null,
): Nothing = throw LegacyMigrationException.InvalidPayload(payload, reason, cause)
