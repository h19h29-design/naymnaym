package com.h19h29.naymnaymlevelup.rebuild.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.core.content.ContextCompat
import com.h19h29.naymnaymlevelup.rebuild.child.ChildNavigation
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.onboarding.NeisSchoolSearchClient
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingFlow
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingBootstrapper
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingRootState
import com.h19h29.naymnaymlevelup.rebuild.onboarding.OnboardingViewModel
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildParentConnectionDestinationScreen
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildLegacyDestinationLauncher
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildIntroDailyGate
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildIntroEntryController
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildIntroScreen
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RoomOnboardingProfileStore
import com.h19h29.naymnaymlevelup.rebuild.onboarding.SharedPreferencesRebuildIntroDateStore
import com.h19h29.naymnaymlevelup.rebuild.onboarding.SharedPreferencesSchoolNameMetadataStore

@Composable
fun RebuildApp(database: RebuildDatabase) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val lifecycleState by lifecycleOwner.lifecycle.currentStateAsState()
    val destinationLauncher = remember(context) {
        RebuildLegacyDestinationLauncher(context)
    }
    val profileStore = remember(database, context) {
        RoomOnboardingProfileStore(
            database,
            SharedPreferencesSchoolNameMetadataStore(
                context.getSharedPreferences(
                    "rebuild-school-name-metadata",
                    android.content.Context.MODE_PRIVATE,
                ),
            ),
        )
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
    val introEntry = remember(context) {
        RebuildIntroEntryController(
            RebuildIntroDailyGate(
                SharedPreferencesRebuildIntroDateStore(
                    context.getSharedPreferences(
                        "rebuild-intro-state",
                        android.content.Context.MODE_PRIVATE,
                    ),
                ),
            ),
        )
    }
    DisposableEffect(introEntry) {
        onDispose {
            introEntry.close()
        }
    }
    DisposableEffect(lifecycleOwner, introEntry) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                introEntry.refresh()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }
    DisposableEffect(context, introEntry) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(
                receiverContext: Context?,
                intent: Intent?,
            ) {
                introEntry.refresh()
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        ContextCompat.registerReceiver(
            context,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        onDispose {
            context.unregisterReceiver(receiver)
        }
    }
    LaunchedEffect(bootstrap, introEntry.canLoadBootstrap) {
        if (introEntry.canLoadBootstrap) {
            bootstrap.load()
        }
    }
    RebuildTheme {
        if (introEntry.showIntro) {
            RebuildIntroScreen(
                onCompleted = {
                    introEntry.completeIntro()
                },
            )
        } else {
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
                        ChildNavigation(
                            profile = state.profile,
                            database = database,
                            isAppActive = lifecycleState.isAtLeast(
                                Lifecycle.State.RESUMED,
                            ),
                        )
                    } else {
                        RebuildParentConnectionDestinationScreen(
                            profile = state.profile,
                            onOpenConnection = destinationLauncher::launch,
                        )
                    }
                }
                OnboardingRootState.Failed -> Text(
                    "프로필을 열 수 없어요. 앱을 다시 시작해 주세요.",
                )
            }
        }
    }
}
