package com.h19h29.naymnaymlevelup.rebuild.migration

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.MessageDigest

data class LegacySnapshot(
    val profileJson: String? = null,
    val progressJson: String? = null,
    val mealsJson: String? = null,
    val mealPhotosJson: String? = null,
    val challengesJson: String? = null,
    val parentJson: String? = null,
    val childLinkJson: String? = null,
    val sourceKeys: Set<String> = presentPayloadNames(
        profileJson = profileJson,
        progressJson = progressJson,
        mealsJson = mealsJson,
        mealPhotosJson = mealPhotosJson,
        challengesJson = challengesJson,
        parentJson = parentJson,
        childLinkJson = childLinkJson,
    ),
) {
    val hasLegacyData: Boolean
        get() = sourceKeys.isNotEmpty()
}

interface LegacyMigrationSource {
    fun readSnapshot(): LegacySnapshot

    fun sourceDigest(snapshot: LegacySnapshot): String =
        LegacySourceDigest.digest(snapshot)
}

/**
 * Read-only projection of the shipped Android test-7 SharedPreferences schema.
 *
 * The legacy app stored school and child-link fields as scalar preferences, and
 * stored meals/challenges together in `mealSnapshotLedger`. This reader turns
 * those exact records into the seven logical payloads used by migration. It
 * deliberately has no editor and never repairs malformed source data in place.
 */
class LegacyPreferencesReader(
    context: Context,
) : LegacyMigrationSource {
    private val preferences: SharedPreferences = context.applicationContext
        .getSharedPreferences(PREFERENCES_FILE_NAME, Context.MODE_PRIVATE)

    override fun readSnapshot(): LegacySnapshot {
        val values = preferences.all
        val sourceKeys = linkedSetOf<String>()

        val profileJson = readProfile(values, sourceKeys)
        val progressJson = readProgress(values, sourceKeys)
        val ledger = readLedger(values, sourceKeys)
        val parentJson = readParentProfile(values, sourceKeys)
        val childLinkJson = readChildLink(values, sourceKeys)

        return LegacySnapshot(
            profileJson = profileJson,
            progressJson = progressJson,
            mealsJson = ledger?.first,
            mealPhotosJson = null,
            challengesJson = ledger?.second,
            parentJson = parentJson,
            childLinkJson = childLinkJson,
            sourceKeys = sourceKeys,
        )
    }

    private fun readProfile(
        values: Map<String, *>,
        sourceKeys: MutableSet<String>,
    ): String? {
        val presentKeys = SCHOOL_KEYS.filter(values::containsKey)
        if (presentKeys.isEmpty()) {
            return null
        }
        sourceKeys += presentKeys
        val schoolName = requiredNonBlankString(values, SCHOOL_NAME)
        val officeCode = optionalString(values, OFFICE_CODE)
        val schoolCode = optionalString(values, SCHOOL_CODE)
        val region = optionalString(values, REGION)
        val address = optionalString(values, ADDRESS)
        val schoolType = optionalString(values, SCHOOL_TYPE)
        return JSONObject()
            .put("id", "legacy-android-profile")
            .put("role", "child")
            .put("nickname", DEFAULT_LEGACY_NICKNAME)
            .put("schoolName", schoolName)
            .put("officeCode", officeCode)
            .put("schoolCode", schoolCode)
            .put("region", region)
            .put("address", address)
            .put("schoolType", schoolType)
            .put("allergyCodes", JSONArray())
            .toString()
    }

    private fun readProgress(
        values: Map<String, *>,
        sourceKeys: MutableSet<String>,
    ): String? {
        val keys = values.keys.filter { it.startsWith(DAILY_XP_PREFIX) }.sorted()
        if (keys.isEmpty()) {
            return null
        }
        var total = 0L
        keys.forEach { key ->
            val value = values[key]
            if (value !is Int || value < 0) {
                throw LegacyMigrationException.InvalidSourcePreference(
                    key = key,
                    reason = "expected a non-negative Int",
                )
            }
            total += value
            if (total > Int.MAX_VALUE) {
                throw LegacyMigrationException.InvalidSourcePreference(
                    key = key,
                    reason = "XP total overflow",
                )
            }
        }
        sourceKeys += keys
        return JSONObject().put("totalXp", total.toInt()).toString()
    }

    private fun readLedger(
        values: Map<String, *>,
        sourceKeys: MutableSet<String>,
    ): Pair<String, String>? {
        if (!values.containsKey(MEAL_SNAPSHOT_LEDGER)) {
            return null
        }
        sourceKeys += MEAL_SNAPSHOT_LEDGER
        val raw = requiredString(values, MEAL_SNAPSHOT_LEDGER)
        val root = parseObject(raw, MEAL_SNAPSHOT_LEDGER)
        val meals = strictArray(root, "latestMeals", MEAL_SNAPSHOT_LEDGER)
        val challenges = strictArray(root, "actions", MEAL_SNAPSHOT_LEDGER)
        return meals.toString() to challenges.toString()
    }

    private fun readParentProfile(
        values: Map<String, *>,
        sourceKeys: MutableSet<String>,
    ): String? {
        if (!values.containsKey(PARENT_CHILDREN)) {
            return null
        }
        sourceKeys += PARENT_CHILDREN
        return parseArray(
            requiredString(values, PARENT_CHILDREN),
            PARENT_CHILDREN,
        ).toString()
    }

    private fun readChildLink(
        values: Map<String, *>,
        sourceKeys: MutableSet<String>,
    ): String? {
        val presentKeys = CHILD_LINK_KEYS.filter(values::containsKey)
        if (presentKeys.isEmpty()) {
            return null
        }
        sourceKeys += presentKeys
        val objectValue = JSONObject()
        presentKeys.forEach { key ->
            objectValue.put(key, optionalString(values, key))
        }
        return objectValue.toString()
    }

    private fun strictArray(
        root: JSONObject,
        key: String,
        sourceKey: String,
    ): JSONArray {
        if (!root.has(key)) {
            return JSONArray()
        }
        val value = root.opt(key)
        if (value !is JSONArray) {
            throw LegacyMigrationException.InvalidSourcePreference(
                key = sourceKey,
                reason = "$key must be a JSON array",
            )
        }
        return value
    }

    private fun requiredNonBlankString(
        values: Map<String, *>,
        key: String,
    ): String {
        val value = requiredString(values, key)
        if (value.isBlank()) {
            throw LegacyMigrationException.InvalidSourcePreference(
                key = key,
                reason = "must not be blank",
            )
        }
        return value
    }

    private fun requiredString(values: Map<String, *>, key: String): String {
        val value = values[key]
        if (value !is String) {
            throw LegacyMigrationException.InvalidSourcePreference(
                key = key,
                reason = "expected a String",
            )
        }
        return value
    }

    private fun optionalString(values: Map<String, *>, key: String): String? {
        if (!values.containsKey(key)) {
            return null
        }
        return requiredString(values, key)
    }

    private fun parseObject(raw: String, key: String): JSONObject =
        try {
            JSONObject(raw)
        } catch (error: JSONException) {
            throw LegacyMigrationException.InvalidSourcePreference(
                key = key,
                reason = "invalid JSON object",
                cause = error,
            )
        }

    private fun parseArray(raw: String, key: String): JSONArray =
        try {
            JSONArray(raw)
        } catch (error: JSONException) {
            throw LegacyMigrationException.InvalidSourcePreference(
                key = key,
                reason = "invalid JSON array",
                cause = error,
            )
        }

    companion object {
        const val PREFERENCES_FILE_NAME = "naymnaym-android"

        const val SCHOOL_NAME = "schoolName"
        const val OFFICE_CODE = "officeCode"
        const val SCHOOL_CODE = "schoolCode"
        const val REGION = "region"
        const val ADDRESS = "address"
        const val SCHOOL_TYPE = "schoolType"
        const val MEAL_SNAPSHOT_LEDGER = "mealSnapshotLedger"
        const val PARENT_CHILDREN = "parentChildren"
        const val CHILD_LINK_ID = "childLinkId"
        const val INVITE_CODE = "inviteCode"
        const val INVITE_SECRET = "inviteSecret"
        const val REGISTERED_AT = "registeredAt"
        const val PARENT_CONNECTED_AT = "parentConnectedAt"
        const val DAILY_XP_PREFIX = "dailyBaseXp-"

        private const val DEFAULT_LEGACY_NICKNAME = "냠냠 도전자"

        private val SCHOOL_KEYS = listOf(
            SCHOOL_NAME,
            OFFICE_CODE,
            SCHOOL_CODE,
            REGION,
            ADDRESS,
            SCHOOL_TYPE,
        )
        private val CHILD_LINK_KEYS = listOf(
            CHILD_LINK_ID,
            INVITE_CODE,
            INVITE_SECRET,
            REGISTERED_AT,
            PARENT_CONNECTED_AT,
        )
    }
}

