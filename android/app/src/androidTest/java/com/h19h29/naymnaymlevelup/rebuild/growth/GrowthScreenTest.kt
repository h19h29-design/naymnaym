package com.h19h29.naymnaymlevelup.rebuild.growth

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import com.h19h29.naymnaymlevelup.rebuild.data.ProgressEventEntity
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import org.junit.Rule
import org.junit.Test

class GrowthScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    private val policy = GrowthPolicy.decode(CANONICAL_POLICY)

    @Test
    fun growthScreenShowsThePersistedLevelProgressPreviewAndRecentEventsInOrder() {
        composeRule.setContent {
            RebuildTheme {
                GrowthScreenContent(
                    snapshot = GrowthSnapshot(
                        totalXp = 734,
                        recentEvents = listOf(
                            ProgressEventEntity(
                                id = "meal:2026-07-25|시금치 나물|oneBite",
                                amount = 18,
                                occurredAtEpochMillis = 100,
                                sourceRecordId = null,
                            ),
                        ),
                    ),
                    policy = policy,
                )
            }
        }

        composeRule.onNodeWithTag("growth_screen").assertIsDisplayed()
        composeRule.onNodeWithTag("growth_current_character").assertIsDisplayed()
        composeRule.onNodeWithTag("growth_progress").assertIsDisplayed()
        composeRule.onNodeWithTag("growth_next_unlock").assertIsDisplayed()
        composeRule.onNodeWithTag("growth_recent_events")
            .performScrollTo()
            .assertIsDisplayed()
        composeRule.onNodeWithText("영양 마스터").assertIsDisplayed()
        composeRule.onNodeWithText("시금치 나물 · 한 입 도전")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun collectionUsesFullColorForUnlockedAndWarmSilhouetteForLockedLevels() {
        composeRule.setContent {
            RebuildTheme {
                CollectionScreenContent(
                    progress = CollectionProgress(80, emptyList(), emptySet(), 0, 0, 0),
                    policy = policy,
                    selectedSection = CollectionSection.Characters,
                    onSectionSelected = {},
                )
            }
        }

        composeRule.onNodeWithTag("collection_level_2_unlocked")
            .performScrollTo()
            .assertIsDisplayed()
        composeRule.onNodeWithTag("collection_level_3_locked_warm_silhouette")
            .performScrollTo()
            .assertIsDisplayed()
        composeRule.onNodeWithContentDescription("레벨 3 잠김, 180 XP에 해금")
            .performScrollTo()
            .assertIsDisplayed()
    }

    private companion object {
        val CANONICAL_POLICY = """
            {
              "version": 1,
              "thresholds": [0, 80, 180, 320, 500, 720, 1000],
              "titles": [
                "냠냠 새싹",
                "한 입 탐험가",
                "냠냠 용사",
                "편식 몬스터 사냥꾼",
                "급식 히어로",
                "영양 마스터",
                "레전드 냠냠러"
              ]
            }
        """.trimIndent().encodeToByteArray()
    }
}
