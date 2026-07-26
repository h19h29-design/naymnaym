package com.h19h29.naymnaymlevelup.rebuild.mascot

import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MascotRigTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun rendersTheLevelOneRigWithItsAccessibleIdentity() {
        composeRule.setContent {
            MascotRig(
                level = 1,
                state = MotionState.MealSuccess,
                reduceMotion = false,
                modifier = Modifier.size(112.dp),
            )
        }

        composeRule.onNodeWithContentDescription("레벨 1 냠냠 다람쥐")
            .assertIsDisplayed()
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithTag("mascot_rig_approved_keyframes")
                .fetchSemanticsNodes().isNotEmpty()
        }
    }
}
