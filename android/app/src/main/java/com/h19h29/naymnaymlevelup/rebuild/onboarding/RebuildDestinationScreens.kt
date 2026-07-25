package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
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
fun RebuildTodayDestinationScreen(profile: RebuildUserProfile) {
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
    }
}

@Composable
fun RebuildParentConnectionDestinationScreen(profile: RebuildUserProfile) {
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
    }
}
