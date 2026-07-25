package com.h19h29.naymnaymlevelup.rebuild.onboarding

import android.content.SharedPreferences
import androidx.room.withTransaction
import com.h19h29.naymnaymlevelup.BuildConfig
import com.h19h29.naymnaymlevelup.rebuild.data.ProfileEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.meal.HttpUrlConnectionNeisTransport
import com.h19h29.naymnaymlevelup.rebuild.meal.MealJsonReader
import com.h19h29.naymnaymlevelup.rebuild.meal.NeisTransport
import java.io.IOException
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class OnboardingRole(val persistedValue: String) {
    Child("child"),
    Parent("parent"),
}

enum class OnboardingStep {
    Role,
    Nickname,
    School,
    Allergies,
    Confirmation,
}

enum class OnboardingDestination {
    Today,
    ParentConnection,
}

data class OnboardingSchool(
    val name: String,
    val officeCode: String,
    val schoolCode: String,
)

data class OnboardingDraft(
    val role: OnboardingRole? = null,
    val nickname: String = "",
    val school: OnboardingSchool? = null,
    val allergyCodes: List<Int> = emptyList(),
)

data class RebuildUserProfile(
    val id: String,
    val role: OnboardingRole,
    val nickname: String,
    val school: OnboardingSchool?,
    val allergyCodes: List<Int>,
    val destination: OnboardingDestination,
)

enum class OnboardingError {
    MissingRole,
    InvalidNickname,
    MissingSchoolIdentifiers,
    WrongStep,
    CompletionInProgress,
    CompletionCancelled,
}

class OnboardingException(
    val reason: OnboardingError,
) : IllegalStateException(reason.name)

sealed interface SchoolSearchState {
    data object Idle : SchoolSearchState
    data object Loading : SchoolSearchState
    data class Results(val schools: List<OnboardingSchool>) : SchoolSearchState
    data class DemoResults(val schools: List<OnboardingSchool>) : SchoolSearchState
    data object Empty : SchoolSearchState
    data class Failed(val message: String) : SchoolSearchState
}

interface OnboardingProfileStore {
    suspend fun save(profile: RebuildUserProfile)

    suspend fun load(): RebuildUserProfile? = null

    suspend fun removeIfCurrent(id: String)
}

fun interface SchoolSearchClient {
    suspend fun search(query: String): List<OnboardingSchool>
}

class RoomOnboardingProfileStore(
    private val database: RebuildDatabase,
    private val schoolNameMetadata: SchoolNameMetadataStore,
    private val profilePublisher: RoomProfilePublisher =
        TransactionalRoomProfilePublisher(database),
) : OnboardingProfileStore {
    private val transactionMutex = Mutex()

    override suspend fun load(): RebuildUserProfile? = transactionMutex.withLock {
        val entity = database.profileDao().load() ?: return@withLock null
        val role = when (entity.role) {
            OnboardingRole.Child.persistedValue -> OnboardingRole.Child
            OnboardingRole.Parent.persistedValue -> OnboardingRole.Parent
            else -> throw IOException("Unsupported persisted role")
        }
        val allergyCodes = parseAllergyCodes(entity.allergyCodesJson)
        val officeCode = entity.officeCode
        val schoolCode = entity.schoolCode
        val school = if (
            role == OnboardingRole.Child &&
            !officeCode.isNullOrBlank() &&
            !schoolCode.isNullOrBlank()
        ) {
            OnboardingSchool(
                name = schoolNameMetadata.name(
                    profileID = entity.id,
                    officeCode = officeCode,
                    schoolCode = schoolCode,
                ) ?: "등록한 학교",
                officeCode = officeCode,
                schoolCode = schoolCode,
            )
        } else {
            null
        }
        RebuildUserProfile(
            id = entity.id,
            role = role,
            nickname = entity.nickname,
            school = school,
            allergyCodes = allergyCodes,
            destination = if (role == OnboardingRole.Child) {
                OnboardingDestination.Today
            } else {
                OnboardingDestination.ParentConnection
            },
        )
    }

    override suspend fun save(profile: RebuildUserProfile) = transactionMutex.withLock {
        val metadataSnapshot = schoolNameMetadata.write(profile)
        try {
            profilePublisher.replace(
                ProfileEntity(
                    id = profile.id,
                    role = profile.role.persistedValue,
                    nickname = profile.nickname,
                    officeCode = profile.school?.officeCode,
                    schoolCode = profile.school?.schoolCode,
                    allergyCodesJson = profile.allergyCodes.joinToString(
                        prefix = "[",
                        postfix = "]",
                    ),
                ),
            )
        } catch (error: Throwable) {
            schoolNameMetadata.restore(metadataSnapshot)
            throw error
        }
    }

    override suspend fun removeIfCurrent(id: String) = transactionMutex.withLock {
        val removedProfile = database.withTransaction {
            val current = database.profileDao().find(id)
            if (current != null) {
                database.profileDao().delete(id)
            }
            current
        }
        schoolNameMetadata.removeIfOwned(
            profileID = id,
            fallbackOfficeCode = removedProfile?.officeCode,
            fallbackSchoolCode = removedProfile?.schoolCode,
        )
    }

    private fun parseAllergyCodes(raw: String): List<Int> {
        val trimmed = raw.trim()
        if (trimmed == "[]") return emptyList()
        if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) {
            throw IOException("Malformed persisted allergy codes")
        }
        return trimmed
            .removePrefix("[")
            .removeSuffix("]")
            .split(",")
            .map { it.trim().toIntOrNull() ?: throw IOException("Malformed allergy code") }
            .distinct()
            .sorted()
    }
}

