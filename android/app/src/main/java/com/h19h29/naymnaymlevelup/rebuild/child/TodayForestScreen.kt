package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Restaurant
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Eco
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.sp
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
import com.h19h29.naymnaymlevelup.R
import com.h19h29.naymnaymlevelup.rebuild.onboarding.AllergyCatalog

@Composable
fun TodayForestScreen(
    viewModel: TodayForestViewModel,
    growthPolicy: GrowthPolicy,
    isTabActive: Boolean = true,
    isAppActive: Boolean = true,
    modifier: Modifier = Modifier,
    profileKey: String = "local",
    schoolKey: String = "unregistered",
    dailyMealReviewStore: DailyMealReviewRepository? = null,
) {
    val state by viewModel.state.collectAsState()
    var showRecorder by remember { mutableStateOf(false) }
    var showConversation by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    var shownMotionRevision by remember { mutableLongStateOf(state.motionRevision) }

    LaunchedEffect(state.motionRevision, showRecorder) {
        if (!showRecorder && state.motionRevision > shownMotionRevision) {
            listState.scrollToItem(1)
            shownMotionRevision = state.motionRevision
        }
    }

    LaunchedEffect(viewModel) {
        viewModel.load()
    }

    ForestScene(
        reduceMotion = false,
        activity = ForestSceneActivity(
            isSheetPresented = showRecorder || showConversation,
            isTabActive = isTabActive,
            isAppActive = isAppActive,
        ),
        modifier = modifier.fillMaxSize(),
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp)
                .testTag("today_forest_list"),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Row(
                    modifier = Modifier
                        .padding(top = RebuildTokens.spacing[3].dp)
                        .fillMaxWidth()
                        .background(
                            Color(RebuildTokens.Cream50),
                            RoundedCornerShape(RebuildTokens.radii[1].dp),
                        )
                        .padding(RebuildTokens.spacing[3].dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "급식레벨업",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = Color(RebuildTokens.Ink900),
                        modifier = Modifier
                            .testTag("today_title")
                            .semantics { heading() },
                    )
                    Text("한 입씩, 쑥쑥 자라는 하루", style = MaterialTheme.typography.labelSmall, color = Color(RebuildTokens.Forest700))
                    }
                    Text(
                        text = viewModel.dateText,
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(RebuildTokens.Muted600),
                        modifier = Modifier.semantics {
                            contentDescription = "날짜 ${viewModel.dateText}"
                        },
                    )
                }
            }

            item {
                CharacterStage(
                    state = state,
                    growthPolicy = growthPolicy,
                    isActive = isTabActive && isAppActive && !showRecorder && !showConversation,
                    onConversation = { showConversation = true },
                    dailyReviewContent = {
                        val meal = state.meal
                        if (meal != null && dailyMealReviewStore != null) {
                            DailyMealReviewEntry(
                                meal = meal,
                                profileKey = profileKey,
                                schoolKey = schoolKey,
                                registeredAllergyCodes = viewModel.allergyCodes,
                                store = dailyMealReviewStore,
                                modifier = Modifier.padding(horizontal = 12.dp),
                            )
                        }
                    },
                )
            }

            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    HomeStat("오늘 메뉴", "${state.meal?.menuItems?.size ?: 0}가지", Icons.Rounded.Restaurant, Color(0xFFE28C3A), Modifier.weight(1f))
                    HomeStat("나의 주의", "${state.meal?.menuItems?.count(viewModel::isAllergyRisk) ?: 0}개", Icons.Rounded.Shield, Color(RebuildTokens.Forest700), Modifier.weight(1f))
                    HomeStat("차곡차곡", "${state.totalXP} XP", Icons.Rounded.Star, Color(0xFFC48420), Modifier.weight(1f))
                }
            }

            item {
                Card(
                    shape = RoundedCornerShape(22.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    border = BorderStroke(1.dp, Color(0xFFF4DBCC)),
                ) {
                  Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text("오늘의 한 입 미션", fontWeight = FontWeight.Bold)
                            Text("한 입씩, 나만의 속도로!", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                            Text("먹은 만큼 솔직하게 기록해요.", style = MaterialTheme.typography.labelSmall, color = Color(RebuildTokens.Muted600))
                        }
                        Image(painterResource(R.drawable.companion_lunch_tray), null, Modifier.size(86.dp))
                    }
                Button(
                    onClick = { showRecorder = true },
                    enabled = state.primaryActionEnabled,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = RebuildTokens.minimumActionSize.dp)
                        .testTag("today_primary_action"),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFF5634F),
                        contentColor = Color.White,
                        disabledContainerColor = Color(RebuildTokens.Muted600),
                        disabledContentColor = Color(RebuildTokens.Cream50),
                    ),
                    shape = RoundedCornerShape(24.dp),
                ) {
                    Icon(Icons.Rounded.Restaurant, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = viewModel.primaryActionTitle,
                        style = MaterialTheme.typography.labelLarge,
                        textAlign = TextAlign.Center,
                    )
                }
                  }
                }
            }

            item { MealSummary(viewModel, state) }

            item { Spacer(Modifier.height(RebuildTokens.spacing[3].dp)) }
        }
    }

    if (showRecorder) {
        MealRecordingSheet(
            viewModel = viewModel,
            onDismiss = { showRecorder = false },
        )
    }
    if (showConversation) {
        CompanionConversationSheet(growthPolicy.level(state.totalXP)) { showConversation = false }
    }
}

