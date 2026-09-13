package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.BuildConfig
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.NutritionRuleEngine
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun MealNutritionCoach(
    meal: MealDay,
    registeredAllergyCodes: List<Int>,
    modifier: Modifier = Modifier,
    developmentConfigEnabled: Boolean = true,
) {
    val context = LocalContext.current
    val rules = remember(context.assets) { NutritionRuleEngine(context.assets) }
    val client = remember(context.filesDir, developmentConfigEnabled) {
        if (developmentConfigEnabled) {
            MealCoachDevelopmentConfig.load(
                filesDir = context.filesDir,
                isDebug = BuildConfig.DEBUG,
            )?.let(::DevelopmentMealCoachClient)
        } else {
            null
        }
    }
    val scope = rememberCoroutineScope()
    val allergyKey = registeredAllergyCodes.distinct().sorted()
    val session = remember(meal, allergyKey, rules, client, scope) {
        MealCoachSession(
            initialMeal = meal,
            rules = rules,
            client = client,
            scope = scope,
            initialRegisteredAllergyCodes = allergyKey,
        )
    }
    DisposableEffect(session) {
        onDispose(session::close)
    }
    val state by session.state.collectAsState()
    val allergyRisk = state.selectedMenuIndices.any { index ->
        meal.menuItems.getOrNull(index)?.allergyCodes?.any(allergyKey::contains) == true
    }
    val isWholeMealSelected = meal.menuItems.isNotEmpty() &&
        state.selectedMenuIndices == meal.menuItems.indices.toSet()
    val useRemote = state.useAi && session.aiAvailable && !allergyRisk

    Card(
        modifier = modifier
            .fillMaxWidth()
            .testTag("meal_nutrition_coach"),
        shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Filled.AutoAwesome,
                    contentDescription = null,
                    tint = Color(RebuildTokens.Forest500),
                )
                Spacer(Modifier.width(8.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = "선택형 영양 코치",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color(RebuildTokens.Forest700),
                    )
                    Text(
                        text = "기록이나 경험치는 바꾸지 않는 가정 안내예요.",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(RebuildTokens.Muted600),
                    )
                }
                Surface(
                    color = if (state.aiConnected) {
                        Color(RebuildTokens.Leaf300).copy(alpha = 0.42f)
                    } else {
                        Color(RebuildTokens.Cream100)
                    },
                    shape = CircleShape,
                    modifier = if (state.aiConnected) {
                        Modifier.testTag("meal_coach_ai_connected")
                    } else {
                        Modifier
                    },
                ) {
                    Text(
                        text = if (state.aiConnected) "AI 응답" else "로컬 기본",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = Color(RebuildTokens.Forest700),
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                }
            }

            Text(
                text = "살펴볼 메뉴 · 처음에는 모두 선택돼요",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Ink900),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                meal.menuItems.forEachIndexed { index, item ->
                    val selected = index in state.selectedMenuIndices
                    FilterChip(
                        selected = selected,
                        onClick = { session.toggleMenu(index) },
                        label = { Text(item.name) },
                        leadingIcon = if (selected) {
                            {
                                Icon(
                                    imageVector = Icons.Filled.Check,
                                    contentDescription = null,
                                )
                            }
                        } else {
                            null
                        },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = Color(RebuildTokens.Leaf300).copy(alpha = 0.4f),
                            selectedLabelColor = Color(RebuildTokens.Forest700),
                        ),
                        modifier = Modifier.testTag("meal_coach_menu_$index"),
                    )
                }
            }

            if (allergyRisk) {
                CoachNotice(
                    text = "등록 알레르기 주의 메뉴가 선택돼 있어요. 이 메뉴는 AI에 전송하지 않고 먹도록 권하지 않아요. 보호자나 선생님에게 먼저 확인해 주세요.",
                    danger = true,
                )
            }

            if (session.aiAvailable) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            text = "개발 AI 연결",
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Bold,
                            color = Color(RebuildTokens.Ink900),
                        )
                        Text(
                            text = if (allergyRisk) {
                                "주의 메뉴 선택 중에는 로컬 안전 안내만 사용해요."
                            } else {
                                "기본은 로컬 안내이며 이 화면 세션에서만 선택돼요."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(RebuildTokens.Muted600),
                        )
                    }
                    Switch(
                        checked = state.useAi,
                        enabled = !allergyRisk,
                        onCheckedChange = session::setUseAi,
                        modifier = Modifier.testTag("meal_coach_ai_toggle"),
                    )
                }
            }

            if (useRemote) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            Color(RebuildTokens.Cream50),
                            RoundedCornerShape(RebuildTokens.radii[0].dp),
                        )
                        .padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(
                        checked = state.consent,
                        onCheckedChange = session::setConsent,
                        modifier = Modifier.testTag("meal_coach_consent"),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = MEAL_COACH_CONSENT_COPY,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(RebuildTokens.Ink900),
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MealCoachQuestion.entries.forEach { question ->
                    OutlinedButton(
                        onClick = {
                            session.ask(question, registeredAllergyCodes)
                        },
                        enabled = !state.isLoading && state.selectedMenuIndices.isNotEmpty(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = RebuildTokens.minimumActionSize.dp)
                            .testTag("meal_coach_question_${question.wireValue}"),
                    ) {
                        Text(question.title(isWholeMealSelected))
                    }
                }
            }

            if (state.isLoading) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = Color(RebuildTokens.Forest500),
                    )
                    Text(
                        text = "안내를 생각하고 있어요.",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(RebuildTokens.Forest700),
                    )
                }
            }
            state.notice?.let { CoachNotice(it, danger = false) }
            state.answer?.let { answer ->
                MealCoachAnswerCard(answer)
            }

            Row(verticalAlignment = Alignment.Top) {
                Icon(
                    imageVector = Icons.Filled.PrivacyTip,
                    contentDescription = null,
                    tint = Color(RebuildTokens.Muted600),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "교육용 일반 안내예요. 정확한 섭취량·알레르기 안전·체중이나 키 상태를 진단하지 않아요. 식단 수치는 선택한 반찬별 양이 아니라 전체 식사 기준이에요.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color(RebuildTokens.Muted600),
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun CoachNotice(text: String, danger: Boolean) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = FontWeight.SemiBold,
        color = if (danger) Color(RebuildTokens.Danger700) else Color(RebuildTokens.Forest700),
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (danger) Color(0xFFFFE9E5) else Color(RebuildTokens.Leaf300).copy(alpha = 0.24f),
                RoundedCornerShape(RebuildTokens.radii[0].dp),
            )
            .padding(12.dp),
    )
}

@Composable
private fun MealCoachAnswerCard(answer: MealCoachAnswer) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Color(RebuildTokens.Cream50),
                RoundedCornerShape(RebuildTokens.radii[0].dp),
            )
            .padding(14.dp)
            .testTag(
                if (answer.source == MealCoachAnswerSource.Ai) {
                    "meal_coach_answer_ai"
                } else {
                    "meal_coach_answer_local"
                },
            ),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = answer.summary,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Bold,
            color = Color(RebuildTokens.Ink900),
        )
        AnswerLine("도움", answer.benefit)
        AnswerLine("주의", answer.caution)
        AnswerLine("한 가지 팁", answer.tip)
    }
}

@Composable
private fun AnswerLine(label: String, text: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = Color(RebuildTokens.Forest500),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = Color(RebuildTokens.Ink900),
        )
    }
}
