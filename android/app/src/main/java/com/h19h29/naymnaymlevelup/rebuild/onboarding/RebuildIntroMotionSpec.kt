package com.h19h29.naymnaymlevelup.rebuild.onboarding

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

data class RebuildIntroWordFrame(
    val opacity: Float,
    val translationY: Float,
    val scale: Float,
) {
    companion object {
        val Hidden = RebuildIntroWordFrame(
            opacity = 0f,
            translationY = RebuildIntroMotionSpec.InitialTranslationY,
            scale = RebuildIntroMotionSpec.InitialScale,
        )
        val Visible = RebuildIntroWordFrame(
            opacity = 1f,
            translationY = 0f,
            scale = 1f,
        )
    }
}

data class RebuildIntroLogoFrame(
    val leftWord: RebuildIntroWordFrame,
    val rightWord: RebuildIntroWordFrame,
    val wholeLogoOpacity: Float,
    val shineProgress: Float?,
    val rendersWholeLogo: Boolean,
)

data class RebuildIntroFloatRange(
    val start: Float,
    val endExclusive: Float,
)

data class RebuildIntroMaskLayout(
    val left: RebuildIntroFloatRange,
    val right: RebuildIntroFloatRange,
) {
    constructor(sourceWidth: Float) : this(
        left = RebuildIntroFloatRange(
            start = 0f,
            endExclusive = sourceWidth * RebuildIntroMotionSpec.SplitFraction,
        ),
        right = RebuildIntroFloatRange(
            start = sourceWidth * RebuildIntroMotionSpec.SplitFraction,
            endExclusive = sourceWidth,
        ),
    )
}

object RebuildIntroMotionSpec {
    const val SourceWidth = 357f
    const val SourceHeight = 86f
    const val SourceAspectRatio = SourceWidth / SourceHeight
    const val SplitFraction = .40f
    const val InitialTranslationY = 10f
    const val InitialScale = .988f
    const val LeftStartMillis = 40L
    const val RightStartMillis = 340L
    const val RiseDurationMillis = 760L
    const val ShineStartMillis = 1_180L
    const val ShineDurationMillis = 820L
    const val NormalDurationMillis = 2_000L
    const val ReduceMotionDurationMillis = 250L
    const val FrameIntervalMillis = 16L

    fun frameAt(
        elapsedMillis: Long,
        reduceMotion: Boolean,
    ): RebuildIntroLogoFrame {
        val elapsed = elapsedMillis.coerceAtLeast(0)
        if (reduceMotion) {
            val opacity = (elapsed.toFloat() / ReduceMotionDurationMillis)
                .coerceIn(0f, 1f)
            return RebuildIntroLogoFrame(
                leftWord = RebuildIntroWordFrame.Visible,
                rightWord = RebuildIntroWordFrame.Visible,
                wholeLogoOpacity = opacity,
                shineProgress = null,
                rendersWholeLogo = true,
            )
        }

        if (elapsed >= NormalDurationMillis) {
            return RebuildIntroLogoFrame(
                leftWord = RebuildIntroWordFrame.Visible,
                rightWord = RebuildIntroWordFrame.Visible,
                wholeLogoOpacity = 1f,
                shineProgress = null,
                rendersWholeLogo = true,
            )
        }

        val shineProgress = if (elapsed >= ShineStartMillis) {
            ((elapsed - ShineStartMillis).toFloat() / ShineDurationMillis)
                .coerceIn(0f, 1f)
        } else {
            null
        }
        return RebuildIntroLogoFrame(
            leftWord = wordFrame(elapsed, LeftStartMillis),
            rightWord = wordFrame(elapsed, RightStartMillis),
            wholeLogoOpacity = 1f,
            shineProgress = shineProgress,
            rendersWholeLogo = false,
        )
    }

    fun durationMillis(reduceMotion: Boolean): Long = if (reduceMotion) {
        ReduceMotionDurationMillis
    } else {
        NormalDurationMillis
    }

    private fun wordFrame(
        elapsedMillis: Long,
        startMillis: Long,
    ): RebuildIntroWordFrame {
        val linear = (
            (elapsedMillis - startMillis).toDouble() /
                RiseDurationMillis.toDouble()
            ).coerceIn(0.0, 1.0)
        val progress = cubicBezierEase(linear).toFloat()
        return RebuildIntroWordFrame(
            opacity = progress,
            translationY = InitialTranslationY * (1f - progress),
            scale = InitialScale + ((1f - InitialScale) * progress),
        )
    }

