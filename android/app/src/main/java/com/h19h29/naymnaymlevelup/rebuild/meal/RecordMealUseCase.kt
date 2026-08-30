package com.h19h29.naymnaymlevelup.rebuild.meal

import android.content.res.AssetManager
import androidx.room.withTransaction
import com.fasterxml.jackson.core.JsonFactory
import com.fasterxml.jackson.core.JsonToken
import com.h19h29.naymnaymlevelup.rebuild.data.MealRecordEntity
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.util.Locale

private const val XP_POLICY_FILENAME = "xp-policy.json"
private const val MEAL_RECORD_FILENAME = "meal-record.json"
private val mealRecordJsonFactory = JsonFactory()

enum class EatingStatus(
    val wireValue: String,
) {
    OneBite("oneBite"),
    Finished("finished"),
    Half("half"),
    SmelledOnly("smelledOnly"),
    DifficultToday("difficultToday"),
    AllergyAvoided("allergyAvoided"),
}

enum class DifficultyReason(
    val wireValue: String,
) {
    Texture("texture"),
    Smell("smell"),
    Taste("taste"),
    Appearance("appearance"),
    Spicy("spicy"),
    Color("color"),
    NewFood("newFood"),
    Allergy("allergy"),
    Other("other"),
}

enum class MotionState {
    Idle,
    TapReaction,
    MealSuccess,
    LevelUp,
    Comfort,
    ReducedMotion,
}

data class RecordMealCommand(
    val recordID: String,
    val date: String,
    val menuName: String,
    val status: EatingStatus,
    val difficultyReasons: List<DifficultyReason>,
    val allergyCodes: List<Int>,
    val childAllergyCodes: List<Int>,
    val itemAllergyCodes: List<Int>,
    val photoIDs: List<String>,
    val parentShareEnabled: Boolean,
    val occurredAt: Instant,
)

data class RecordMealResult(
    val xpGranted: Int,
    val totalXP: Int,
    val motion: MotionState,
)

enum class RecordMealFailure {
    InvalidRecordIdentity,
    RecordIdentityCollision,
    InactiveStatus,
    AllergyContextMismatch,
    AllergySafetyRequired,
    StaleRevision,
    ConflictingRevision,
    XpOverflow,
}

class RecordMealException(
    val failure: RecordMealFailure,
) : IllegalArgumentException(failure.name)

internal object MealSafetyPolicy {
    fun allowedStatuses(
        childAllergyCodes: Set<Int>,
        itemAllergyCodes: Set<Int>,
    ): Set<EatingStatus> = allowedStatuses(
        hasAllergyOverlap = itemAllergyCodes.any(childAllergyCodes::contains),
    )

    private fun allowedStatuses(hasAllergyOverlap: Boolean): Set<EatingStatus> =
        if (hasAllergyOverlap) {
            setOf(EatingStatus.AllergyAvoided)
        } else {
            EatingStatus.entries.toSet()
        }
}

internal interface MealRecordingStore {
    suspend fun <T> withTransaction(
        block: suspend MealRecordingTransaction.() -> T,
    ): T
}

internal interface MealRecordingTransaction {
    suspend fun findRecord(id: String): MealRecordEntity?
    suspend fun findLogicalRecords(
        date: String,
        normalizedMenuName: String,
    ): List<MealRecordEntity>
    suspend fun upsertRecord(record: MealRecordEntity)
    suspend fun findLogicalMealEvents(
        recordIds: List<String>,
        eventIds: List<String>,
    ): List<ProgressEventEntity>
    suspend fun insertProgressEvent(event: ProgressEventEntity): Boolean
    suspend fun dailyBaseXp(
        date: String,
        dayStartEpochMillis: Long,
        nextDayStartEpochMillis: Long,
    ): Long
    suspend fun dailyTotalXp(
        date: String,
        dayStartEpochMillis: Long,
        nextDayStartEpochMillis: Long,
    ): Long
    suspend fun totalXp(): Long
}

