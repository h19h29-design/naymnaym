package com.h19h29.naymnaymlevelup.rebuild.growth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.mascot.MascotRestArt
import com.h19h29.naymnaymlevelup.rebuild.mascot.MascotRig
import com.h19h29.naymnaymlevelup.rebuild.mascot.MotionState
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun GrowthScreen(
    repository: GrowthRepository,
    policy: GrowthPolicy,
    modifier: Modifier = Modifier,
) {
    var snapshot by remember(repository) { mutableStateOf<GrowthSnapshot?>(null) }
    var loadFailed by remember(repository) { mutableStateOf(false) }

    LaunchedEffect(repository) {
        loadFailed = false
        runCatching { repository.load() }
            .onSuccess { snapshot = it }
            .onFailure { loadFailed = true }
    }

    when (val loaded = snapshot) {
        null -> GrowthLoadingState(loadFailed, modifier)
        else -> GrowthScreenContent(loaded, policy, modifier)
    }
}

@Composable
private fun GrowthLoadingState(
    loadFailed: Boolean,
    modifier: Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(RebuildTokens.spacing[4].dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (loadFailed) {
            Text("성장 기록을 불러오지 못했어요.")
        } else {
            CircularProgressIndicator()
            Text(
                text = "성장 기록을 불러오고 있어요.",
                modifier = Modifier.padding(top = RebuildTokens.spacing[2].dp),
            )
        }
    }
}

@Composable
fun GrowthScreenContent(
    snapshot: GrowthSnapshot,
    policy: GrowthPolicy,
    modifier: Modifier = Modifier,
) {
    val level = policy.level(snapshot.totalXp)
    val nextThreshold = policy.nextThreshold(snapshot.totalXp)

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .testTag("growth_screen")
            .background(
                Brush.verticalGradient(
                    listOf(
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.18f),
                    ),
                ),
            )
            .padding(horizontal = RebuildTokens.spacing[4].dp),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        item {
            Text(
                text = "나의 성장",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .padding(top = RebuildTokens.spacing[3].dp)
                    .semantics { heading() },
            )
        }
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("growth_current_character"),
                shape = RoundedCornerShape(RebuildTokens.radii[2].dp),
                colors = CardDefaults.cardColors(
                    containerColor = Color(RebuildTokens.Cream50),
                ),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(RebuildTokens.spacing[3].dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    MascotRig(
            level = level.coerceAtMost(7),
                        state = MotionState.Idle,
                        reduceMotion = false,
                        modifier = Modifier.size(188.dp),
                    )
                    Text(
                        text = policy.title(level),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = Color(RebuildTokens.Forest700),
                    )
                }
            }
        }
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("growth_progress"),
                shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
            ) {
                Column(
                    modifier = Modifier.padding(RebuildTokens.spacing[3].dp),
                    verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            text = "레벨 $level",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text("${snapshot.totalXp} XP")
                    }
                    LinearProgressIndicator(
                        progress = { policy.progress(snapshot.totalXp) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 8.dp),
                        color = Color(RebuildTokens.Forest500),
                        trackColor = Color(RebuildTokens.Leaf300).copy(alpha = 0.28f),
                    )
                    Text(
                        text = nextThreshold?.let {
                            "다음 성장까지 ${it - snapshot.totalXp} XP"
                        } ?: "모든 성장 단계를 열었어요!",
                        color = Color(RebuildTokens.Muted600),
                    )
                }
            }
        }
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("growth_next_unlock"),
                shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
                colors = CardDefaults.cardColors(
                    containerColor = Color(RebuildTokens.Cream100),
                ),
            ) {
                if (nextThreshold == null) {
                    Text(
                        text = "최고 레벨 달성",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(RebuildTokens.spacing[3].dp),
                    )
                } else {
                    val nextLevel = level + 1
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(RebuildTokens.spacing[3].dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
                    ) {
                        MascotRestArt(
                            level = nextLevel.coerceAtMost(7),
                            silhouetteColor = WarmLockedMascot,
                            modifier = Modifier.size(92.dp),
                        )
                        Column {
                            Text(
                                text = "다음 해금",
                                style = MaterialTheme.typography.labelLarge,
                                color = Color(RebuildTokens.Muted600),
                            )
                            Text(
                                text = policy.title(nextLevel),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                text = "$nextThreshold XP에 만나요",
                                color = LockedGrowthText,
                            )
                        }
                    }
                }
            }
        }
        item {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("growth_recent_events"),
                verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
            ) {
                Text(
                    text = "최근 성장 기록",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                if (snapshot.recentEvents.isEmpty()) {
                    Text(
                        text = "급식을 기록하면 성장 이야기가 여기에 쌓여요.",
                        color = Color(RebuildTokens.Muted600),
                    )
                } else {
                    snapshot.recentEvents.forEach { event ->
                        val presentation = GrowthEventPresentation.from(event)
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(containerColor = Color.White),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(RebuildTokens.spacing[3].dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = presentation.title,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Text(
                                        text = presentation.dateText,
                                        color = Color(RebuildTokens.Muted600),
                                    )
                                }
                                Text(
                                    text = presentation.xpText,
                                    color = Color(RebuildTokens.Forest700),
                                    fontWeight = FontWeight.Bold,
                                    textAlign = TextAlign.End,
                                )
                            }
                        }
                    }
                }
            }
        }
        item {
            Text(
                text = "성장은 천천히, 매일의 한 입으로",
                color = Color(RebuildTokens.Muted600),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = RebuildTokens.spacing[4].dp)
                    .semantics {
                        contentDescription = "성장은 천천히, 매일의 한 입으로"
                    },
            )
        }
    }
}

internal const val WarmLockedMascotArgb = 0xFFB87548L
internal const val LockedGrowthTextArgb = 0xFF1F5E43L
internal const val LockedGrowthSurfaceArgb = 0xFFFFF0DFL
internal val WarmLockedMascot = Color(WarmLockedMascotArgb)
internal val LockedGrowthText = Color(LockedGrowthTextArgb)
