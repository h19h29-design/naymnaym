package com.h19h29.naymnaymlevelup.rebuild.onboarding

import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RebuildIntroMotionTest {
    @Test
    fun normalFramesUseApprovedBoundariesAndBecomeExactlyStatic() {
        val initial = RebuildIntroMotionSpec.frameAt(0, reduceMotion = false)
        assertEquals(0f, initial.leftWord.opacity, EPSILON)
        assertEquals(10f, initial.leftWord.translationY, EPSILON)
        assertEquals(.988f, initial.leftWord.scale, EPSILON)
        assertEquals(initial.leftWord, initial.rightWord)
        assertNull(initial.shineProgress)
        assertFalse(initial.rendersWholeLogo)

        val leftStart = RebuildIntroMotionSpec.frameAt(40, reduceMotion = false)
        assertEquals(initial.leftWord, leftStart.leftWord)
        assertEquals(initial.rightWord, leftStart.rightWord)

        val rightStart = RebuildIntroMotionSpec.frameAt(340, reduceMotion = false)
        assertTrue(rightStart.leftWord.opacity > 0f)
        assertTrue(rightStart.leftWord.translationY < 10f)
        assertEquals(initial.rightWord, rightStart.rightWord)

        val leftMiddle = RebuildIntroMotionSpec.frameAt(420, reduceMotion = false)
        assertEquals(.911_465f, leftMiddle.leftWord.opacity, .000_01f)

        val leftEnd = RebuildIntroMotionSpec.frameAt(800, reduceMotion = false)
        assertEquals(RebuildIntroWordFrame.Visible, leftEnd.leftWord)
        assertTrue(leftEnd.rightWord != RebuildIntroWordFrame.Visible)

        val rightEnd = RebuildIntroMotionSpec.frameAt(1_100, reduceMotion = false)
        assertEquals(RebuildIntroWordFrame.Visible, rightEnd.leftWord)
        assertEquals(RebuildIntroWordFrame.Visible, rightEnd.rightWord)
        assertNull(rightEnd.shineProgress)

        val shineStart = RebuildIntroMotionSpec.frameAt(1_180, reduceMotion = false)
        assertEquals(0f, shineStart.shineProgress ?: -1f, EPSILON)
        assertFalse(shineStart.rendersWholeLogo)
        val shineMiddle = RebuildIntroMotionSpec.frameAt(1_590, reduceMotion = false)
        assertEquals(.5f, shineMiddle.shineProgress ?: -1f, EPSILON)

        val final = RebuildIntroMotionSpec.frameAt(2_000, reduceMotion = false)
        assertEquals(RebuildIntroWordFrame.Visible, final.leftWord)
        assertEquals(RebuildIntroWordFrame.Visible, final.rightWord)
        assertEquals(1f, final.wholeLogoOpacity, EPSILON)
        assertNull(final.shineProgress)
        assertTrue(final.rendersWholeLogo)
        assertEquals(final, RebuildIntroMotionSpec.frameAt(2_500, false))
        assertEquals(final, RebuildIntroMotionSpec.frameAt(200_000, false))
    }

    @Test
    fun timingAndComplementaryMaskUseTheApprovedTransparentGap() {
        assertEquals(.40f, RebuildIntroMotionSpec.SplitFraction, EPSILON)
        assertEquals(40L, RebuildIntroMotionSpec.LeftStartMillis)
        assertEquals(340L, RebuildIntroMotionSpec.RightStartMillis)
        assertEquals(760L, RebuildIntroMotionSpec.RiseDurationMillis)
        assertEquals(1_180L, RebuildIntroMotionSpec.ShineStartMillis)
        assertEquals(820L, RebuildIntroMotionSpec.ShineDurationMillis)

        val layout = RebuildIntroMaskLayout(sourceWidth = 357f)
        assertEquals(0f, layout.left.start, EPSILON)
        assertEquals(layout.left.endExclusive, layout.right.start, EPSILON)
        assertEquals(357f, layout.right.endExclusive, EPSILON)
        assertTrue(layout.left.endExclusive > 139f)
        assertTrue(layout.left.endExclusive < 146f)
    }

    @Test
    fun reduceMotionUsesOnlyWholeLogoQuarterSecondFade() {
        val initial = RebuildIntroMotionSpec.frameAt(0, reduceMotion = true)
        assertEquals(0f, initial.wholeLogoOpacity, EPSILON)
        assertEquals(RebuildIntroWordFrame.Visible, initial.leftWord)
        assertEquals(RebuildIntroWordFrame.Visible, initial.rightWord)
        assertNull(initial.shineProgress)
        assertTrue(initial.rendersWholeLogo)

        val middle = RebuildIntroMotionSpec.frameAt(125, reduceMotion = true)
        assertEquals(.5f, middle.wholeLogoOpacity, EPSILON)
        assertEquals(0f, middle.leftWord.translationY, EPSILON)
        assertEquals(0f, middle.rightWord.translationY, EPSILON)
        assertEquals(1f, middle.leftWord.scale, EPSILON)
        assertEquals(1f, middle.rightWord.scale, EPSILON)
        assertNull(middle.shineProgress)

        val final = RebuildIntroMotionSpec.frameAt(250, reduceMotion = true)
        assertEquals(1f, final.wholeLogoOpacity, EPSILON)
        assertEquals(final, RebuildIntroMotionSpec.frameAt(2_500, true))
    }

    @Test
    fun secondStartCannotResetSequenceAndCancellationBlocksLateCompletion() = runTest {
        val firstSleep = CompletableDeferred<Unit>()
        var completions = 0
        val controller = RebuildIntroMotionController(
            sleepMillis = { firstSleep.await() },
        )

        val run = async {
            controller.start(reduceMotion = false) {
                completions += 1
            }
        }
        runCurrent()
        assertEquals(false, controller.effectiveReduceMotion)
        val firstElapsed = controller.elapsedMillis

        assertFalse(
            controller.start(reduceMotion = true) {
                completions += 100
            },
        )
        assertEquals(false, controller.effectiveReduceMotion)
        assertEquals(firstElapsed, controller.elapsedMillis)

        controller.cancel()
        firstSleep.complete(Unit)
        runCurrent()
        run.await()

        assertEquals(firstElapsed, controller.elapsedMillis)
        assertFalse(controller.isComplete)
        assertEquals(0, completions)
    }

    @Test
    fun presentationLatchesReducedMotionInBothToggleDirections() = runTest {
        val normalSleep = CompletableDeferred<Unit>()
        val normal = RebuildIntroMotionController {
            normalSleep.await()
        }
        val normalRun = async {
            normal.start(reduceMotion = false) {}
        }
        runCurrent()
        assertFalse(normal.start(reduceMotion = true) {})
        assertEquals(false, normal.effectiveReduceMotion)
        normal.cancel()
        normalSleep.complete(Unit)
        runCurrent()
        normalRun.await()

        val reducedSleep = CompletableDeferred<Unit>()
        val reduced = RebuildIntroMotionController {
            reducedSleep.await()
        }
        val reducedRun = async {
            reduced.start(reduceMotion = true) {}
        }
        runCurrent()
        assertFalse(reduced.start(reduceMotion = false) {})
        assertEquals(true, reduced.effectiveReduceMotion)
        reduced.cancel()
        reducedSleep.complete(Unit)
        runCurrent()
        reducedRun.await()
    }

    @Test
    fun dailyGateCommitsOnlyOnCompletionAndSurvivesRecreationInLocalZone() =
        runTest {
        val zone = ZoneId.of("Asia/Seoul")
        val firstDayClock = Clock.fixed(
            Instant.parse("2026-07-26T14:59:00Z"),
            zone,
        )
        val store = MemoryIntroDateStore()
        val firstGate = RebuildIntroDailyGate(store, firstDayClock, zone)

        assertTrue(firstGate.shouldPresent())
        assertEquals(0, store.writeCount)
        assertNull(store.value)

        assertTrue(firstGate.markCompleted())
        assertEquals("20260726", store.value)
        assertEquals(1, store.writeCount)

        val recreated = RebuildIntroDailyGate(store, firstDayClock, zone)
        assertFalse(recreated.shouldPresent())

        val nextDayClock = Clock.fixed(
            Instant.parse("2026-07-26T15:01:00Z"),
            zone,
        )
        val nextDay = RebuildIntroDailyGate(store, nextDayClock, zone)
        assertTrue(nextDay.shouldPresent())
        assertEquals(1, store.writeCount)
        }

    @Test
    fun missingAndMalformedDailyValuesKeepIntroAheadOfBootstrap() {
        val zone = ZoneId.of("Asia/Seoul")
        val clock = Clock.fixed(
            Instant.parse("2026-07-26T03:00:00Z"),
            zone,
        )
        val missing = RebuildIntroEntryController(
            RebuildIntroDailyGate(MemoryIntroDateStore(), clock, zone),
        )
        assertTrue(missing.showIntro)
        assertFalse(missing.canLoadBootstrap)

        val malformedStore = MemoryIntroDateStore().apply {
            value = "July 26"
        }
        val malformed = RebuildIntroEntryController(
            RebuildIntroDailyGate(malformedStore, clock, zone),
        )
        assertTrue(malformed.showIntro)
        assertFalse(malformed.canLoadBootstrap)
    }

    @Test
    fun dailyGateReevaluatesInjectedLocalZoneAfterTravel() = runTest {
        val instant = Instant.parse("2026-07-26T16:30:00Z")
        val store = MemoryIntroDateStore()
        var zone = ZoneId.of("UTC")
        val gate = RebuildIntroDailyGate(
            store = store,
            clock = Clock.fixed(instant, ZoneId.of("UTC")),
            zoneProvider = { zone },
        )

        assertTrue(gate.markCompleted())
        assertEquals("20260726", store.value)
        assertFalse(gate.shouldPresent())

        zone = ZoneId.of("Asia/Seoul")

        assertTrue(gate.shouldPresent())
        assertTrue(gate.markCompleted())
        assertEquals("20260727", store.value)
    }

    @Test
    fun failedDurableCommitKeepsIntroActiveAndBootstrapBlocked() = runTest {
        val zone = ZoneId.of("Asia/Seoul")
        val clock = Clock.fixed(
            Instant.parse("2026-07-26T03:00:00Z"),
            zone,
        )
        val store = MemoryIntroDateStore(acceptsWrites = false)
        val entry = RebuildIntroEntryController(
            RebuildIntroDailyGate(store, clock, zone),
        )

        assertFalse(entry.completeIntro())

        assertTrue(entry.showIntro)
        assertFalse(entry.canLoadBootstrap)
        assertNull(store.value)
        assertEquals(1, store.writeCount)

        store.acceptsWrites = true
        assertTrue(entry.completeIntro())
        assertFalse(entry.showIntro)
        assertTrue(entry.canLoadBootstrap)
        assertEquals("20260726", store.value)
    }

    @Test
    fun activeIntroMustCompleteBeforeBootstrapCanLoad() = runTest {
        val zone = ZoneId.of("Asia/Seoul")
        val clock = Clock.fixed(
            Instant.parse("2026-07-26T03:00:00Z"),
            zone,
        )
        val entry = RebuildIntroEntryController(
            RebuildIntroDailyGate(MemoryIntroDateStore(), clock, zone),
        )
        assertTrue(entry.showIntro)
        assertFalse(entry.canLoadBootstrap)

        assertTrue(entry.completeIntro())

        assertFalse(entry.showIntro)
        assertTrue(entry.canLoadBootstrap)
    }

    @Test
    fun delayedPersistenceKeepsIntroActiveUntilCommitSucceeds() = runTest {
        val writeStarted = CompletableDeferred<Unit>()
        val writeResult = CompletableDeferred<Boolean>()
        var writeCount = 0
        val store = object : RebuildIntroDateStore {
            override fun read(): String? = null

            override suspend fun writeDurably(value: String): Boolean {
                writeCount += 1
                writeStarted.complete(Unit)
                return writeResult.await()
            }
        }
        val zone = ZoneId.of("Asia/Seoul")
        val clock = Clock.fixed(
            Instant.parse("2026-07-26T03:00:00Z"),
            zone,
        )
        val entry = RebuildIntroEntryController(
            RebuildIntroDailyGate(store, clock, zone),
        )

        val completion = async { entry.completeIntro() }
        writeStarted.await()
        val joinedCompletion = async { entry.completeIntro() }
        runCurrent()
        assertEquals(1, writeCount)
        assertTrue(entry.showIntro)
        assertFalse(entry.canLoadBootstrap)

        writeResult.complete(true)
        assertTrue(completion.await())
        assertTrue(joinedCompletion.await())
        assertEquals(1, writeCount)
        assertFalse(entry.showIntro)
        assertTrue(entry.canLoadBootstrap)
    }

    @Test
    fun inFlightRefreshCannotConsumePendingValueAndRolloverBlocksCompletion() =
        runTest {
            val writeStarted = CompletableDeferred<Unit>()
            val writeResult = CompletableDeferred<Boolean>()
            var storedValue: String? = null
            val store = object : RebuildIntroDateStore {
                override fun read(): String? = storedValue

                override suspend fun writeDurably(value: String): Boolean {
                    storedValue = value
                    writeStarted.complete(Unit)
                    return writeResult.await()
                }
            }
            val instant = Instant.parse("2026-07-26T16:30:00Z")
            var zone = ZoneId.of("UTC")
            val entry = RebuildIntroEntryController(
                RebuildIntroDailyGate(
                    store = store,
                    clock = Clock.fixed(instant, ZoneId.of("UTC")),
                    zoneProvider = { zone },
                ),
            )

            val completion = async { entry.completeIntro() }
            writeStarted.await()
            assertEquals("20260726", storedValue)

            entry.refresh()
            assertTrue(entry.showIntro)
            assertFalse(entry.canLoadBootstrap)

            zone = ZoneId.of("Asia/Seoul")
            entry.refresh()
            writeResult.complete(true)

            assertFalse(completion.await())
            assertTrue(entry.showIntro)
            assertFalse(entry.canLoadBootstrap)
            assertEquals("20260726", storedValue)
        }

    private class MemoryIntroDateStore(
        var acceptsWrites: Boolean = true,
    ) : RebuildIntroDateStore {
        var value: String? = null
        var writeCount = 0

        override fun read(): String? = value

        override suspend fun writeDurably(value: String): Boolean {
            writeCount += 1
            if (!acceptsWrites) return false
            this.value = value
            return true
        }
    }

    private companion object {
        const val EPSILON = .000_001f
    }
}
