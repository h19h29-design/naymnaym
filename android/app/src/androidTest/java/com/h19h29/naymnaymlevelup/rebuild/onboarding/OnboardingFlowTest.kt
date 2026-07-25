package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.core.app.ActivityScenario
import com.h19h29.naymnaymlevelup.MainActivity
import com.h19h29.naymnaymlevelup.rebuild.data.ProfileEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class OnboardingFlowTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun allergyListKeepsNextActionVisibleAtLargeText() {
        val viewModel = OnboardingViewModel(
            profileStore = object : OnboardingProfileStore {
                override suspend fun save(profile: RebuildUserProfile) = Unit
                override suspend fun removeIfCurrent(id: String) = Unit
            },
            schoolSearchClient = SchoolSearchClient { emptyList() },
        )
        viewModel.selectRole(OnboardingRole.Child)
        viewModel.setNickname("냠냠이")
        viewModel.selectSchool(
            OnboardingSchool(
                name = "서울 냠냠초",
                officeCode = "B10",
                schoolCode = "7010111",
            ),
        )

        composeRule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(
                    density = density.density,
                    fontScale = 1.5f,
                ),
            ) {
                RebuildTheme {
                    OnboardingFlow(
                        viewModel = viewModel,
                        onCompleted = {},
                    )
                }
            }
        }

        composeRule.onNodeWithText("다음")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun childDestinationOpensRealMealActionWithPersistedSchool() {
        val profile = childProfile()
        var openedProfile: RebuildUserProfile? = null
        composeRule.setContent {
            RebuildTheme {
                RebuildTodayDestinationScreen(
                    profile = profile,
                    onOpenMeal = { openedProfile = it },
                )
            }
        }

        composeRule.onNodeWithText("오늘 급식 불러오기")
            .assertIsDisplayed()
            .assertHasClickAction()
            .performClick()

        composeRule.runOnIdle {
            assertEquals("B10", openedProfile?.school?.officeCode)
            assertEquals("7010111", openedProfile?.school?.schoolCode)
            assertEquals(OnboardingRole.Child, openedProfile?.role)
        }
    }

    @Test
    fun parentDestinationOpensRealConnectionActionWithPersistedRole() {
        val profile = RebuildUserProfile(
            id = "parent",
            role = OnboardingRole.Parent,
            nickname = "보호자",
            school = null,
            allergyCodes = emptyList(),
            destination = OnboardingDestination.ParentConnection,
        )
        var openedProfile: RebuildUserProfile? = null
        composeRule.setContent {
            RebuildTheme {
                RebuildParentConnectionDestinationScreen(
                    profile = profile,
                    onOpenConnection = { openedProfile = it },
                )
            }
        }

        composeRule.onNodeWithText("아이 연결하기")
            .assertIsDisplayed()
            .assertHasClickAction()
            .performClick()

        composeRule.runOnIdle {
            assertEquals(OnboardingRole.Parent, openedProfile?.role)
            assertEquals(OnboardingDestination.ParentConnection, openedProfile?.destination)
        }
    }

    @Test
    fun legacyDestinationLauncherBridgesStoredProfileIntoFunctionalActivity() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val preferences = context.getSharedPreferences(
            RebuildLegacyDestinationLauncher.LEGACY_PREFERENCES,
            android.content.Context.MODE_PRIVATE,
        )
        preferences.edit().clear().commit()
        val launcher = RebuildLegacyDestinationLauncher(context)

        val mealIntent = launcher.prepare(childProfile())

        assertEquals(MainActivity::class.java.name, mealIntent.component?.className)
        assertEquals(
            RebuildLegacyDestinationLauncher.ROUTE_TODAY_MEAL,
            mealIntent.getStringExtra(RebuildLegacyDestinationLauncher.EXTRA_ROUTE),
        )
        assertNotNull(
            mealIntent.getStringExtra(RebuildLegacyDestinationLauncher.EXTRA_CAPABILITY),
        )
        assertEquals("child", preferences.getString("rebuildRole", null))
        assertEquals("서울 냠냠초", preferences.getString("schoolName", null))
        assertEquals("B10", preferences.getString("officeCode", null))
        assertEquals("7010111", preferences.getString("schoolCode", null))

        val parentIntent = launcher.prepare(
            RebuildUserProfile(
                id = "parent",
                role = OnboardingRole.Parent,
                nickname = "보호자",
                school = null,
                allergyCodes = emptyList(),
                destination = OnboardingDestination.ParentConnection,
            ),
        )
        assertEquals(
            RebuildLegacyDestinationLauncher.ROUTE_PARENT_CONNECTION,
            parentIntent.getStringExtra(RebuildLegacyDestinationLauncher.EXTRA_ROUTE),
        )
        assertEquals("parent", preferences.getString("rebuildRole", null))
    }

    @Test
    fun parentDestinationIntentLaunchesTheFunctionalConnectionScreen() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launcher = RebuildLegacyDestinationLauncher(context)
        val parentProfile = RebuildUserProfile(
            id = "parent",
            role = OnboardingRole.Parent,
            nickname = "보호자",
            school = null,
            allergyCodes = emptyList(),
            destination = OnboardingDestination.ParentConnection,
        )

        val intent = launcher.prepare(parentProfile)
        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                val visibleTexts = visibleTexts(activity)
                assertTrue(visibleTexts.contains("연결된 아이"))
                assertTrue(visibleTexts.contains("아이에게 연결 요청 보내기"))
            }
        }

        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { activity ->
                val visibleTexts = visibleTexts(activity)
                assertTrue(visibleTexts.contains("오늘 급식 보러가기"))
                assertTrue(!visibleTexts.contains("아이에게 연결 요청 보내기"))
            }
        }
    }

    @Test
    fun forgedLegacyDestinationIntentCannotOpenThePrivateDestination() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val forged = android.content.Intent(context, MainActivity::class.java)
            .putExtra(
                RebuildLegacyDestinationLauncher.EXTRA_ROUTE,
                RebuildLegacyDestinationLauncher.ROUTE_PARENT_CONNECTION,
            )
            .putExtra(
                RebuildLegacyDestinationLauncher.EXTRA_CAPABILITY,
                "forged-capability",
            )

        ActivityScenario.launch<MainActivity>(forged).use { scenario ->
            scenario.onActivity { activity ->
                val visibleTexts = visibleTexts(activity)
                assertTrue(visibleTexts.contains("오늘 급식 보러가기"))
                assertTrue(!visibleTexts.contains("아이에게 연결 요청 보내기"))
            }
        }
    }

    @Test
    fun missingAndUnknownLegacyRoutesCannotOpenThePrivateDestination() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val blockedIntents = listOf(
            android.content.Intent(context, MainActivity::class.java),
            android.content.Intent(context, MainActivity::class.java)
                .putExtra(RebuildLegacyDestinationLauncher.EXTRA_ROUTE, "unknown")
                .putExtra(
                    RebuildLegacyDestinationLauncher.EXTRA_CAPABILITY,
                    "unknown-capability",
                ),
        )

        blockedIntents.forEach { blocked ->
            ActivityScenario.launch<MainActivity>(blocked).use { scenario ->
                scenario.onActivity { activity ->
                    val visibleTexts = visibleTexts(activity)
                    assertTrue(visibleTexts.contains("오늘 급식 보러가기"))
                    assertTrue(!visibleTexts.contains("아이에게 연결 요청 보내기"))
                }
            }
        }
    }

    @Test
    fun roomProfileStorePreservesExactSchoolNameAcrossRecreation() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        val preferences = context.getSharedPreferences(
            "rebuild-school-name-test",
            android.content.Context.MODE_PRIVATE,
        )
        preferences.edit().clear().commit()
        val metadata = SharedPreferencesSchoolNameMetadataStore(preferences)
        try {
            RoomOnboardingProfileStore(database, metadata).save(
                childProfile().copy(
                    school = childProfile().school?.copy(
                        name = "서울 냠냠초등학교",
                    ),
                ),
            )

            val relaunched = RoomOnboardingProfileStore(database, metadata).load()

            assertEquals("서울 냠냠초등학교", relaunched?.school?.name)

            database.profileDao().deleteAll()
            preferences.edit().clear().commit()
            database.profileDao().upsert(
                ProfileEntity(
                    id = "legacy-profile",
                    role = "child",
                    nickname = "냠냠이",
                    officeCode = "B10",
                    schoolCode = "7010111",
                    allergyCodesJson = "[1,5]",
                ),
            )

            val backwardsCompatible = RoomOnboardingProfileStore(
                database,
                metadata,
            ).load()

            assertEquals("등록한 학교", backwardsCompatible?.school?.name)
        } finally {
            database.close()
            preferences.edit().clear().commit()
        }
    }

    private fun childProfile() = RebuildUserProfile(
        id = "child",
        role = OnboardingRole.Child,
        nickname = "냠냠이",
        school = OnboardingSchool(
            name = "서울 냠냠초",
            officeCode = "B10",
            schoolCode = "7010111",
        ),
        allergyCodes = listOf(1, 5),
        destination = OnboardingDestination.Today,
    )

    private fun collectText(
        view: android.view.View,
        result: MutableList<String>,
    ) {
        if (view is android.widget.TextView) {
            result += view.text.toString()
        }
        if (view is android.view.ViewGroup) {
            repeat(view.childCount) { index ->
                collectText(view.getChildAt(index), result)
            }
        }
    }

    private fun visibleTexts(activity: MainActivity): List<String> {
        return buildList {
            collectText(activity.findViewById(android.R.id.content), this)
        }
    }
}
