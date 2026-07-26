package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import org.junit.Rule
import org.junit.Test

class ForestSceneTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun fiveDecorativeLayersRenderBelowReadableContent() {
        composeRule.setContent {
            RebuildTheme {
                ForestScene(
                    reduceMotion = true,
                    isPaused = false,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    Box(Modifier.testTag("forest_readable_content")) {
                        Text("오늘 급식")
                    }
                }
            }
        }

        ForestSceneLayer.entries.forEach { layer ->
            composeRule.waitUntil(timeoutMillis = 10_000) {
                composeRule
                    .onAllNodesWithTag("forest_layer_${layer.name}")
                    .fetchSemanticsNodes()
                    .isNotEmpty()
            }
            composeRule.onNodeWithTag("forest_layer_${layer.name}")
                .assertIsDisplayed()
        }
        composeRule.onNodeWithTag("forest_readable_content")
            .assertIsDisplayed()
    }

    @Test
    fun activeMotionCooperatesWithComposeIdleness() {
        composeRule.setContent {
            RebuildTheme {
                ForestScene(
                    reduceMotion = false,
                    isPaused = false,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    Box(Modifier.testTag("forest_active_content")) {
                        Text("움직이는 숲")
                    }
                }
            }
        }

        composeRule.onNodeWithTag("forest_active_content")
            .assertIsDisplayed()
    }
}
