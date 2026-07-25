package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.text.BreakIterator
import java.util.Locale
import kotlinx.coroutines.delay

class OnboardingViewModel(
    private val profileStore: OnboardingProfileStore,
    private val schoolSearchClient: SchoolSearchClient,
    private val demoMode: Boolean = false,
    private val demoSchools: List<OnboardingSchool> = emptyList(),
    private val delayMillis: suspend (Long) -> Unit = { delay(it) },
) {
    var step by mutableStateOf(OnboardingStep.Role)
        private set
    var draft by mutableStateOf(OnboardingDraft())
        private set
    var validationMessage by mutableStateOf<String?>(null)
        private set
    var schoolSearchState by mutableStateOf<SchoolSearchState>(SchoolSearchState.Idle)
        private set
    var completedProfile by mutableStateOf<RebuildUserProfile?>(null)
        private set

    private var searchGeneration = 0

    val progressText: String
        get() {
            val steps = if (draft.role == OnboardingRole.Parent) {
                listOf(
                    OnboardingStep.Role,
                    OnboardingStep.Nickname,
                    OnboardingStep.Confirmation,
                )
            } else {
                OnboardingStep.entries
            }
            return "${(steps.indexOf(step).coerceAtLeast(0) + 1)}/${steps.size}"
        }

    fun selectRole(role: OnboardingRole) {
        draft = draft.copy(
            role = role,
            school = if (role == OnboardingRole.Parent) null else draft.school,
            allergyCodes = if (role == OnboardingRole.Parent) {
                emptyList()
            } else {
                draft.allergyCodes
            },
        )
        validationMessage = null
        step = OnboardingStep.Nickname
    }

    fun setNickname(nickname: String) {
        val trimmed = nickname.trim()
        if (graphemeCount(trimmed) !in 1..12) {
            validationMessage = "별명을 1~12자로 입력해 주세요."
            return
        }
        draft = draft.copy(nickname = trimmed)
        validationMessage = null
        step = if (draft.role == OnboardingRole.Parent) {
            OnboardingStep.Confirmation
        } else {
            OnboardingStep.School
        }
    }

    fun selectSchool(school: OnboardingSchool) {
        draft = draft.copy(school = school)
        validationMessage = null
        step = OnboardingStep.Allergies
    }

    fun setAllergies(allergyCodes: List<Int>) {
        draft = draft.copy(allergyCodes = allergyCodes.distinct().sorted())
        validationMessage = null
        step = OnboardingStep.Confirmation
    }

    suspend fun complete(): RebuildUserProfile {
        if (step != OnboardingStep.Confirmation) {
            throw OnboardingException(OnboardingError.WrongStep)
        }
        val role = draft.role
            ?: throw OnboardingException(OnboardingError.MissingRole)
        if (graphemeCount(draft.nickname) !in 1..12) {
            throw OnboardingException(OnboardingError.InvalidNickname)
        }
        if (
            role == OnboardingRole.Child &&
            (
                draft.school == null ||
                    draft.school?.officeCode.isNullOrBlank() ||
                    draft.school?.schoolCode.isNullOrBlank()
                )
        ) {
            throw OnboardingException(OnboardingError.MissingSchoolIdentifiers)
        }
        val profile = RebuildUserProfile(
            id = "current",
            role = role,
            nickname = draft.nickname,
            school = if (role == OnboardingRole.Child) draft.school else null,
            allergyCodes = if (role == OnboardingRole.Child) {
                draft.allergyCodes
            } else {
                emptyList()
            },
            destination = if (role == OnboardingRole.Child) {
                OnboardingDestination.Today
            } else {
                OnboardingDestination.ParentConnection
            },
        )
        profileStore.save(profile)
        completedProfile = profile
        return profile
    }

    fun cancel() {
        searchGeneration += 1
        step = OnboardingStep.Role
        draft = OnboardingDraft()
        validationMessage = null
        schoolSearchState = SchoolSearchState.Idle
        completedProfile = null
    }

    suspend fun searchSchools(query: String) {
        val trimmed = query.trim()
        searchGeneration += 1
        val generation = searchGeneration
        if (trimmed.isEmpty()) {
            schoolSearchState = SchoolSearchState.Idle
            return
        }
        schoolSearchState = SchoolSearchState.Loading
        try {
            delayMillis(SEARCH_DEBOUNCE_MILLIS)
            if (generation != searchGeneration) return
            if (demoMode) {
                val matches = demoSchools.filter {
                    it.name.contains(trimmed, ignoreCase = true)
                }
                schoolSearchState = SchoolSearchState.DemoResults(
                    matches.ifEmpty { demoSchools },
                )
                return
            }
            val schools = schoolSearchClient.search(trimmed)
            if (generation != searchGeneration) return
            schoolSearchState = if (schools.isEmpty()) {
                SchoolSearchState.Empty
            } else {
                SchoolSearchState.Results(schools)
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (_: Throwable) {
            if (generation == searchGeneration) {
                schoolSearchState = SchoolSearchState.Failed(
                    "학교 검색에 실패했어요. 네트워크 상태를 확인해 주세요.",
                )
            }
        }
    }

    private fun graphemeCount(value: String): Int {
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
        iterator.setText(value)
        var count = 0
        var boundary = iterator.first()
        while (boundary != BreakIterator.DONE) {
            val next = iterator.next()
            if (next == BreakIterator.DONE) break
            count += 1
            boundary = next
        }
        return count
    }

    companion object {
        const val SEARCH_DEBOUNCE_MILLIS = 300L
    }
}
