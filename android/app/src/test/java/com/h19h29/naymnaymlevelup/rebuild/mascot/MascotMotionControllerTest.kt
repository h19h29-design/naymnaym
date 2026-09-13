package com.h19h29.naymnaymlevelup.rebuild.mascot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MascotMotionControllerTest {
    @Test
    fun companionClipKeepsSafetyAndUnapprovedStagesOutOfEatingAnimation() {
        assertEquals(CompanionClip.Eating, CompanionClip.forMotion(MotionState.MealSuccess))
        assertEquals(CompanionClip.Growth, CompanionClip.forMotion(MotionState.LevelUp))
        assertEquals(CompanionClip.Greeting, CompanionClip.forMotion(MotionState.Idle))
        assertEquals(null, CompanionClip.forMotion(MotionState.Comfort))
        assertEquals(null, CompanionClip.forMotion(MotionState.ReducedMotion))
        assertTrue(CompanionClip.supports(1))
        assertEquals(false, CompanionClip.supports(2))
    }

    @Test
    fun mealSuccessUsesSquashThenJumpThenRest() {
        val controller = MascotMotionController(MotionSpec.fixture)

        assertEquals(1f, controller.pose(MotionState.MealSuccess, 0f).bodyScaleY)
        assertEquals(.96f, controller.pose(MotionState.MealSuccess, .2f).bodyScaleY)
        assertTrue(controller.pose(MotionState.MealSuccess, .5f).bodyOffsetY < 0f)
        assertEquals(MascotPose.Rest, controller.pose(MotionState.MealSuccess, 1f))
    }

    @Test
    fun reducedMotionKeepsTheBlinkExpressionWithoutSpatialMotion() {
        val pose = MascotMotionController(MotionSpec.fixture).pose(
            state = MotionState.TapReaction,
            rawProgress = .5f,
            reduceMotion = true,
        )

        assertTrue(pose.eyesClosed)
        assertEquals(MascotPose.Rest.bodyOffsetY, pose.bodyOffsetY)
        assertEquals(MascotPose.Rest.bodyScaleX, pose.bodyScaleX)
        assertEquals(MascotPose.Rest.bodyScaleY, pose.bodyScaleY)
        assertEquals(MascotPose.Rest.headRotationDegrees, pose.headRotationDegrees)
        assertEquals(MascotPose.Rest.leftArmRotationDegrees, pose.leftArmRotationDegrees)
        assertEquals(MascotPose.Rest.rightArmRotationDegrees, pose.rightArmRotationDegrees)
        assertEquals(MascotPose.Rest.tailRotationDegrees, pose.tailRotationDegrees)
    }

    @Test
    fun celebrationProjectionUsesTheApprovedKeyframeInsteadOfPartRotation() {
        val controller = MascotMotionController(MotionSpec.fixture)
        val projection = MascotRenderProjection.from(
            MotionState.MealSuccess,
            controller.pose(MotionState.MealSuccess, .5f),
        )

        assertEquals(1f, projection.celebrationBlend)
        assertEquals(1f, projection.bodyScaleX)
        assertEquals(1f, projection.bodyScaleY)
        assertEquals(-52f, projection.bodyOffsetY)
        assertEquals(-2f, projection.wholeCharacterRotationDegrees)
    }

    @Test
    fun idleAndReducedMotionRemainStaticWhileIdleProgressStillLoops() {
        val controller = MascotMotionController(MotionSpec.fixture)

        assertEquals(.1f, controller.progress(MotionState.Idle, 6_600L))
        assertEquals(MascotPose.Rest, controller.pose(MotionState.Idle, .4f))
        assertEquals(MascotPose.Rest, controller.pose(MotionState.ReducedMotion, .4f))
        assertTrue(
            !controller.playback(
                MotionState.Idle,
                eventRevision = 0,
                reduceMotion = false,
            ).isActive,
        )
        assertTrue(
            controller.playback(
                MotionState.MealSuccess,
                eventRevision = 1,
                reduceMotion = true,
            ).isActive,
        )
    }

    @Test
    fun consecutiveMealSuccessEventsCreateFreshPlaybackSessions() {
        val controller = MascotMotionController(MotionSpec.fixture)

        val first = controller.playback(
            state = MotionState.MealSuccess,
            eventRevision = 1,
            reduceMotion = false,
        )
        val second = controller.playback(
            state = MotionState.MealSuccess,
            eventRevision = 2,
            reduceMotion = false,
        )

        assertNotEquals(first.key, second.key)
        assertEquals(MascotPose.Rest, second.poseAt(0))
        assertTrue(second.poseAt(700).bodyOffsetY < 0f)
    }

    @Test
    fun reducedPlaybackUses250MillisecondsThenReturnsToSpatialRest() {
        val playback = MascotMotionController(MotionSpec.fixture).playback(
            state = MotionState.MealSuccess,
            eventRevision = 1,
            reduceMotion = true,
        )

        assertEquals(250L, playback.durationMs)
        assertEquals(MascotPose.Rest, playback.poseAt(0))
        assertExpressionOnlyBlink(playback.poseAt(125))
        assertEquals(1f, playback.expressionBlendAt(125))
        assertEquals(MascotPose.Rest, playback.poseAt(250))
        assertEquals(0f, playback.expressionBlendAt(250))
        assertEquals(MascotPose.Rest, playback.poseAt(10_000))
    }

    private fun assertExpressionOnlyBlink(pose: MascotPose) {
        assertTrue(pose.eyesClosed)
        assertEquals(0f, pose.bodyOffsetY)
        assertEquals(1f, pose.bodyScaleX)
        assertEquals(1f, pose.bodyScaleY)
        assertEquals(0f, pose.headRotationDegrees)
        assertEquals(0f, pose.leftArmRotationDegrees)
        assertEquals(0f, pose.rightArmRotationDegrees)
        assertEquals(0f, pose.tailRotationDegrees)
    }
}
