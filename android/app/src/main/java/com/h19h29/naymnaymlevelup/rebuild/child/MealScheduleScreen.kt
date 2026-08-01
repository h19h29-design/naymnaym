package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.h19h29.naymnaymlevelup.R
import com.h19h29.naymnaymlevelup.rebuild.meal.MealDay
import com.h19h29.naymnaymlevelup.rebuild.meal.MealItem
import com.h19h29.naymnaymlevelup.rebuild.meal.MealLoadState
import com.h19h29.naymnaymlevelup.rebuild.meal.MealRepository
import com.h19h29.naymnaymlevelup.rebuild.meal.School
import com.h19h29.naymnaymlevelup.rebuild.onboarding.AllergyCatalog
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class MealScheduleMode(val title: String) {
    Daily("일간"),
    Weekly("주간"),
    Monthly("월간"),
}

enum class MealScheduleRow(
    val title: String,
    val compactTitle: String,
) {
    Grain("밥/면", "밥"),
    Soup("국/탕", "국"),
    Side1("반찬 1", "찬1"),
    Side2("반찬 2", "찬2"),
    Kimchi("김치", "김치"),
    Beverage("음료", "음료"),
}

data class MealScheduleDisplayRow(
    val row: MealScheduleRow,
    val value: String,
)

data class MealScheduleMenuSlots(
    val grain: List<String>,
    val soup: List<String>,
    val side1: List<String>,
    val side2: List<String>,
    val kimchi: List<String>,
    val beverage: List<String>,
) {
    fun value(row: MealScheduleRow): String {
        val values = when (row) {
            MealScheduleRow.Grain -> grain
            MealScheduleRow.Soup -> soup
            MealScheduleRow.Side1 -> side1
            MealScheduleRow.Side2 -> side2
            MealScheduleRow.Kimchi -> kimchi
            MealScheduleRow.Beverage -> beverage
        }
        return values.takeIf(List<String>::isNotEmpty)
            ?.joinToString(separator = " · ")
            ?: "—"
    }

    val dailyRows: List<MealScheduleDisplayRow>
        get() = listOf(
            MealScheduleDisplayRow(
                MealScheduleRow.Grain,
                value(MealScheduleRow.Grain),
            ),
            MealScheduleDisplayRow(
                MealScheduleRow.Soup,
                value(MealScheduleRow.Soup),
            ),
            MealScheduleDisplayRow(
                MealScheduleRow.Side1,
                value(MealScheduleRow.Side1),
            ),
            MealScheduleDisplayRow(
                MealScheduleRow.Side2,
                (side2 + kimchi).takeIf(List<String>::isNotEmpty)
                    ?.joinToString(separator = " · ")
                    ?: "—",
            ),
            MealScheduleDisplayRow(
                MealScheduleRow.Beverage,
                value(MealScheduleRow.Beverage),
            ),
        )

    companion object {
        fun from(items: List<MealItem>): MealScheduleMenuSlots {
            val values = MealScheduleRow.entries.associateWith {
                mutableListOf<String>()
            }
            items.forEach { item ->
                val name = item.name.trim()
                if (name.isEmpty()) return@forEach
                val row = classify(name)
                val resolvedRow = if (
                    row == MealScheduleRow.Side1 &&
                    values.getValue(MealScheduleRow.Side1).isNotEmpty()
                ) {
                    MealScheduleRow.Side2
                } else {
                    row
                }
                values.getValue(resolvedRow).add(name)
            }
            return MealScheduleMenuSlots(
                grain = values.getValue(MealScheduleRow.Grain),
                soup = values.getValue(MealScheduleRow.Soup),
                side1 = values.getValue(MealScheduleRow.Side1),
                side2 = values.getValue(MealScheduleRow.Side2),
                kimchi = values.getValue(MealScheduleRow.Kimchi),
                beverage = values.getValue(MealScheduleRow.Beverage),
            )
        }

        fun classify(name: String): MealScheduleRow {
            val normalized = name.replace(" ", "")
            return when {
                normalized.containsAny(
                    "우유",
                    "요구르트",
                    "요거트",
                    "주스",
                    "쥬스",
                    "음료",
                ) -> MealScheduleRow.Beverage
                normalized.containsAny(
                    "김치",
                    "깍두기",
                    "석박지",
                    "겉절이",
                ) -> MealScheduleRow.Kimchi
                normalized.containsAny(
                    "국",
                    "탕",
                    "찌개",
                    "스프",
                    "전골",
                ) -> MealScheduleRow.Soup
                normalized.containsAny(
                    "밥",
                    "면",
                    "라이스",
                    "국수",
                    "우동",
                    "죽",
                    "떡국",
                    "수제비",
                    "카레",
                ) -> MealScheduleRow.Grain
                else -> MealScheduleRow.Side1
            }
        }

        private fun String.containsAny(vararg candidates: String): Boolean =
            candidates.any(::contains)
    }
}

