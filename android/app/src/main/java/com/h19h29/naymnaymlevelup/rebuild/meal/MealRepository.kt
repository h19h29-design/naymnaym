package com.h19h29.naymnaymlevelup.rebuild.meal

import com.fasterxml.jackson.core.JsonFactory
import com.h19h29.naymnaymlevelup.rebuild.data.MealDayDao
import com.h19h29.naymnaymlevelup.rebuild.data.MealDayEntity
import java.io.StringWriter
import java.time.Instant
import java.time.LocalDate
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class MealRepository(
    private val store: MealDayStore,
    private val client: MealClient,
    @Suppress("UNUSED_PARAMETER") scope: CoroutineScope,
    private val now: () -> Instant = Instant::now,
) {
    private data class StateEntry(
        var current: MealLoadState,
        val events: MutableSharedFlow<MealLoadState>,
    )

    private val mutex = Mutex()
    private val states = mutableMapOf<String, StateEntry>()
    private val refreshGenerations = mutableMapOf<String, Long>()
    private val dateLocks = ConcurrentHashMap<String, Mutex>()

    fun observe(date: LocalDate): Flow<MealLoadState> = flow {
        val entry = stateEntry(date.toString())
        emitAll(entry.events)
    }

    suspend fun currentState(date: String): MealLoadState {
        val entry = stateEntry(date)
        return mutex.withLock { entry.current }
    }

    suspend fun refresh(date: LocalDate, school: School) {
        val dateKey = date.toString()
        val operationLock = dateLock(dateKey)
        val generation = operationLock.withLock {
            mutex.withLock {
                ((refreshGenerations[dateKey] ?: 0L) + 1L).also {
                    refreshGenerations[dateKey] = it
                }
            }
        }
        val cached = try {
            operationLock.withLock {
                if (!isLatest(dateKey, generation)) {
                    return
                }
                val loaded = store.load(dateKey)
                mutex.withLock {
                    if (refreshGenerations[dateKey] == generation) {
                        updateLocked(
                            dateKey,
                            MealLoadState.Refreshing(loaded?.meal),
                        )
                    }
                }
                loaded
            }
        } catch (error: Throwable) {
            if (error is CancellationException) {
                reconcileCancellation(
                    date = dateKey,
                    generation = generation,
                    operationLock = operationLock,
                    cancellation = error,
                )
            }
            operationLock.withLock {
                mutex.withLock {
                    if (refreshGenerations[dateKey] == generation) {
                        updateLocked(
                            dateKey,
                            MealLoadState.Refreshing(cached = null),
                        )
                    }
                }
            }
            null
        }

        try {
            val meal = client.fetch(date, school)
            operationLock.withLock {
                if (!isLatest(dateKey, generation)) {
                    return@withLock
                }
                if (meal == null) {
                    store.remove(dateKey)
                    mutex.withLock {
                        if (refreshGenerations[dateKey] == generation) {
                            updateLocked(dateKey, MealLoadState.Empty)
                        }
                    }
                } else {
                    store.save(
                        meal = meal,
                        refreshedAt = now(),
                        source = "neis",
                    )
                    mutex.withLock {
                        if (refreshGenerations[dateKey] == generation) {
                            updateLocked(dateKey, MealLoadState.Live(meal))
                        }
                    }
                }
            }
        } catch (error: Throwable) {
            if (error is CancellationException) {
                reconcileCancellation(
                    date = dateKey,
                    generation = generation,
                    operationLock = operationLock,
                    cancellation = error,
                )
            }
            operationLock.withLock {
                mutex.withLock stateLock@{
                    if (refreshGenerations[dateKey] != generation) {
                        return@stateLock
                    }
                    updateLocked(
                        dateKey,
                        cached?.let {
                            MealLoadState.Cached(it.meal, it.refreshedAt)
                        } ?: MealLoadState.Failed(
                            message = message(error),
                            cached = null,
                        ),
                    )
                }
            }
        }
    }

    private suspend fun stateEntry(date: String): StateEntry {
        mutex.withLock { states[date] }?.let { return it }
        return dateLock(date).withLock {
            mutex.withLock { states[date] }?.let { return@withLock it }
            val initial = try {
                store.load(date)?.let {
                    MealLoadState.Cached(it.meal, it.refreshedAt)
                } ?: MealLoadState.Empty
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                MealLoadState.Failed(message(error), cached = null)
            }
            mutex.withLock {
                states[date] ?: createEntry(initial).also {
                    states[date] = it
                }
            }
        }
    }

    private suspend fun isLatest(date: String, generation: Long): Boolean =
        mutex.withLock { refreshGenerations[date] == generation }

    private suspend fun reconcileCancellation(
        date: String,
        generation: Long,
        operationLock: Mutex,
        cancellation: CancellationException,
    ): Nothing {
        withContext(NonCancellable) {
            operationLock.withLock {
                if (!isLatest(date, generation)) {
                    return@withLock
                }
                val state = try {
                    store.load(date)?.let {
                        MealLoadState.Cached(it.meal, it.refreshedAt)
                    } ?: MealLoadState.Empty
                } catch (error: Throwable) {
                    MealLoadState.Failed(
                        message = message(error),
                        cached = null,
                    )
                }
                mutex.withLock {
                    if (refreshGenerations[date] == generation) {
                        updateLocked(date, state)
                    }
                }
            }
        }
        throw cancellation
    }

    private fun dateLock(date: String): Mutex =
        dateLocks.computeIfAbsent(date) { Mutex() }

    private fun updateLocked(date: String, state: MealLoadState) {
        val entry = states[date] ?: createEntry(state).also {
            states[date] = it
        }
        entry.current = state
        entry.events.tryEmit(state)
    }

    private fun createEntry(initial: MealLoadState): StateEntry {
        val events = MutableSharedFlow<MealLoadState>(
            replay = 1,
            extraBufferCapacity = 4,
            onBufferOverflow = BufferOverflow.DROP_OLDEST,
        )
        check(events.tryEmit(initial))
        return StateEntry(initial, events)
    }

    private fun message(error: Throwable): String =
        error.message?.takeIf(String::isNotBlank) ?: error.toString()
}