object LegacySourceDigest {
    fun digest(snapshot: LegacySnapshot): String {
        val digest = MessageDigest.getInstance("SHA-256")
        snapshot.sourceKeys.sorted().forEach { appendFramed(digest, "key", it) }
        listOf(
            "profile" to snapshot.profileJson,
            "progress" to snapshot.progressJson,
            "meals" to snapshot.mealsJson,
            "mealPhotos" to snapshot.mealPhotosJson,
            "challenges" to snapshot.challengesJson,
            "parent" to snapshot.parentJson,
            "childLink" to snapshot.childLinkJson,
        ).forEach { (name, payload) ->
            appendFramed(digest, name, payload ?: "<missing>")
        }
        return "sha256:" + digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun appendFramed(
        digest: MessageDigest,
        name: String,
        value: String,
    ) {
        val bytes = value.toByteArray(StandardCharsets.UTF_8)
        digest.update(name.toByteArray(StandardCharsets.UTF_8))
        digest.update(0)
        digest.update(bytes.size.toString().toByteArray(StandardCharsets.US_ASCII))
        digest.update(0)
        digest.update(bytes)
        digest.update(0)
    }
}

private fun presentPayloadNames(
    profileJson: String?,
    progressJson: String?,
    mealsJson: String?,
    mealPhotosJson: String?,
    challengesJson: String?,
    parentJson: String?,
    childLinkJson: String?,
): Set<String> = buildSet {
    if (profileJson != null) add("profile")
    if (progressJson != null) add("progress")
    if (mealsJson != null) add("meals")
    if (mealPhotosJson != null) add("mealPhotos")
    if (challengesJson != null) add("challenges")
    if (parentJson != null) add("parent")
    if (childLinkJson != null) add("childLink")
}