object MealScheduleCalendar {
    private val zone = ZoneId.of("Asia/Seoul")

    fun today(): LocalDate = LocalDate.now(zone)

    fun weekDates(date: LocalDate): List<LocalDate> {
        val monday = date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        return (0L..4L).map(monday::plusDays)
    }

    fun monthWeekdays(date: LocalDate): List<LocalDate> {
        val monthStart = date.withDayOfMonth(1)
        val monthEnd = date.withDayOfMonth(date.lengthOfMonth())
        val start = monthStart.with(
            TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY),
        )
        val endingFriday = monthEnd.with(
            TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY),
        ).plusDays(4)
        return generateSequence(start) { current ->
            current.plusDays(1).takeIf { !it.isAfter(endingFriday) }
        }.filter { it.dayOfWeek.value in 1..5 }
            .toList()
    }

    fun shifted(
        date: LocalDate,
        mode: MealScheduleMode,
        direction: Int,
    ): LocalDate = when (mode) {
        MealScheduleMode.Daily -> date.plusDays(direction.toLong())
        MealScheduleMode.Weekly -> date.plusWeeks(direction.toLong())
        MealScheduleMode.Monthly -> date.plusMonths(direction.toLong())
    }
}

data class MealScheduleUiState(
    val meals: Map<String, MealDay> = emptyMap(),
    val isLoading: Boolean = false,
    val message: String? = null,
)

class MealScheduleViewModel(
    private val repository: MealRepository,
    private val school: School?,
) {
    val schoolName: String = school?.name ?: "학교 등록 전"

    private val mutableState = MutableStateFlow(MealScheduleUiState())
    val state: StateFlow<MealScheduleUiState> = mutableState.asStateFlow()

    fun meal(date: LocalDate): MealDay? = mutableState.value.meals[date.toString()]

    suspend fun load(dates: List<LocalDate>) = coroutineScope {
        val requests = dates.distinct()
        if (requests.isEmpty()) return@coroutineScope

        mutableState.value = mutableState.value.copy(
            isLoading = true,
            message = if (school == null) {
                "학교를 등록하면 최신 급식을 확인할 수 있어요."
            } else {
                null
            },
        )

        val results = requests.chunked(5).flatMap { batch ->
            batch.map { date ->
                async {
                    var loadState = repository.currentState(date.toString())
                    school?.let {
                        repository.refresh(date, it)
                        loadState = repository.currentState(date.toString())
                    }
                    MealScheduleLoadResult(
                        key = date.toString(),
                        meal = loadState.resolvedMeal(),
                        failed = loadState is MealLoadState.Failed,
                    )
                }
            }.awaitAll()
        }

        val updated = mutableState.value.meals.toMutableMap()
        results.forEach { result ->
            if (result.meal == null) {
                updated.remove(result.key)
            } else {
                updated[result.key] = result.meal
            }
        }
        mutableState.value = MealScheduleUiState(
            meals = updated,
            isLoading = false,
            message = when {
                school == null ->
                    "학교를 등록하면 최신 급식을 확인할 수 있어요."
                results.all(MealScheduleLoadResult::failed) ->
                    "급식을 불러오지 못했어요. 네트워크 연결을 확인해 주세요."
                else -> null
            },
        )
    }
}

