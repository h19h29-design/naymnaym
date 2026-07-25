package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import org.junit.Rule
import org.junit.Test

class OnboardingFlowTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun allergyListKeepsNextActionVisibleAtLargeText() {
        val viewModel = OnboardingViewModel(
            profileStore = OnboardingProfileStore { },
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
}
