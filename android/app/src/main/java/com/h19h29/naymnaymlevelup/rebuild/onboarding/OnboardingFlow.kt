package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens
import kotlinx.coroutines.launch

@Composable
fun OnboardingFlow(
    viewModel: OnboardingViewModel,
    onCompleted: (RebuildUserProfile) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var nickname by remember { mutableStateOf("") }
    var saveMessage by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(RebuildTokens.spacing[4].dp),
        verticalArrangement = Arrangement.spacedBy(RebuildTokens.spacing[3].dp),
    ) {
        Text(
            text = viewModel.progressText,
            style = MaterialTheme.typography.titleMedium,
        )
        when (viewModel.step) {
            OnboardingStep.Role -> {
                QuestionTitle("누가 사용하나요?")
                OnboardingAction("아이로 시작") {
                    viewModel.selectRole(OnboardingRole.Child)
                }
                OnboardingAction("보호자로 시작") {
                    viewModel.selectRole(OnboardingRole.Parent)
                }
            }
            OnboardingStep.Nickname -> {
                QuestionTitle("어떤 별명으로 부를까요?")
                OutlinedTextField(
                    value = nickname,
                    onValueChange = { nickname = it },
                    label = { Text("별명 1~12자") },
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                )
                OnboardingAction("다음") { viewModel.setNickname(nickname) }
                viewModel.validationMessage?.let {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
            }
            OnboardingStep.School -> SchoolSearchScreen(viewModel)
            OnboardingStep.Allergies -> AllergySelectionScreen(viewModel)
            OnboardingStep.Confirmation -> {
                QuestionTitle("이대로 시작할까요?")
                Text("별명: ${viewModel.draft.nickname}")
                Text("학교: ${viewModel.draft.school?.name ?: "해당 없음"}")
                Text(
                    "알레르기: ${
                        viewModel.draft.allergyCodes
                            .takeIf { it.isNotEmpty() }
                            ?.joinToString()
                            ?: "선택 안 함"
                    }",
                )
                OnboardingAction(
                    title = "완료",
                    enabled = !viewModel.isCompleting,
                ) {
                    scope.launch {
                        try {
                            onCompleted(viewModel.complete())
                        } catch (error: Throwable) {
                            if (
                                (error as? OnboardingException)?.reason !=
                                OnboardingError.CompletionCancelled
                            ) {
                                saveMessage = "저장하지 못했어요. 다시 시도해 주세요."
                            }
                        }
                    }
                }
                if (viewModel.isCompleting) {
                    Text("프로필을 저장하고 있어요.")
                }
                saveMessage?.let {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Button(
            onClick = {
                nickname = ""
                viewModel.cancel()
            },
            modifier = Modifier.heightIn(min = RebuildTokens.minimumActionSize.dp),
        ) {
            Text("처음부터 다시")
        }
    }
}

@Composable
internal fun QuestionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.headlineMedium,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
internal fun OnboardingAction(
    title: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = RebuildTokens.minimumActionSize.dp),
    ) {
        Text(title)
    }
}