class RecordMealUseCase internal constructor(
    private val store: MealRecordingStore,
    policyBytes: ByteArray,
) {
    private val policy = XpPolicy.decode(policyBytes)

    constructor(
        database: RebuildDatabase,
        assetManager: AssetManager,
    ) : this(
        store = RoomMealRecordingStore(database),
        policyBytes = RebuildContractReader.readAsset(
            assetManager,
            XP_POLICY_FILENAME,
        ),
    )

    suspend fun execute(command: RecordMealCommand): RecordMealResult {
        val normalizedMenuName = validate(command)
        val logicalRecordIds = logicalRecordIds(
            command.date,
            normalizedMenuName,
        )
        val seoulDate = LocalDate.parse(command.date)
        val seoulZone = ZoneId.of("Asia/Seoul")
        val dayStartEpochMillis = seoulDate
            .atStartOfDay(seoulZone)
            .toInstant()
            .toEpochMilli()
        val nextDayStartEpochMillis = seoulDate
            .plusDays(1)
            .atStartOfDay(seoulZone)
            .toInstant()
            .toEpochMilli()
        return store.withTransaction {
            val logicalRecords = findLogicalRecords(
                command.date,
                normalizedMenuName,
            )
            val activeRecords = logicalRecords
                .filter { it.deletedAtEpochMillis == null }
                .sortedWith(
                    compareByDescending<MealRecordEntity> {
                        it.updatedAtEpochMillis
                    }.thenBy { it.id },
                )
            val reusableStableRecord = if (activeRecords.isEmpty()) {
                logicalRecords.firstOrNull { it.id == command.recordID }
            } else {
                null
            }
            val existingRecord = activeRecords.firstOrNull()
                ?: reusableStableRecord
            val occurredAtEpochMillis = command.occurredAt.toEpochMilli()
            if (
                activeRecords.firstOrNull()?.updatedAtEpochMillis
                    ?.let { it > occurredAtEpochMillis } == true
            ) {
                throw RecordMealException(RecordMealFailure.StaleRevision)
            }
            val stableIdRecord = findRecord(command.recordID)
            if (stableIdRecord != null && stableIdRecord !in logicalRecords) {
                throw RecordMealException(
                    RecordMealFailure.RecordIdentityCollision,
                )
            }
            val actualRecordId = existingRecord?.id ?: command.recordID
            val photoSourceRecords = if (activeRecords.isEmpty()) {
                listOfNotNull(existingRecord)
            } else {
                activeRecords
            }
            val mergedPhotoIds = orderedUnique(
                photoSourceRecords.flatMap { record ->
                    decodePhotoIds(record.photoIdsJson)
                } + command.photoIDs,
            )
            if (
                existingRecord?.updatedAtEpochMillis == occurredAtEpochMillis &&
                !isExactReplay(
                    existingRecord,
                    command,
                    normalizedMenuName,
                )
            ) {
                throw RecordMealException(
                    RecordMealFailure.ConflictingRevision,
                )
            }
            val eventRecordIds = orderedUnique(
                logicalRecordIds + logicalRecords.map { it.id },
            )
            val logicalEvents = findLogicalMealEvents(
                eventRecordIds,
                eventRecordIds.map { "meal:$it" },
            )
            val awardAlreadyRecorded =
                logicalRecords.isNotEmpty() || logicalEvents.isNotEmpty()
            val dailyBase = dailyBaseXp(
                command.date,
                dayStartEpochMillis,
                nextDayStartEpochMillis,
            )
            val dailyTotal = dailyTotalXp(
                command.date,
                dayStartEpochMillis,
                nextDayStartEpochMillis,
            )
            val statusXp = policy.statusXp[command.status.wireValue]
                ?: throw RecordMealException(RecordMealFailure.InactiveStatus)
            var xpGranted =
                if (awardAlreadyRecorded) {
                    0
                } else {
                    minOf(
                        statusXp.toLong(),
                        (policy.baseCap.toLong() - dailyBase.coerceAtLeast(0L))
                            .coerceAtLeast(0L),
                        (policy.totalCap.toLong() - dailyTotal.coerceAtLeast(0L))
                            .coerceAtLeast(0L),
                    ).toInt()
                }

            val updatedRecord = MealRecordEntity(
                id = actualRecordId,
                date = command.date,
                menuName = command.menuName,
                normalizedMenuName = normalizedMenuName,
                status = command.status.wireValue,
                difficultyReasonsJson = encodeStringArray(
                    command.difficultyReasons.map(DifficultyReason::wireValue),
                ),
                allergyCodesJson = encodeIntArray(command.allergyCodes),
                photoIdsJson = encodeStringArray(mergedPhotoIds),
                parentShareEnabled = existingRecord?.parentShareEnabled
                    ?: command.parentShareEnabled,
                updatedAtEpochMillis = occurredAtEpochMillis,
                deletedAtEpochMillis = null,
            )
            upsertRecord(updatedRecord)
            activeRecords
                .filterNot { it.id == updatedRecord.id }
                .forEach { duplicate ->
                    upsertRecord(
                        duplicate.copy(
                            deletedAtEpochMillis = occurredAtEpochMillis,
                        ),
                    )
                }
            if (logicalEvents.isEmpty()) {
                val inserted = insertProgressEvent(
                    ProgressEventEntity(
                        id = "meal:$actualRecordId",
                        amount = xpGranted,
                        occurredAtEpochMillis = occurredAtEpochMillis,
                        sourceRecordId = actualRecordId,
                    ),
                )
                if (!inserted) {
                    xpGranted = 0
                }
            }

            val total = checkedXp(totalXp())
            RecordMealResult(
                xpGranted = xpGranted,
                totalXP = total,
                motion = if (command.status == EatingStatus.DifficultToday) {
                    MotionState.Comfort
                } else {
                    MotionState.MealSuccess
                },
            )
        }
    }

    private fun checkedXp(value: Long): Int {
        if (value !in 0L..Int.MAX_VALUE.toLong()) {
            throw RecordMealException(RecordMealFailure.XpOverflow)
        }
        return value.toInt()
    }

    private fun validate(command: RecordMealCommand): String {
        if (command.status.wireValue !in policy.activeStatuses) {
            throw RecordMealException(RecordMealFailure.InactiveStatus)
        }
        val childAllergyCodes = command.childAllergyCodes.toSet()
        val itemAllergyCodes = command.itemAllergyCodes.toSet()
        val expectedAllergyCodes = childAllergyCodes
            .intersect(itemAllergyCodes)
            .sorted()
        if (command.allergyCodes != expectedAllergyCodes) {
            throw RecordMealException(
                RecordMealFailure.AllergyContextMismatch,
            )
        }
        if (
            command.status !in MealSafetyPolicy.allowedStatuses(
                childAllergyCodes = childAllergyCodes,
                itemAllergyCodes = itemAllergyCodes,
            )
        ) {
            throw RecordMealException(RecordMealFailure.AllergySafetyRequired)
        }
        val date = try {
            LocalDate.parse(command.date)
        } catch (_: DateTimeParseException) {
            throw RecordMealException(RecordMealFailure.InvalidRecordIdentity)
        }
        val normalizedName = command.menuName.trim().lowercase(Locale.ROOT)
        val expectedId = "${date}|$normalizedName"
        if (
            date.toString() != command.date ||
            normalizedName.isEmpty() ||
            '|' in normalizedName ||
            command.recordID != expectedId
        ) {
            throw RecordMealException(RecordMealFailure.InvalidRecordIdentity)
        }
        return normalizedName
    }

    private fun logicalRecordIds(
        date: String,
        normalizedMenuName: String,
    ): List<String> {
        val stableId = "$date|$normalizedMenuName"
        return buildList {
            add(stableId)
            EatingStatus.entries.forEach { status ->
                add("$stableId|${status.wireValue}")
            }
        }
    }

    private fun isExactReplay(
        record: MealRecordEntity,
        command: RecordMealCommand,
        normalizedMenuName: String,
    ): Boolean {
        val storedReasons = decodeMealRecordStringArray(
            record.difficultyReasonsJson,
        )
        val storedAllergies = decodeMealRecordIntArray(record.allergyCodesJson)
        val storedPhotos = decodePhotoIds(record.photoIdsJson)
        val replayPhotos = orderedUnique(storedPhotos + command.photoIDs)
        return record.date == command.date &&
            record.menuName == command.menuName &&
            record.normalizedMenuName == normalizedMenuName &&
            record.status == command.status.wireValue &&
            storedReasons == command.difficultyReasons.map(
                DifficultyReason::wireValue,
            ) &&
            storedAllergies == command.allergyCodes &&
            storedPhotos == replayPhotos
    }
}

