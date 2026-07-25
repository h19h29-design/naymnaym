package com.h19h29.naymnaymlevelup.rebuild.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun RebuildApp() {
    var selectedRole by remember { mutableStateOf<String?>(null) }

    RebuildTheme {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(RebuildTokens.spacing[4].dp),
            verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
        ) {
            Text(
                text = "어떻게 시작할까요?",
                style = androidx.compose.material3.MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = "역할을 선택하면 다음 단계로 안내할게요.",
                style = androidx.compose.material3.MaterialTheme.typography.bodyLarge,
            )
            Button(
                onClick = { selectedRole = "child" },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = RebuildTokens.minimumActionSize.dp),
            ) {
                Text("아이로 시작")
            }
            Button(
                onClick = { selectedRole = "guardian" },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = RebuildTokens.minimumActionSize.dp),
            ) {
                Text("보호자로 시작")
            }
            selectedRole?.let {
                Text(
                    text = "선택했어요.",
                    style = androidx.compose.material3.MaterialTheme.typography.bodyLarge,
                )
            }
        }
    }
}
