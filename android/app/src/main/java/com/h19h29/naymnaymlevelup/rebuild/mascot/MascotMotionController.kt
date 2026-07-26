package com.h19h29.naymnaymlevelup.rebuild.mascot

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/** Deterministic, Android-free state-to-pose sampling. */
class MascotMotionController(private val spec: MotionSpec) {
    fun pose(state: MotionState, rawProgress: Float, reduceMotion: Boolean = false): MascotPose {
        val progress = rawProgress.coerceIn(0f, 1f)
        val fullMotionPose = fullMotionPose(state, progress)
        return if (reduceMotion) {
            MascotPose.Rest.copy(
                eyesClosed = progress in 0.35f..0.65f,
                smiling = fullMotionPose.smiling,
            )
        } else {
            fullMotionPose
        }
    }

    fun progress(state: MotionState, elapsedMs: Long): Float {
        val elapsed = elapsedMs.coerceAtLeast(0)
        val stateSpec = spec.stateFor(state)
        return if (stateSpec.loops) {
            (elapsed % stateSpec.durationMs).toFloat() / stateSpec.durationMs
        } else {
            (elapsed.toFloat() / stateSpec.durationMs).coerceAtMost(1f)
        }
    }

    fun isPlaybackActive(state: MotionState, reduceMotion: Boolean): Boolean =
        !reduceMotion && state != MotionState.Idle && state != MotionState.ReducedMotion

    private fun fullMotionPose(state: MotionState, progress: Float): MascotPose {
        if (progress <= 0f || progress >= 1f) return MascotPose.Rest
        return when (state) {
            MotionState.Idle, MotionState.ReducedMotion -> MascotPose.Rest
            MotionState.TapReaction -> {
                val peak = triangularPeak(progress)
                MascotPose(-8f * peak, 1f + .015f * peak, 1f - .015f * peak, -4f * peak, 3f * peak, -3f * peak, 4f * peak, progress in .35f.. .65f, true)
            }
            MotionState.MealSuccess -> mealSuccessPose(progress)
            MotionState.LevelUp -> {
                val peak = sin(progress * PI.toFloat())
                MascotPose(-36f * peak, 1f + .04f * peak, 1f - .04f * peak, -2f * peak, 12f * peak, -12f * peak, 8f * peak, false, true)
            }
            MotionState.Comfort -> {
                val peak = sin(progress * PI.toFloat())
                MascotPose(-3f * peak, 1f, 1f, -5f * peak, 5f * peak, -2f * peak, -5f * peak, progress in .3f.. .7f, true)
            }
        }
    }

    private fun mealSuccessPose(progress: Float): MascotPose {
        if (progress <= .2f) {
            val amount = progress / .2f
            return MascotPose.Rest.copy(bodyScaleX = 1f + .04f * amount, bodyScaleY = 1f - .04f * amount)
        }
        val amount = if (progress <= .5f) (progress - .2f) / .3f else (1f - progress) / .5f
        return MascotPose(-52f * amount, 1f + .04f * amount, 1f - .04f * amount, -2f * amount, 12f * amount, -12f * amount, 8f * amount, false, true)
    }

    private fun triangularPeak(progress: Float): Float = 1f - abs((2f * progress) - 1f)
}