private class RoomMealRecordingStore(
    private val database: RebuildDatabase,
) : MealRecordingStore {
    override suspend fun <T> withTransaction(
        block: suspend MealRecordingTransaction.() -> T,
    ): T = database.withTransaction {
        val transaction = object : MealRecordingTransaction {
            override suspend fun findRecord(id: String): MealRecordEntity? =
                database.mealRecordDao().find(id)

            override suspend fun findLogicalRecords(
                date: String,
                normalizedMenuName: String,
            ): List<MealRecordEntity> =
                database.mealRecordDao().findLogicalRecords(
                    date,
                    normalizedMenuName,
                )

            override suspend fun upsertRecord(record: MealRecordEntity) {
                database.mealRecordDao().upsert(record)
            }

            override suspend fun findLogicalMealEvents(
                recordIds: List<String>,
                eventIds: List<String>,
            ): List<ProgressEventEntity> =
                database.progressDao().findLogicalMealEvents(
                    recordIds,
                    eventIds,
                )

            override suspend fun insertProgressEvent(event: ProgressEventEntity): Boolean =
                database.progressDao().insert(event) != INSERT_IGNORED

            override suspend fun dailyBaseXp(
                date: String,
                dayStartEpochMillis: Long,
                nextDayStartEpochMillis: Long,
            ): Long =
                database.progressDao().dailyBaseXp(
                    "$date|",
                    dayStartEpochMillis,
                    nextDayStartEpochMillis,
                )

            override suspend fun dailyTotalXp(
                date: String,
                dayStartEpochMillis: Long,
                nextDayStartEpochMillis: Long,
            ): Long =
                database.progressDao().dailyTotalXp(
                    "$date|",
                    dayStartEpochMillis,
                    nextDayStartEpochMillis,
                )

            override suspend fun totalXp(): Long =
                database.progressDao().totalXp()
        }
        transaction.block()
    }

    private companion object {
        const val INSERT_IGNORED = -1L
    }
}

