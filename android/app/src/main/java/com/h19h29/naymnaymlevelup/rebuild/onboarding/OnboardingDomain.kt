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
            database.withTransaction {
                database.profileDao().deleteAll()
                database.profileDao().upsert(
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
            }
        } catch (error: Throwable) {
            schoolNameMetadata.restore(metadataSnapshot)
            throw error
        }
    }

    override suspend fun removeIfCurrent(id: String) = transactionMutex.withLock {
        val removed = database.withTransaction {
            val current = database.profileDao().find(id)
            if (current != null) {
                database.profileDao().delete(id)
                true
            } else {
                false
            }
        }
        if (removed) {
            schoolNameMetadata.removeProfile(id)
        }
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

interface SchoolNameMetadataStore {
    data class Snapshot(
        val profileKey: String,
        val previousProfileName: String?,
        val schoolKey: String?,
        val previousSchoolName: String?,
    )

    fun name(
        profileID: String,
        officeCode: String,
        schoolCode: String,
    ): String?

    fun write(profile: RebuildUserProfile): Snapshot

    fun restore(snapshot: Snapshot)

    fun removeProfile(id: String)
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
        return preferences.getString(profileKey(profileID), null)
            ?: preferences.getString(schoolKey(officeCode, schoolCode), null)
    }

    @Synchronized
    override fun write(profile: RebuildUserProfile): SchoolNameMetadataStore.Snapshot {
        val profileKey = profileKey(profile.id)
        val schoolKey = profile.school?.let {
            schoolKey(it.officeCode, it.schoolCode)
        }
        val snapshot = SchoolNameMetadataStore.Snapshot(
            profileKey = profileKey,
            previousProfileName = preferences.getString(profileKey, null),
            schoolKey = schoolKey,
            previousSchoolName = schoolKey?.let {
                preferences.getString(it, null)
            },
        )
        val editor = preferences.edit()
        if (profile.school == null) {
            editor.remove(profileKey)
        } else {
            editor.putString(profileKey, profile.school.name)
            editor.putString(requireNotNull(schoolKey), profile.school.name)
        }
        check(editor.commit()) {
            "Could not persist the school display name"
        }
        return snapshot
    }

    @Synchronized
    override fun restore(snapshot: SchoolNameMetadataStore.Snapshot) {
        val editor = preferences.edit()
        restore(
            editor = editor,
            key = snapshot.profileKey,
            value = snapshot.previousProfileName,
        )
        snapshot.schoolKey?.let {
            restore(
                editor = editor,
                key = it,
                value = snapshot.previousSchoolName,
            )
        }
        check(editor.commit()) {
            "Could not restore the school display name"
        }
    }

    @Synchronized
    override fun removeProfile(id: String) {
        check(preferences.edit().remove(profileKey(id)).commit()) {
            "Could not remove the obsolete school display name"
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

    private fun profileKey(id: String) = "rebuild.school-name.profile.$id"

    private fun schoolKey(
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
