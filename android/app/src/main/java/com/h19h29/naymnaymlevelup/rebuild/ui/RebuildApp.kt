package com.h19h29.naymnaymlevelup.rebuild.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.onboarding.NeisSchoolSearchClient
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingFlow
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingViewModel
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RoomOnboardingProfileStore

@Composable
fun RebuildApp(database: RebuildDatabase) {
    val viewModel = remember(database) {
        OnboardingViewModel(
            profileStore = RoomOnboardingProfileStore(database),
            schoolSearchClient = NeisSchoolSearchClient(),
        )
    }
    RebuildTheme {
        OnboardingFlow(viewModel)
    }
}
