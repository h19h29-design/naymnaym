package com.h19h29.naymnaymlevelup.rebuild.child

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionRuleEngine
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens
import java.util.UUID
import kotlinx.coroutines.launch

internal const val DAILY_MEAL_REVIEW_CONSENT =
    "급식레벨업 서버에는 임시 요청 ID·임의 설치 ID·익명 메뉴별 대표 영양소·확인된 전체 식단 영양량을 보내고, OpenCode Go에는 익명 식단 정보만 전달해요. 학교·메뉴 이름·날짜·식사 기록·등록 알레르기는 전송하지 않아요."

private const val DAILY_REVIEW_PREFERENCES = "daily_meal_review"
private const val DAILY_REVIEW_INSTALLATION_ID = "installation_id_v1"

internal fun dailyMealReviewInstallationId(context: Context): UUID {
    val preferences = context.getSharedPreferences(DAILY_REVIEW_PREFERENCES, Context.MODE_PRIVATE)
    val existing = preferences.getString(DAILY_REVIEW_INSTALLATION_ID, null)
        ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
    if (existing != null) return existing
    return UUID.randomUUID().also {
        preferences.edit().putString(DAILY_REVIEW_INSTALLATION_ID, it.toString().lowercase()).apply()
    }
}

@Composable
fun DailyMealReviewEntry(
    meal: MealDay,
    profileKey: String,
    schoolKey: String,
    registeredAllergyCodes: List<Int>,
    store: DailyMealReviewRepository,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val rules = remember(context.assets) { NutritionRuleEngine(context.assets) }
    val client = remember { DevelopmentDailyMealReviewClient(DailyMealReviewDevelopmentConfig.production()) }
    val installationId = remember(context) { dailyMealReviewInstallationId(context) }
    val deletionRevision by store.deletionRevision?.collectAsState()
        ?: remember { mutableStateOf(0L) }
    var open by remember { mutableStateOf(false) }
    val session = remember(meal, profileKey, schoolKey, registeredAllergyCodes, store, client, rules) {
        DailyMealReviewSession(
            profileKey = profileKey,
            schoolKey = schoolKey,
            mealType = "lunch",
            meal = meal,
            registeredAllergyCodes = registeredAllergyCodes,
            store = store,
            client = client,
            rules = rules,
            sessionId = installationId,
        )
    }
    LaunchedEffect(session, deletionRevision) { session.reload() }
    val state by session.state.collectAsState()
    OutlinedButton(
        onClick = { open = true },
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = RebuildTokens.minimumActionSize.dp)
            .testTag("daily_meal_review_entry"),
    ) {
        Icon(Icons.Filled.AutoAwesome, contentDescription = null)
        Spacer(Modifier.width(8.dp))
        Text(if (state.record == null) "오늘 식단 AI 해설" else "오늘 평가 다시 보기")
    }
    if (open) {
        Dialog(
            onDismissRequest = { open = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            DailyMealReviewScreen(
                session = session,
                meal = meal,
                onDismiss = { open = false },
            )
        }
    }
}

