package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
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
    val symbol: String,
) {
    Today("today", "오늘", "🌿"),
    Growth("growth", "성장", "📈"),
    Collection("collection", "도감", "📚"),
}

@Composable
fun ChildNavigation(
    profile: RebuildUserProfile,
    database: RebuildDatabase,
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
    val viewModel = remember(profile, database, context, repositoryScope) {
        val repository = MealRepository(
            store = RoomMealDayStore(database.mealDayDao()),
            client = NeisMealClient(),
            scope = repositoryScope,
        )
        TodayForestViewModel(
            repository = LiveTodayMealRepository(repository),
            recorder = LiveTodayMealRecorder(
                RecordMealUseCase(database, context.assets),
            ),
            photoMetadataStore = RoomTodayPhotoMetadataStore(database),
            progressProvider = RoomTodayProgressProvider(database),
            school = profile.school?.let {
                School(
                    name = it.name,
                    officeCode = it.officeCode,
                    schoolCode = it.schoolCode,
                )
            },
            allergyCodes = profile.allergyCodes,
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
                        icon = { Text(item.symbol) },
                        label = { Text(item.title) },
                        modifier = Modifier.testTag("child_route_${item.route}"),
                    )
                }
            }
        },
    ) { contentPadding ->
        when (route) {
            ChildRoute.Today -> TodayForestScreen(
                viewModel = viewModel,
                growthPolicy = growthPolicy,
                modifier = Modifier.padding(contentPadding),
            )
            ChildRoute.Growth -> GrowthScreen(
                repository = growthRepository,
                policy = growthPolicy,
                modifier = Modifier.padding(contentPadding),
            )
            ChildRoute.Collection -> CollectionScreen(
                repository = growthRepository,
                policy = growthPolicy,
                modifier = Modifier.padding(contentPadding),
            )
        }
    }
}