fun interface RoomProfilePublisher {
    suspend fun replace(profile: ProfileEntity)
}

class TransactionalRoomProfilePublisher(
    private val database: RebuildDatabase,
    private val afterWrite: suspend () -> Unit = {},
) : RoomProfilePublisher {
    override suspend fun replace(profile: ProfileEntity) {
        database.withTransaction {
            database.profileDao().deleteAll()
            database.profileDao().upsert(profile)
            afterWrite()
        }
    }
}

interface SchoolNameMetadataStore {
    data class Entry(
        val key: String,
        val value: String?,
    )

    data class Snapshot(
        val entries: List<Entry>,
    )

    fun name(
        profileID: String,
        officeCode: String,
        schoolCode: String,
    ): String?

    fun write(profile: RebuildUserProfile): Snapshot

    fun restore(snapshot: Snapshot)

    fun removeIfOwned(
        profileID: String,
        fallbackOfficeCode: String? = null,
        fallbackSchoolCode: String? = null,
    )
}

class SharedPreferencesSchoolNameMetadataStore(
    private val preferences: SharedPreferences,
) : SchoolNameMetadataStore {
    @Synchronized
    override fun name(
        profileID: String,
        officeCode: String,
        schoolCode: String,
    ): String? {
        return preferences.getString(profileNameKey(profileID), null)
            ?: preferences.getString(legacyProfileNameKey(profileID), null)
            ?: preferences.getString(
                schoolNameKey(officeCode, schoolCode),
                null,
            )
            ?: preferences.getString(
                legacySchoolNameKey(officeCode, schoolCode),
                null,
            )
    }

    @Synchronized
    override fun write(profile: RebuildUserProfile): SchoolNameMetadataStore.Snapshot {
        val profileNameKey = profileNameKey(profile.id)
        val profileOfficeKey = profileOfficeKey(profile.id)
        val profileSchoolKey = profileSchoolKey(profile.id)
        val legacyProfileNameKey = legacyProfileNameKey(profile.id)
        val previousOfficeCode = preferences.getString(profileOfficeKey, null)
        val previousSchoolCode = preferences.getString(profileSchoolKey, null)
        val affectedKeys = buildSet {
            add(profileNameKey)
            add(profileOfficeKey)
            add(profileSchoolKey)
            add(legacyProfileNameKey)
            if (previousOfficeCode != null && previousSchoolCode != null) {
                add(schoolNameKey(previousOfficeCode, previousSchoolCode))
                add(schoolOwnerKey(previousOfficeCode, previousSchoolCode))
                add(
                    legacySchoolNameKey(
                        previousOfficeCode,
                        previousSchoolCode,
                    ),
                )
            }
            profile.school?.let {
                add(schoolNameKey(it.officeCode, it.schoolCode))
                add(schoolOwnerKey(it.officeCode, it.schoolCode))
                add(legacySchoolNameKey(it.officeCode, it.schoolCode))
            }
        }
        val snapshot = SchoolNameMetadataStore.Snapshot(
            entries = affectedKeys.map {
                SchoolNameMetadataStore.Entry(
                    key = it,
                    value = preferences.getString(it, null),
                )
            },
        )
        val previousProfileName = preferences.getString(profileNameKey, null)
            ?: preferences.getString(legacyProfileNameKey, null)
        val editor = preferences.edit()
        removeOwnedSchoolMetadata(
            editor = editor,
            profileID = profile.id,
            profileName = previousProfileName,
            officeCode = previousOfficeCode,
            schoolCode = previousSchoolCode,
        )
        editor.remove(legacyProfileNameKey)
        if (profile.school == null) {
            editor.remove(profileNameKey)
            editor.remove(profileOfficeKey)
            editor.remove(profileSchoolKey)
        } else {
            editor.putString(profileNameKey, profile.school.name)
            editor.putString(profileOfficeKey, profile.school.officeCode)
            editor.putString(profileSchoolKey, profile.school.schoolCode)
            editor.putString(
                schoolNameKey(
                    profile.school.officeCode,
                    profile.school.schoolCode,
                ),
                profile.school.name,
            )
            editor.putString(
                schoolOwnerKey(
                    profile.school.officeCode,
                    profile.school.schoolCode,
                ),
                profile.id,
            )
        }
        check(editor.commit()) {
            "Could not persist the school display name"
        }
        return snapshot
    }

    @Synchronized
    override fun restore(snapshot: SchoolNameMetadataStore.Snapshot) {
        val editor = preferences.edit()
        snapshot.entries.forEach {
            restore(
                editor = editor,
                key = it.key,
                value = it.value,
            )
        }
        check(editor.commit()) {
            "Could not restore the school display name"
        }
    }

    @Synchronized
    override fun removeIfOwned(
        profileID: String,
        fallbackOfficeCode: String?,
        fallbackSchoolCode: String?,
    ) {
        val profileNameKey = profileNameKey(profileID)
        val profileOfficeKey = profileOfficeKey(profileID)
        val profileSchoolKey = profileSchoolKey(profileID)
        val legacyProfileNameKey = legacyProfileNameKey(profileID)
        val editor = preferences.edit()
        removeOwnedSchoolMetadata(
            editor = editor,
            profileID = profileID,
            profileName = preferences.getString(profileNameKey, null)
                ?: preferences.getString(legacyProfileNameKey, null),
            officeCode = preferences.getString(profileOfficeKey, null)
                ?: fallbackOfficeCode,
            schoolCode = preferences.getString(profileSchoolKey, null)
                ?: fallbackSchoolCode,
        )
        editor.remove(profileNameKey)
        editor.remove(profileOfficeKey)
        editor.remove(profileSchoolKey)
        editor.remove(legacyProfileNameKey)
        check(editor.commit()) {
            "Could not remove owned school display-name metadata"
        }
    }

    @Synchronized
    fun hasProfileMetadata(id: String): Boolean {
        return preferences.contains(profileNameKey(id)) ||
            preferences.contains(profileOfficeKey(id)) ||
            preferences.contains(profileSchoolKey(id)) ||
            preferences.contains(legacyProfileNameKey(id))
    }

    @Synchronized
    fun hasSchoolMetadata(
        officeCode: String,
        schoolCode: String,
    ): Boolean {
        return preferences.contains(schoolNameKey(officeCode, schoolCode)) ||
            preferences.contains(schoolOwnerKey(officeCode, schoolCode)) ||
            preferences.contains(legacySchoolNameKey(officeCode, schoolCode))
    }

    @Synchronized
    fun schoolOwner(
        officeCode: String,
        schoolCode: String,
    ): String? {
        return preferences.getString(
            schoolOwnerKey(officeCode, schoolCode),
            null,
        )
    }

    private fun removeOwnedSchoolMetadata(
        editor: SharedPreferences.Editor,
        profileID: String,
        profileName: String?,
        officeCode: String?,
        schoolCode: String?,
    ) {
        if (officeCode == null || schoolCode == null) return
        val nameKey = schoolNameKey(officeCode, schoolCode)
        val ownerKey = schoolOwnerKey(officeCode, schoolCode)
        val legacyNameKey = legacySchoolNameKey(officeCode, schoolCode)
        val owner = preferences.getString(ownerKey, null)
        val hasLegacyOwnership = owner == null &&
            profileName != null &&
            (
                preferences.getString(nameKey, null) == profileName ||
                    preferences.getString(legacyNameKey, null) == profileName
                )
        if (owner == profileID || hasLegacyOwnership) {
            editor.remove(nameKey)
            editor.remove(ownerKey)
            editor.remove(legacyNameKey)
        }
    }

    private fun restore(
        editor: SharedPreferences.Editor,
        key: String,
        value: String?,
    ) {
        if (value == null) {
            editor.remove(key)
        } else {
            editor.putString(key, value)
        }
    }

    private fun profileNameKey(id: String) =
        "rebuild.school-name.profile.$id.name"

    private fun profileOfficeKey(id: String) =
        "rebuild.school-name.profile.$id.office"

    private fun profileSchoolKey(id: String) =
        "rebuild.school-name.profile.$id.school"

    private fun legacyProfileNameKey(id: String) =
        "rebuild.school-name.profile.$id"

    private fun schoolNameKey(
        officeCode: String,
        schoolCode: String,
    ) = "rebuild.school-name.codes.$officeCode.$schoolCode.name"

    private fun schoolOwnerKey(
        officeCode: String,
        schoolCode: String,
    ) = "rebuild.school-name.codes.$officeCode.$schoolCode.owner"

    private fun legacySchoolNameKey(
        officeCode: String,
        schoolCode: String,
    ) = "rebuild.school-name.codes.$officeCode.$schoolCode"
}