private data class MealScheduleLoadResult(
    val key: String,
    val meal: MealDay?,
    val failed: Boolean,
)

private fun MealLoadState.resolvedMeal(): MealDay? = when (this) {
    is MealLoadState.Cached -> meal
    is MealLoadState.Live -> meal
    is MealLoadState.Refreshing -> cached
    is MealLoadState.Failed -> cached
    MealLoadState.Empty -> null
}

@Composable
fun MealScheduleScreen(
    viewModel: MealScheduleViewModel,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    var mode by remember { mutableStateOf(MealScheduleMode.Daily) }
    var anchorDate by remember { mutableStateOf(MealScheduleCalendar.today()) }
    var selectedDate by remember { mutableStateOf(anchorDate) }
    val visibleDates = remember(mode, anchorDate) {
        when (mode) {
            MealScheduleMode.Daily -> listOf(anchorDate)
            MealScheduleMode.Weekly -> MealScheduleCalendar.weekDates(anchorDate)
            MealScheduleMode.Monthly -> MealScheduleCalendar.monthWeekdays(anchorDate)
        }
    }

    LaunchedEffect(mode, anchorDate) {
        viewModel.load(visibleDates)
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(Color(RebuildTokens.Cream50))
            .padding(horizontal = 16.dp)
            .testTag("meal_schedule_screen"),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            MealScheduleHeader(
                schoolName = viewModel.schoolName,
                isLoading = state.isLoading,
                modifier = Modifier.padding(top = 14.dp),
            )
        }
        item {
            MealScheduleModeSelector(
                mode = mode,
                onModeSelected = {
                    mode = it
                    selectedDate = preferredSelectedDate(anchorDate, it)
                },
            )
        }
        item {
            MealSchedulePeriodNavigation(
                title = periodTitle(mode, anchorDate),
                onPrevious = {
                    val shifted = MealScheduleCalendar.shifted(
                        anchorDate,
                        mode,
                        -1,
                    )
                    anchorDate = shifted
                    selectedDate = preferredSelectedDate(shifted, mode)
                },
                onNext = {
                    val shifted = MealScheduleCalendar.shifted(
                        anchorDate,
                        mode,
                        1,
                    )
                    anchorDate = shifted
                    selectedDate = preferredSelectedDate(shifted, mode)
                },
            )
        }
        if (state.isLoading) {
            item {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = Color(RebuildTokens.Forest700),
                    )
                    Text(
                        text = "급식을 업데이트하고 있어요.",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(RebuildTokens.Forest700),
                    )
                }
            }
        }
        state.message?.let { message ->
            item { MealScheduleNotice(message) }
        }
        item {
            when (mode) {
                MealScheduleMode.Daily -> DailyMealSchedule(
                    meal = viewModel.meal(anchorDate),
                )
                MealScheduleMode.Weekly -> WeeklyMealSchedule(
                    dates = visibleDates,
                    selectedDate = selectedDate,
                    meal = viewModel::meal,
                    onSelected = { selectedDate = it },
                )
                MealScheduleMode.Monthly -> MonthlyMealSchedule(
                    dates = visibleDates,
                    displayedMonth = anchorDate.monthValue,
                    selectedDate = selectedDate,
                    meal = viewModel::meal,
                    onSelected = { selectedDate = it },
                )
            }
        }
        item { Spacer(Modifier.height(12.dp)) }
    }
}

