package com.h19h29.naymnaymlevelup.rebuild.mascot

enum class MotionState { Idle, TapReaction, MealSuccess, LevelUp, Comfort, ReducedMotion }

data class MotionSpec(val states: Map<MotionState, State>) {
    data class State(val durationMs: Long, val loops: Boolean)
    fun stateFor(state: MotionState): State = checkNotNull(states[state])

    companion object {
        val fixture = MotionSpec(
            mapOf(
                MotionState.Idle to State(6_000, true),
                MotionState.TapReaction to State(420, false),
                MotionState.MealSuccess to State(1_400, false),
                MotionState.LevelUp to State(3_000, false),
                MotionState.Comfort to State(1_200, false),
                MotionState.ReducedMotion to State(250, false),
            ),
        )
    }
}

data class MascotPose(
    val bodyOffsetY: Float,
    val bodyScaleX: Float,
    val bodyScaleY: Float,
    val headRotationDegrees: Float,
    val leftArmRotationDegrees: Float,
    val rightArmRotationDegrees: Float,
    val tailRotationDegrees: Float,
    val eyesClosed: Boolean,
    val smiling: Boolean,
) {
    companion object {
        val Rest = MascotPose(0f, 1f, 1f, 0f, 0f, 0f, 0f, false, true)
    }
}

data class MascotRenderProjection(
    val celebrationBlend: Float,
    val bodyOffsetY: Float,
    val bodyScaleX: Float,
    val bodyScaleY: Float,
    val wholeCharacterRotationDegrees: Float,
    val eyesClosed: Boolean,
    val smiling: Boolean,
) {
    companion object {
        fun from(state: MotionState, pose: MascotPose): MascotRenderProjection {
            val blend = when (state) {
                MotionState.MealSuccess, MotionState.LevelUp -> maxOf(
                    kotlin.math.abs(pose.leftArmRotationDegrees) / 12f,
                    kotlin.math.abs(pose.rightArmRotationDegrees) / 12f,
                    kotlin.math.abs(pose.tailRotationDegrees) / 8f,
                ).coerceIn(0f, 1f)
                else -> 0f
            }
            return MascotRenderProjection(
                celebrationBlend = blend,
                bodyOffsetY = pose.bodyOffsetY,
                bodyScaleX = 1f + ((pose.bodyScaleX - 1f) * (1f - blend)),
                bodyScaleY = 1f + ((pose.bodyScaleY - 1f) * (1f - blend)),
                wholeCharacterRotationDegrees = pose.headRotationDegrees,
                eyesClosed = pose.eyesClosed,
                smiling = pose.smiling,
            )
        }
    }
}

enum class MascotRigSemanticPart {
    TailBack, Body, Scarf, Head, ArmLeft, ArmRight, EyesOpen, EyesClosed, MouthNeutral, MouthSmile, Sprout,
}

fun com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.toMascotMotionState(): MotionState =
    when (this) {
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.Idle -> MotionState.Idle
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.TapReaction -> MotionState.TapReaction
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.MealSuccess -> MotionState.MealSuccess
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.LevelUp -> MotionState.LevelUp
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.Comfort -> MotionState.Comfort
        com.h19h29.naymnaymlevelup.rebuild.meal.MotionState.ReducedMotion -> MotionState.ReducedMotion
    }
