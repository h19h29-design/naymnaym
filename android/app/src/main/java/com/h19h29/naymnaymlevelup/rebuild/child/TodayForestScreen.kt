package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.mascot.MascotRig
import com.h19h29.naymnaymlevelup.rebuild.mascot.toMascotMotionState
import com.h19h29.naymnaymlevelup.rebuild.growth.GrowthPolicy
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun TodayForestScreen(
    viewModel: TodayForestViewModel,
    growthPolicy: GrowthPolicy,
    isTabActive: Boolean = true,
    isAppActive: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    var showRecorder by remember { mutableStateOf(false) }

    LaunchedEffect(viewModel) {
        viewModel.load()
    }

    ForestScene(
        reduceMotion = false,
        activity = ForestSceneActivity(
            isSheetPresented = showRecorder,
            isTabActive = isTabActive,
            isAppActive = isAppActive,
        ),
        modifier = modifier.fillMaxSize(),
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = RebuildTokens.spacing[4].dp)
                .testTag("today_forest_list"),
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
        ) {
            item {
                Column(
                    modifier = Modifier
                        .padding(top = RebuildTokens.spacing[3].dp)
                        .fillMaxWidth()
                        .background(
                            Color(RebuildTokens.Cream50),
                            RoundedCornerShape(RebuildTokens.radii[1].dp),
                        )
                        .padding(RebuildTokens.spacing[3].dp),
                    verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[1].dp),
                ) {
                    Text(
                        text = viewModel.title,
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = Color(RebuildTokens.Ink900),
                        modifier = Modifier
                            .testTag("today_title")
                            .semantics { heading() },
                    )
                    Text(
                        text = viewModel.dateText,
                        color = Color(RebuildTokens.Muted600),
                        modifier = Modifier.semantics {
                            contentDescription = "날짜 ${viewModel.dateText}"
                        },
                    )
                }
            }

            item {
                CharacterStage(state, growthPolicy)
            }

            item {
                MealSummary(viewModel, state)
            }

            item {
                Button(
                    onClick = { showRecorder = true },
                    enabled = state.primaryActionEnabled,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = RebuildTokens.minimumActionSize.dp)
                        .testTag("today_primary_action"),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(RebuildTokens.Forest700),
                        contentColor = Color.White,
                        disabledContainerColor = Color(RebuildTokens.Muted600),
                        disabledContentColor = Color(RebuildTokens.Cream50),
                    ),
                    shape = RoundedCornerShape(RebuildTokens.radii[0].dp),
                ) {
                    Text(
                        text = viewModel.primaryActionTitle,
                        style = MaterialTheme.typography.labelLarge,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            item { Spacer(Modifier.height(RebuildTokens.spacing[3].dp)) }
        }
    }

    if (showRecorder) {
        MealRecordingSheet(
            viewModel = viewModel,
            onDismiss = { showRecorder = false },
        )
    }
}

@Composable
private fun CharacterStage(
    state: TodayForestUiState,
    growthPolicy: GrowthPolicy,
) {
    val level = growthPolicy.level(state.totalXP)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("today_character_hub")
            .semantics {
                contentDescription = "현재 캐릭터, ${characterMessage(state)}"
            },
        shape = RoundedCornerShape(RebuildTokens.radii[2].dp),
        colors = CardDefaults.cardColors(
            containerColor = Color(RebuildTokens.Cream50),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(RebuildTokens.spacing[2].dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            MascotRig(
                level = level.coerceAtMost(7),
                state = state.motion.toMascotMotionState(),
                reduceMotion = false,
                playbackRevision = state.motionRevision,
                modifier = Modifier.size(112.dp),
            )
            Text(
                text = "레벨 $level · ${growthPolicy.title(level)}",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Forest700),
                textAlign = TextAlign.Center,
            )
            Text(
                text = characterMessage(state),
                style = MaterialTheme.typography.bodyMedium,
                color = Color(RebuildTokens.Ink900),
                textAlign = TextAlign.Center,
            )
            Text(
                text = "총 ${state.totalXP} XP",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                color = Color(RebuildTokens.Muted600),
            )
            LinearProgressIndicator(
                progress = { growthPolicy.progress(state.totalXP) },
                modifier = Modifier.fillMaxWidth(),
                color = Color(RebuildTokens.Forest500),
                trackColor = Color(RebuildTokens.Cream100),
            )
        }
    }
}

@Composable
private fun MealSummary(
    viewModel: TodayForestViewModel,
    state: TodayForestUiState,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("today_meal_summary"),
        shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
        colors = CardDefaults.cardColors(containerColor = Color(RebuildTokens.Cream50)),
    ) {
        Column(
            modifier = Modifier.padding(RebuildTokens.spacing[3].dp),
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(
                    RebuildTokens.spacing[1].dp,
                ),
            ) {
                Text(
                    text = "오늘의 점심",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    text = state.sourceLabel,
                    color = Color(RebuildTokens.Forest700),
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Start,
                )
            }
            val meal = state.meal
            when {
                meal != null -> {
                    meal.menuItems.forEach { item ->
                        val risk = viewModel.isAllergyRisk(item)
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(
                                RebuildTokens.spacing[2].dp,
                            ),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Box(
                                modifier = Modifier
                                    .padding(top = 7.dp)
                                    .size(7.dp)
                                    .background(
                                        if (risk) {
                                            Color(RebuildTokens.Danger700)
                                        } else {
                                            Color(RebuildTokens.Forest500)
                                        },
                                        CircleShape,
                                    ),
                            )
                            Text(
                                text = item.name,
                                style = MaterialTheme.typography.bodyLarge,
                                modifier = Modifier.semantics {
                                    contentDescription = if (risk) {
                                        "${item.name}, 알레르기 주의 메뉴"
                                    } else {
                                        item.name
                                    }
                                },
                            )
                        }
                    }
                    Text(
                        text = meal.calorie,
                        color = Color(RebuildTokens.Muted600),
                    )
                }
                state.isLoading -> Row(
                    modifier = Modifier.heightIn(min = RebuildTokens.minimumActionSize.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
                ) {
                    CircularProgressIndicator()
                    Text("급식을 확인하고 있어요.")
                }
                else -> Text(
                    text = state.message ?: "오늘 급식 정보가 아직 없어요.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = Color(RebuildTokens.Muted600),
                )
            }
        }
    }
}

private fun characterMessage(state: TodayForestUiState): String =
    when (state.motion) {
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.MealSuccess ->
            "멋진 만남이었어! 숲이 반짝이고 있어."
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.LevelUp ->
            "레벨 업! 새로운 잎이 자랐어."
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.Comfort ->
            "괜찮아. 오늘 만난 것만으로도 충분해."
        else -> "오늘 급식을 만나러 가 볼까?"
    }
