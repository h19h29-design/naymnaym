package com.h19h29.naymnaymlevelup.rebuild.growth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.mascot.MascotRestArt
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun CollectionScreen(
    repository: GrowthRepository,
    policy: GrowthPolicy,
    modifier: Modifier = Modifier,
) {
    var totalXp by remember(repository) { mutableStateOf<Int?>(null) }
    var loadFailed by remember(repository) { mutableStateOf(false) }

    LaunchedEffect(repository) {
        loadFailed = false
        runCatching { repository.load(limit = 0).totalXp }
            .onSuccess { totalXp = it }
            .onFailure { loadFailed = true }
    }

    when (val loadedXp = totalXp) {
        null -> Column(
            modifier = modifier
                .fillMaxSize()
                .padding(RebuildTokens.spacing[4].dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            if (loadFailed) {
                Text("도감을 불러오지 못했어요.")
            } else {
                CircularProgressIndicator()
            }
        }
        else -> CollectionScreenContent(loadedXp, policy, modifier)
    }
}

@Composable
fun CollectionScreenContent(
    totalXp: Int,
    policy: GrowthPolicy,
    modifier: Modifier = Modifier,
) {
    val unlockedLevel = policy.level(totalXp)

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .testTag("collection_screen")
            .padding(horizontal = RebuildTokens.spacing[4].dp),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        item {
            Column(
                modifier = Modifier.padding(top = RebuildTokens.spacing[3].dp),
                verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[1].dp),
            ) {
                Text(
                    text = "성장 도감",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    text = "지금까지 만난 모습과 앞으로 만날 친구들이에요.",
                    color = Color(RebuildTokens.Muted600),
                )
            }
        }

        items(7) { index ->
            val level = index + 1
            val unlocked = level <= unlockedLevel
            val threshold = policy.thresholds[index]
            val tag = if (unlocked) {
                "collection_level_${level}_unlocked"
            } else {
                "collection_level_${level}_locked_warm_silhouette"
            }
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(tag)
                    .semantics {
                        contentDescription = if (unlocked) {
                            "레벨 $level 해금, ${policy.title(level)}"
                        } else {
                            "레벨 $level 잠김, $threshold XP에 해금"
                        }
                    },
                shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (unlocked) {
                        Color.White
                    } else {
                        Color(LockedGrowthSurfaceArgb)
                    },
                ),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(RebuildTokens.spacing[3].dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
                ) {
                    MascotRestArt(
                        level = level,
                        silhouetteColor = if (unlocked) null else WarmLockedMascot,
                        modifier = Modifier.size(112.dp),
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[1].dp),
                    ) {
                        Text(
                            text = "레벨 $level",
                            style = MaterialTheme.typography.labelLarge,
                            color = Color(RebuildTokens.Muted600),
                        )
                        Text(
                            text = if (unlocked) policy.title(level) else "아직 잠겨 있어요",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = if (unlocked) {
                                "해금 완료"
                            } else {
                                "잠금 · $threshold XP에 해금"
                            },
                            color = if (unlocked) {
                                Color(RebuildTokens.Forest700)
                            } else {
                                LockedGrowthText
                            },
                        )
                    }
                }
            }
        }
        item {
            Text(
                text = "총 $totalXp XP",
                color = Color(RebuildTokens.Muted600),
                modifier = Modifier.padding(bottom = RebuildTokens.spacing[4].dp),
            )
        }
    }
}
