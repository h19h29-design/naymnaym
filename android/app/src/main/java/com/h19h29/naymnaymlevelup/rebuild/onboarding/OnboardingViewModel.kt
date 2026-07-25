package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.UUID
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
    var isCompleting by mutableStateOf(false)
        private set

    private var searchGeneration = 0
    private var completionGeneration = 0

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
        if (isCompleting) {
            throw OnboardingException(OnboardingError.CompletionInProgress)
        }
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
            id = UUID.randomUUID().toString(),
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
        val generation = completionGeneration
        isCompleting = true
        try {
            profileStore.save(profile)
            if (generation != completionGeneration) {
                profileStore.removeIfCurrent(profile.id)
                throw OnboardingException(OnboardingError.CompletionCancelled)
            }
            completedProfile = profile
            return profile
        } finally {
            if (generation == completionGeneration) {
                isCompleting = false
            }
        }
    }

    fun cancel() {
        searchGeneration += 1
        completionGeneration += 1
        isCompleting = false
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

    private fun graphemeCount(value: String): Int =
        ExtendedGraphemeCounter.count(value)

    companion object {
        const val SEARCH_DEBOUNCE_MILLIS = 300L
    }
}

internal object ExtendedGraphemeCounter {
    private const val ZERO_WIDTH_JOINER = 0x200D
    private const val CARRIAGE_RETURN = 0x000D
    private const val LINE_FEED = 0x000A

    fun count(value: String): Int {
        val codePoints = mutableListOf<Int>()
        var offset = 0
        while (offset < value.length) {
            val codePoint = Character.codePointAt(value, offset)
            codePoints += codePoint
            offset += Character.charCount(codePoint)
        }
        var index = 0
        var count = 0
        var regionalIndicators = 0
        while (index < codePoints.size) {
            val current = codePoints[index]
            if (
                current == LINE_FEED &&
                index > 0 &&
                codePoints[index - 1] == CARRIAGE_RETURN
            ) {
                index += 1
                continue
            }
            if (isRegionalIndicator(current)) {
                if (regionalIndicators % 2 == 0) count += 1
                regionalIndicators += 1
                index += 1
                continue
            }
            regionalIndicators = 0
            count += 1
            index += 1
            while (index < codePoints.size && isExtender(codePoints[index])) {
                index += 1
            }
            while (
                index < codePoints.size &&
                codePoints[index] == ZERO_WIDTH_JOINER
            ) {
                index += 1
                if (index >= codePoints.size) break
                index += 1
                while (index < codePoints.size && isExtender(codePoints[index])) {
                    index += 1
                }
            }
        }
        return count
    }

    private fun isExtender(codePoint: Int): Boolean {
        val type = Character.getType(codePoint)
        return type == Character.NON_SPACING_MARK.toInt() ||
            type == Character.COMBINING_SPACING_MARK.toInt() ||
            type == Character.ENCLOSING_MARK.toInt() ||
            codePoint in 0xFE00..0xFE0F ||
            codePoint in 0xE0100..0xE01EF ||
            codePoint in 0x1F3FB..0x1F3FF ||
            codePoint in 0xE0020..0xE007F
    }

    private fun isRegionalIndicator(codePoint: Int): Boolean =
        codePoint in 0x1F1E6..0x1F1FF
}

sealed interface OnboardingRootState {
    data object Loading : OnboardingRootState
    data object Onboarding : OnboardingRootState
    data class Destination(val profile: RebuildUserProfile) : OnboardingRootState
    data object Failed : OnboardingRootState
}

class OnboardingBootstrapper(
    private val profileStore: OnboardingProfileStore,
) {
    var state by mutableStateOf<OnboardingRootState>(OnboardingRootState.Loading)
        private set
    private var didLoad = false

    suspend fun load() {
        if (didLoad) return
        didLoad = true
        state = try {
            profileStore.load()?.let(OnboardingRootState::Destination)
                ?: OnboardingRootState.Onboarding
        } catch (_: Throwable) {
            OnboardingRootState.Failed
        }
    }

    fun accept(profile: RebuildUserProfile) {
        state = OnboardingRootState.Destination(profile)
    }
}