@Composable
private fun MealScheduleHeader(
    schoolName: String,
    isLoading: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 124.dp)
            .clip(RoundedCornerShape(RebuildTokens.radii[2].dp))
            .border(
                width = 1.dp,
                color = Color(RebuildTokens.Forest500).copy(alpha = 0.18f),
                shape = RoundedCornerShape(RebuildTokens.radii[2].dp),
            ),
    ) {
        Image(
            painter = painterResource(R.drawable.forest_home_sky),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(RebuildTokens.Cream50).copy(alpha = 0.72f)),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = "급식표",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Ink900),
                modifier = Modifier.semantics { heading() },
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = schoolName,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                    color = Color(RebuildTokens.Forest700),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Surface(
                    color = Color.White.copy(alpha = 0.86f),
                    shape = CircleShape,
                ) {
                    Row(
                        modifier = Modifier.padding(
                            horizontal = 9.dp,
                            vertical = 6.dp,
                        ),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = if (isLoading) {
                                Icons.Filled.Sync
                            } else {
                                Icons.Filled.CheckCircle
                            },
                            contentDescription = null,
                            tint = Color(RebuildTokens.Forest500),
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            text = if (isLoading) "업데이트 중" else "업데이트됨",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(RebuildTokens.Forest500),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MealScheduleModeSelector(
    mode: MealScheduleMode,
    onModeSelected: (MealScheduleMode) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.9f))
            .border(
                1.dp,
                Color(RebuildTokens.Forest500).copy(alpha = 0.2f),
                CircleShape,
            )
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        MealScheduleMode.entries.forEach { item ->
            val selected = mode == item
            Box(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 38.dp)
                    .clip(CircleShape)
                    .background(
                        if (selected) {
                            Color(RebuildTokens.Forest700)
                        } else {
                            Color.Transparent
                        },
                    )
                    .clickable { onModeSelected(item) }
                    .testTag("meal_schedule_mode_${item.name.lowercase()}"),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = item.title,
                    fontWeight = FontWeight.Bold,
                    color = if (selected) {
                        Color.White
                    } else {
                        Color(RebuildTokens.Muted600)
                    },
                )
            }
        }
    }
}

@Composable
private fun MealSchedulePeriodNavigation(
    title: String,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = RebuildTokens.minimumActionSize.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PeriodArrow(Icons.Filled.ChevronLeft, "이전 기간", onPrevious)
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = Color(RebuildTokens.Ink900),
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        PeriodArrow(Icons.Filled.ChevronRight, "다음 기간", onNext)
    }
}

@Composable
private fun PeriodArrow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(RebuildTokens.minimumActionSize.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = description,
            tint = Color(RebuildTokens.Forest700),
        )
    }
}

@Composable
private fun DailyMealSchedule(meal: MealDay?) {
    val slots = MealScheduleMenuSlots.from(meal?.menuItems.orEmpty())
    MealScheduleCard(
        modifier = Modifier.testTag("meal_schedule_daily"),
    ) {
        Text(
            text = "오늘의 메뉴",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = Color(RebuildTokens.Forest500),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(RebuildTokens.radii[0].dp))
                .border(
                    1.dp,
                    Color(RebuildTokens.Forest500).copy(alpha = 0.2f),
                    RoundedCornerShape(RebuildTokens.radii[0].dp),
                ),
        ) {
            slots.dailyRows.forEachIndexed { index, display ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            if (index % 2 == 0) {
                                Color(RebuildTokens.Cream50).copy(alpha = 0.7f)
                            } else {
                                Color.White
                            },
                        )
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .background(
                                Color(RebuildTokens.Leaf300).copy(alpha = 0.22f),
                                CircleShape,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = display.row.compactTitle,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(RebuildTokens.Forest700),
                        )
                    }
                    Text(
                        text = display.row.title,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color(RebuildTokens.Forest700),
                        modifier = Modifier.width(58.dp),
                    )
                    Text(
                        text = display.value,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = if (display.value == "—") {
                            Color(RebuildTokens.Muted600)
                        } else {
                            Color(RebuildTokens.Ink900)
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
                if (index < slots.dailyRows.lastIndex) {
                    Spacer(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(
                                Color(RebuildTokens.Forest500).copy(alpha = 0.16f),
                            ),
                    )
                }
            }
        }
        Text(
            text = "영양 정보",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = Color(RebuildTokens.Forest500),
        )
        NutritionSummary(meal?.let(::listOf).orEmpty())
        AllergySummary(meal)
    }
}

