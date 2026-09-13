package com.h19h29.naymnaymlevelup.rebuild.child

import android.provider.Settings
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.R
import com.h19h29.naymnaymlevelup.rebuild.mascot.CompanionAnimation
import com.h19h29.naymnaymlevelup.rebuild.mascot.CompanionClip
import com.h19h29.naymnaymlevelup.rebuild.mascot.MascotRig
import com.h19h29.naymnaymlevelup.rebuild.mascot.MotionState
import kotlinx.coroutines.delay

// Prepared choices only. No network, stored conversation or growth mutations.
enum class CompanionTopic(val title: String, val reaction: CompanionClip) {
    Hello("안녕! 같이 놀자", CompanionClip.Greeting),
    Meal("오늘 한 입 먹어 봤어", CompanionClip.Encouraging),
    Difficult("먹기 어려운 반찬이 있어", CompanionClip.Listening),
    Allergy("알레르기가 걱정돼", CompanionClip.Listening),
    Growth("우리 얼마나 자랐지?", CompanionClip.Encouraging),
    Tired("오늘은 조금 지쳤어", CompanionClip.Listening);

    fun reply(turn: Int, level: Int): String {
        val alternate = turn % 2 != 0
        return when (this) {
            Hello -> if (alternate) "반가워! 오늘도 네 이야기를 들을 준비가 됐어." else "안녕! 잠깐 쉬면서 오늘 이야기를 나눠 보자."
            Meal -> if (alternate) "새로운 맛을 만나 봤구나! 어떤 느낌이었는지 천천히 떠올려 봐. 기록은 오늘 탭에서 할 수 있어." else "네 속도로 해 본 게 멋져! 많이 먹는 것보다 네 느낌을 알아가는 게 중요해."
            Difficult -> if (alternate) "맛이나 냄새, 식감이 낯설 수 있어. 지금 꼭 먹어야 하는 건 아니야. 어른에게 어떤 점이 어려운지 말해 봐." else "그럴 수 있어. 싫은 마음도 말해 줘서 고마워. 억지로 먹지 말고 믿을 수 있는 어른과 이야기해 보자."
            Allergy -> "알레르기가 걱정되는 음식은 먹어 보지 말고, 보호자나 선생님에게 먼저 확인해 줘. 나는 음식이 안전한지 판단할 수 없어. 몸이 불편하면 바로 어른에게 알려 줘."
            Growth -> "지금 우리는 레벨 ${level.coerceAtLeast(1)}이야! 성장 탭에서 함께 쌓은 기록을 볼 수 있어. 여기서 이야기하는 것만으로 경험치가 바뀌지는 않아."
            Tired -> if (alternate) "쉬어 가도 괜찮아. 오늘은 편안하게 숨을 고르고 네 몸의 이야기를 들어 보자." else "지친 날도 있지. 잘해야 한다는 부담은 잠깐 내려놓자. 힘들면 가까운 어른에게 이야기해 줘."
        }
    }
}

data class CompanionDialogue(val isUser: Boolean, val text: String)
data class CompanionConversation(val messages: List<CompanionDialogue> = emptyList(), val turn: Int = 0) {
    fun respond(topic: CompanionTopic, level: Int) = CompanionConversation(
        (messages + listOf(CompanionDialogue(true, topic.title), CompanionDialogue(false, topic.reply(turn, level)))).takeLast(12),
        turn + 1,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CompanionConversationSheet(level: Int, onDismiss: () -> Unit) {
    var conversation by remember { mutableStateOf(CompanionConversation()) }
    var selected by remember { mutableStateOf<CompanionTopic?>(null) }
    var clip by remember { mutableStateOf(CompanionClip.IdleBreathing) }
    var revision by remember { mutableLongStateOf(0L) }
    val context = LocalContext.current
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val reduced = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    val listState = rememberLazyListState()
    LaunchedEffect(selected) {
        val topic = selected ?: return@LaunchedEffect
        clip = CompanionClip.Thinking; revision++
        delay(1400)
        conversation = conversation.respond(topic, level)
        clip = topic.reaction; revision++
        selected = null
    }
    LaunchedEffect(conversation.turn) {
        if (conversation.turn > 0) listState.scrollToItem(conversation.messages.size)
    }
    LaunchedEffect(revision) {
        if (selected == null && clip != CompanionClip.IdleBreathing) {
            delay(4800)
            clip = CompanionClip.IdleBreathing; revision++
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(.92f).padding(horizontal = 16.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("냠냠이와 이야기", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("닫기") }
                }
                Box(Modifier.fillMaxWidth().height(if (largeText) 100.dp else 180.dp).clip(RoundedCornerShape(24.dp)), contentAlignment = Alignment.BottomCenter) {
                    Image(painterResource(R.drawable.companion_forest_stage), null, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
                    if (CompanionClip.supports(level)) CompanionAnimation(clip, reduced, revision, Modifier.size(if (largeText) 100.dp else 180.dp))
                    else MascotRig(level = level, state = MotionState.Idle, reduceMotion = reduced, playbackRevision = 0, isActive = true, modifier = Modifier.size(if (largeText) 100.dp else 180.dp))
                }
                Spacer(Modifier.height(12.dp))
                Text("선택형 대화 · 저장·전송하지 않아요", style = MaterialTheme.typography.bodyMedium)
        LazyColumn(state = listState, modifier = Modifier.fillMaxWidth().weight(1f).testTag("companion_conversation"), contentPadding = PaddingValues(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                if (conversation.messages.isEmpty()) {
                    Text("반가워! 오늘은 어떤 하루였어? 네 속도로 천천히 이야기해 줘.", style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(20.dp)).padding(14.dp))
                    Spacer(Modifier.height(12.dp))
                }
                Text("아래 문장을 골라 주세요. 대화는 저장·전송하지 않아요.", style = MaterialTheme.typography.bodySmall)
            }
            items(conversation.messages) { message ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (message.isUser) Arrangement.End else Arrangement.Start) {
                    Text(message.text, modifier = Modifier.fillMaxWidth(.9f).background(if (message.isUser) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(20.dp)).padding(14.dp), style = MaterialTheme.typography.bodyLarge)
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (selected != null) Text("대화 준비 중", style = MaterialTheme.typography.bodySmall)
                    CompanionTopic.entries.chunked(if (largeText) 1 else 2).forEach { topics ->
                      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        topics.forEach { topic ->
                        OutlinedButton(onClick = { selected = topic }, enabled = selected == null, modifier = Modifier.weight(1f).heightIn(min = 56.dp).testTag("companion_topic_${topic.name.lowercase()}")) {
                            Icon(Icons.Rounded.ChatBubbleOutline, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(topic.title, modifier = Modifier.weight(1f))
                        }
                        }
                      }
                    }
                }
            }
        }
        }
    }
}