private data class XpPolicy(
    val activeStatuses: Set<String>,
    val statusXp: Map<String, Int>,
    val baseCap: Int,
    val totalCap: Int,
) {
    companion object {
        fun decode(bytes: ByteArray): XpPolicy =
            try {
                val root = RebuildContractReader.parse(bytes)
                val expectedKeys = setOf(
                    "version",
                    "activeStatuses",
                    "legacyReadCompatibleStatuses",
                    "awardIdentityComponents",
                    "awardIdentity",
                    "statusTransitionsGrantAdditionalXP",
                    "statusXP",
                    "caps",
                )
                val version = root.policyInt("version")
                val active = root.policyStringList("activeStatuses")
                val legacy = root.policyStringList("legacyReadCompatibleStatuses")
                val awardComponents = root.policyStringList(
                    "awardIdentityComponents",
                )
                val awardIdentity = root["awardIdentity"] as? String
                    ?: throw ContractLoadException(XP_POLICY_FILENAME)
                val statusTransitionsGrantAdditionalXP =
                    root["statusTransitionsGrantAdditionalXP"] as? Boolean
                        ?: throw ContractLoadException(XP_POLICY_FILENAME)
                val statusObject = root.policyObject("statusXP")
                val statusXp = statusObject.mapValues { (_, value) ->
                    (value as? Long)?.toInt()?.takeIf { it.toLong() == value }
                        ?: throw ContractLoadException(XP_POLICY_FILENAME)
                }
                val caps = root.policyObject("caps")
                val expectedCapKeys = setOf(
                    "base",
                    "challengeBonus",
                    "total",
                )
                val base = caps.policyInt("base")
                val challenge = caps.policyInt("challengeBonus")
                val total = caps.policyInt("total")
                val activeSet = active.toSet()
                val legacySet = legacy.toSet()
                val knownStatuses = EatingStatus.entries
                    .map(EatingStatus::wireValue)
                    .toSet()
                val valid = root.keys == expectedKeys &&
                    version == 1 &&
                    active.isNotEmpty() &&
                    activeSet.size == active.size &&
                    legacySet.size == legacy.size &&
                    activeSet.intersect(legacySet).isEmpty() &&
                    legacySet.isEmpty() &&
                    activeSet == knownStatuses &&
                    awardComponents == listOf("date", "normalizedMenuName") &&
                    awardIdentity == "{date}|{normalizedMenuName}" &&
                    !statusTransitionsGrantAdditionalXP &&
                    statusXp.keys == activeSet &&
                    statusXp.values.all { it >= 0 } &&
                    caps.keys == expectedCapKeys &&
                    base >= 0 &&
                    challenge >= 0 &&
                    total >= 0 &&
                    base <= total &&
                    challenge <= total
                if (!valid) {
                    throw ContractLoadException(XP_POLICY_FILENAME)
                }
                XpPolicy(
                    activeStatuses = activeSet,
                    statusXp = statusXp,
                    baseCap = base,
                    totalCap = total,
                )
            } catch (error: ContractLoadException) {
                throw error
            } catch (_: Exception) {
                throw ContractLoadException(XP_POLICY_FILENAME)
            }
    }
}

