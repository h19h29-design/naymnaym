package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import com.h19h29.naymnaymlevelup.rebuild.onboarding.AllergyCatalog
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildUserProfile
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun RebuildSettingsScreen(
    profile: RebuildUserProfile,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(Color(RebuildTokens.Cream50))
            .padding(horizontal = RebuildTokens.spacing[4].dp)
            .testTag("settings_screen"),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        item {
            Column(
                modifier = Modifier.padding(top = RebuildTokens.spacing[3].dp),
                verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[1].dp),
            ) {
                Text(
                    text = "설정",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color(RebuildTokens.Ink900),
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    text = "내 학교와 알레르기 정보를 확인해요.",
                    color = Color(RebuildTokens.Muted600),
                )
            }
        }
        item {
            SettingsCard(title = "프로필") {
                SettingsLine("별명", profile.nickname)
                SettingsLine("이용 모드", if (profile.role.persistedValue == "child") "아이" else "보호자")
            }
        }
        item {
            SettingsCard(title = "급식 설정") {
                SettingsLine("학교", profile.school?.name ?: "등록된 학교가 없어요")
                val allergyText = profile.allergyCodes
                    .sorted()
                    .joinToString(separator = " · ") { AllergyCatalog.label(it) }
                    .ifBlank { "설정한 알레르기가 없어요" }
                SettingsLine("알레르기", allergyText)
            }
        }
        item {
            SettingsCard(title = "안내") {
                SettingsLine("데이터 출처", "학교 급식 정보는 교육부 NEIS를 바탕으로 표시해요.")
                SettingsLine("초기화", "설정을 다시 시작하려면 앱을 삭제 후 다시 설치해 주세요.")
            }
        }
        item { Spacer(Modifier.height(RebuildTokens.spacing[4].dp)) }
    }
}

@Composable
private fun SettingsCard(
    title: String,
    content: @Composable () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.94f)),
    ) {
        Column(
            modifier = Modifier.padding(RebuildTokens.spacing[3].dp),
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Forest700),
            )
            content()
        }
    }
}

@Composable
private fun SettingsLine(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = Color(RebuildTokens.Muted600),
            modifier = Modifier.weight(0.28f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = Color(RebuildTokens.Ink900),
            modifier = Modifier.weight(0.72f),
        )
    }
}