    // CSS-equivalent cubic-bezier(.22, .78, .36, 1).
    private fun cubicBezierEase(progress: Double): Double {
        if (progress <= 0) return 0.0
        if (progress >= 1) return 1.0

        var lower = 0.0
        var upper = 1.0
        repeat(18) {
            val parameter = (lower + upper) / 2
            if (cubicCoordinate(parameter, .22, .36) < progress) {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return cubicCoordinate((lower + upper) / 2, .78, 1.0)
    }

    private fun cubicCoordinate(
        parameter: Double,
        first: Double,
        second: Double,
    ): Double {
        val inverse = 1 - parameter
        return (3 * inverse * inverse * parameter * first) +
            (3 * inverse * parameter * parameter * second) +
            (parameter * parameter * parameter)
    }
}

class RebuildIntroMotionController(
    private val sleepMillis: suspend (Long) -> Unit = { delay(it) },
) {
    var elapsedMillis by mutableLongStateOf(0)
        private set
    var isComplete by mutableStateOf(false)
        private set
    var effectiveReduceMotion by mutableStateOf<Boolean?>(null)
        private set
    var hasStarted by mutableStateOf(false)
        private set

    private var generation = 0

    suspend fun start(
        reduceMotion: Boolean,
        onCompleted: () -> Unit,
    ): Boolean {
        if (hasStarted) return false
        hasStarted = true
        isComplete = false
        elapsedMillis = 0
        effectiveReduceMotion = reduceMotion
        generation += 1
        val playbackGeneration = generation
        val duration = RebuildIntroMotionSpec.durationMillis(reduceMotion)
        var sampledElapsed = 0L

        try {
            while (sampledElapsed < duration) {
                val delta = min(
                    RebuildIntroMotionSpec.FrameIntervalMillis,
                    duration - sampledElapsed,
                )
                sleepMillis(delta)
                if (
                    playbackGeneration != generation
                ) {
                    return true
                }
                sampledElapsed += delta
                elapsedMillis = sampledElapsed
            }
        } catch (cancellation: CancellationException) {
            if (playbackGeneration == generation) {
                generation += 1
            }
            throw cancellation
        }

        if (playbackGeneration != generation) return true
        elapsedMillis = duration
        isComplete = true
        onCompleted()
        return true
    }

    fun cancel() {
        generation += 1
    }
}

interface RebuildIntroDateStore {
    fun read(): String?
    suspend fun writeDurably(value: String): Boolean
}

private object RebuildIntroPreferencesCoordinator {
    private val writerLock =
        java.util.concurrent.locks.ReentrantLock()
    private var activeWriteCount = 0

    fun beginWrite() {
        writerLock.lock()
        synchronized(this) {
            activeWriteCount += 1
        }
    }

    fun endWrite() {
        synchronized(this) {
            activeWriteCount -= 1
        }
        writerLock.unlock()
    }

    fun <Result> withStableRead(
        block: (isWriteInFlight: Boolean) -> Result,
    ): Result = synchronized(this) {
        block(activeWriteCount > 0)
    }
}

class SharedPreferencesRebuildIntroDateStore(
    private val preferences: SharedPreferences,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val commit: (SharedPreferences.Editor) -> Boolean = {
        it.commit()
    },
) : RebuildIntroDateStore {
    override fun read(): String? =
        RebuildIntroPreferencesCoordinator.withStableRead {
            isWriteInFlight ->
            val publicValue = preferences.getString(
                RebuildIntroDailyGate.StorageKey,
                null,
            )
            if (isWriteInFlight) {
                return@withStableRead publicValue
            }
            if (!preferences.contains(DurableValueKey) ||
                !preferences.contains(DurablePreviousPublicValueKey)
            ) {
                return@withStableRead publicValue
            }

            val durableValue = preferences.getString(DurableValueKey, null)
                ?: return@withStableRead publicValue
            val previousPublicValue = preferences.getString(
                DurablePreviousPublicValueKey,
                null,
            ) ?: return@withStableRead publicValue
            if (publicValue == durableValue) {
                return@withStableRead durableValue
            }
            if ((publicValue ?: "") != previousPublicValue) {
                return@withStableRead publicValue
            }

            preferences
                .edit()
                .putString(RebuildIntroDailyGate.StorageKey, durableValue)
                .apply()
            durableValue
        }

    override suspend fun writeDurably(value: String): Boolean =
        withContext(ioDispatcher) {
            RebuildIntroPreferencesCoordinator.beginWrite()
            try {
                val previousPublicValue = preferences.getString(
                    RebuildIntroDailyGate.StorageKey,
                    null,
                )
                val hadPreviousDurableValue =
                    preferences.contains(DurableValueKey)
                val previousDurableValue = preferences.getString(
                    DurableValueKey,
                    null,
                )
                val hadPreviousDurablePublicValue =
                    preferences.contains(DurablePreviousPublicValueKey)
                val previousDurablePublicValue = preferences.getString(
                    DurablePreviousPublicValueKey,
                    null,
                )
                val didCommit = commit(
                    preferences
                        .edit()
                        .putString(DurableValueKey, value)
                        .putString(
                            DurablePreviousPublicValueKey,
                            previousPublicValue ?: "",
                        ),
                )
                val didReadBack =
                    preferences.getString(DurableValueKey, null) == value &&
                        preferences.getString(
                            DurablePreviousPublicValueKey,
                            null,
                        ) == (previousPublicValue ?: "")

                if (didCommit && didReadBack) {
                    preferences
                        .edit()
                        .putString(RebuildIntroDailyGate.StorageKey, value)
                        .apply()
                    true
                } else {
                    val rollback = preferences.edit()
                    if (hadPreviousDurableValue) {
                        rollback.putString(
                            DurableValueKey,
                            previousDurableValue,
                        )
                    } else {
                        rollback.remove(DurableValueKey)
                    }
                    if (hadPreviousDurablePublicValue) {
                        rollback.putString(
                            DurablePreviousPublicValueKey,
                            previousDurablePublicValue,
                        )
                    } else {
                        rollback.remove(DurablePreviousPublicValueKey)
                    }
                    rollback.commit()
                    false
                }
            } finally {
                RebuildIntroPreferencesCoordinator.endWrite()
            }
        }

    private companion object {
        const val DurableValueKey =
            "last-intro-date.rebuild-durable-value"
        const val DurablePreviousPublicValueKey =
            "last-intro-date.rebuild-durable-previous-public-value"
    }
}

class RebuildIntroDailyGate(
    private val store: RebuildIntroDateStore,
    private val clock: Clock = Clock.systemUTC(),
    private val zoneId: ZoneId? = null,
    private val zoneProvider: () -> ZoneId = ZoneId::systemDefault,
) {
    private data class CompletionAttempt(
        val day: String,
        val result: CompletableDeferred<Boolean>,
    )

    private val completionLock = Any()
    @Volatile
    private var completionAttempt: CompletionAttempt? = null

    fun shouldPresent(): Boolean = completionAttempt != null ||
        store.read() != todayKey()

    suspend fun markCompleted(): Boolean {
        while (true) {
            val requestedDay = todayKey()
            var ownsCompletion = false
            var isAlreadyCompleted = false
            val attempt = synchronized(completionLock) {
                completionAttempt ?: if (store.read() == requestedDay) {
                    isAlreadyCompleted = true
                    null
                } else {
                    CompletionAttempt(
                        day = requestedDay,
                        result = CompletableDeferred(),
                    ).also {
                        completionAttempt = it
                        ownsCompletion = true
                    }
                }
            }
            if (isAlreadyCompleted) return true
            checkNotNull(attempt)

            if (!ownsCompletion) {
                val didComplete = try {
                    attempt.result.await()
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (error: Throwable) {
                    if (attempt.day != todayKey()) continue
                    throw error
                }
                if (attempt.day == todayKey()) return didComplete
                continue
            }

            return try {
                val didComplete = store.writeDurably(requestedDay) &&
                    requestedDay == todayKey()
                synchronized(completionLock) {
                    if (completionAttempt === attempt) {
                        completionAttempt = null
                    }
                    attempt.result.complete(didComplete)
                }
                didComplete
            } catch (error: Throwable) {
                synchronized(completionLock) {
                    if (completionAttempt === attempt) {
                        completionAttempt = null
                    }
                    attempt.result.completeExceptionally(error)
                }
                throw error
            }
        }
    }

    private fun todayKey(): String = LocalDate.now(
        clock.withZone(zoneId ?: zoneProvider()),
    )
        .format(DateTimeFormatter.BASIC_ISO_DATE)

    companion object {
        const val StorageKey = "last-intro-date"
    }
}

class RebuildIntroEntryController(
    private val dailyGate: RebuildIntroDailyGate,
) {
    var showIntro by mutableStateOf(dailyGate.shouldPresent())
        private set

    val canLoadBootstrap: Boolean
        get() = !showIntro

    fun refresh() {
        showIntro = dailyGate.shouldPresent()
    }

    suspend fun completeIntro(): Boolean {
        if (!dailyGate.markCompleted()) {
            showIntro = true
            return false
        }
        showIntro = false
        return true
    }
}
