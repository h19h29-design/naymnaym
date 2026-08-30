package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.meal.DifficultyReason
import com.h19h29.naymnaymlevelup.rebuild.meal.EatingStatus
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MealRecordingSheet(
    viewModel: TodayForestViewModel,
    onDismiss: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val scope = rememberCoroutineScope()
    var difficultItem by remember { mutableStateOf<MealItem?>(null) }
    var guardianItem by remember { mutableStateOf<MealItem?>(null) }
    val selectedReasons = remember { mutableStateListOf<DifficultyReason>() }
    val savedMenuNames = remember { mutableStateListOf<String>() }
    var feedback by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    fun save(
        item: MealItem,
        status: EatingStatus,
        reasons: List<DifficultyReason> = emptyList(),
    ) {
        if (saving) return
        saving = true
        scope.launch {
            runCatching {
                viewModel.record(item, status, reasons)
            }.onSuccess { result ->
                if (item.name !in savedMenuNames) savedMenuNames += item.name
                feedback = if (result.xpGranted > 0) {
                    "${item.name} 기록 완료 · ${result.xpGranted} XP"
                } else {
                    "${item.name} 기록을 저장했어요."
                }
                difficultItem = null
                selectedReasons.clear()
            }.onFailure {
                feedback = "기록을 저장하지 못했어요. 다시 시도해 주세요."
            }
            saving = false
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = RebuildTokens.spacing[4].dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = RebuildTokens.spacing[4].dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = if (difficultItem == null) "급식 기록" else "어려웠던 점",
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.heightIn(min = RebuildTokens.minimumActionSize.dp),
                ) {
                    Text("닫기")
                }
            }

            if (difficultItem != null) {
                DifficultyReasonStep(
                    item = requireNotNull(difficultItem),
                    selectedReasons = selectedReasons,
                    saving = saving,
                    onToggle = { reason ->
                        if (reason in selectedReasons) {
                            selectedReasons.remove(reason)
                        } else {
                            selectedReasons += reason
                        }
                        val ordered = TodayForestViewModel
                            .orderedDifficultyReasons(selectedReasons)
                        selectedReasons.clear()
                        selectedReasons.addAll(ordered)
                    },
                    onSave = {
                        save(
                            requireNotNull(difficultItem),
                            EatingStatus.DifficultToday,
                            selectedReasons.toList(),
                        )
                    },
                )
            } else {
                LazyColumn(
                    modifier = Modifier.padding(horizontal = RebuildTokens.spacing[4].dp),
                    verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[4].dp),
                ) {
                    feedback?.let { message ->
                        item {
                            Text(
                                text = message,
                                color = Color(RebuildTokens.Forest700),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(
                                        Color(RebuildTokens.Leaf300).copy(alpha = 0.28f),
                                        RoundedCornerShape(RebuildTokens.radii[0].dp),
                                    )
                                    .padding(RebuildTokens.spacing[3].dp)
                                    .testTag("meal_recording_feedback"),
                            )
                        }
                    }
                    item {
                        Text(
                            "사진은 선택 사항이에요. 이전에 저장한 급식판 사진 정보는 " +
                                "새 기록에도 그대로 유지돼요.",
                            color = Color(RebuildTokens.Muted600),
                        )
                    }
                    itemsIndexed(state.meal?.menuItems.orEmpty()) { index, item ->
                        MealItemCard(
                            item = item,
                            index = index,
                            viewModel = viewModel,
                            saved = item.name in savedMenuNames,
                            saving = saving,
                            onGuardianCheck = { guardianItem = item },
                            onStatus = { status ->
                                if (status == EatingStatus.DifficultToday) {
                                    difficultItem = item
                                    selectedReasons.clear()
                                } else {
                                    save(item, status)
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    guardianItem?.let { item ->
        AlertDialog(
            onDismissRequest = { guardianItem = null },
            confirmButton = {
                TextButton(
                    onClick = { guardianItem = null },
                    modifier = Modifier.heightIn(min = RebuildTokens.minimumActionSize.dp),
                ) {
                    Text("확인했어요")
                }
            },
            title = { Text("보호자와 먼저 확인해 주세요") },
            text = {
                Text(
                    "${item.name}은 선택한 알레르기와 관련될 수 있어요. " +
                        "학교 알레르기 안내와 보호자의 판단을 우선해 주세요.",
                )
            },
        )
    }
}

@Composable
private fun MealItemCard(
    item: MealItem,
    index: Int,
    viewModel: TodayForestViewModel,
    saved: Boolean,
    saving: Boolean,
    onGuardianCheck: () -> Unit,
    onStatus: (EatingStatus) -> Unit,
) {
    val risk = viewModel.isAllergyRisk(item)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("meal_item_$index"),
        shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
    ) {
        Column(
            modifier = Modifier.padding(RebuildTokens.spacing[3].dp),
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
        ) {
            Text(
                text = item.name + if (saved) " · 기록 완료" else "",
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
            if (risk) {
                AllergySafetyPanel(
                    enabled = !saving,
                    onAvoided = { onStatus(EatingStatus.AllergyAvoided) },
                    onGuardianCheck = onGuardianCheck,
                )
            }
            Text("어떻게 만났나요?", fontWeight = FontWeight.Bold)
            TodayForestViewModel.activeStatuses.forEach { status ->
                val enabled = viewModel.isStatusEnabled(status, item) && !saving
                OutlinedButton(
                    onClick = { onStatus(status) },
                    enabled = enabled,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = RebuildTokens.minimumActionSize.dp)
                        .testTag("status_${status.wireValue}")
                        .semantics {
                            contentDescription = if (enabled) {
                                "${item.name}을 ${status.childTitle} 상태로 기록"
                            } else {
                                "알레르기 주의 메뉴에서는 한입도전할 수 없습니다"
                            }
                        },
                    shape = RoundedCornerShape(RebuildTokens.radii[0].dp),
                ) {
                    Text(status.childTitle, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun AllergySafetyPanel(
    enabled: Boolean,
    onAvoided: () -> Unit,
    onGuardianCheck: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Color(RebuildTokens.Danger700).copy(alpha = 0.08f),
                RoundedCornerShape(RebuildTokens.radii[0].dp),
            )
            .padding(RebuildTokens.spacing[3].dp),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
    ) {
        Text(
            "⚠ 알레르기 안전을 먼저 확인해 주세요",
            color = Color(RebuildTokens.Danger700),
            fontWeight = FontWeight.Bold,
        )
        Text("먹기 권유보다 학교 안내와 보호자의 판단이 먼저예요.")
        Button(
            onClick = onAvoided,
            enabled = enabled,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = RebuildTokens.minimumActionSize.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color(RebuildTokens.Danger700),
            ),
        ) {
            Text(EatingStatus.AllergyAvoided.childTitle)
        }
        OutlinedButton(
            onClick = onGuardianCheck,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = RebuildTokens.minimumActionSize.dp),
        ) {
            Text("보호자와 확인하기")
        }
    }
}

@Composable
private fun DifficultyReasonStep(
    item: MealItem,
    selectedReasons: List<DifficultyReason>,
    saving: Boolean,
    onToggle: (DifficultyReason) -> Unit,
    onSave: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.padding(RebuildTokens.spacing[4].dp),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        item {
            Text(
                item.name,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
        }
        item {
            Text("어떤 점이 어려웠나요?", fontWeight = FontWeight.Bold)
        }
        items(TodayForestViewModel.difficultyReasonOrder.size) { index ->
            val reason = TodayForestViewModel.difficultyReasonOrder[index]
            OutlinedButton(
                onClick = { onToggle(reason) },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = RebuildTokens.minimumActionSize.dp)
                    .semantics {
                        contentDescription =
                            "${reason.childTitle}, " +
                            if (reason in selectedReasons) "선택됨" else "선택 안 됨"
                    },
            ) {
                Text(
                    (if (reason in selectedReasons) "✓ " else "") +
                        reason.childTitle,
                )
            }
        }
        item {
            Button(
                onClick = onSave,
                enabled = !saving,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = RebuildTokens.minimumActionSize.dp),
            ) {
                Text("이대로 기록하기")
            }
        }
    }
}

internal val EatingStatus.childTitle: String
    get() = when (this) {
        EatingStatus.Finished -> "다 먹었어요"
        EatingStatus.Half -> "반 정도 먹었어요"
        EatingStatus.OneBite -> "한 입 도전"
        EatingStatus.SmelledOnly -> "냄새만 맡았어요"
        EatingStatus.DifficultToday -> "오늘은 안 먹어요"
        EatingStatus.AllergyAvoided -> "알레르기로 피했어요"
    }

private val DifficultyReason.childTitle: String
    get() = when (this) {
        DifficultyReason.Smell -> "냄새"
        DifficultyReason.Texture -> "식감"
        DifficultyReason.Taste -> "맛"
        DifficultyReason.Appearance -> "모양"
        DifficultyReason.Other -> "기타"
        DifficultyReason.Spicy -> "매운맛"
        DifficultyReason.Color -> "색"
        DifficultyReason.NewFood -> "처음 보는 음식"
        DifficultyReason.Allergy -> "알레르기"
    }
