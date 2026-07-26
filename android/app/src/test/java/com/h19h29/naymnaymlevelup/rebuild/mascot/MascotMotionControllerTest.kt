package com.h19h29.naymnaymlevelup.rebuild.mascot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MascotMotionControllerTest {
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
        assertTrue(!controller.isPlaybackActive(MotionState.Idle, reduceMotion = false))
        assertTrue(!controller.isPlaybackActive(MotionState.MealSuccess, reduceMotion = true))
    }
}
