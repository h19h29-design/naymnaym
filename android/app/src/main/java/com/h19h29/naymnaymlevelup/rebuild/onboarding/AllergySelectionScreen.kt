package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

@Composable
fun AllergySelectionScreen(viewModel: OnboardingViewModel) {
    var selected by remember { mutableStateOf(emptySet<Int>()) }
    Column(verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp)) {
        QuestionTitle("확인이 필요한 알레르기가 있나요?")
        LazyColumn {
            items((1..19).toList()) { code ->
                TextButton(
                    onClick = {
                        selected = if (code in selected) {
                            selected - code
                        } else {
                            selected + code
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = RebuildTokens.minimumActionSize.dp)
                        .semantics { role = Role.Checkbox },
                ) {
                    Text("$code 번 알레르기", modifier = Modifier.weight(1f))
                    Checkbox(
                        checked = code in selected,
                        onCheckedChange = null,
                    )
                }
            }
        }
        OnboardingAction("다음") {
            viewModel.setAllergies(selected.toList())
        }
    }
}
