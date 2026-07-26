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
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

        assertTrue(
            preferences
                .edit()
                .putString(RebuildIntroDailyGate.StorageKey, "20260725")
                .commit(),
        )
        val legacyUpdatedStore =
            SharedPreferencesRebuildIntroDateStore(preferences)
        assertEquals("20260725", legacyUpdatedStore.read())
        assertEquals(
            "20260725",
            preferences.getString(RebuildIntroDailyGate.StorageKey, null),
        )
        assertTrue(preferences.edit().clear().commit())
        }

    @Test
    fun ownedPendingSharedPreferencesRecordRecoversPublicMirror() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-pending-test-${System.nanoTime()}",
            Context.MODE_PRIVATE,
        )
        assertTrue(
            preferences
                .edit()
                .clear()
                .putString(RebuildIntroDailyGate.StorageKey, "20260725")
                .putString(
                    "last-intro-date.rebuild-durable-owner",
                    "rebuild-intro-daily-gate-v1",
                )
                .putLong(
                    "last-intro-date.rebuild-durable-version",
                    1L,
                )
                .putString(
                    "last-intro-date.rebuild-durable-state",
                    "pending",
                )
                .putString(
                    "last-intro-date.rebuild-durable-value",
                    "20260726",
                )
                .putString(
                    "last-intro-date.rebuild-durable-previous-public-value",
                    "20260725",
                )
                .commit(),
        )

        val recoveredStore =
            SharedPreferencesRebuildIntroDateStore(preferences)
        assertEquals("20260726", recoveredStore.read())
        assertEquals(
            "20260726",
            preferences.getString(RebuildIntroDailyGate.StorageKey, null),
        )
        assertEquals(
            "published",
            preferences.getString(
                "last-intro-date.rebuild-durable-state",
                null,
            ),
        )
        assertTrue(preferences.edit().clear().commit())
    }

    @Test
    fun invalidPendingSharedPreferencesRecordCannotRecoverPublicMirror() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-invalid-pending-test-${System.nanoTime()}",
            Context.MODE_PRIVATE,
        )
        val invalidOwnershipAndVersions =
            listOf<Pair<String?, Long?>>(
                null to 1L,
                "legacy-intro-writer" to 1L,
                "rebuild-intro-daily-gate-v1" to 0L,
                "rebuild-intro-daily-gate-v1" to null,
            )

        for ((owner, version) in invalidOwnershipAndVersions) {
            val editor = preferences
                .edit()
                .clear()
                .putString(RebuildIntroDailyGate.StorageKey, "20260725")
                .putString(
                    "last-intro-date.rebuild-durable-state",
                    "pending",
                )
                .putString(
                    "last-intro-date.rebuild-durable-value",
                    "20260726",
                )
                .putString(
                    "last-intro-date.rebuild-durable-previous-public-value",
                    "20260725",
                )
            if (owner != null) {
                editor.putString(
                    "last-intro-date.rebuild-durable-owner",
                    owner,
                )
            }
            if (version != null) {
                editor.putLong(
                    "last-intro-date.rebuild-durable-version",
                    version,
                )
            }
            assertTrue(editor.commit())

            val store = SharedPreferencesRebuildIntroDateStore(preferences)
            assertEquals("20260725", store.read())
            assertEquals(
                "20260725",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )
        }
        assertTrue(preferences.edit().clear().commit())
    }

    @Test
    fun publicDateAndConcurrentRecreationWaitForDurableCommit() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-visible-test-${System.nanoTime()}",
            Context.MODE_PRIVATE,
        )
        assertTrue(
            preferences
                .edit()
                .clear()
                .putString(RebuildIntroDailyGate.StorageKey, "20260725")
                .commit(),
        )
        val zone = ZoneId.of("Asia/Seoul")
        val clock = Clock.fixed(
            Instant.parse("2026-07-26T03:00:00Z"),
            zone,
        )
        val dispatcher = Executors.newSingleThreadExecutor()
            .asCoroutineDispatcher()
        val commitCompleted = CountDownLatch(1)
        val returnCommitResult = CountDownLatch(1)
        val durableStates = CopyOnWriteArrayList<String?>()
        val commitHook: (android.content.SharedPreferences.Editor) -> Boolean =
            { editor ->
                val didCommit = editor.commit()
                durableStates += preferences.getString(
                    "last-intro-date.rebuild-durable-state",
                    null,
                )
                if (durableStates.size == 1) {
                    commitCompleted.countDown()
                    check(returnCommitResult.await(1, TimeUnit.SECONDS))
                }
                didCommit
            }
        val store = SharedPreferencesRebuildIntroDateStore(
            preferences = preferences,
            ioDispatcher = dispatcher,
            commit = commitHook,
        )
        val gate = RebuildIntroDailyGate(store, clock, zone)

        try {
            val completion = async(Dispatchers.Default) {
                gate.markCompleted()
            }
            assertTrue(commitCompleted.await(3, TimeUnit.SECONDS))
            assertEquals(
                "20260725",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )
            val concurrentRequestReserved = CountDownLatch(1)
            val concurrentGate = RebuildIntroDailyGate(
                SharedPreferencesRebuildIntroDateStore(
                    preferences = preferences,
                    commit = commitHook,
                    onRequestReserved = {
                        concurrentRequestReserved.countDown()
                    },
                ),
                clock,
                zone,
            )
            assertTrue(concurrentGate.shouldPresent())
            val concurrentCompletion = async(Dispatchers.Default) {
                concurrentGate.markCompleted()
            }
            assertTrue(
                concurrentRequestReserved.await(1, TimeUnit.SECONDS),
            )

            returnCommitResult.countDown()
            assertTrue(completion.await())
            assertTrue(concurrentCompletion.await())
            assertEquals(
                "20260726",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )
            assertTrue(!gate.shouldPresent())
            assertTrue(!concurrentGate.shouldPresent())
            assertEquals(
                listOf("pending", "published"),
                durableStates.toList(),
            )
        } finally {
            returnCommitResult.countDown()
            dispatcher.close()
            assertTrue(preferences.edit().clear().commit())
        }
    }

    @Test
    fun entryCreatedDuringSameDayWriteConvergesAfterCommitWithoutSecondRequest() =
        runBlocking {
            val context =
                InstrumentationRegistry.getInstrumentation().targetContext
            val preferences = context.getSharedPreferences(
                "rebuild-intro-shared-entry-${System.nanoTime()}",
                Context.MODE_PRIVATE,
            )
            assertTrue(
                preferences
                    .edit()
                    .clear()
                    .putString(
                        RebuildIntroDailyGate.StorageKey,
                        "20260725",
                    )
                    .commit(),
            )
            val zone = ZoneId.of("Asia/Seoul")
            val clock = Clock.fixed(
                Instant.parse("2026-07-26T03:00:00Z"),
                zone,
            )
            val dispatcher = Executors.newSingleThreadExecutor()
                .asCoroutineDispatcher()
            val pendingCommitEntered = CountDownLatch(1)
            val releasePendingCommit = CountDownLatch(1)
            val requestCount = AtomicInteger()
            val store = SharedPreferencesRebuildIntroDateStore(
                preferences = preferences,
                ioDispatcher = dispatcher,
                commit = { editor ->
                    val didCommit = editor.commit()
                    if (
                        preferences.getString(
                            "last-intro-date.rebuild-durable-state",
                            null,
                        ) == "pending"
                    ) {
                        pendingCommitEntered.countDown()
                        check(
                            releasePendingCommit.await(
                                3,
                                TimeUnit.SECONDS,
                            ),
                        )
                    }
                    didCommit
                },
                onRequestReserved = {
                    requestCount.incrementAndGet()
                },
            )
            val firstEntry = RebuildIntroEntryController(
                RebuildIntroDailyGate(store, clock, zone),
            )

            try {
                val completion = async(Dispatchers.Default) {
                    firstEntry.completeIntro()
                }
                assertTrue(
                    pendingCommitEntered.await(1, TimeUnit.SECONDS),
                )

                val recreatedEntry = RebuildIntroEntryController(
                    RebuildIntroDailyGate(store, clock, zone),
                )
                assertTrue(recreatedEntry.showIntro)

                releasePendingCommit.countDown()
                assertTrue(completion.await())

                assertFalse(recreatedEntry.showIntro)
                assertEquals(1, requestCount.get())
            } finally {
                releasePendingCommit.countDown()
                dispatcher.close()
                assertTrue(preferences.edit().clear().commit())
            }
        }

    @Test
    fun queuedPreviousDayWriteCannotOverwriteCurrentDay() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-order-test-${System.nanoTime()}",
            Context.MODE_PRIVATE,
        )
        assertTrue(preferences.edit().clear().commit())
        val staleExecutor = Executors.newSingleThreadExecutor()
        val staleDispatcher = staleExecutor.asCoroutineDispatcher()
        val staleQueueBlocked = CountDownLatch(1)
        val releaseStaleQueue = CountDownLatch(1)
        staleExecutor.execute {
            staleQueueBlocked.countDown()
            check(releaseStaleQueue.await(3, TimeUnit.SECONDS))
        }
        assertTrue(staleQueueBlocked.await(1, TimeUnit.SECONDS))
        val staleRequestReserved = CountDownLatch(1)
        val staleStore = SharedPreferencesRebuildIntroDateStore(
            preferences = preferences,
            ioDispatcher = staleDispatcher,
            onRequestReserved = {
                staleRequestReserved.countDown()
            },
        )

        try {
            val staleWrite = async(Dispatchers.Default) {
                staleStore.writeDurably("20260726")
            }
            assertTrue(staleRequestReserved.await(1, TimeUnit.SECONDS))
            val currentStore =
                SharedPreferencesRebuildIntroDateStore(preferences)
            assertTrue(currentStore.writeDurably("20260727"))
            assertEquals(
                "20260727",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )

            releaseStaleQueue.countDown()
            assertFalse(staleWrite.await())
            assertEquals("20260727", currentStore.read())
            assertEquals(
                "20260727",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )
        } finally {
            releaseStaleQueue.countDown()
            staleDispatcher.close()
            assertTrue(preferences.edit().clear().commit())
        }
    }

    @Test
    fun queuedWriteCannotOverwriteDirectPublicCommit() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-direct-order-test-${System.nanoTime()}",
            Context.MODE_PRIVATE,
        )
        assertTrue(
            preferences
                .edit()
                .clear()
                .putString(RebuildIntroDailyGate.StorageKey, "20260725")
                .commit(),
        )
        val staleExecutor = Executors.newSingleThreadExecutor()
        val staleDispatcher = staleExecutor.asCoroutineDispatcher()
        val staleQueueBlocked = CountDownLatch(1)
        val releaseStaleQueue = CountDownLatch(1)
        staleExecutor.execute {
            staleQueueBlocked.countDown()
            check(releaseStaleQueue.await(3, TimeUnit.SECONDS))
        }
        assertTrue(staleQueueBlocked.await(1, TimeUnit.SECONDS))
        val staleRequestReserved = CountDownLatch(1)
        val staleStore = SharedPreferencesRebuildIntroDateStore(
            preferences = preferences,
            ioDispatcher = staleDispatcher,
            onRequestReserved = {
                staleRequestReserved.countDown()
            },
        )

        try {
            val staleWrite = async(Dispatchers.Default) {
                staleStore.writeDurably("20260726")
            }
            assertTrue(staleRequestReserved.await(1, TimeUnit.SECONDS))
            assertTrue(
                preferences
                    .edit()
                    .putString(
                        RebuildIntroDailyGate.StorageKey,
                        "20260727",
                    )
                    .commit(),
            )

            releaseStaleQueue.countDown()
            assertFalse(staleWrite.await())
            assertEquals("20260727", staleStore.read())
            assertEquals(
                "20260727",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )
        } finally {
            releaseStaleQueue.countDown()
            staleDispatcher.close()
            assertTrue(preferences.edit().clear().commit())
        }
    }

    @Test
    fun laterDateWinsAtFinalPublicationBoundary() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-publication-order-test-${System.nanoTime()}",
            Context.MODE_PRIVATE,
        )
        assertTrue(
            preferences
                .edit()
                .clear()
                .putString(RebuildIntroDailyGate.StorageKey, "20260725")
                .commit(),
        )
        val stalePublicationEntered = CountDownLatch(1)
        val releaseStalePublication = CountDownLatch(1)
        val staleStore = SharedPreferencesRebuildIntroDateStore(
            preferences = preferences,
            beforePublication = {
                stalePublicationEntered.countDown()
                check(
                    releaseStalePublication.await(
                        3,
                        TimeUnit.SECONDS,
                    ),
                )
            },
        )

        try {
            val staleWrite = async(Dispatchers.Default) {
                staleStore.writeDurably("20260726")
            }
            assertTrue(
                stalePublicationEntered.await(1, TimeUnit.SECONDS),
            )
            val currentRequestReserved = CountDownLatch(1)
            val currentStore = SharedPreferencesRebuildIntroDateStore(
                preferences = preferences,
                onRequestReserved = {
                    currentRequestReserved.countDown()
                },
            )
            val currentWrite = async(Dispatchers.Default) {
                currentStore.writeDurably("20260727")
            }
            assertTrue(
                currentRequestReserved.await(1, TimeUnit.SECONDS),
            )

            releaseStalePublication.countDown()
            assertFalse(staleWrite.await())
            assertTrue(currentWrite.await())
            assertEquals("20260727", currentStore.read())
            assertEquals(
                "20260727",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )
        } finally {
            releaseStalePublication.countDown()
            assertTrue(preferences.edit().clear().commit())
        }
    }

    @Test
    fun laterReservationAfterAtomicPublicationLetsBothDaysSucceedInOrder() =
        runBlocking {
            val context =
                InstrumentationRegistry.getInstrumentation().targetContext
            val preferences = context.getSharedPreferences(
                "rebuild-intro-post-publication-${System.nanoTime()}",
                Context.MODE_PRIVATE,
            )
            assertTrue(
                preferences
                    .edit()
                    .clear()
                    .putString(
                        RebuildIntroDailyGate.StorageKey,
                        "20260725",
                    )
                    .commit(),
            )
            val firstStore =
                SharedPreferencesRebuildIntroDateStore(preferences)

            assertTrue(firstStore.writeDurably("20260726"))
            assertEquals("20260726", firstStore.read())

            val secondRequestReserved = CountDownLatch(1)
            val secondStore = SharedPreferencesRebuildIntroDateStore(
                preferences = preferences,
                onRequestReserved = {
                    secondRequestReserved.countDown()
                },
            )
            val secondWrite = async(Dispatchers.Default) {
                secondStore.writeDurably("20260727")
            }
            assertTrue(
                secondRequestReserved.await(1, TimeUnit.SECONDS),
            )
            assertTrue(secondWrite.await())
            assertEquals("20260727", secondStore.read())
            assertEquals(
                "20260727",
                preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                ),
            )
            assertTrue(preferences.edit().clear().commit())
        }

    @Test
    fun reservationUsesSharedOrderingQueueWithoutBlockingMainThread() =
        runBlocking {
            val context =
                InstrumentationRegistry.getInstrumentation().targetContext
            val preferences = context.getSharedPreferences(
                "rebuild-intro-reservation-io-${System.nanoTime()}",
                Context.MODE_PRIVATE,
            )
            assertTrue(
                preferences
                    .edit()
                    .clear()
                    .putString(
                        RebuildIntroDailyGate.StorageKey,
                        "20260725",
                    )
                    .commit(),
            )
            val executor = Executors.newSingleThreadExecutor()
            val dispatcher = executor.asCoroutineDispatcher()
            val ioOccupied = CountDownLatch(1)
            val releaseIo = CountDownLatch(1)
            executor.execute {
                ioOccupied.countDown()
                runCatching {
                    releaseIo.await(3, TimeUnit.SECONDS)
                }
            }
            assertTrue(ioOccupied.await(1, TimeUnit.SECONDS))
            val publicValueRead = CountDownLatch(1)
            val reservationThread = AtomicReference<Thread>()
            val store = SharedPreferencesRebuildIntroDateStore(
                preferences = preferences,
                ioDispatcher = dispatcher,
                onPublicValueRead = {
                    reservationThread.set(Thread.currentThread())
                    publicValueRead.countDown()
                },
            )

            try {
                val write = async(Dispatchers.Main) {
                    store.writeDurably("20260726")
                }
                val mainThreadHeartbeat = async(Dispatchers.Main) {
                    true
                }

                assertEquals(
                    true,
                    withTimeoutOrNull(1_000) {
                        mainThreadHeartbeat.await()
                    },
                )
                assertTrue(
                    publicValueRead.await(1, TimeUnit.SECONDS),
                )
                assertFalse(
                    reservationThread.get() ==
                        Looper.getMainLooper().thread,
                )
                releaseIo.countDown()

                assertTrue(write.await())
                assertEquals("20260726", store.read())
            } finally {
                releaseIo.countDown()
                dispatcher.close()
                executor.shutdown()
                executor.awaitTermination(1, TimeUnit.SECONDS)
                assertTrue(preferences.edit().clear().commit())
            }
        }

    @Test
    fun cancellationAtReservationReturnReleasesLease() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences(
            "rebuild-intro-reservation-cancel-${System.nanoTime()}",
            Context.MODE_PRIVATE,
        )
        assertTrue(
            preferences
                .edit()
                .clear()
                .putString(
                    RebuildIntroDailyGate.StorageKey,
                    "20260725",
                )
                .commit(),
        )
        val olderPublicationClaimed = CountDownLatch(1)
        val releaseOlderPublication = CountDownLatch(1)
        val olderStore = SharedPreferencesRebuildIntroDateStore(
            preferences = preferences,
            beforePublication = {
                olderPublicationClaimed.countDown()
                releaseOlderPublication.await(3, TimeUnit.SECONDS)
            },
        )
        val reservationReturning = CountDownLatch(1)
        val releaseReservation = CountDownLatch(1)
        val cancelledStore = SharedPreferencesRebuildIntroDateStore(
            preferences = preferences,
            onReservationReturning = {
                reservationReturning.countDown()
                releaseReservation.await(3, TimeUnit.SECONDS)
            },
        )
        val olderWrite = async(Dispatchers.Default) {
            olderStore.writeDurably("20260726")
        }

        try {
            assertTrue(
                olderPublicationClaimed.await(1, TimeUnit.SECONDS),
            )
            val cancelledWrite = async(Dispatchers.Default) {
                cancelledStore.writeDurably("20260727")
            }
            assertTrue(
                reservationReturning.await(1, TimeUnit.SECONDS),
            )
            cancelledWrite.cancel()
            releaseOlderPublication.countDown()
            releaseReservation.countDown()
            runCatching { cancelledWrite.await() }

            assertTrue(cancelledWrite.isCancelled)
            assertTrue(olderWrite.await())
            assertEquals("20260726", olderStore.read())
            assertEquals(
                0,
                olderStore.activeReservationCountForTesting,
            )

            val subsequentStore =
                SharedPreferencesRebuildIntroDateStore(preferences)
            assertTrue(subsequentStore.writeDurably("20260727"))
            assertEquals("20260727", subsequentStore.read())
            assertEquals(
                0,
                subsequentStore.activeReservationCountForTesting,
            )
        } finally {
            releaseReservation.countDown()
            releaseOlderPublication.countDown()
            runCatching { olderWrite.await() }
            assertTrue(preferences.edit().clear().commit())
        }
    }

    @Test
    fun readCannotRecoverPendingTransactionWhileFailingWriterIsActive() =
        runBlocking {
            val context =
                InstrumentationRegistry.getInstrumentation().targetContext
            val preferences = context.getSharedPreferences(
                "rebuild-intro-read-writer-race-${System.nanoTime()}",
                Context.MODE_PRIVATE,
            )
            assertTrue(
                preferences
                    .edit()
                    .clear()
                    .putString(
                        RebuildIntroDailyGate.StorageKey,
                        "20260725",
                    )
                    .commit(),
            )
            val readerEnteredAuthoritativePath = CountDownLatch(1)
            val releaseReader = CountDownLatch(1)
            val pendingCommitCompleted = CountDownLatch(1)
            val releaseFailedCommit = CountDownLatch(1)
            val authoritativeReadCount = AtomicInteger()
            val store = SharedPreferencesRebuildIntroDateStore(
                preferences = preferences,
                commit = { editor ->
                    val didCommit = editor.commit()
                    if (
                        preferences.getString(
                            "last-intro-date.rebuild-durable-state",
                            null,
                        ) == "pending"
                    ) {
                        pendingCommitCompleted.countDown()
                        releaseFailedCommit.await(
                            3,
                            TimeUnit.SECONDS,
                        )
                        false
                    } else {
                        didCommit
                    }
                },
                onAuthoritativeReadStarted = {
                    if (authoritativeReadCount.incrementAndGet() == 1) {
                        readerEnteredAuthoritativePath.countDown()
                        releaseReader.await(3, TimeUnit.SECONDS)
                    }
                },
            )

            try {
                val read = async(Dispatchers.Default) {
                    store.read()
                }
                assertTrue(
                    readerEnteredAuthoritativePath.await(
                        1,
                        TimeUnit.SECONDS,
                    ),
                )
                val write = async(Dispatchers.Default) {
                    store.writeDurably("20260726")
                }
                val didWriterOverlapReader =
                    pendingCommitCompleted.await(
                        150,
                        TimeUnit.MILLISECONDS,
                    )

                releaseReader.countDown()
                val readValue = read.await()
                if (!didWriterOverlapReader) {
                    assertTrue(
                        pendingCommitCompleted.await(
                            1,
                            TimeUnit.SECONDS,
                        ),
                    )
                }
                releaseFailedCommit.countDown()
                val didWrite = write.await()

                assertFalse(didWriterOverlapReader)
                assertEquals("20260725", readValue)
                assertFalse(didWrite)
                assertEquals(
                    "20260725",
                    preferences.getString(
                        RebuildIntroDailyGate.StorageKey,
                        null,
                    ),
                )
            } finally {
                releaseReader.countDown()
                releaseFailedCommit.countDown()
                assertTrue(preferences.edit().clear().commit())
            }
        }

    @Test
    fun reservationSnapshotsPublicValueInsidePublicationOrder() =
        runBlocking {
            val context =
                InstrumentationRegistry.getInstrumentation().targetContext
            val preferences = context.getSharedPreferences(
                "rebuild-intro-reservation-snapshot-${System.nanoTime()}",
                Context.MODE_PRIVATE,
            )
            assertTrue(
                preferences
                    .edit()
                    .clear()
                    .putString(
                        RebuildIntroDailyGate.StorageKey,
                        "20260725",
                    )
                    .commit(),
            )
            val publicationClaimed = CountDownLatch(1)
            val releasePublication = CountDownLatch(1)
            val secondSnapshotRead = CountDownLatch(1)
            val firstStore = SharedPreferencesRebuildIntroDateStore(
                preferences = preferences,
                onPublicationClaimed = {
                    publicationClaimed.countDown()
                    check(
                        releasePublication.await(
                            3,
                            TimeUnit.SECONDS,
                        ),
                    )
                },
            )

            try {
                val firstWrite = async(Dispatchers.Default) {
                    firstStore.writeDurably("20260726")
                }
                assertTrue(
                    publicationClaimed.await(1, TimeUnit.SECONDS),
                )
                val secondStore = SharedPreferencesRebuildIntroDateStore(
                    preferences = preferences,
                    onPublicValueRead = {
                        secondSnapshotRead.countDown()
                    },
                )
                val secondWrite = async(Dispatchers.Main) {
                    secondStore.writeDurably("20260727")
                }
                val mainThreadHeartbeat = async(Dispatchers.Main) {
                    true
                }

                assertEquals(
                    true,
                    withTimeoutOrNull(1_000) {
                        mainThreadHeartbeat.await()
                    },
                )
                val didReadBeforePublication =
                    secondSnapshotRead.await(100, TimeUnit.MILLISECONDS)
                releasePublication.countDown()
                val firstResult = firstWrite.await()
                val secondResult = secondWrite.await()

                assertFalse(didReadBeforePublication)
                assertTrue(firstResult)
                assertTrue(secondResult)
                assertEquals("20260727", secondStore.read())
            } finally {
                releasePublication.countDown()
                assertTrue(preferences.edit().clear().commit())
            }
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