class RoomMealDayStore(
    private val dao: MealDayDao,
) : MealDayStore {
    override suspend fun load(date: String): CachedMealDay? =
        dao.observe(date).first()?.let { entity ->
            CachedMealDay(
                meal = MealDayJsonCodec.decode(entity.payloadJson),
                refreshedAt = Instant.ofEpochMilli(entity.fetchedAtEpochMillis),
                source = entity.source,
            )
        }

    override suspend fun save(
        meal: MealDay,
        refreshedAt: Instant,
        source: String,
    ) {
        dao.upsert(
            MealDayEntity(
                date = meal.date,
                payloadJson = MealDayJsonCodec.encode(meal),
                fetchedAtEpochMillis = refreshedAt.toEpochMilli(),
                source = source,
            ),
        )
    }

    override suspend fun remove(date: String) {
        dao.delete(date)
    }
}

private object MealDayJsonCodec {
    private val factory = JsonFactory()

    fun encode(meal: MealDay): String {
        val output = StringWriter()
        factory.createGenerator(output).use { json ->
            json.writeStartObject()
            json.writeStringField("date", meal.date)
            json.writeArrayFieldStart("menuItems")
            meal.menuItems.forEach { item ->
                json.writeStartObject()
                json.writeStringField("name", item.name)
                json.writeNumberArray("allergyCodes", item.allergyCodes)
                json.writeStringArray("nutrients", item.nutrients)
                json.writeStringArray("tags", item.tags)
                json.writeStringField("sourceRawText", item.sourceRawText)
                json.writeEndObject()
            }
            json.writeEndArray()
            json.writeStringField("calorie", meal.calorie)
            json.writeObjectFieldStart("nutrition")
            json.writeNumberField("carbs", meal.nutrition.carbs)
            json.writeNumberField("protein", meal.nutrition.protein)
            json.writeNumberField("fat", meal.nutrition.fat)
            json.writeNumberField("calcium", meal.nutrition.calcium)
            json.writeNumberField("iron", meal.nutrition.iron)
            json.writeNumberField("vitamin", meal.nutrition.vitamin)
            json.writeEndObject()
            json.writeEndObject()
        }
        return output.toString()
    }

    fun decode(raw: String): MealDay {
        val root = MealJsonReader.parseObject(raw)
        val menuItems = root.array("menuItems").map { value ->
            val item = value.objectValue()
                ?: error("Meal cache menu item must be an object")
            MealItem(
                name = item.requiredString("name"),
                allergyCodes = item.array("allergyCodes").map {
                    (it as? Number)?.toInt()
                        ?: error("Meal allergy code must be numeric")
                },
                nutrients = item.array("nutrients").map {
                    it as? String ?: error("Meal nutrient must be a string")
                },
                tags = item.array("tags").map {
                    it as? String ?: error("Meal tag must be a string")
                },
                sourceRawText = item.requiredString("sourceRawText"),
            )
        }
        val nutrition = root["nutrition"].objectValue()
            ?: error("Meal cache nutrition must be an object")
        return MealDay(
            date = root.requiredString("date"),
            menuItems = menuItems,
            calorie = root.requiredString("calorie"),
            nutrition = NutritionInfo(
                carbs = nutrition.requiredDouble("carbs"),
                protein = nutrition.requiredDouble("protein"),
                fat = nutrition.requiredDouble("fat"),
                calcium = nutrition.requiredDouble("calcium"),
                iron = nutrition.requiredDouble("iron"),
                vitamin = nutrition.requiredDouble("vitamin"),
            ),
        )
    }

    private fun com.fasterxml.jackson.core.JsonGenerator.writeNumberArray(
        name: String,
        values: List<Int>,
    ) {
        writeArrayFieldStart(name)
        values.forEach(::writeNumber)
        writeEndArray()
    }

    private fun com.fasterxml.jackson.core.JsonGenerator.writeStringArray(
        name: String,
        values: List<String>,
    ) {
        writeArrayFieldStart(name)
        values.forEach(::writeString)
        writeEndArray()
    }

    @Suppress("UNCHECKED_CAST")
    private fun Any?.objectValue(): Map<String, Any?>? =
        this as? Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any?>.array(name: String): List<Any?> =
        this[name] as? List<Any?> ?: error("Missing meal cache array: $name")

    private fun Map<String, Any?>.requiredString(name: String): String =
        this[name] as? String ?: error("Missing meal cache string: $name")

    private fun Map<String, Any?>.requiredDouble(name: String): Double =
        (this[name] as? Number)?.toDouble()
            ?: error("Missing meal cache number: $name")
}
