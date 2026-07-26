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
import java.lang.ref.WeakReference
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
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
    fun observeCommittedValue(
        listener: (String?) -> Unit,
    ): AutoCloseable? = null
}

private class RebuildIntroPreferencesScope {
    private val writerMutex = Mutex()
    private val orderingMutex = Mutex()
    private var activeWriteCount = 0
    private var nextRequestId = 0L
    private var latestCommittedRequestId = 0L
    private val reservedValues = mutableMapOf<Long, String>()
    private var committedValue: String? = null
    private var hasLoadedCommittedValue = false
    private var version = 0L
    private var nextListenerId = 0L
    private val listeners = mutableMapOf<Long, (String?) -> Unit>()

    fun readThrough(
        authoritativeValue: () -> String?,
    ): String? {
        val inFlight = synchronized(this) {
            Triple(
                activeWriteCount > 0,
                committedValue,
                hasLoadedCommittedValue,
            )
        }
        if (inFlight.first) {
            return if (inFlight.third) inFlight.second else null
        }

        if (!writerMutex.tryLock()) {
            val snapshot = synchronized(this) {
                committedValue to hasLoadedCommittedValue
            }
            return if (snapshot.second) snapshot.first else null
        }
        return try {
            val afterLock = synchronized(this) {
                Triple(
                    activeWriteCount > 0,
                    committedValue,
                    hasLoadedCommittedValue,
                )
            }
            if (afterLock.first) {
                if (afterLock.third) afterLock.second else null
            } else {
                publishReadThrough(authoritativeValue())
            }
        } finally {
            writerMutex.unlock()
        }
    }

    fun observe(
        listener: (String?) -> Unit,
    ): AutoCloseable {
        val snapshot = synchronized(this) {
            nextListenerId += 1
            listeners[nextListenerId] = listener
            Triple(nextListenerId, committedValue, hasLoadedCommittedValue)
        }
        if (snapshot.third) {
            listener(snapshot.second)
        }
        return AutoCloseable {
            synchronized(this) {
                listeners.remove(snapshot.first)
            }
        }
    }

    suspend fun <Result> withSerializedWrite(
        block: suspend () -> Result,
    ): Result {
        synchronized(this) {
            activeWriteCount += 1
        }
        return try {
            writerMutex.lock()
            try {
                block()
            } finally {
                writerMutex.unlock()
            }
        } finally {
            synchronized(this) {
                activeWriteCount -= 1
            }
        }
    }

    suspend fun reserveRequestId(
        value: String,
        readPublicValue: () -> String?,
    ): Pair<Long, String?> {
        orderingMutex.lock()
        return try {
            withContext(Dispatchers.IO) {
                val publicValue = readPublicValue()
                synchronized(this@RebuildIntroPreferencesScope) {
                    if (!hasLoadedCommittedValue) {
                        committedValue = publicValue
                        hasLoadedCommittedValue = true
                    }
                    nextRequestId += 1
                    reservedValues[nextRequestId] = value
                    nextRequestId to publicValue
                }
            }
        } finally {
            orderingMutex.unlock()
        }
    }

    @Synchronized
    fun isSuperseded(
        requestId: Long,
        value: String,
    ): Boolean =
        requestId < latestCommittedRequestId ||
            reservedValues.any { (reservedId, reservedValue) ->
                reservedId > requestId && reservedValue != value
            }

    @Synchronized
    fun finishRequest(requestId: Long) {
        reservedValues.remove(requestId)
    }

    fun adoptAuthoritativeValue(value: String?) {
        publishReadThrough(value)
    }

    suspend fun completeWithoutWrite(
        requestId: Long,
        value: String,
    ): Boolean {
        orderingMutex.lock()
        val result = try {
            var listenersToNotify = emptyList<(String?) -> Unit>()
            val didComplete = synchronized(this) {
                if (isSupersededLocked(requestId, value)) {
                    false
                } else {
                    latestCommittedRequestId = maxOf(
                        latestCommittedRequestId,
                        requestId,
                    )
                    if (
                        !hasLoadedCommittedValue ||
                        committedValue != value
                    ) {
                        committedValue = value
                        hasLoadedCommittedValue = true
                        version += 1
                        listenersToNotify = listeners.values.toList()
                    }
                    true
                }
            }
            didComplete to listenersToNotify
        } finally {
            orderingMutex.unlock()
        }
        result.second.forEach { it(value) }
        return result.first
    }

