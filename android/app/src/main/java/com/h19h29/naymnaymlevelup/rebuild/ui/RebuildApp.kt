package com.h19h29.naymnaymlevelup.rebuild.ui

import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.onboarding.NeisSchoolSearchClient
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingFlow
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingBootstrapper
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingRootState
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingViewModel
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildParentConnectionDestinationScreen
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildTodayDestinationScreen
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RoomOnboardingProfileStore

@Composable
fun RebuildApp(database: RebuildDatabase) {
    val profileStore = remember(database) {
        RoomOnboardingProfileStore(database)
    }
    val bootstrap = remember(profileStore) {
        OnboardingBootstrapper(profileStore)
    }
    val viewModel = remember(database) {
        OnboardingViewModel(
            profileStore = profileStore,
            schoolSearchClient = NeisSchoolSearchClient(),
        )
    }
    LaunchedEffect(bootstrap) {
        bootstrap.load()
    }
    RebuildTheme {
        when (val state = bootstrap.state) {
            OnboardingRootState.Loading -> CircularProgressIndicator()
            OnboardingRootState.Onboarding -> OnboardingFlow(
                viewModel = viewModel,
                onCompleted = bootstrap::accept,
            )
            is OnboardingRootState.Destination -> {
                if (
                    state.profile.destination ==
                    com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingDestination.Today
                ) {
                    RebuildTodayDestinationScreen(state.profile)
                } else {
                    RebuildParentConnectionDestinationScreen(state.profile)
                }
            }
            OnboardingRootState.Failed -> Text(
                "프로필을 열 수 없어요. 앱을 다시 시작해 주세요.",
            )
        }
    }
}
