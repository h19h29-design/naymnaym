package com.h19h29.naymnaymlevelup.rebuild.growth

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import com.h19h29.naymnaymlevelup.R
import com.h19h29.naymnaymlevelup.rebuild.ui.CompanionSectionBanner
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.mascot.MascotRestArt
import com.h19h29.naymnaymlevelup.rebuild.meal.RebuildContractReader
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

internal enum class CollectionSection(
    val label: String,
    val category: CollectionBadgeCategory?,
) {
    Characters("캐릭터 14", null),
    Nutrition("영양 탐험 12", CollectionBadgeCategory.nutrition),
    Challenge("식사 도전 12", CollectionBadgeCategory.challenge),
    Streak("꾸준함 12", CollectionBadgeCategory.streak),
}

@Composable
fun CollectionScreen(
    repository: CollectionRepository,
    policy: GrowthPolicy,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var progress by remember(repository) { mutableStateOf<CollectionProgress?>(null) }
    var loadFailed by remember(repository) { mutableStateOf(false) }
    var selectedSection by remember { mutableStateOf(CollectionSection.Characters) }

    LaunchedEffect(repository, context) {
        loadFailed = false
        runCatching {
            val snapshot = repository.loadCollection()
            CollectionProgress.evaluate(
                totalXp = snapshot.totalXp,
                records = snapshot.records,
                policyBytes = RebuildContractReader.readAsset(
                    context.assets,
                    "collection-policy.json",
                ),
            )
        }.onSuccess { progress = it }
            .onFailure { loadFailed = true }
    }

    when (val loadedProgress = progress) {
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
        else -> CollectionScreenContent(
            progress = loadedProgress,
            policy = policy,
            selectedSection = selectedSection,
            onSectionSelected = { selectedSection = it },
            modifier = modifier,
        )
    }
}