sealed class SchoolSearchException(message: String) : IOException(message) {
    data class ResultError(
        val code: String,
        val resultMessage: String?,
    ) : SchoolSearchException(
        listOfNotNull(code, resultMessage).joinToString(": "),
    )

    class MalformedResponse : SchoolSearchException("Malformed school response")
}

class NeisSchoolSearchClient(
    private val apiKey: String = BuildConfig.NEIS_API_KEY,
    private val transport: NeisTransport = HttpUrlConnectionNeisTransport(),
) : SchoolSearchClient {
    override suspend fun search(query: String): List<OnboardingSchool> {
        if (apiKey.isBlank() || apiKey == "YOUR_KEY_HERE") {
            throw IOException("NEIS API key is unavailable")
        }
        val url = URL(
            "$BASE_URL?KEY=${encode(apiKey)}&Type=json&pIndex=1&pSize=100" +
                "&SCHUL_NM=${encode(query)}",
        )
        val root = try {
            MealJsonReader.parseObject(transport.get(url))
        } catch (_: IllegalArgumentException) {
            throw SchoolSearchException.MalformedResponse()
        }
        val resultValue = root["RESULT"]
        if (resultValue != null) {
            val result = resultValue as? Map<*, *>
                ?: throw SchoolSearchException.MalformedResponse()
            val code = result["CODE"] as? String
                ?: throw SchoolSearchException.MalformedResponse()
            val messageValue = result["MESSAGE"]
            val message = when (messageValue) {
                null -> null
                is String -> messageValue
                else -> throw SchoolSearchException.MalformedResponse()
            }
            if (code == "INFO-200") {
                return emptyList()
            }
            throw SchoolSearchException.ResultError(code, message)
        }
        val sections = root["schoolInfo"] as? List<*>
            ?: throw SchoolSearchException.MalformedResponse()
        if (sections.isEmpty()) {
            throw SchoolSearchException.MalformedResponse()
        }
        var foundRows = false
        val schools = sections.flatMap { sectionValue ->
            val section = sectionValue as? Map<*, *>
                ?: throw SchoolSearchException.MalformedResponse()
            val rows = if (section.containsKey("row")) {
                foundRows = true
                section["row"] as? List<*>
                    ?: throw SchoolSearchException.MalformedResponse()
            } else {
                emptyList<Any?>()
            }
            rows.map { rowValue ->
                val row = rowValue as? Map<*, *>
                    ?: throw SchoolSearchException.MalformedResponse()
                val name = row["SCHUL_NM"] as? String
                    ?: throw SchoolSearchException.MalformedResponse()
                val officeCode = row["ATPT_OFCDC_SC_CODE"] as? String
                    ?: throw SchoolSearchException.MalformedResponse()
                val schoolCode = row["SD_SCHUL_CODE"] as? String
                    ?: throw SchoolSearchException.MalformedResponse()
                if (name.isBlank() || officeCode.isBlank() || schoolCode.isBlank()) {
                    throw SchoolSearchException.MalformedResponse()
                }
                OnboardingSchool(name, officeCode, schoolCode)
            }
        }
        if (!foundRows || schools.isEmpty()) {
            throw SchoolSearchException.MalformedResponse()
        }
        return schools
    }

    private companion object {
        const val BASE_URL = "https://open.neis.go.kr/hub/schoolInfo"

        fun encode(value: String): String =
            URLEncoder.encode(value, StandardCharsets.UTF_8.name())
    }
}