    suspend fun publishAtomically(
        requestId: Long,
        value: String,
        onClaimed: () -> Unit = {},
        publication: () -> Boolean,
    ): Boolean {
        orderingMutex.lock()
        val result = try {
            val canPublish = synchronized(this) {
                !isSupersededLocked(requestId, value)
            }
            if (!canPublish) {
                false to emptyList()
            } else {
                onClaimed()
                if (!publication()) {
                    false to emptyList()
                } else {
                    val listenersToNotify = synchronized(this) {
                        latestCommittedRequestId = maxOf(
                            latestCommittedRequestId,
                            requestId,
                        )
                        committedValue = value
                        hasLoadedCommittedValue = true
                        version += 1
                        listeners.values.toList()
                    }
                    true to listenersToNotify
                }
            }
        } finally {
            orderingMutex.unlock()
        }
        result.second.forEach { it(value) }
        return result.first
    }

    private fun publishReadThrough(value: String?): String? {
        var listenersToNotify = emptyList<(String?) -> Unit>()
        val result = synchronized(this) {
            if (activeWriteCount > 0) {
                Pair(
                    if (hasLoadedCommittedValue) committedValue else null,
                    false,
                )
            } else if (
                hasLoadedCommittedValue &&
                committedValue == value
            ) {
                value to false
            } else {
                committedValue = value
                hasLoadedCommittedValue = true
                version += 1
                listenersToNotify = listeners.values.toList()
                value to true
            }
        }
        if (result.second) {
            listenersToNotify.forEach { it(value) }
        }
        return result.first
    }

    private fun isSupersededLocked(
        requestId: Long,
        value: String,
    ): Boolean =
        requestId < latestCommittedRequestId ||
            reservedValues.any { (reservedId, reservedValue) ->
                reservedId > requestId && reservedValue != value
            }
}

private object RebuildIntroPreferencesRegistry {
    private data class Entry(
        val preferences: WeakReference<SharedPreferences>,
        val scope: RebuildIntroPreferencesScope,
    )

    private val entries = mutableListOf<Entry>()

    @Synchronized
    fun scopeFor(
        preferences: SharedPreferences,
    ): RebuildIntroPreferencesScope {
        entries.removeAll { it.preferences.get() == null }
        entries.firstOrNull {
            it.preferences.get() === preferences
        }?.let {
            return it.scope
        }
        return RebuildIntroPreferencesScope().also { scope ->
            entries += Entry(
                preferences = WeakReference(preferences),
                scope = scope,
            )
        }
    }
}

