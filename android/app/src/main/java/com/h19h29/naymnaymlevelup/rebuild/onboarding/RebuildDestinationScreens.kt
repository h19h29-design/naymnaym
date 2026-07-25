package com.h19h29.naymnaymlevelup.rebuild.onboarding

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun RebuildTodayDestinationScreen(
    profile: RebuildUserProfile,
    onOpenMeal: (RebuildUserProfile) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(RebuildTokens.spacing[4].dp)
            .testTag("rebuild_today_destination"),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        Text(
            text = "오늘 급식",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.semantics { heading() },
        )
        Text("${profile.nickname}의 학교 급식을 확인해요.")
        Text("학교: ${profile.school?.name ?: "등록한 학교"}")
        Button(onClick = { onOpenMeal(profile) }) {
            Text("오늘 급식 불러오기")
        }
    }
}

@Composable
fun RebuildParentConnectionDestinationScreen(
    profile: RebuildUserProfile,
    onOpenConnection: (RebuildUserProfile) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(RebuildTokens.spacing[4].dp)
            .testTag("rebuild_parent_connection_destination"),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        Text(
            text = "아이 연결",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.semantics { heading() },
        )
        Text("${profile.nickname} 보호자 계정으로 아이의 초대 코드를 연결해요.")
        Button(onClick = { onOpenConnection(profile) }) {
            Text("아이 연결하기")
        }
    }
}

class RebuildLegacyDestinationLauncher(
    private val context: Context,
) {
    fun prepare(profile: RebuildUserProfile): Intent {
        val preferences = context.getSharedPreferences(
            LEGACY_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        val editor = preferences.edit()
            .putString("rebuildRole", profile.role.persistedValue)
            .putString("nickname", profile.nickname)
        val route = when (profile.role) {
            OnboardingRole.Child -> {
                val school = requireNotNull(profile.school) {
                    "Child destination requires a persisted school"
                }
                editor
                    .putString("schoolName", school.name)
                    .putString("officeCode", school.officeCode)
                    .putString("schoolCode", school.schoolCode)
                    .putString("region", "")
                    .putString("address", "")
                    .putString("schoolType", "")
                    .putBoolean("demoMode", false)
                ROUTE_TODAY_MEAL
            }
            OnboardingRole.Parent -> {
                editor
                    .remove("schoolName")
                    .remove("officeCode")
                    .remove("schoolCode")
                    .remove("region")
                    .remove("address")
                    .remove("schoolType")
                    .putBoolean("demoMode", false)
                ROUTE_PARENT_CONNECTION
            }
        }
        check(editor.commit()) {
            "Could not bridge the persisted rebuild profile"
        }
        return Intent()
            .setClassName(
                context,
                "com.h19h29.naymnaymlevelup.MainActivity",
            )
            .putExtra(EXTRA_ROUTE, route)
            .apply {
                if (context !is Activity) {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            }
    }

    fun launch(profile: RebuildUserProfile) {
        context.startActivity(prepare(profile))
    }

    companion object {
        const val LEGACY_PREFERENCES = "naymnaym-android"
        const val EXTRA_ROUTE =
            "com.h19h29.naymnaymlevelup.rebuild.LEGACY_DESTINATION"
        const val ROUTE_TODAY_MEAL = "todayMeal"
        const val ROUTE_PARENT_CONNECTION = "parentConnection"
    }
}
