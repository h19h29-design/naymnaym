package com.h19h29.naymnaymlevelup.rebuild.onboarding

import java.io.IOException
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
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
    fun nicknameCountsExtendedGraphemeClustersOnBothSidesOfLimit() {
        val viewModel = OnboardingViewModel(ProfileStoreSpy(), SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Child)

        viewModel.setNickname("👨‍👩‍👧‍👦".repeat(12))
        assertEquals(OnboardingStep.School, viewModel.step)

        viewModel.cancel()
        viewModel.selectRole(OnboardingRole.Child)
        viewModel.setNickname("👨‍👩‍👧‍👦".repeat(13))
        assertEquals(OnboardingStep.Nickname, viewModel.step)

        viewModel.setNickname("🇰🇷e\u0301")
        assertEquals(OnboardingStep.School, viewModel.step)
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
    fun duplicateCompletionTapStartsOnlyOneSave() = runTest {
        val store = ControlledProfileStore()
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Parent)
        viewModel.setNickname("보호자")

        val first = async { viewModel.complete() }
        store.saveStarted.await()
        assertTrue(viewModel.isCompleting)

        val error = expectFailure<OnboardingException> {
            viewModel.complete()
        }
        assertEquals(OnboardingError.CompletionInProgress, error.reason)
        assertEquals(1, store.saveCount)

        store.allowSave.complete(Unit)
        first.await()
        assertTrue(!viewModel.isCompleting)
    }

    @Test
    fun cancelDuringSaveNeverPublishesCompletion() = runTest {
        val store = ControlledProfileStore()
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Parent)
        viewModel.setNickname("보호자")

        val completion = async { runCatching { viewModel.complete() } }
        store.saveStarted.await()
        viewModel.cancel()
        store.allowSave.complete(Unit)

        val error = completion.await().exceptionOrNull() as OnboardingException
        assertEquals(OnboardingError.CompletionCancelled, error.reason)
        assertNull(viewModel.completedProfile)
        assertEquals(OnboardingStep.Role, viewModel.step)
        assertNull(store.load())

        val recreatedRoot = OnboardingBootstrapper(store)
        recreatedRoot.load()
        assertEquals(OnboardingRootState.Onboarding, recreatedRoot.state)
    }

    @Test
    fun cancelledSaveCleanupNeverDeletesLaterProfile() = runTest {
        val store = RacingProfileStore()
        val viewModel = OnboardingViewModel(store, SchoolSearchClientStub())
        viewModel.selectRole(OnboardingRole.Parent)
        viewModel.setNickname("취소할 보호자")

        val cancelled = async { runCatching { viewModel.complete() } }
        store.firstSaveStarted.await()
        viewModel.cancel()
        store.allowFirstSave.complete(Unit)
        store.removalStarted.await()

        viewModel.selectRole(OnboardingRole.Parent)
        viewModel.setNickname("최종 보호자")
        val latest = viewModel.complete()
        store.allowRemoval.complete(Unit)

        val error = cancelled.await().exceptionOrNull() as OnboardingException
        assertEquals(OnboardingError.CompletionCancelled, error.reason)
        assertEquals(latest, store.load())
    }

    @Test
    fun bootstrapLoadsPersistedProfilesAcrossRootRecreation() = runTest {
        val child = profile(OnboardingRole.Child)
        val store = ProfileStoreSpy(loadedProfile = child)

        val firstRoot = OnboardingBootstrapper(store)
        firstRoot.load()
        assertEquals(OnboardingRootState.Destination(child), firstRoot.state)

        val recreatedRoot = OnboardingBootstrapper(store)
        recreatedRoot.load()
        assertEquals(OnboardingRootState.Destination(child), recreatedRoot.state)

        val parent = profile(OnboardingRole.Parent)
        val parentRoot = OnboardingBootstrapper(
            ProfileStoreSpy(loadedProfile = parent),
        )
        parentRoot.load()
        assertEquals(OnboardingRootState.Destination(parent), parentRoot.state)
        assertEquals(OnboardingDestination.ParentConnection, parent.destination)
    }

    @Test
    fun bootstrapShowsOnboardingOnlyWithoutPersistedProfile() = runTest {
        val root = OnboardingBootstrapper(ProfileStoreSpy())

        root.load()

        assertEquals(OnboardingRootState.Onboarding, root.state)
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

    @Test
    fun schoolSearchTreatsInfo200AsEmptyAndRejectsErrorsOrMalformedRows() = runTest {
        val noData = NeisSchoolSearchClient(
            apiKey = "test-key",
            transport = { """{"RESULT":{"CODE":"INFO-200","MESSAGE":"none"}}""".encodeToByteArray() },
        )
        assertEquals(emptyList<OnboardingSchool>(), noData.search("없는학교"))

        val serverError = NeisSchoolSearchClient(
            apiKey = "test-key",
            transport = {
                """{"RESULT":{"CODE":"ERROR-300","MESSAGE":"auth failed"}}"""
                    .encodeToByteArray()
            },
        )
        val resultError = expectFailure<SchoolSearchException.ResultError> {
            serverError.search("냠냠초")
        }
        assertEquals("ERROR-300", resultError.code)
        assertEquals("auth failed", resultError.resultMessage)

        val malformed = NeisSchoolSearchClient(
            apiKey = "test-key",
            transport = {
                """{"schoolInfo":[{"row":[{"SCHUL_NM":"코드 없는 학교"}]}]}"""
                    .encodeToByteArray()
            },
        )
        expectFailure<SchoolSearchException.MalformedResponse> {
            malformed.search("코드 없는 학교")
        }

        listOf(
            """{"schoolInfo":[]}""",
            """{"schoolInfo":[{"head":[{"list_total_count":1}]}]}""",
            """{"schoolInfo":[{"head":[{"list_total_count":1}]},{"row":[]}]}""",
            """{"schoolInfo":[{"head":[{"list_total_count":1}]},{"other":[]}]}""",
        ).forEach { payload ->
            val missingRows = NeisSchoolSearchClient(
                apiKey = "test-key",
                transport = { payload.encodeToByteArray() },
            )
            expectFailure<SchoolSearchException.MalformedResponse> {
                missingRows.search("행 없는 학교")
            }
        }
    }

    @Test
    fun allergyListIsConstrainedSoNextActionRemainsOutsideScrollableItems() {
        val source = File(
            "src/main/java/com/h19h29/naymnaymlevelup/rebuild/onboarding/" +
                "AllergySelectionScreen.kt",
        ).readText()

        assertTrue(source.contains("LazyColumn(modifier = Modifier.weight(1f))"))
        assertTrue(
            source.indexOf("LazyColumn") <
                source.indexOf("OnboardingAction(\"다음\")"),
        )
    }

    private class ProfileStoreSpy(
        private val error: Throwable? = null,
        private val loadedProfile: RebuildUserProfile? = null,
    ) : OnboardingProfileStore {
        val savedProfiles = mutableListOf<RebuildUserProfile>()

        override suspend fun load(): RebuildUserProfile? = loadedProfile

        override suspend fun save(profile: RebuildUserProfile) {
            error?.let { throw it }
            savedProfiles += profile
        }

        override suspend fun removeIfCurrent(id: String) {
            if (savedProfiles.lastOrNull()?.id == id) {
                savedProfiles.removeLast()
            }
        }
    }

    private class ControlledProfileStore : OnboardingProfileStore {
        var saveCount = 0
        var persistedProfile: RebuildUserProfile? = null
        val saveStarted = CompletableDeferred<Unit>()
        val allowSave = CompletableDeferred<Unit>()

        override suspend fun load(): RebuildUserProfile? = persistedProfile

        override suspend fun save(profile: RebuildUserProfile) {
            saveCount += 1
            saveStarted.complete(Unit)
            allowSave.await()
            persistedProfile = profile
        }

        override suspend fun removeIfCurrent(id: String) {
            if (persistedProfile?.id == id) {
                persistedProfile = null
            }
        }
    }

    private class RacingProfileStore : OnboardingProfileStore {
        private var saveCount = 0
        private var persistedProfile: RebuildUserProfile? = null
        val firstSaveStarted = CompletableDeferred<Unit>()
        val allowFirstSave = CompletableDeferred<Unit>()
        val removalStarted = CompletableDeferred<Unit>()
        val allowRemoval = CompletableDeferred<Unit>()

        override suspend fun load(): RebuildUserProfile? = persistedProfile

        override suspend fun save(profile: RebuildUserProfile) {
            saveCount += 1
            if (saveCount == 1) {
                firstSaveStarted.complete(Unit)
                allowFirstSave.await()
            }
            persistedProfile = profile
        }

        override suspend fun removeIfCurrent(id: String) {
            removalStarted.complete(Unit)
            allowRemoval.await()
            if (persistedProfile?.id == id) {
                persistedProfile = null
            }
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

        fun profile(role: OnboardingRole) = RebuildUserProfile(
            id = "current",
            role = role,
            nickname = if (role == OnboardingRole.Child) "냠냠이" else "보호자",
            school = if (role == OnboardingRole.Child) SCHOOL else null,
            allergyCodes = if (role == OnboardingRole.Child) listOf(1, 5) else emptyList(),
            destination = if (role == OnboardingRole.Child) {
                OnboardingDestination.Today
            } else {
                OnboardingDestination.ParentConnection
            },
        )
    }
}