@Composable
private fun WeeklyMealSchedule(
    dates: List<LocalDate>,
    selectedDate: LocalDate,
    meal: (LocalDate) -> MealDay?,
    onSelected: (LocalDate) -> Unit,
) {
    MealScheduleCard(
        modifier = Modifier.testTag("meal_schedule_weekly"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "이번 주 메뉴",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Forest500),
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = "요일별 메뉴를 한눈에 비교",
                fontSize = 10.sp,
                color = Color(RebuildTokens.Muted600),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(RebuildTokens.radii[0].dp)),
        ) {
            Row {
                Box(Modifier.width(52.dp).height(50.dp))
                dates.forEach { date ->
                    val selected = date == selectedDate
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .height(50.dp)
                            .background(
                                if (selected) {
                                    Color(RebuildTokens.Forest700)
                                } else {
                                    Color.White
                                },
                            )
                            .clickable { onSelected(date) }
                            .mealScheduleCellBorder(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(
                            text = date.format(weekdayFormatter),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (selected) {
                                Color.White
                            } else {
                                Color(RebuildTokens.Forest700)
                            },
                        )
                        Text(
                            text = date.format(shortDateFormatter),
                            fontSize = 9.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (selected) {
                                Color.White
                            } else {
                                Color(RebuildTokens.Muted600)
                            },
                        )
                    }
                }
            }
            MealScheduleRow.entries.forEach { row ->
                Row {
                    Box(
                        modifier = Modifier
                            .width(52.dp)
                            .heightIn(min = 58.dp)
                            .background(
                                Color(RebuildTokens.Cream50).copy(alpha = 0.72f),
                            )
                            .mealScheduleCellBorder(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = row.compactTitle,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(RebuildTokens.Forest700),
                        )
                    }
                    dates.forEach { date ->
                        val selected = date == selectedDate
                        val value = MealScheduleMenuSlots.from(
                            meal(date)?.menuItems.orEmpty(),
                        ).value(row)
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 58.dp)
                                .background(
                                    if (selected) {
                                        Color(RebuildTokens.Leaf300)
                                            .copy(alpha = 0.2f)
                                    } else {
                                        Color.White
                                    },
                                )
                                .clickable { onSelected(date) }
                                .mealScheduleCellBorder()
                                .padding(horizontal = 2.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = value,
                                fontSize = 9.sp,
                                lineHeight = 12.sp,
                                fontWeight = if (selected) {
                                    FontWeight.Bold
                                } else {
                                    FontWeight.Medium
                                },
                                color = if (selected) {
                                    Color(RebuildTokens.Forest700)
                                } else {
                                    Color(RebuildTokens.Ink900)
                                },
                                textAlign = TextAlign.Center,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
        SelectedMealInformation(selectedDate = selectedDate, meal = meal(selectedDate))
    }
}

@Composable
private fun MonthlyMealSchedule(
    dates: List<LocalDate>,
    displayedMonth: Int,
    selectedDate: LocalDate,
    meal: (LocalDate) -> MealDay?,
    onSelected: (LocalDate) -> Unit,
) {
    MealScheduleCard(
        modifier = Modifier.testTag("meal_schedule_monthly"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "${displayedMonth}월 급식 달력",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Forest500),
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = "선택 전에도 대표 메뉴 표시",
                fontSize = 10.sp,
                color = Color(RebuildTokens.Muted600),
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(RebuildTokens.radii[0].dp)),
        ) {
            Row {
                listOf("월", "화", "수", "목", "금").forEach { day ->
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(36.dp)
                            .background(Color.White)
                            .mealScheduleCellBorder(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = day,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(RebuildTokens.Forest700),
                        )
                    }
                }
            }
            dates.chunked(5).forEach { week ->
                Row {
                    week.forEach { date ->
                        val selected = date == selectedDate
                        val dayMeal = meal(date)
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 82.dp)
                                .background(
                                    if (selected) {
                                        Color(RebuildTokens.Leaf300)
                                            .copy(alpha = 0.22f)
                                    } else {
                                        Color.White
                                    },
                                )
                                .mealScheduleCellBorder()
                                .clickable { onSelected(date) }
                                .semantics {
                                    contentDescription = buildString {
                                        append(date.format(fullDateFormatter))
                                        append(", ")
                                        append(
                                            dayMeal?.menuItems
                                                ?.joinToString { it.name }
                                                ?: "급식 정보 없음",
                                        )
                                    }
                                }
                                .padding(5.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Text(
                                text = date.dayOfMonth.toString(),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = when {
                                    selected -> Color(RebuildTokens.Forest500)
                                    date.monthValue != displayedMonth ->
                                        Color(RebuildTokens.Muted600).copy(alpha = 0.45f)
                                    else -> Color(RebuildTokens.Forest700)
                                },
                            )
                            dayMeal?.menuItems?.take(3)?.forEach { item ->
                                Text(
                                    text = item.name,
                                    fontSize = 9.sp,
                                    lineHeight = 11.sp,
                                    fontWeight = if (selected) {
                                        FontWeight.Bold
                                    } else {
                                        FontWeight.Medium
                                    },
                                    color = if (selected) {
                                        Color(RebuildTokens.Forest700)
                                    } else {
                                        Color(RebuildTokens.Ink900)
                                    },
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            if (dayMeal == null) {
                                Text(
                                    text = "정보 없음",
                                    fontSize = 9.sp,
                                    color = Color(RebuildTokens.Muted600),
                                    maxLines = 1,
                                )
                            }
                        }
                    }
                }
            }
        }
        SelectedMealInformation(selectedDate = selectedDate, meal = meal(selectedDate))
    }
}

