package com.h19h29.naymnaymlevelup.rebuild.child

import com.h19h29.naymnaymlevelup.BuildConfig

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Icon
import com.h19h29.naymnaymlevelup.rebuild.ui.CompanionSectionBanner
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import com.h19h29.naymnaymlevelup.rebuild.onboarding.AllergyCatalog
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildUserProfile
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun RebuildSettingsScreen(
    profile: RebuildUserProfile,
    modifier: Modifier = Modifier,
    dailyMealReviewStore: DailyMealReviewRepository? = null,
) {
    var confirmDeleteReviews by remember { mutableStateOf(false) }
    var deleteMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFF4F8F0))
            .padding(horizontal = 16.dp)
            .testTag("settings_screen"),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        item {
            CompanionSectionBanner("나의 작은 숲", "${profile.nickname}의 급식 모험\n학교와 알레르기를 챙겨요.",
                Icons.Filled.AccountCircle, modifier = Modifier.padding(top = 16.dp))
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
        if (BuildConfig.DEBUG && dailyMealReviewStore != null) {
            item {
                SettingsCard(title = "AI 평가 기록") {
                    Text(
                        "기기에 저장된 AI 식단 평가만 삭제해요. 급식·성장·도감 기록과 서버의 오늘 사용 횟수는 바뀌지 않아요.",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(RebuildTokens.Muted600),
                    )
                    OutlinedButton(
                        onClick = { confirmDeleteReviews = true },
                        modifier = Modifier.fillMaxWidth().testTag("settings_delete_daily_reviews"),
                    ) { Text("AI 평가 기록 삭제") }
                    deleteMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                }
            }
        }
        item { Spacer(Modifier.height(RebuildTokens.spacing[4].dp)) }
    }
    if (BuildConfig.DEBUG && confirmDeleteReviews && dailyMealReviewStore != null) {
        AlertDialog(
            onDismissRequest = { confirmDeleteReviews = false },
            title = { Text("AI 평가 기록을 삭제할까요?") },
            text = { Text("저장된 AI 식단 평가만 삭제되며 되돌릴 수 없어요.") },
            confirmButton = {
                Button(
                    onClick = {
                        confirmDeleteReviews = false
                        scope.launch {
                            deleteMessage = runCatching { dailyMealReviewStore.deleteAll() }
                                .fold(
                                    onSuccess = { "AI 평가 기록을 삭제했어요." },
                                    onFailure = { "AI 평가 기록을 삭제하지 못했어요." },
                                )
                        }
                    },
                    modifier = Modifier.testTag("settings_confirm_delete_daily_reviews"),
                ) { Text("삭제") }
            },
            dismissButton = {
                OutlinedButton(onClick = { confirmDeleteReviews = false }) { Text("취소") }
            },
        )
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
          Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val accent = when (title) { "프로필" -> Color(RebuildTokens.Forest500); "급식 설정" -> Color(0xFF20758C); else -> Color(0xFF825A9B) }
            Icon(when (title) { "프로필" -> Icons.Filled.Person; "급식 설정" -> Icons.Filled.Restaurant; else -> Icons.Filled.Info }, null,
                tint = accent, modifier = Modifier.background(accent.copy(alpha = 0.12f), RoundedCornerShape(11.dp)).padding(8.dp).size(20.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Forest700),
            )
          }
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