@Composable
fun DailyMealReviewScreen(
    session: DailyMealReviewSession,
    meal: MealDay,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by session.state.collectAsState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(session) { session.load() }
    val displayed = state.record ?: state.unsavedRecord
    val displayedWholeMeal = displayed?.wholeMeal ?: dailyMealReviewWholeMeal(meal)
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFF4F8F0))
            .statusBarsPadding()
            .padding(horizontal = 16.dp)
            .testTag("daily_meal_review_screen"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("AI 영양 안내", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text(
                        displayed?.let { dailyMealReviewSourceLabel(it.response.source) }
                            ?: if (state.error != null) "기본 영양 안내" else "오늘 한 번 생성할 수 있어요",
                        color = Color(RebuildTokens.Forest700),
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.testTag("daily_meal_review_source"),
                    )
                    displayed?.let {
                        Text(
                            "생성 시각 ${it.response.generatedAt}",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(RebuildTokens.Muted600),
                        )
                    }
                }
                IconButton(onClick = onDismiss, modifier = Modifier.testTag("daily_meal_review_close")) {
                    Icon(Icons.Filled.Close, contentDescription = "닫기")
                }
            }
        }
        if (state.mealChangedSinceReview) {
            item { ReviewNotice("현재 식단과 달라요. 아래 내용은 평가 당시 식단을 기준으로 해요.") }
        }
        state.notice?.let { notice -> item { ReviewNotice(notice) } }
        if (displayed == null && state.generationAvailable) {
            item {
                Card(colors = CardDefaults.cardColors(containerColor = Color.White)) {
                    Row(
                        Modifier.fillMaxWidth().padding(12.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Checkbox(
                            checked = state.consent,
                            onCheckedChange = session::setConsent,
                            modifier = Modifier.testTag("daily_meal_review_consent"),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(DAILY_MEAL_REVIEW_CONSENT, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            item {
                Button(
                    onClick = { scope.launch { session.generate() } },
                    enabled = !state.isLoading,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("daily_meal_review_generate"),
                ) {
                    if (state.isLoading) {
                        CircularProgressIndicator(modifier = Modifier.width(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("해설을 생각하고 있어요")
                    } else {
                        Text(if (state.error == DailyMealReviewError.SaveFailed) "기기에 다시 저장" else "오늘 AI 해설 만들기")
                    }
                }
            }
        }
        if (displayed != null) {
            item { ReviewSection("1. 오늘 식단의 특징", displayed.response.summary) }
            item { ReviewSection("2. 영양소가 하는 일", displayed.response.benefit) }
            item {
                val highlights = session.visibleHighlights()
                ReviewSection(
                    "3. 눈여겨볼 메뉴",
                    if (highlights.isEmpty()) {
                        "현재 알레르기 설정을 반영해 표시할 추천 메뉴가 없어요."
                    } else {
                        highlights.joinToString("\n") { highlight ->
                            val name = displayed.menuName(highlight.itemId) ?: "평가 당시 메뉴"
                            "$name · ${dailyMealReviewNutrientRole(highlight.nutrient)}"
                        }
                    },
                )
            }
            item { ReviewSection("4. 다음 식사 팁", "${displayed.response.caution}\n${displayed.response.tip}") }
            if (state.unsavedRecord != null) {
                item {
                    Button(
                        onClick = { scope.launch { session.retrySave() } },
                        modifier = Modifier.fillMaxWidth().testTag("daily_meal_review_retry_save"),
                    ) { Text("기기에 다시 저장") }
                }
            }
        }
        if (displayed == null && state.error != null) {
            item { ReviewSection("1. 오늘 식단의 특징", "급식 제공 정보를 기준으로 식단 구성을 살펴봐요.") }
            item { ReviewSection("2. 영양소가 하는 일", "여러 메뉴를 만나면 서로 다른 영양소를 경험할 수 있어요.") }
            item { ReviewSection("3. 눈여겨볼 메뉴", "알레르기 주의 메뉴는 보호자나 선생님에게 먼저 확인해 주세요.") }
            item { ReviewSection("4. 다음 식사 팁", "실제로 먹은 양은 알 수 없어요. 다음 식사에서도 다양한 음식을 만나 봐요.") }
        }
        item {
            ReviewSection(
                "급식 제공 영양정보",
                listOfNotNull(
                    displayedWholeMeal.protein?.let { "단백질 ${it}g" },
                    displayedWholeMeal.carbs?.let { "탄수화물 ${it}g" },
                    displayedWholeMeal.fat?.let { "지방 ${it}g" },
                ).joinToString(" · ").ifBlank { "제공된 전체 영양 수치가 없어요." },
            )
        }
        item {
            Row(Modifier.fillMaxWidth().padding(bottom = 20.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Filled.PrivacyTip, contentDescription = null, tint = Color(RebuildTokens.Muted600))
                Spacer(Modifier.width(8.dp))
                Text(
                    "영양 교육용 참고 안내이며 실제 영양사·의료 상담을 대신하지 않아요. 실제로 먹은 양은 알 수 없어요.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color(RebuildTokens.Muted600),
                )
            }
        }
    }
}

@Composable
private fun ReviewSection(title: String, body: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, fontWeight = FontWeight.Bold, color = Color(RebuildTokens.Forest700))
            Text(body, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun ReviewNotice(message: String) {
    Text(
        message,
        modifier = Modifier.fillMaxWidth().background(Color(0xFFFFF3D6), RoundedCornerShape(12.dp)).padding(12.dp),
        style = MaterialTheme.typography.bodySmall,
        fontWeight = FontWeight.SemiBold,
    )
}