class SharedPreferencesRebuildIntroDateStore(
    private val preferences: SharedPreferences,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val commit: (SharedPreferences.Editor) -> Boolean = {
        it.commit()
    },
    private val onRequestReserved: () -> Unit = {},
    private val beforePublication: () -> Unit = {},
    private val onPublicValueRead: () -> Unit = {},
    private val onPublicationClaimed: () -> Unit = {},
    private val onAuthoritativeReadStarted: () -> Unit = {},
) : RebuildIntroDateStore {
    private val scope =
        RebuildIntroPreferencesRegistry.scopeFor(preferences)

    override fun read(): String? =
        scope.readThrough {
            authoritativeCommittedValue()
        }

    override fun observeCommittedValue(
        listener: (String?) -> Unit,
    ): AutoCloseable = scope.observe(listener)

    override suspend fun writeDurably(value: String): Boolean {
        val reservation = scope.reserveRequestId(
            value = value,
        ) {
            preferences.getString(
                RebuildIntroDailyGate.StorageKey,
                null,
            ).also {
                onPublicValueRead()
            }
        }
        val requestId = reservation.first
        val publicValueAtRequest = reservation.second
        onRequestReserved()
        return try {
            withContext(ioDispatcher) {
                scope.withSerializedWrite {
                    val authoritativeValue =
                        authoritativeCommittedValue()
                    scope.adoptAuthoritativeValue(authoritativeValue)
                    if (authoritativeValue == value) {
                        return@withSerializedWrite scope
                            .completeWithoutWrite(
                                requestId = requestId,
                                value = value,
                            )
                    }
                    if (authoritativeValue != publicValueAtRequest) {
                        return@withSerializedWrite false
                    }
                    if (scope.isSuperseded(requestId, value)) {
                        return@withSerializedWrite false
                    }

                    val previousPublicValue = preferences.getString(
                        RebuildIntroDailyGate.StorageKey,
                        null,
                    )
                    if (previousPublicValue != publicValueAtRequest) {
                        return@withSerializedWrite false
                    }
                    val hadPreviousDurableOwner =
                        preferences.contains(DurableOwnerKey)
                    val previousDurableOwner = preferences.getString(
                        DurableOwnerKey,
                        null,
                    )
                    val hadPreviousDurableVersion =
                        preferences.contains(DurableVersionKey)
                    val previousDurableVersion = preferences.getLong(
                        DurableVersionKey,
                        0L,
                    )
                    val hadPreviousDurableState =
                        preferences.contains(DurableStateKey)
                    val previousDurableState = preferences.getString(
                        DurableStateKey,
                        null,
                    )
                    val hadPreviousDurableValue =
                        preferences.contains(DurableValueKey)
                    val previousDurableValue = preferences.getString(
                        DurableValueKey,
                        null,
                    )
                    val hadPreviousDurablePublicValue =
                        preferences.contains(
                            DurablePreviousPublicValueKey,
                        )
                    val previousDurablePublicValue =
                        preferences.getString(
                            DurablePreviousPublicValueKey,
                            null,
                        )
                    val version = maxOf(
                        requestId,
                        previousDurableVersion + 1L,
                    )
                    val didCommit = commit(
                        preferences
                            .edit()
                            .putString(DurableOwnerKey, DurableOwner)
                            .putLong(DurableVersionKey, version)
                            .putString(
                                DurableStateKey,
                                PendingState,
                            )
                            .putString(DurableValueKey, value)
                            .putString(
                                DurablePreviousPublicValueKey,
                                previousPublicValue ?: "",
                            ),
                    )
                    val didReadBack =
                        preferences.getString(
                            DurableOwnerKey,
                            null,
                        ) == DurableOwner &&
                            preferences.getLong(
                                DurableVersionKey,
                                0L,
                            ) == version &&
                            preferences.getString(
                                DurableStateKey,
                                null,
                            ) == PendingState &&
                            preferences.getString(
                                DurableValueKey,
                                null,
                            ) == value &&
                            preferences.getString(
                                DurablePreviousPublicValueKey,
                                null,
                            ) == (previousPublicValue ?: "")

                    if (!didCommit || !didReadBack) {
                        val rollback = preferences.edit()
                        restoreString(
                            rollback,
                            DurableOwnerKey,
                            hadPreviousDurableOwner,
                            previousDurableOwner,
                        )
                        if (hadPreviousDurableVersion) {
                            rollback.putLong(
                                DurableVersionKey,
                                previousDurableVersion,
                            )
                        } else {
                            rollback.remove(DurableVersionKey)
                        }
                        restoreString(
                            rollback,
                            DurableStateKey,
                            hadPreviousDurableState,
                            previousDurableState,
                        )
                        restoreString(
                            rollback,
                            DurableValueKey,
                            hadPreviousDurableValue,
                            previousDurableValue,
                        )
                        restoreString(
                            rollback,
                            DurablePreviousPublicValueKey,
                            hadPreviousDurablePublicValue,
                            previousDurablePublicValue,
                        )
                        rollback.commit()
                        return@withSerializedWrite false
                    }

                    beforePublication()
                    val didPublish = scope.publishAtomically(
                        requestId = requestId,
                        value = value,
                        onClaimed = onPublicationClaimed,
                    ) {
                        val publicValueBeforePublication =
                            preferences.getString(
                                RebuildIntroDailyGate.StorageKey,
                                null,
                            )
                        if (
                            publicValueBeforePublication !=
                            previousPublicValue &&
                            publicValueBeforePublication != value
                        ) {
                            return@publishAtomically false
                        }
                        val didCommitPublication = commit(
                            preferences
                                .edit()
                                .putString(
                                    RebuildIntroDailyGate.StorageKey,
                                    value,
                                )
                                .putString(
                                    DurableStateKey,
                                    PublishedState,
                                ),
                        )
                        val didReadBackPublication =
                            preferences.getString(
                                RebuildIntroDailyGate.StorageKey,
                                null,
                            ) == value &&
                                preferences.getString(
                                    DurableStateKey,
                                    null,
                                ) == PublishedState
                        if (
                            !didCommitPublication ||
                            !didReadBackPublication
                        ) {
                            val rollback = preferences.edit()
                            restoreString(
                                rollback,
                                RebuildIntroDailyGate.StorageKey,
                                previousPublicValue != null,
                                previousPublicValue,
                            )
                            rollback.putString(
                                DurableStateKey,
                                PendingState,
                            )
                            rollback.commit()
                            return@publishAtomically false
                        }
                        true
                    }
                    if (!didPublish) {
                        commit(
                            preferences
                                .edit()
                                .putString(
                                    DurableStateKey,
                                    SupersededState,
                                ),
                        )
                        return@withSerializedWrite false
                    }
                    true
                }
            }
        } finally {
            scope.finishRequest(requestId)
        }
    }

    private fun authoritativeCommittedValue(): String? {
        onAuthoritativeReadStarted()
        val publicValue = preferences.getString(
            RebuildIntroDailyGate.StorageKey,
            null,
        )
        if (preferences.getString(DurableOwnerKey, null) != DurableOwner ||
            preferences.getLong(DurableVersionKey, 0L) <= 0L
        ) {
            return publicValue
        }
        val state = preferences.getString(DurableStateKey, null)
            ?: return publicValue
        val durableValue = preferences.getString(DurableValueKey, null)
            ?: return publicValue
        val previousPublicValue = preferences.getString(
            DurablePreviousPublicValueKey,
            null,
        ) ?: return publicValue

        if (state == PublishedState || state == SupersededState) {
            return publicValue
        }
        if (state != PendingState) return publicValue

        if (publicValue == durableValue) {
            preferences
                .edit()
                .putString(DurableStateKey, PublishedState)
                .apply()
            return durableValue
        }
        if ((publicValue ?: "") == previousPublicValue) {
            preferences
                .edit()
                .putString(RebuildIntroDailyGate.StorageKey, durableValue)
                .putString(DurableStateKey, PublishedState)
                .apply()
            return durableValue
        }
        preferences
            .edit()
            .putString(DurableStateKey, SupersededState)
            .apply()
        return publicValue
    }

    private fun restoreString(
        editor: SharedPreferences.Editor,
        key: String,
        hadValue: Boolean,
        value: String?,
    ) {
        if (hadValue) {
            editor.putString(key, value)
        } else {
            editor.remove(key)
        }
    }

    private companion object {
        const val DurableOwnerKey =
            "last-intro-date.rebuild-durable-owner"
        const val DurableVersionKey =
            "last-intro-date.rebuild-durable-version"
        const val DurableStateKey =
            "last-intro-date.rebuild-durable-state"
        const val DurableValueKey =
            "last-intro-date.rebuild-durable-value"
        const val DurablePreviousPublicValueKey =
            "last-intro-date.rebuild-durable-previous-public-value"
        const val DurableOwner = "rebuild-intro-daily-gate-v1"
        const val PendingState = "pending"
        const val PublishedState = "published"
        const val SupersededState = "superseded"
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

    fun observeShouldPresent(
        listener: (Boolean) -> Unit,
    ): AutoCloseable? = store.observeCommittedValue { committedDay ->
        listener(committedDay != todayKey())
    }

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
    private val gateObservation: AutoCloseable?

    init {
        val weakEntry = WeakReference(this)
        gateObservation =
            dailyGate.observeShouldPresent { shouldPresent ->
                weakEntry.get()?.showIntro = shouldPresent
            }
    }

    fun close() {
        gateObservation?.close()
    }

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
