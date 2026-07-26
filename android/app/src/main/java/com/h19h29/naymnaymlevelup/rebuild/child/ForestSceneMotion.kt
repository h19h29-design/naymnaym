package com.h19h29.naymnaymlevelup.rebuild.child

enum class ForestSceneLayer(
    val zIndex: Float,
) {
    Sky(0f),
    DistantTrees(1f),
    MidgroundTrees(2f),
    ForegroundLeaves(3f),
    Ground(4f),
    ;

    companion object {
        const val ContentZIndex = 10f
    }
}

data class ForestSceneOffset(
    val x: Float,
    val y: Float,
) {
    companion object {
        val Zero = ForestSceneOffset(0f, 0f)
    }
}

data class ForestSceneFrame(
    val progress: Float,
    private val transforms: Map<ForestSceneLayer, ForestSceneOffset>,
) {
    operator fun get(layer: ForestSceneLayer): ForestSceneOffset =
        transforms[layer] ?: ForestSceneOffset.Zero
}

data class ForestSceneActivity(
    val isSheetPresented: Boolean,
    val isTabActive: Boolean,
    val isAppActive: Boolean,
) {
    val isPaused: Boolean
        get() = isSheetPresented || !isTabActive || !isAppActive

    companion object {
        val Active = ForestSceneActivity(
            isSheetPresented = false,
            isTabActive = true,
            isAppActive = true,
        )
    }
}

class ForestSceneMotionClock(
    private val startNanos: Long,
) {
    private var accumulatedPauseNanos = 0L
    private var pauseStartedAtNanos: Long? = null

    fun update(
        activity: ForestSceneActivity,
        atNanos: Long,
    ) {
        if (activity.isPaused) {
            if (pauseStartedAtNanos == null) {
                pauseStartedAtNanos = atNanos
            }
        } else {
            pauseStartedAtNanos?.let { pauseStart ->
                accumulatedPauseNanos += (atNanos - pauseStart).coerceAtLeast(0L)
                pauseStartedAtNanos = null
            }
        }
    }

    fun elapsedMillis(atNanos: Long): Long {
        val effectiveNanos = pauseStartedAtNanos ?: atNanos
        return (
            effectiveNanos - startNanos - accumulatedPauseNanos
        ).coerceAtLeast(0L) / 1_000_000L
    }
}

object ForestSceneMotionSpec {
    const val CycleDurationMillis = 8_000L

    fun frameAt(
        elapsedMillis: Long,
        reduceMotion: Boolean,
    ): ForestSceneFrame {
        if (reduceMotion) {
            return ForestSceneFrame(
                progress = 0f,
                transforms = ForestSceneLayer.entries.associateWith {
                    ForestSceneOffset.Zero
                },
            )
        }
        val wrapped = elapsedMillis.coerceAtLeast(0L) % CycleDurationMillis
        val halfCycle = CycleDurationMillis / 2f
        val progress = if (wrapped <= CycleDurationMillis / 2) {
            wrapped / halfCycle
        } else {
            (CycleDurationMillis - wrapped) / halfCycle
        }
        return ForestSceneFrame(
            progress = progress,
            transforms = mapOf(
                ForestSceneLayer.Sky to ForestSceneOffset.Zero,
                ForestSceneLayer.DistantTrees to ForestSceneOffset(
                    x = 0f,
                    y = -2f * progress,
                ),
                ForestSceneLayer.MidgroundTrees to ForestSceneOffset(
                    x = 0f,
                    y = -4f * progress,
                ),
                ForestSceneLayer.ForegroundLeaves to ForestSceneOffset(
                    x = 6f * progress,
                    y = -3f * progress,
                ),
                ForestSceneLayer.Ground to ForestSceneOffset.Zero,
            ),
        )
    }

    fun shouldScheduleFrameCallback(
        reduceMotion: Boolean,
        activity: ForestSceneActivity,
    ): Boolean = !reduceMotion && !activity.isPaused
}
