package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.zIndex
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.growth.CollectionScreen
import com.h19h29.naymnaymlevelup.rebuild.growth.GrowthPolicyLoader
import com.h19h29.naymnaymlevelup.rebuild.growth.GrowthRepository
import com.h19h29.naymnaymlevelup.rebuild.growth.GrowthScreen
import com.h19h29.naymnaymlevelup.rebuild.growth.RoomGrowthProgressSource
import com.h19h29.naymnaymlevelup.rebuild.meal.MealRepository
import com.h19h29.naymnaymlevelup.rebuild.meal.NeisMealClient
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealUseCase
import com.h19h29.naymnaymlevelup.rebuild.meal.RoomMealDayStore
import com.h19h29.naymnaymlevelup.rebuild.meal.School
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildUserProfile

enum class ChildRoute(
    val route: String,
    val title: String,
    val icon: ImageVector,
) {
    Today("today", "오늘", Icons.Filled.Forest),
    Meals("meals", "급식표", Icons.Filled.CalendarMonth),
    Growth("growth", "성장", Icons.AutoMirrored.Filled.TrendingUp),
    Collection("collection", "도감", Icons.AutoMirrored.Filled.MenuBook),
}

@Composable
fun ChildNavigation(
    profile: RebuildUserProfile,
    database: RebuildDatabase,
    isAppActive: Boolean,
) {
    val context = LocalContext.current
    val repositoryScope = rememberCoroutineScope()
    val growthPolicy = remember(context.assets) {
        GrowthPolicyLoader.load(context.assets)
    }
    val growthRepository = remember(database) {
        GrowthRepository(
            RoomGrowthProgressSource(database.progressDao()),
        )
    }
    val mealRepository = remember(database, repositoryScope) {
        MealRepository(
            store = RoomMealDayStore(database.mealDayDao()),
            client = NeisMealClient(),
            scope = repositoryScope,
        )
    }
    val school = remember(profile.school) {
        profile.school?.let {
            School(
                name = it.name,
                officeCode = it.officeCode,
                schoolCode = it.schoolCode,
            )
        }
    }
    val viewModel = remember(
        profile,
        database,
        context,
        mealRepository,
    ) {
        TodayForestViewModel(
            repository = LiveTodayMealRepository(mealRepository),
            recorder = LiveTodayMealRecorder(
                RecordMealUseCase(database, context.assets),
            ),
            photoMetadataStore = RoomTodayPhotoMetadataStore(database),
            progressProvider = RoomTodayProgressProvider(database),
            school = school,
            allergyCodes = profile.allergyCodes,
        )
    }
    val mealScheduleViewModel = remember(mealRepository, school) {
        MealScheduleViewModel(
            repository = mealRepository,
            school = school,
        )
    }
    var route by remember { mutableStateOf(ChildRoute.Today) }

    Scaffold(
        modifier = Modifier.testTag("child_navigation"),
        bottomBar = {
            NavigationBar {
                ChildRoute.entries.forEach { item ->
                    NavigationBarItem(
                        selected = route == item,
                        onClick = { route = item },
                        icon = {
                            Icon(
                                imageVector = item.icon,
                                contentDescription = null,
                            )
                        },
                        label = { Text(item.title) },
                        modifier = Modifier.testTag("child_route_${item.route}"),
                    )
                }
            }
        },
    ) { contentPadding ->
        Box(
            modifier = Modifier
                .padding(contentPadding)
                .fillMaxSize(),
        ) {
            TodayForestScreen(
                viewModel = viewModel,
                growthPolicy = growthPolicy,
                isTabActive = route == ChildRoute.Today,
                isAppActive = isAppActive,
                modifier = Modifier
                    .fillMaxSize()
                    .routeVisibility(route == ChildRoute.Today),
            )
            when (route) {
                ChildRoute.Today -> Unit
                ChildRoute.Meals -> MealScheduleScreen(
                    viewModel = mealScheduleViewModel,
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex(1f),
                )
                ChildRoute.Growth -> GrowthScreen(
                    repository = growthRepository,
                    policy = growthPolicy,
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex(1f),
                )
                ChildRoute.Collection -> CollectionScreen(
                    repository = growthRepository,
                    policy = growthPolicy,
                    modifier = Modifier
                        .fillMaxSize()
                        .zIndex(1f),
                )
            }
        }
    }
}

internal fun Modifier.routeVisibility(isActive: Boolean): Modifier {
    val visual = alpha(if (isActive) 1f else 0f)
        .zIndex(if (isActive) 1f else 0f)
    return if (isActive) {
        visual
    } else {
        visual
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent(PointerEventPass.Initial)
                            .changes
                            .forEach { it.consume() }
                    }
                }
            }
            .clearAndSetSemantics { }
    }
}