@Composable
private fun HomeStat(title: String, value: String, icon: ImageVector, color: Color, modifier: Modifier) {
    Card(modifier, shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = Color.White), border = BorderStroke(1.dp, Color(0xFFF0DEC9))) {
        Column(Modifier.fillMaxWidth().padding(vertical = 11.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(icon, null, Modifier.size(14.dp), tint = color)
                Text(title, style = MaterialTheme.typography.labelSmall, color = color)
            }
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun CharacterStage(
    state: TodayForestUiState,
    growthPolicy: GrowthPolicy,
    isActive: Boolean,
    onConversation: () -> Unit,
    dailyReviewContent: @Composable () -> Unit = {},
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
        border = BorderStroke(2.dp, Color.White),
    ) {
        Column {
          Box(Modifier.fillMaxWidth().height(238.dp)) {
            Image(painterResource(R.drawable.companion_forest_stage), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            MascotRig(
                level = level.coerceAtMost(7),
                state = state.motion.toMascotMotionState(),
                reduceMotion = false,
                playbackRevision = state.motionRevision,
                isActive = isActive,
                modifier = Modifier.size(234.dp).align(Alignment.BottomStart),
            )
            Row(Modifier.padding(12.dp).align(Alignment.TopStart).background(Color.White.copy(alpha = .94f), RoundedCornerShape(24.dp)).padding(horizontal = 10.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Eco, null, Modifier.size(14.dp), tint = Color(RebuildTokens.Forest700))
                Text(growthPolicy.title(level), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = Color(RebuildTokens.Forest700))
            }
            Text(
                text = characterMessage(state),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color(RebuildTokens.Ink900),
                textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.TopEnd).padding(top = 55.dp, end = 12.dp).width(126.dp).background(Color.White.copy(alpha = .96f), RoundedCornerShape(18.dp)).padding(11.dp),
            )
          }
          Button(onClick = onConversation, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp).testTag("companion_open_conversation")) {
              Text("냠냠이와 이야기하기")
          }
          dailyReviewContent()
          Row(Modifier.fillMaxWidth().background(Color.White).padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Lv.$level", fontSize = 21.sp, fontWeight = FontWeight.ExtraBold, color = Color(RebuildTokens.Forest700))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            LinearProgressIndicator(
                progress = { growthPolicy.progress(state.totalXP) },
                modifier = Modifier.fillMaxWidth(),
                color = Color(RebuildTokens.Forest500),
                trackColor = Color(RebuildTokens.Cream100),
            )
            Text(growthPolicy.thresholds.getOrNull(level)?.let { "EXP ${state.totalXP} / $it" } ?: "최고 레벨 달성 · ${state.totalXP} XP", style = MaterialTheme.typography.labelSmall, color = Color(RebuildTokens.Muted600))
            }
          }
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
                    meal.menuItems.chunked(2).forEach { pair ->
                      Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                       pair.forEach { item ->
                        val risk = viewModel.isAllergyRisk(item)
                        Column(
                            modifier = Modifier.weight(1f).background(if (risk) Color(0xFFFFEDE8) else Color(0xFFFAF7ED), RoundedCornerShape(14.dp)).padding(10.dp),
                            verticalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            Text(
                                text = item.name,
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.semantics {
                                    contentDescription = if (risk) {
                                        "${item.name}, 알레르기 주의 메뉴"
                                    } else {
                                        item.name
                                    }
                                },
                            )
                            if (risk) {
                                val matches = item.allergyCodes.filter(viewModel.allergyCodes::contains)
                                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Icon(Icons.Rounded.Shield, null, Modifier.size(14.dp), tint = Color(RebuildTokens.Danger700))
                                    Text("${AllergyCatalog.summary(matches)} 주의", style = MaterialTheme.typography.labelSmall, color = Color(RebuildTokens.Danger700))
                                }
                            }
                        }
                       }
                       if (pair.size == 1) Spacer(Modifier.weight(1f))
                      }
                    }
                    Text(
                        text = meal.calorie,
                        color = Color(RebuildTokens.Muted600),
                    )
                    Text("전체 영양·알레르기 정보는 급식 상세에서 확인해요.", style = MaterialTheme.typography.labelSmall, color = Color(RebuildTokens.Muted600))
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
