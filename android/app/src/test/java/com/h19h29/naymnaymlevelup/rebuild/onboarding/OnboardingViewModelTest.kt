package com.h19h29.naymnaymlevelup.rebuild.onboarding

import java.io.IOException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingViewModelTest {
    @Test
    fun childFlowTrimsNicknameAndSavesCanonicalProfileOnce() = runTest {
        val store = ProfileStoreSpy()
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())

        assertEquals(OnboardingStep.Role, viewModel.step)
        viewModel.selectRole(OnboardingRole.Child)
        assertEquals(OnboardingStep.Nickname, viewModel.step)
        viewModel.setNickname(" 냠냠이 ")
        assertEquals(OnboardingStep.School, viewModel.step)
        viewModel.selectSchool(SCHOOL)
        assertEquals(OnboardingStep.Allergies, viewModel.step)
        viewModel.setAllergies(listOf(5, 1, 5))
        assertEquals(OnboardingStep.Confirmation, viewModel.step)

        val profile = viewModel.complete()

        assertEquals("냠냠이", profile.nickname)
        assertEquals(SCHOOL, profile.school)
        assertEquals(listOf(1, 5), profile.allergyCodes)
        assertEquals(OnboardingDestination.Today, profile.destination)
        assertEquals(listOf(profile), store.savedProfiles)
    }

    @Test
    fun parentSkipsSchoolAndAllergiesAndRoutesToConnection() = runTest {
        val store = ProfileStoreSpy()
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())

        viewModel.selectRole(OnboardingRole.Parent)
        viewModel.setNickname("보호자")

        assertEquals(OnboardingStep.Confirmation, viewModel.step)
        val profile = viewModel.complete()
        assertNull(profile.school)
        assertEquals(emptyList<Int>(), profile.allergyCodes)
        assertEquals(OnboardingDestination.ParentConnection, profile.destination)
    }

    @Test
    fun nicknameUsesTrimmedGraphemeClusterLimit() {
        val viewModel = OnboardingViewModel(ProfileStoreSpy(), SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Child)

        viewModel.setNickname("   ")
        assertEquals(OnboardingStep.Nickname, viewModel.step)
        assertEquals("별명을 1~12자로 입력해 주세요.", viewModel.validationMessage)

        viewModel.setNickname("🍱".repeat(13))
        assertEquals(OnboardingStep.Nickname, viewModel.step)
        assertEquals("별명을 1~12자로 입력해 주세요.", viewModel.validationMessage)

        viewModel.setNickname("🍱".repeat(12))
        assertEquals(OnboardingStep.School, viewModel.step)
        assertNull(viewModel.validationMessage)
    }

    @Test
    fun childCompletionRequiresBothSchoolIdentifiers() = runTest {
        val store = ProfileStoreSpy()
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Child)
        viewModel.setNickname("냠냠이")
        viewModel.selectSchool(
            OnboardingSchool(
                name = "잘못된 학교",
                officeCode = "",
                schoolCode = "7010111",
            ),
        )
        viewModel.setAllergies(emptyList())

        val error = expectFailure<OnboardingException> {
            viewModel.complete()
        }

        assertEquals(OnboardingError.MissingSchoolIdentifiers, error.reason)
        assertTrue(store.savedProfiles.isEmpty())
    }

    @Test
    fun cancelLeavesNoPartialProfile() {
        val store = ProfileStoreSpy()
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Child)
        viewModel.setNickname("냠냠이")
        viewModel.selectSchool(SCHOOL)

        viewModel.cancel()

        assertEquals(OnboardingStep.Role, viewModel.step)
        assertEquals(OnboardingDraft(), viewModel.draft)
        assertTrue(store.savedProfiles.isEmpty())
    }

    @Test
    fun completionFailureDoesNotPublishCompletedProfile() = runTest {
        val store = ProfileStoreSpy(error = IOException("save failed"))
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Parent)
        viewModel.setNickname("보호자")

        expectFailure<IOException> {
            viewModel.complete()
        }

        assertNull(viewModel.completedProfile)
        assertEquals(OnboardingStep.Confirmation, viewModel.step)
        assertTrue(store.savedProfiles.isEmpty())
    }

    @Test
    fun schoolSearchDebouncesAndDistinguishesResultsEmptyAndFailure() = runTest {
        val delays = mutableListOf<Long>()
        val results = OnboardingViewModel(
            profileStore = ProfileStoreSpy(),
            schoolSearchClient = SchoolSearchClientStub(schools = listOf(SCHOOL)),
            delayMillis = { delays += it },
        )

        results.searchSchools(" 냠냠초 ")

        assertEquals(listOf(300L), delays)
        assertEquals(SchoolSearchState.Results(listOf(SCHOOL)), results.schoolSearchState)

        val empty = OnboardingViewModel(ProfileStoreSpy(), SchoolSearchClientStub())
        empty.searchSchools("없는학교")
        assertEquals(SchoolSearchState.Empty, empty.schoolSearchState)

        val failed = OnboardingViewModel(
            ProfileStoreSpy(),
            SchoolSearchClientStub(error = IOException("offline")),
        )
        failed.searchSchools("냠냠초")
        assertEquals(
            SchoolSearchState.Failed("학교 검색에 실패했어요. 네트워크 상태를 확인해 주세요."),
            failed.schoolSearchState,
        )
    }

    @Test
    fun sampleSchoolsAppearOnlyInExplicitDemoMode() = runTest {
        val live = OnboardingViewModel(
            profileStore = ProfileStoreSpy(),
            schoolSearchClient = SchoolSearchClientStub(error = IOException("offline")),
            demoMode = false,
            demoSchools = listOf(SCHOOL),
        )
        live.searchSchools("냠냠")
        assertEquals(
            SchoolSearchState.Failed("학교 검색에 실패했어요. 네트워크 상태를 확인해 주세요."),
            live.schoolSearchState,
        )

        val demo = OnboardingViewModel(
            profileStore = ProfileStoreSpy(),
            schoolSearchClient = SchoolSearchClientStub(error = IOException("offline")),
            demoMode = true,
            demoSchools = listOf(SCHOOL),
        )
        demo.searchSchools("냠냠")
        assertEquals(SchoolSearchState.DemoResults(listOf(SCHOOL)), demo.schoolSearchState)
    }

    private class ProfileStoreSpy(
        private val error: Throwable? = null,
    ) : OnboardingProfileStore {
        val savedProfiles = mutableListOf<RebuildUserProfile>()

        override suspend fun save(profile: RebuildUserProfile) {
            error?.let { throw it }
            savedProfiles += profile
        }
    }

    private class SchoolSearchClientStub(
        private val schools: List<OnboardingSchool> = emptyList(),
        private val error: Throwable? = null,
    ) : SchoolSearchClient {
        override suspend fun search(query: String): List<OnboardingSchool> {
            error?.let { throw it }
            return schools
        }
    }

    private inline fun <reified T : Throwable> expectFailure(block: () -> Unit): T {
        try {
            block()
        } catch (error: Throwable) {
            if (error !is T) {
                throw error
            }
            return error
        }
        throw AssertionError("Expected ${T::class.java.simpleName}")
    }

    private companion object {
        val SCHOOL = OnboardingSchool(
            name = "서울 냠냠초",
            officeCode = "B10",
            schoolCode = "7010111",
        )
    }
}
