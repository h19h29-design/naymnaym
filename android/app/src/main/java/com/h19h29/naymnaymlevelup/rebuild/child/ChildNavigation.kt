package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.R
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.meal.MealRepository
import com.h19h29.naymnaymlevelup.rebuild.meal.NeisMealClient
import com.h19h29.naymnaymlevelup.rebuild.meal.RecordMealUseCase
import com.h19h29.naymnaymlevelup.rebuild.meal.RoomMealDayStore
import com.h19h29.naymnaymlevelup.rebuild.meal.School
import com.h19h29.naymnaymlevelup.rebuild.onboarding.RebuildUserProfile
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

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
                modifier = Modifier.padding(contentPadding),
            )
            ChildRoute.Growth -> ChildPlaceholderScreen(
                title = "성장",
                message = "급식을 기록하면 캐릭터의 성장 이야기가 차곡차곡 쌓여요.",
                drawable = R.drawable.icon_growth_report,
                modifier = Modifier.padding(contentPadding),
            )
            ChildRoute.Collection -> ChildPlaceholderScreen(
                title = "도감",
                message = "먹어 본 음식과 만난 영양소가 이곳에 모여요.",
                drawable = R.drawable.mascot_onboarding,
                modifier = Modifier.padding(contentPadding),
            )
        }
    }
}

@Composable
private fun ChildPlaceholderScreen(
    title: String,
    message: String,
    drawable: Int,
    modifier: Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(RebuildTokens.spacing[4].dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[4].dp),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier
                .align(Alignment.Start)
                .semantics { heading() },
        )
        Image(
            painter = painterResource(drawable),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.height(144.dp),
        )
        Text(text = message, style = MaterialTheme.typography.bodyLarge)
    }
}
