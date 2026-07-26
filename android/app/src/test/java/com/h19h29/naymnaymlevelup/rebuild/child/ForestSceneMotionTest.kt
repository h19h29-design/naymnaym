package com.h19h29.naymnaymlevelup.rebuild.child

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ForestSceneMotionTest {
    @Test
    fun processAssetCacheLoadsEachLayerOnlyOnce() {
        val cache = ForestSceneProcessCache<String>()
        var loadCount = 0

        repeat(2) {
            ForestSceneLayer.entries.forEach { layer ->
                val value = cache.getOrLoad(layer) {
                    loadCount += 1
                    "decoded-${layer.name}"
                }
                assertEquals("decoded-${layer.name}", value)
            }
        }

        assertEquals(ForestSceneLayer.entries.size, loadCount)
    }

    @Test
    fun eightSecondTriangleCycleUsesSharedDepthOffsets() {
        val samples = listOf(
            0L to 0f,
            2_000L to 0.5f,
            4_000L to 1f,
            6_000L to 0.5f,
            8_000L to 0f,
        )

        samples.forEach { (elapsed, progress) ->
            val frame = ForestSceneMotionSpec.frameAt(
                elapsedMillis = elapsed,
                reduceMotion = false,
            )
            assertEquals(progress, frame.progress, 0.0001f)
            assertEquals(-2f * progress, frame[ForestSceneLayer.DistantTrees].y, 0.0001f)
            assertEquals(-4f * progress, frame[ForestSceneLayer.MidgroundTrees].y, 0.0001f)
            assertEquals(6f * progress, frame[ForestSceneLayer.ForegroundLeaves].x, 0.0001f)
            assertEquals(-3f * progress, frame[ForestSceneLayer.ForegroundLeaves].y, 0.0001f)
            assertEquals(ForestSceneOffset.Zero, frame[ForestSceneLayer.Ground])
        }
    }

    @Test
    fun reduceMotionUsesZeroTransformsAndNoFrameCallback() {
        val frame = ForestSceneMotionSpec.frameAt(
            elapsedMillis = 4_000,
            reduceMotion = true,
        )

        assertEquals(0f, frame.progress, 0f)
        ForestSceneLayer.entries.forEach {
            assertEquals(ForestSceneOffset.Zero, frame[it])
        }
        assertFalse(
            ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion = true,
                activity = ForestSceneActivity.Active,
            ),
        )
    }

    @Test
    fun sheetTabAndAppPauseSourcesFreezeThenResumeWithoutJump() {
        val clock = ForestSceneMotionClock(startNanos = 0)

        assertEquals(1_000L, clock.elapsedMillis(1_000_000_000))
        clock.update(
            ForestSceneActivity(
                isSheetPresented = true,
                isTabActive = true,
                isAppActive = true,
            ),
            atNanos = 1_000_000_000,
        )
        assertEquals(1_000L, clock.elapsedMillis(5_000_000_000))

        clock.update(ForestSceneActivity.Active, atNanos = 5_000_000_000)
        assertEquals(2_000L, clock.elapsedMillis(6_000_000_000))

        clock.update(
            ForestSceneActivity(
                isSheetPresented = false,
                isTabActive = false,
                isAppActive = true,
            ),
            atNanos = 6_000_000_000,
        )
        assertEquals(2_000L, clock.elapsedMillis(9_000_000_000))

        clock.update(ForestSceneActivity.Active, atNanos = 9_000_000_000)
        clock.update(
            ForestSceneActivity(
                isSheetPresented = false,
                isTabActive = true,
                isAppActive = false,
            ),
            atNanos = 10_000_000_000,
        )
        assertEquals(3_000L, clock.elapsedMillis(14_000_000_000))

        assertFalse(
            ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion = false,
                activity = ForestSceneActivity(
                    isSheetPresented = false,
                    isTabActive = true,
                    isAppActive = false,
                ),
            ),
        )
        assertTrue(
            ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion = false,
                activity = ForestSceneActivity.Active,
            ),
        )
    }

    @Test
    fun decorativeLayersStayBelowContent() {
        assertEquals(
            listOf(
                ForestSceneLayer.Sky,
                ForestSceneLayer.DistantTrees,
                ForestSceneLayer.MidgroundTrees,
                ForestSceneLayer.ForegroundLeaves,
                ForestSceneLayer.Ground,
            ),
            ForestSceneLayer.entries,
        )
        assertTrue(ForestSceneLayer.entries.all { it.zIndex < ForestSceneLayer.ContentZIndex })
    }
}
