package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun SchoolSearchScreen(viewModel: OnboardingViewModel) {
    var query by remember { mutableStateOf("") }
    LaunchedEffect(query) {
        viewModel.searchSchools(query)
    }
    Column(verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp)) {
        QuestionTitle("어느 학교에 다니나요?")
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            label = { Text("학교 이름") },
            modifier = Modifier.fillMaxWidth(),
        )
        when (val state = viewModel.schoolSearchState) {
            SchoolSearchState.Idle -> Text("학교 이름을 입력해 주세요.")
            SchoolSearchState.Loading -> CircularProgressIndicator()
            SchoolSearchState.Empty -> Text("검색 결과가 없어요. 학교 이름을 확인해 주세요.")
            is SchoolSearchState.Failed -> Text(
                state.message,
                color = MaterialTheme.colorScheme.error,
            )
            is SchoolSearchState.Results -> SchoolResults(
                state.schools,
                viewModel::selectSchool,
            )
            is SchoolSearchState.DemoResults -> SchoolResults(
                state.schools,
                viewModel::selectSchool,
            )
        }
    }
}

@Composable
private fun SchoolResults(
    schools: List<OnboardingSchool>,
    onSelect: (OnboardingSchool) -> Unit,
) {
    LazyColumn {
        items(
            items = schools,
            key = { "${it.officeCode}-${it.schoolCode}" },
        ) { school ->
            Button(
                onClick = { onSelect(school) },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = RebuildTokens.minimumActionSize.dp)
                    .padding(vertical = RebuildTokens.spacing[1].dp),
            ) {
                Text(school.name)
            }
        }
    }
}