@Composable
private fun SelectedMealInformation(
    selectedDate: LocalDate,
    meal: MealDay?,
) {
    Column(
        modifier = Modifier.testTag("meal_schedule_selected_information_${selectedDate}"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "선택한 날짜의 영양 정보",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Forest500),
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = selectedDate.format(fullDateFormatter),
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color(RebuildTokens.Muted600),
            )
        }
        if (meal == null) {
            Text(
                text = "해당 날짜의 영양 정보가 없어요.",
                style = MaterialTheme.typography.bodyMedium,
                color = Color(RebuildTokens.Muted600),
                modifier = Modifier.heightIn(min = RebuildTokens.minimumActionSize.dp),
            )
        } else {
            NutritionSummary(listOf(meal))
            AllergySummary(meal)
        }
    }
}

@Composable
private fun NutritionSummary(meals: List<MealDay>) {
    val tiles = remember(meals) { nutritionTiles(meals) }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        tiles.forEach { tile ->
            Column(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 52.dp)
                    .background(
                        Color(RebuildTokens.Cream50).copy(alpha = 0.9f),
                        RoundedCornerShape(RebuildTokens.radii[0].dp),
                    )
                    .border(
                        1.dp,
                        Color(RebuildTokens.Forest500).copy(alpha = 0.18f),
                        RoundedCornerShape(RebuildTokens.radii[0].dp),
                    )
                    .padding(horizontal = 2.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = tile.title,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color(RebuildTokens.Muted600),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = tile.value,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (tile.title == "열량") {
                        Color(0xFFEB6B2E)
                    } else {
                        Color(RebuildTokens.Ink900)
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun AllergySummary(meal: MealDay?) {
    val codes = meal?.menuItems
        ?.flatMap(MealItem::allergyCodes)
        ?.distinct()
        ?.sorted()
        .orEmpty()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Color(RebuildTokens.Leaf300).copy(alpha = 0.2f),
                RoundedCornerShape(RebuildTokens.radii[0].dp),
            )
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row {
            Text(
                text = "알레르기 정보",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = Color(RebuildTokens.Forest700),
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = "번호와 이름을 함께 표시",
                fontSize = 10.sp,
                color = Color(RebuildTokens.Muted600),
            )
        }
        if (codes.isEmpty()) {
            Text(
                text = "표시된 알레르기 정보가 없어요.",
                style = MaterialTheme.typography.bodySmall,
                color = Color(RebuildTokens.Muted600),
            )
        } else {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                codes.forEach { code ->
                    Text(
                        text = AllergyCatalog.label(code),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFFA35914),
                        modifier = Modifier
                            .background(
                                Color(0xFFFFF0E0),
                                CircleShape,
                            )
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun MealScheduleCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(RebuildTokens.radii[1].dp),
        colors = CardDefaults.cardColors(
            containerColor = Color.White.copy(alpha = 0.94f),
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content,
        )
    }
}

@Composable
private fun MealScheduleNotice(message: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Color(RebuildTokens.Leaf300).copy(alpha = 0.22f),
                RoundedCornerShape(RebuildTokens.radii[0].dp),
            )
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.Info,
            contentDescription = null,
            tint = Color(RebuildTokens.Forest700),
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodySmall,
            color = Color(RebuildTokens.Ink900),
        )
    }
}

private fun Modifier.mealScheduleCellBorder(): Modifier = border(
    width = 0.5.dp,
    color = Color(RebuildTokens.Forest500).copy(alpha = 0.16f),
)

private data class NutritionTile(
    val title: String,
    val value: String,
)

private fun nutritionTiles(meals: List<MealDay>): List<NutritionTile> {
    val calories = meals.mapNotNull { meal ->
        Regex("""[\d.]+""").find(meal.calorie)?.value?.toDoubleOrNull()
    }
    val calorieAverage = calories.takeIf(List<Double>::isNotEmpty)?.average()
    fun average(value: (MealDay) -> Double): Int? =
        meals.takeIf(List<MealDay>::isNotEmpty)
            ?.map(value)
            ?.average()
            ?.roundToInt()

    return listOf(
        NutritionTile(
            "열량",
            calorieAverage?.roundToInt()?.let { "$it kcal" } ?: "—",
        ),
        NutritionTile(
            "단백질",
            average { it.nutrition.protein }?.let { "$it g" } ?: "—",
        ),
        NutritionTile(
            "탄수화물",
            average { it.nutrition.carbs }?.let { "$it g" } ?: "—",
        ),
        NutritionTile(
            "지방",
            average { it.nutrition.fat }?.let { "$it g" } ?: "—",
        ),
        NutritionTile(
            "칼슘",
            average { it.nutrition.calcium }?.let { "$it mg" } ?: "—",
        ),
    )
}

private fun periodTitle(
    mode: MealScheduleMode,
    date: LocalDate,
): String = when (mode) {
    MealScheduleMode.Daily -> date.format(fullDateFormatter)
    MealScheduleMode.Weekly -> {
        val dates = MealScheduleCalendar.weekDates(date)
        "${dates.first().format(monthDayFormatter)} – " +
            dates.last().format(monthDayFormatter)
    }
    MealScheduleMode.Monthly -> date.format(monthFormatter)
}

private fun preferredSelectedDate(
    anchor: LocalDate,
    mode: MealScheduleMode,
): LocalDate = when (mode) {
    MealScheduleMode.Daily -> anchor
    MealScheduleMode.Weekly -> MealScheduleCalendar.weekDates(anchor)
        .firstOrNull { it == anchor }
        ?: MealScheduleCalendar.weekDates(anchor).first()
    MealScheduleMode.Monthly -> MealScheduleCalendar.monthWeekdays(anchor)
        .firstOrNull { it == anchor }
        ?: MealScheduleCalendar.monthWeekdays(anchor).first()
}

private val fullDateFormatter = DateTimeFormatter.ofPattern(
    "yyyy년 M월 d일",
    Locale.KOREAN,
)
private val monthDayFormatter = DateTimeFormatter.ofPattern(
    "M월 d일",
    Locale.KOREAN,
)
private val monthFormatter = DateTimeFormatter.ofPattern(
    "yyyy년 M월",
    Locale.KOREAN,
)
private val weekdayFormatter = DateTimeFormatter.ofPattern("E", Locale.KOREAN)
private val shortDateFormatter = DateTimeFormatter.ofPattern("M/d", Locale.KOREAN)
