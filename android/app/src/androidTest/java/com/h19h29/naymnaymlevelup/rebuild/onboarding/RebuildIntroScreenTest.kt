package com.h19h29.naymnaymlevelup.rebuild.onboarding

import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.graphics.BitmapFactory
import android.os.Looper
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildApp
import com.h19h29.naymnaymlevelup.R
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RebuildIntroScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun reducedMotionRendersOneUncroppedLogoWithoutSplitOrShine() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            Box(Modifier.width(320.dp).height(600.dp)) {
                RebuildIntroScreen(
                    reduceMotionOverride = true,
                    onCompleted = { true },
                )
            }
        }

        composeRule.onNodeWithContentDescription("냠냠레벨업")
            .assertIsDisplayed()
        composeRule.onNodeWithTag("rebuild_intro_logo_viewport")
            .assertIsDisplayed()
        assertEquals(
            1,
            composeRule.onAllNodesWithTag("rebuild_intro_logo_whole")
                .fetchSemanticsNodes().size,
        )
        assertTrue(
            composeRule.onAllNodesWithTag("rebuild_intro_logo_left")
                .fetchSemanticsNodes().isEmpty(),
        )
        assertTrue(
            composeRule.onAllNodesWithTag("rebuild_intro_logo_right")
                .fetchSemanticsNodes().isEmpty(),
        )
        assertTrue(
            composeRule.onAllNodesWithTag("rebuild_intro_logo_shine")
                .fetchSemanticsNodes().isEmpty(),
        )
    }

    @Test
    fun normalMotionStartsWithComplementaryWordLayersInCompactViewport() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            Box(Modifier.width(360.dp).height(800.dp)) {
                RebuildIntroScreen(
                    reduceMotionOverride = false,
                    onCompleted = { true },
                )
            }
        }

        composeRule.onNodeWithTag("rebuild_intro_logo_viewport")
            .assertIsDisplayed()
        assertEquals(
            1,
            composeRule.onAllNodesWithTag("rebuild_intro_logo_left")
                .fetchSemanticsNodes().size,
        )
        assertEquals(
            1,
            composeRule.onAllNodesWithTag("rebuild_intro_logo_right")
                .fetchSemanticsNodes().size,
        )
        assertTrue(
            composeRule.onAllNodesWithTag("rebuild_intro_logo_whole")
                .fetchSemanticsNodes().isEmpty(),
        )
    }

    @Test
    fun complementarySplitBoundsMeetWithoutOverlapAtSupportedWidths() {
        var canvasWidth by mutableStateOf(272f)
        composeRule.setContent {
            RebuildIntroLogoCanvas(
                frame = RebuildIntroMotionSpec.frameAt(
                    1_100,
                    reduceMotion = false,
                ),
                modifier = Modifier
                    .width(canvasWidth.dp)
                    .height(
                        (
                            canvasWidth /
                                RebuildIntroMotionSpec.SourceAspectRatio
                            ).dp,
                    )
                    .testTag("rebuild_intro_pixel_canvas"),
            )
        }

        for (width in listOf(272f, 345f, 357f)) {
            composeRule.runOnUiThread {
                canvasWidth = width
            }
            composeRule.waitForIdle()
            val viewport = composeRule
                .onNodeWithTag("rebuild_intro_pixel_canvas")
                .fetchSemanticsNode().boundsInRoot
            val left = composeRule
                .onNodeWithTag("rebuild_intro_logo_left")
                .fetchSemanticsNode().boundsInRoot
            val right = composeRule
                .onNodeWithTag("rebuild_intro_logo_right")
                .fetchSemanticsNode().boundsInRoot
            val rendered = composeRule
                .onNodeWithTag("rebuild_intro_pixel_canvas")
                .captureToImage()

            assertEquals(viewport.left, left.left, .5f)
            assertEquals(left.right, right.left, .5f)
            assertEquals(viewport.right, right.right, .5f)
            assertTrue(rendered.width > 0)
            assertTrue(rendered.height > 0)
        }
    }

    @Test
    fun sharedPreferencesCompletionIsVisibleToImmediateSameDayRecreation() =
        runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-test-${System.nanoTime()}",
            android.content.Context.MODE_PRIVATE,
        )
        assertTrue(preferences.edit().clear().commit())
        val zone = ZoneId.of("Asia/Seoul")
        val clock = Clock.fixed(
            Instant.parse("2026-07-26T03:00:00Z"),
            zone,
        )
        val first = RebuildIntroDailyGate(
            SharedPreferencesRebuildIntroDateStore(preferences),
            clock,
            zone,
        )
        assertTrue(first.shouldPresent())

        assertTrue(first.markCompleted())

        val recreated = RebuildIntroDailyGate(
            SharedPreferencesRebuildIntroDateStore(preferences),
            clock,
            zone,
        )
        assertTrue(!recreated.shouldPresent())
        assertEquals(
            "20260726",
            preferences.getString(RebuildIntroDailyGate.StorageKey, null),
        )
        assertTrue(preferences.edit().clear().commit())
        }

    @Test
    fun sharedPreferencesCommitRunsOffMainAndFailureKeepsIntroActive() =
        runBlocking {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val preferences = context.getSharedPreferences(
                "rebuild-intro-io-test-${System.nanoTime()}",
                Context.MODE_PRIVATE,
            )
            assertTrue(preferences.edit().clear().commit())
            val dispatcher = Executors.newSingleThreadExecutor {
                Thread(it, "rebuild-intro-persistence-test")
            }.asCoroutineDispatcher()
            val commitThread = AtomicReference<Thread>()
            val zone = ZoneId.of("Asia/Seoul")
            val clock = Clock.fixed(
                Instant.parse("2026-07-26T03:00:00Z"),
                zone,
            )

            try {
                val successEntry = RebuildIntroEntryController(
                    RebuildIntroDailyGate(
                        SharedPreferencesRebuildIntroDateStore(
                            preferences = preferences,
                            ioDispatcher = dispatcher,
                            commit = { editor ->
                                commitThread.set(Thread.currentThread())
                                editor.commit()
                            },
                        ),
                        clock,
                        zone,
                    ),
                )

                assertTrue(successEntry.completeIntro())
                assertEquals(
                    "rebuild-intro-persistence-test",
                    commitThread.get().name,
                )
                assertTrue(commitThread.get() !== Looper.getMainLooper().thread)
                assertTrue(successEntry.canLoadBootstrap)

                assertTrue(preferences.edit().clear().commit())
                val failedEntry = RebuildIntroEntryController(
                    RebuildIntroDailyGate(
                        SharedPreferencesRebuildIntroDateStore(
                            preferences = preferences,
                            ioDispatcher = dispatcher,
                            commit = { editor ->
                                commitThread.set(Thread.currentThread())
                                editor.commit()
                                false
                            },
                        ),
                        clock,
                        zone,
                    ),
                )

                assertTrue(!failedEntry.completeIntro())
                assertTrue(commitThread.get() !== Looper.getMainLooper().thread)
                assertTrue(failedEntry.showIntro)
                assertTrue(!failedEntry.canLoadBootstrap)
                assertTrue(
                    preferences.getString(
                        RebuildIntroDailyGate.StorageKey,
                        null,
                    ) == null,
                )
            } finally {
                dispatcher.close()
                assertTrue(preferences.edit().clear().commit())
            }
        }

    @Test
    fun changingReduceMotionDuringPlaybackDoesNotLoseCompletion() {
        composeRule.mainClock.autoAdvance = false
        var reduceMotion by mutableStateOf(false)
        var completions = 0
        composeRule.setContent {
            RebuildIntroScreen(
                reduceMotionOverride = reduceMotion,
                onCompleted = {
                    completions += 1
                    true
                },
            )
        }

        composeRule.runOnUiThread {
            reduceMotion = true
        }
        composeRule.mainClock.advanceTimeBy(400)
        composeRule.waitForIdle()
        assertEquals(
            1,
            composeRule.onAllNodesWithTag("rebuild_intro_logo_left")
                .fetchSemanticsNodes().size,
        )
        composeRule.runOnIdle {
            assertEquals(0, completions)
        }
        composeRule.mainClock.advanceTimeBy(1_800)
        composeRule.waitForIdle()

        composeRule.runOnIdle {
            assertEquals(1, completions)
        }
    }

    @Test
    fun changingFromReducedToNormalKeepsWholeLogoAndQuarterSecondCompletion() {
        composeRule.mainClock.autoAdvance = false
        var reduceMotion by mutableStateOf(true)
        var completions = 0
        composeRule.setContent {
            RebuildIntroScreen(
                reduceMotionOverride = reduceMotion,
                onCompleted = {
                    completions += 1
                    true
                },
            )
        }

        composeRule.runOnUiThread {
            reduceMotion = false
        }
        composeRule.mainClock.advanceTimeBy(400)
        composeRule.waitForIdle()

        composeRule.onNodeWithTag("rebuild_intro_logo_whole")
            .assertIsDisplayed()
        assertTrue(
            composeRule.onAllNodesWithTag("rebuild_intro_logo_left")
                .fetchSemanticsNodes().isEmpty(),
        )
        composeRule.runOnIdle {
            assertEquals(1, completions)
        }
    }

    @Test
    fun packagedLogoMatchesExactPixelAlphaAndHashContract() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val bytes = context.resources
            .openRawResource(R.drawable.logo_naym_levelup)
            .use { it.readBytes() }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)

        assertEquals(357, bitmap.width)
        assertEquals(86, bitmap.height)
        assertTrue(bitmap.hasAlpha())
        assertEquals(
            "0132e9075a8a3953cc87ae43154be317fb846630ea5e1f7dfbced8fb0860120b",
            MessageDigest.getInstance("SHA-256")
                .digest(bytes)
                .joinToString("") {
                    "%02x".format(it.toInt() and 0xff)
                },
        )
    }

    @Test
    fun failedCompletionExposesRetryAndCanFinishWithoutRecreatingScreen() {
        composeRule.mainClock.autoAdvance = false
        var attempts = 0
        composeRule.setContent {
            RebuildIntroScreen(
                reduceMotionOverride = true,
                onCompleted = {
                    attempts += 1
                    attempts >= 2
                },
            )
        }

        composeRule.mainClock.advanceTimeBy(400)
        composeRule.waitForIdle()
        composeRule.onNodeWithText("저장 다시 시도")
            .assertIsDisplayed()
            .performClick()

        composeRule.runOnIdle {
            assertEquals(2, attempts)
        }
        composeRule.mainClock.advanceTimeByFrame()
        composeRule.waitForIdle()
        assertTrue(
            composeRule.onAllNodesWithText("저장 다시 시도")
                .fetchSemanticsNodes().isEmpty(),
        )
    }

    @Test
    fun retryCompletionCannotStartOverlappingPersistenceAttempts() {
        composeRule.mainClock.autoAdvance = false
        val retryStarted = CompletableDeferred<Unit>()
        val retryResult = CompletableDeferred<Boolean>()
        var attempts = 0
        composeRule.setContent {
            RebuildIntroScreen(
                reduceMotionOverride = true,
                onCompleted = {
                    attempts += 1
                    if (attempts == 1) {
                        false
                    } else {
                        retryStarted.complete(Unit)
                        retryResult.await()
                    }
                },
            )
        }

        composeRule.mainClock.advanceTimeBy(400)
        composeRule.waitForIdle()
        composeRule.onNodeWithText("저장 다시 시도")
            .assertIsDisplayed()
            .performClick()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            retryStarted.isCompleted
        }
        composeRule.mainClock.advanceTimeByFrame()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("저장 다시 시도")
            .assertIsNotEnabled()
        composeRule.runOnIdle {
            assertEquals(2, attempts)
        }

        retryResult.complete(true)
        composeRule.mainClock.advanceTimeByFrame()
        composeRule.waitUntil(timeoutMillis = 2_000) {
            composeRule.onAllNodesWithText("저장 다시 시도")
                .fetchSemanticsNodes().isEmpty()
        }
        composeRule.runOnIdle {
            assertEquals(2, attempts)
        }
    }

    @Test
    fun activeDailyIntroPrecedesRealBootstrapAndOnboarding() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val preferences = context.getSharedPreferences(
            "rebuild-intro-state",
            android.content.Context.MODE_PRIVATE,
        )
        assertTrue(preferences.edit().clear().commit())
        val database = Room.inMemoryDatabaseBuilder(
            context,
            RebuildDatabase::class.java,
        ).build()
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RebuildApp(database)
        }

        composeRule.onNodeWithContentDescription("냠냠레벨업")
            .assertIsDisplayed()
        assertTrue(
            composeRule.onAllNodesWithText("누가 사용하나요?")
                .fetchSemanticsNodes().isEmpty(),
        )

        composeRule.mainClock.advanceTimeBy(2_200)
        composeRule.mainClock.autoAdvance = true
        composeRule.waitUntil(timeoutMillis = 5_000) {
            composeRule.onAllNodesWithText("누가 사용하나요?")
                .fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("누가 사용하나요?")
            .assertIsDisplayed()

        database.close()
        assertTrue(preferences.edit().clear().commit())
    }

    @Test
    fun compactReducedMotionLogoRemainsVisibleAtTwoHundredPercentText() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(
                    density = density.density,
                    fontScale = 2f,
                ),
            ) {
                Box(Modifier.width(320.dp).height(600.dp)) {
                    RebuildIntroScreen(
                        reduceMotionOverride = true,
                        onCompleted = { true },
                    )
                }
            }
        }

        composeRule.onNodeWithContentDescription("냠냠레벨업")
            .assertIsDisplayed()
        composeRule.onNodeWithTag("rebuild_intro_logo_whole")
            .assertIsDisplayed()
    }
}