@Composable
internal fun CollectionScreenContent(
    progress: CollectionProgress,
    policy: GrowthPolicy,
    selectedSection: CollectionSection,
    onSectionSelected: (CollectionSection) -> Unit,
    modifier: Modifier = Modifier,
) {
    val unlockedLevel = policy.level(progress.totalXp)
    val unlockedCharacters = unlockedLevel.coerceAtMost(policy.thresholds.size)
    val totalCollected = unlockedCharacters + progress.collectedCount

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .testTag("collection_screen")
            .background(Color(0xFFF7F3FA))
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        item {
            CollectionHeader(
                totalCollected = totalCollected,
                progress = progress,
                unlockedLevel = unlockedLevel,
                modifier = Modifier.padding(top = RebuildTokens.spacing[3].dp),
            )
        }
        item {
            CollectionSectionSelector(
                selected = selectedSection,
                progress = progress,
                onSelected = onSectionSelected,
            )
        }
        if (selectedSection == CollectionSection.Characters) {
            policy.thresholds.chunked(2).forEachIndexed { row, thresholds ->
                item(key = "characters_$row") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(
                            RebuildTokens.spacing[3].dp,
                        ),
                    ) {
                        thresholds.forEachIndexed { index, threshold ->
                            val level = row * 2 + index + 1
                            CharacterTile(
                                level = level,
                                threshold = threshold,
                                title = policy.title(level),
                                isUnlocked = level <= unlockedLevel,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        if (thresholds.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
        } else {
            val category = checkNotNull(selectedSection.category)
            progress.badges(category).chunked(3).forEachIndexed { row, badges ->
                item(key = "badges_${category.name}_$row") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(
                            RebuildTokens.spacing[3].dp,
                        ),
                    ) {
                        badges.forEach { badge ->
                            BadgeTile(
                                badge = badge,
                                isEarned = badge.id in progress.earnedBadgeIds,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        repeat(3 - badges.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        item { Spacer(Modifier.height(RebuildTokens.spacing[4].dp)) }
    }
}

@Composable
private fun CollectionHeader(
    totalCollected: Int,
    progress: CollectionProgress,
    unlockedLevel: Int,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(RebuildTokens.radii[2].dp),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.94f)),
    ) {
        Column(
            modifier = Modifier,
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
        ) {
            CompanionSectionBanner("성장 도감", "한 입의 추억을 모아\n나만의 도감을 채워요.",
                Icons.Filled.AutoStories, accent = Color(0xFF825A9B))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        Color(0xFFF4EDFA),
                        RoundedCornerShape(RebuildTokens.radii[0].dp),
                    )
                    .padding(RebuildTokens.spacing[2].dp),
                horizontalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.AutoAwesome, null, tint = Color(RebuildTokens.Forest500), modifier = Modifier.size(22.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = "전체 수집 $totalCollected / 50",
                        fontWeight = FontWeight.Bold,
                        color = Color(RebuildTokens.Ink900),
                    )
                    Text(
                        text = "레벨 $unlockedLevel · 배지 ${progress.collectedCount} / 36",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(RebuildTokens.Muted600),
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionSectionSelector(
    selected: CollectionSection,
    progress: CollectionProgress,
    onSelected: (CollectionSection) -> Unit,
) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[2].dp),
    ) {
        CollectionSection.entries.forEach { section ->
            val isSelected = section == selected
            Text(
                text = section.label,
                fontWeight = FontWeight.Bold,
                color = if (isSelected) Color.White else Color(RebuildTokens.Forest700),
                modifier = Modifier
                    .heightIn(min = RebuildTokens.minimumActionSize.dp)
                    .background(
                        if (isSelected) Color(RebuildTokens.Forest700)
                        else Color(RebuildTokens.Cream100),
                        CircleShape,
                    )
                    .clickable { onSelected(section) }
                    .semantics {
                        contentDescription = if (section.category == null) {
                            "캐릭터 14개"
                        } else {
                            "${section.label}, ${progress.earnedCount(section.category)}개 획득"
                        }
                    }
                    .testTag("collection_section_${section.name.lowercase()}")
                    .padding(horizontal = RebuildTokens.spacing[3].dp),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun CharacterTile(
    level: Int,
    threshold: Int,
    title: String,
    isUnlocked: Boolean,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .semantics {
                contentDescription = if (isUnlocked) {
                    "레벨 $level 해금, $title"
                } else {
                    "레벨 $level 잠김, $threshold XP에 해금"
                }
            }
            .testTag(
                if (isUnlocked) "collection_level_${level}_unlocked"
                else "collection_level_${level}_locked_warm_silhouette",
            ),
        shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isUnlocked) Color.White else Color(LockedGrowthSurfaceArgb),
        ),
    ) {
        Column(
            modifier = Modifier.padding(RebuildTokens.spacing[2].dp),
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[1].dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(122.dp)
                    .background(
                        if (isUnlocked) Color(RebuildTokens.Cream100)
                        else Color(LockedGrowthSurfaceArgb),
                        RoundedCornerShape(RebuildTokens.radii[1].dp),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                if (isUnlocked) {
                    Image(painterResource(R.drawable.companion_forest_stage), null, Modifier.matchParentSize(), contentScale = ContentScale.Crop, alpha = 0.65f)
                }
                MascotRestArt(
                    level = level.coerceAtMost(7),
                    silhouetteColor = if (isUnlocked) null else WarmLockedMascot,
                    modifier = Modifier.fillMaxSize().padding(RebuildTokens.spacing[2].dp),
                )
                Icon(if (isUnlocked) Icons.Filled.CheckCircle else Icons.Filled.Lock, null,
                    tint = if (isUnlocked) Color(RebuildTokens.Forest500) else LockedGrowthText,
                    modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).background(Color.White, CircleShape).padding(6.dp).size(14.dp))
                if (level >= 8) {
                    Text(
                        text = stageSymbol(level),
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(RebuildTokens.spacing[1].dp)
                            .background(
                                if (isUnlocked) Color(RebuildTokens.Forest700)
                                else Color(LockedGrowthSurfaceArgb),
                                CircleShape,
                            )
                            .padding(6.dp),
                    )
                }
            }
            Text(
                text = "레벨 $level",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = Color(RebuildTokens.Muted600),
            )
            Text(
                text = if (isUnlocked) title else "아직 잠겨 있어요",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Ink900),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = if (isUnlocked) "해금 완료" else "$threshold XP에 해금",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = if (isUnlocked) Color(RebuildTokens.Forest700) else LockedGrowthText,
            )
        }
    }
}

@Composable
private fun BadgeTile(
    badge: CollectionBadge,
    isEarned: Boolean,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier
            .heightIn(min = 116.dp)
            .semantics {
                contentDescription = if (isEarned) {
                    "배지 획득, ${badge.title}"
                } else {
                    "잠긴 배지, ${badge.threshold}회 기록하면 해금"
                }
            }
            .testTag("collection_badge_${badge.id}_${if (isEarned) "earned" else "locked"}"),
        shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isEarned) Color.White else Color(LockedGrowthSurfaceArgb),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(RebuildTokens.spacing[2].dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[1].dp),
        ) {
            Text(
                text = badgeSymbol(badge.category),
                modifier = Modifier
                    .width(48.dp)
                    .height(48.dp)
                    .background(
                        if (isEarned) Color(RebuildTokens.Cream100)
                        else Color(LockedGrowthSurfaceArgb),
                        CircleShape,
                    )
                    .padding(12.dp),
                textAlign = TextAlign.Center,
            )
            Text(
                text = if (isEarned) badge.title else "잠긴 배지",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Ink900),
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private fun stageSymbol(level: Int): String = when (level) {
    in 8..9 -> "🍃"
    in 10..11 -> "🏅"
    in 12..13 -> "👑"
    else -> "✦"
}

private fun badgeSymbol(category: CollectionBadgeCategory): String = when (category) {
    CollectionBadgeCategory.nutrition -> "🍀"
    CollectionBadgeCategory.challenge -> "🍽"
    CollectionBadgeCategory.streak -> "🔥"
}