private fun Map<String, Any?>.policyInt(name: String): Int {
    val value = this[name] as? Long
        ?: throw ContractLoadException(XP_POLICY_FILENAME)
    return value.toInt().takeIf { it.toLong() == value }
        ?: throw ContractLoadException(XP_POLICY_FILENAME)
}

private fun Map<String, Any?>.policyStringList(name: String): List<String> {
    val values = this[name] as? List<*>
        ?: throw ContractLoadException(XP_POLICY_FILENAME)
    return values.map {
        it as? String ?: throw ContractLoadException(XP_POLICY_FILENAME)
    }
}

private fun Map<String, Any?>.policyObject(name: String): Map<String, Any?> =
    RebuildContractReader.asObject(this[name])
        ?: throw ContractLoadException(XP_POLICY_FILENAME)

private fun encodeIntArray(values: List<Int>): String =
    values.joinToString(prefix = "[", postfix = "]")

private fun decodePhotoIds(raw: String): List<String> =
    decodeMealRecordStringArray(raw)

private fun decodeMealRecordStringArray(raw: String): List<String> =
    try {
        mealRecordJsonFactory.createParser(raw).use { parser ->
            if (parser.nextToken() != JsonToken.START_ARRAY) {
                throw ContractLoadException(MEAL_RECORD_FILENAME)
            }
            val values = mutableListOf<String>()
            while (true) {
                when (parser.nextToken()) {
                    JsonToken.END_ARRAY -> break
                    JsonToken.VALUE_STRING -> values += parser.text
                    else -> throw ContractLoadException(MEAL_RECORD_FILENAME)
                }
            }
            if (parser.nextToken() != null) {
                throw ContractLoadException(MEAL_RECORD_FILENAME)
            }
            values
        }
    } catch (error: ContractLoadException) {
        throw error
    } catch (_: Exception) {
        throw ContractLoadException(MEAL_RECORD_FILENAME)
    }

private fun decodeMealRecordIntArray(raw: String): List<Int> =
    try {
        mealRecordJsonFactory.createParser(raw).use { parser ->
            if (parser.nextToken() != JsonToken.START_ARRAY) {
                throw ContractLoadException(MEAL_RECORD_FILENAME)
            }
            val values = mutableListOf<Int>()
            while (true) {
                when (parser.nextToken()) {
                    JsonToken.END_ARRAY -> break
                    JsonToken.VALUE_NUMBER_INT -> {
                        val value = parser.longValue
                        if (value !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
                            throw ContractLoadException(MEAL_RECORD_FILENAME)
                        }
                        values += value.toInt()
                    }
                    else -> throw ContractLoadException(MEAL_RECORD_FILENAME)
                }
            }
            if (parser.nextToken() != null) {
                throw ContractLoadException(MEAL_RECORD_FILENAME)
            }
            values
        }
    } catch (error: ContractLoadException) {
        throw error
    } catch (_: Exception) {
        throw ContractLoadException(MEAL_RECORD_FILENAME)
    }

private fun orderedUnique(values: List<String>): List<String> {
    val seen = linkedSetOf<String>()
    return values.filter(seen::add)
}

private fun encodeStringArray(values: List<String>): String =
    values.joinToString(prefix = "[", postfix = "]") { value ->
        buildString {
            append('"')
            value.forEach { character ->
                when (character) {
                    '"' -> append("\\\"")
                    '\\' -> append("\\\\")
                    '\b' -> append("\\b")
                    '\u000C' -> append("\\f")
                    '\n' -> append("\\n")
                    '\r' -> append("\\r")
                    '\t' -> append("\\t")
                    else -> {
                        if (character.code < 0x20) {
                            append("\\u")
                            append(character.code.toString(16).padStart(4, '0'))
                        } else {
                            append(character)
                        }
                    }
                }
            }
            append('"')
        }
    }
