package com.h19h29.naymnaymlevelup.rebuild.onboarding

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

fun interface OnboardingProfileStore {
    suspend fun save(profile: RebuildUserProfile)
}

fun interface SchoolSearchClient {
    suspend fun search(query: String): List<OnboardingSchool>
}

class RoomOnboardingProfileStore(
    private val database: RebuildDatabase,
) : OnboardingProfileStore {
    override suspend fun save(profile: RebuildUserProfile) {
        database.withTransaction {
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
    }
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
        val root = MealJsonReader.parseObject(transport.get(url))
        val sections = root["schoolInfo"] as? List<*> ?: return emptyList()
        return sections.flatMap { sectionValue ->
            val section = sectionValue as? Map<*, *> ?: return@flatMap emptyList()
            val rows = section["row"] as? List<*> ?: return@flatMap emptyList()
            rows.mapNotNull { rowValue ->
                val row = rowValue as? Map<*, *> ?: return@mapNotNull null
                val name = row["SCHUL_NM"] as? String ?: return@mapNotNull null
                val officeCode =
                    row["ATPT_OFCDC_SC_CODE"] as? String ?: return@mapNotNull null
                val schoolCode =
                    row["SD_SCHUL_CODE"] as? String ?: return@mapNotNull null
                OnboardingSchool(name, officeCode, schoolCode)
            }
        }
    }

    private companion object {
        const val BASE_URL = "https://open.neis.go.kr/hub/schoolInfo"

        fun encode(value: String): String =
            URLEncoder.encode(value, StandardCharsets.UTF_8.name())
    }
}
