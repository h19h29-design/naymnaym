package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingDestination
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingRole
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildUserProfile
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test

class ChildNavigationTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun growthReloadsPersistedXpWheneverItsTabBecomesActive() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        try {
            insertProgress(database, id = "initial", amount = 80, occurredAt = 1)
            composeRule.setContent {
                RebuildTheme {
                    ChildNavigation(
                        profile = RebuildUserProfile(
                            id = "child",
                            role = OnboardingRole.Child,
                            nickname = "냠냠이",
                            school = null,
                            allergyCodes = emptyList(),
                            destination = OnboardingDestination.Today,
                        ),
                        database = database,
                        isAppActive = true,
                    )
                }
            }

            composeRule.onNodeWithTag("child_route_growth").performClick()
            waitForText("한 입 탐험가")

            composeRule.onNodeWithTag("child_route_today").performClick()
            insertProgress(database, id = "new-record", amount = 500, occurredAt = 2)
            composeRule.onNodeWithTag("child_route_growth").performClick()

            waitForText("급식 히어로")
        } finally {
            database.close()
        }
    }

    @Test
    fun collectionReloadsPersistedXpWheneverItsTabBecomesActive() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        try {
            insertProgress(database, id = "initial", amount = 80, occurredAt = 1)
            composeRule.setContent {
                RebuildTheme {
                    ChildNavigation(
                        profile = RebuildUserProfile(
                            id = "child",
                            role = OnboardingRole.Child,
                            nickname = "냠냠이",
                            school = null,
                            allergyCodes = emptyList(),
                            destination = OnboardingDestination.Today,
                        ),
                        database = database,
                        isAppActive = true,
                    )
                }
            }

            composeRule.onNodeWithTag("child_route_collection").performClick()
            waitForTag("collection_screen")
            composeRule.onNodeWithTag("collection_screen").performScrollToIndex(2)
            waitForTag("collection_level_2_unlocked")

            composeRule.onNodeWithTag("child_route_today").performClick()
            insertProgress(database, id = "new-record", amount = 500, occurredAt = 2)
            composeRule.onNodeWithTag("child_route_collection").performClick()
            waitForTag("collection_screen")
            composeRule.onNodeWithTag("collection_screen").performScrollToIndex(5)

            waitForTag("collection_level_5_unlocked")
        } finally {
            database.close()
        }
    }

    private fun insertProgress(
        database: RebuildDatabase,
        id: String,
        amount: Int,
        occurredAt: Long,
    ) {
        runBlocking {
            database.progressDao().insert(
                ProgressEventEntity(
                    id = id,
                    amount = amount,
                    occurredAtEpochMillis = occurredAt,
                    sourceRecordId = null,
                ),
            )
        }
    }

    private fun waitForText(text: String) {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithText(text)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }

    private fun waitForTag(tag: String) {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithTag(tag)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }
}
