package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTheme
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertTrue
import android.graphics.Bitmap
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File

class CompanionConversationScreenTest {
    @get:Rule val rule = createComposeRule()

    @Test fun preparedConversationShowsSafetyResponseAndDismisses() {
        var dismissed = false
        rule.setContent { RebuildTheme { CompanionConversationSheet(1) { dismissed = true } } }
        rule.onNodeWithText("준비된 대화 · AI 연결 전").assertIsDisplayed()
        capture("conversation-android-light.png")
        rule.onNodeWithTag("companion_topic_allergy").performScrollTo().performClick()
        rule.waitUntil(10000) {
            rule.onAllNodesWithText("알레르기가 걱정되는 음식은 먹어 보지 말고", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNodeWithText("알레르기가 걱정되는 음식은 먹어 보지 말고", substring = true).assertExists()
        capture("conversation-android-reply.png")
        rule.onNodeWithText("닫기").performClick()
        rule.runOnIdle { assertTrue(dismissed) }
    }

    private fun capture(name: String) {
        rule.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val screenshot = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        File(instrumentation.targetContext.cacheDir, name).outputStream().use {
            screenshot.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        screenshot.recycle()
    }
}
