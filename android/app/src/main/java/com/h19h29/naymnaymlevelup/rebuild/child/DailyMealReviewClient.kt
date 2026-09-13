package com.h19h29.naymnaymlevelup.rebuild.child

import com.fasterxml.jackson.core.JsonFactory
import com.fasterxml.jackson.core.JsonParser
import com.fasterxml.jackson.core.JsonToken
import com.fasterxml.jackson.core.StreamReadFeature
import com.h19h29.naymnaymlevelup.rebuild.meal.MealJsonReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withContext

sealed class DailyMealReviewProtocolException(message: String, cause: Throwable? = null) :
    IOException(message, cause) {
    class InvalidPayload(cause: Throwable? = null) :
        DailyMealReviewProtocolException("Invalid daily meal review payload", cause)

    class RequestTooLarge : DailyMealReviewProtocolException("Daily meal review request exceeds 8 KB")
    class ResponseTooLarge : DailyMealReviewProtocolException("Daily meal review response exceeds 16 KB")
}

object DailyMealReviewJson {
    private val writerFactory = JsonFactory()
    private val strictReaderFactory = JsonFactory.builder()
        .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION)
        .build()
    private val responseKeys = setOf(
        "source", "reviewId", "day", "generatedAt", "model", "policyVersion",
        "summary", "benefit", "highlights", "caution", "tip",
    )
    private val highlightKeys = setOf("itemId", "nutrient", "reason")
    private val forbiddenText = listOf(
        Regex("\\p{N}|그램|칼로리|\\b(?:mg|g|kcal)\\b", RegexOption.IGNORE_CASE),
        Regex("안전|익혀|조리|신선|먹어도\\s*괜찮|알레르기.{0,12}(?:무시|극복)", RegexOption.IGNORE_CASE),
        Regex("혈압|혈당|빈혈|키가\\s*안\\s*커|치료|완치|질병|비만|다이어트|살이\\s*찌|키가\\s*커|결핍입니다|부족합니다", RegexOption.IGNORE_CASE),
        Regex("https?:|www\\.|<|>|반드시\\s*먹|꼭\\s*먹|ignore|instructions|system\\s*prompt", RegexOption.IGNORE_CASE),
    )
    private val ungroundedQuantityReference =
        Regex("(?:이|그|해당|위|주어진|제공된)\\s*(?:수치|함량|숫자|수량)")

    fun encodeRequest(request: DailyMealReviewRequest): ByteArray {
        validateRequest(request)
        val output = ByteArrayOutputStream()
        writerFactory.createGenerator(output).use { json ->
            json.writeStartObject()
            json.writeStringField("requestId", request.requestId)
            json.writeStringField("sessionId", request.sessionId)
            json.writeArrayFieldStart("items")
            request.items.forEach { item ->
                json.writeStartObject()
                json.writeStringField("id", item.id)
                json.writeArrayFieldStart("nutrients")
                item.nutrients.forEach(json::writeString)
                json.writeEndArray()
                json.writeEndObject()
            }
            json.writeEndArray()
            json.writeObjectFieldStart("wholeMeal")
            request.wholeMeal.protein?.let { json.writeNumberField("protein", it) }
            request.wholeMeal.carbs?.let { json.writeNumberField("carbs", it) }
            request.wholeMeal.fat?.let { json.writeNumberField("fat", it) }
            json.writeEndObject()
            json.writeEndObject()
        }
        return output.toByteArray().also {
            if (it.size > MAX_REQUEST_BYTES) throw DailyMealReviewProtocolException.RequestTooLarge()
        }
    }

    fun decodeResponse(
        bytes: ByteArray,
        request: DailyMealReviewRequest,
    ): DailyMealReviewResponse {
        if (bytes.size > MAX_RESPONSE_BYTES) {
            throw DailyMealReviewProtocolException.ResponseTooLarge()
        }
        validateRequest(request)
        val root = parseObject(bytes)
        if (root.keys != responseKeys || root["source"] != "ai") invalid()
        val reviewId = root.requiredText("reviewId")
        val day = root.requiredText("day")
        val generatedAt = root.requiredText("generatedAt")
        runCatching { UUID.fromString(reviewId) }.getOrElse { invalid() }
        if (reviewId.lowercase() != request.requestId.lowercase()) invalid()
        runCatching { LocalDate.parse(day) }.getOrElse { invalid() }
        runCatching { Instant.parse(generatedAt) }.getOrElse { invalid() }
        val model = root.requiredText("model")
        val policyVersion = root.requiredText("policyVersion")
        val quantityFree = listOf(request.wholeMeal.protein, request.wholeMeal.carbs, request.wholeMeal.fat)
            .all { it == null }
        val summary = root.safeKoreanText("summary", quantityFree)
        val benefit = root.safeKoreanText("benefit", quantityFree)
        val caution = root.safeKoreanText("caution", quantityFree)
        val tip = root.safeKoreanText("tip", quantityFree)
        val allowed = request.items.associate { it.id to it.nutrients.toSet() }
        val rawHighlights = root["highlights"] as? List<*> ?: invalid()
        if (rawHighlights.size > 2) invalid()
        val highlights = rawHighlights.map { raw ->
            @Suppress("UNCHECKED_CAST")
            val value = raw as? Map<String, Any?> ?: invalid()
            if (value.keys != highlightKeys) invalid()
            val itemId = value.requiredText("itemId")
            val nutrient = value.requiredText("nutrient")
            if (nutrient !in allowed[itemId].orEmpty()) invalid()
            DailyMealReviewHighlight(itemId, nutrient, value.safeKoreanText("reason", quantityFree))
        }
        if (highlights.map { it.itemId }.toSet().size != highlights.size) invalid()
        return DailyMealReviewResponse(
            source = "ai",
            reviewId = reviewId,
            day = day,
            generatedAt = generatedAt,
            model = model,
            policyVersion = policyVersion,
            summary = summary,
            benefit = benefit,
            highlights = highlights,
            caution = caution,
            tip = tip,
        )
    }

    fun encodeStored(record: SavedDailyMealReview): String {
        require(record.response.source == "ai")
        require(record.date == record.response.day)
        validateStoredResponse(record)
        val output = ByteArrayOutputStream()
        writerFactory.createGenerator(output).use { json ->
            json.writeStartObject()
            json.writeStringField("profileKey", record.profileKey)
            json.writeStringField("schoolKey", record.schoolKey)
            json.writeStringField("date", record.date)
            json.writeStringField("mealType", record.mealType)
            json.writeStringField("mealFingerprint", record.mealFingerprint)
            json.writeStringField("requestId", record.requestId)
            writeWholeMeal(json, record.wholeMeal)
            json.writeArrayFieldStart("menuSnapshot")
            record.menuSnapshot.forEach { item ->
                json.writeStartObject()
                json.writeStringField("id", item.id)
                json.writeStringField("name", item.name)
                json.writeArrayFieldStart("allergyCodes")
                item.allergyCodes.forEach(json::writeNumber)
                json.writeEndArray()
                json.writeArrayFieldStart("nutrients")
                item.nutrients.forEach(json::writeString)
                json.writeEndArray()
                json.writeEndObject()
            }
            json.writeEndArray()
            writeResponse(json, record.response)
            json.writeEndObject()
        }
        return output.toString(Charsets.UTF_8.name())
    }

    fun decodeStored(value: String): SavedDailyMealReview = try {
        val root = parseObject(value.encodeToByteArray())
        if (root.keys != STORED_KEYS) invalid()
        @Suppress("UNCHECKED_CAST")
        val snapshots = (root["menuSnapshot"] as? List<*>)?.map { raw ->
            val item = raw as? Map<String, Any?> ?: invalid()
            if (item.keys != setOf("id", "name", "allergyCodes", "nutrients")) invalid()
            DailyMealReviewMenuSnapshot(
                id = item.requiredText("id"),
                name = item.requiredText("name"),
                allergyCodes = (item["allergyCodes"] as? List<*>)?.map {
                    (it as? Long)?.toInt()?.takeIf { code -> code > 0 } ?: invalid()
                } ?: invalid(),
                nutrients = (item["nutrients"] as? List<*>)?.map {
                    (it as? String)?.takeIf(DailyMealReviewRequestFactory.NUTRIENT_ORDER::contains) ?: invalid()
                } ?: invalid(),
            )
        } ?: invalid()
        val candidates = snapshots.filter { it.nutrients.isNotEmpty() }.map {
            DailyMealReviewItem(it.id, it.nutrients)
        }
        val requestId = root.requiredText("requestId")
        val wholeMeal = root.requiredWholeMeal("wholeMeal")
        val responseBytes = encodeResponseMap(root["response"] as? Map<String, Any?> ?: invalid())
        val request = DailyMealReviewRequest(
            requestId = requestId,
            sessionId = "00000000-0000-4000-8000-000000000000",
            items = candidates,
            wholeMeal = wholeMeal,
        )
        val response = decodeResponse(responseBytes, request)
        if (response.day != root.requiredText("date")) invalid()
        SavedDailyMealReview(
            profileKey = root.requiredText("profileKey"),
            schoolKey = root.requiredText("schoolKey"),
            date = root.requiredText("date"),
            mealType = root.requiredText("mealType"),
            mealFingerprint = root.requiredText("mealFingerprint"),
            menuSnapshot = snapshots,
            response = response,
            requestId = requestId,
            wholeMeal = wholeMeal,
        )
    } catch (error: DailyMealReviewProtocolException) {
        throw DailyMealReviewCorruptRecordException(error)
    } catch (error: Exception) {
        throw DailyMealReviewCorruptRecordException(error)
    }

    private fun validateRequest(request: DailyMealReviewRequest) {
        val requestUuid = runCatching { UUID.fromString(request.requestId) }.getOrNull() ?: invalid()
        val sessionUuid = runCatching { UUID.fromString(request.sessionId) }.getOrNull() ?: invalid()
        if (requestUuid.version() != 4 || sessionUuid.version() != 4) invalid()
        if (request.items.size !in 1..30) invalid()
        if (request.items.map { it.id }.toSet().size != request.items.size) invalid()
        request.items.forEachIndexed { index, item ->
            if (item.id != "m$index" && !item.id.matches(Regex("m(?:[0-9]|[12][0-9])"))) invalid()
            if (item.nutrients.isEmpty() || item.nutrients.size > 6 ||
                item.nutrients.toSet().size != item.nutrients.size ||
                item.nutrients.any { it !in DailyMealReviewRequestFactory.NUTRIENT_ORDER }
            ) invalid()
        }
        listOfNotNull(request.wholeMeal.protein, request.wholeMeal.carbs, request.wholeMeal.fat)
            .forEach { if (!it.isFinite() || it <= 0.0 || it > 1_000.0) invalid() }
    }

    private fun parseObject(bytes: ByteArray): Map<String, Any?> = try {
        strictReaderFactory.createParser(bytes).use { parser ->
            if (parser.nextToken() != JsonToken.START_OBJECT) invalid()
            val value = parser.readObjectValue()
            if (parser.nextToken() != null) invalid()
            value
        }
    } catch (error: DailyMealReviewProtocolException) {
        throw error
    } catch (error: Exception) {
        throw DailyMealReviewProtocolException.InvalidPayload(error)
    }

    private fun JsonParser.readObjectValue(): Map<String, Any?> = buildMap {
        while (nextToken() != JsonToken.END_OBJECT) {
            if (currentToken() != JsonToken.FIELD_NAME) invalid()
            val name = currentName()
            nextToken()
            put(name, readValue())
        }
    }

    private fun JsonParser.readValue(): Any? = when (currentToken()) {
        JsonToken.VALUE_STRING -> text
        JsonToken.VALUE_NUMBER_INT -> longValue
        JsonToken.VALUE_NUMBER_FLOAT -> doubleValue
        JsonToken.VALUE_TRUE -> true
        JsonToken.VALUE_FALSE -> false
        JsonToken.VALUE_NULL -> null
        JsonToken.START_OBJECT -> readObjectValue()
        JsonToken.START_ARRAY -> buildList {
            while (nextToken() != JsonToken.END_ARRAY) add(readValue())
        }
        else -> invalid()
    }

    private fun Map<String, Any?>.requiredText(key: String): String =
        (this[key] as? String)?.takeIf { it.isNotBlank() && it.length <= 240 } ?: invalid()

    private fun Map<String, Any?>.safeKoreanText(key: String, quantityFree: Boolean): String =
        requiredText(key).trim().also {
        if (!it.any { character -> character in '\uAC00'..'\uD7A3' } ||
            forbiddenText.any { pattern -> pattern.containsMatchIn(it) } ||
            quantityFree && ungroundedQuantityReference.containsMatchIn(it)
        ) invalid()
    }

    private fun Map<String, Any?>.requiredWholeMeal(key: String): DailyMealReviewWholeMeal {
        @Suppress("UNCHECKED_CAST")
        val value = this[key] as? Map<String, Any?> ?: invalid()
        if (value.keys.any { it !in setOf("protein", "carbs", "fat") }) invalid()
        fun amount(name: String): Double? = value[name]?.let {
            when (it) {
                is Double -> it
                is Long -> it.toDouble()
                else -> invalid()
            }.takeIf { number -> number.isFinite() && number > 0 && number <= 1_000 } ?: invalid()
        }
        return DailyMealReviewWholeMeal(amount("protein"), amount("carbs"), amount("fat"))
    }

    private fun writeWholeMeal(
        json: com.fasterxml.jackson.core.JsonGenerator,
        wholeMeal: DailyMealReviewWholeMeal,
    ) {
        json.writeObjectFieldStart("wholeMeal")
        wholeMeal.protein?.let { json.writeNumberField("protein", it) }
        wholeMeal.carbs?.let { json.writeNumberField("carbs", it) }
        wholeMeal.fat?.let { json.writeNumberField("fat", it) }
        json.writeEndObject()
    }

    private fun validateStoredResponse(record: SavedDailyMealReview) {
        val request = DailyMealReviewRequest(
            requestId = record.requestId,
            sessionId = "00000000-0000-4000-8000-000000000000",
            items = record.menuSnapshot.filter { it.nutrients.isNotEmpty() }.map {
                DailyMealReviewItem(it.id, it.nutrients)
            },
            wholeMeal = record.wholeMeal,
        )
        decodeResponse(encodeResponse(record.response), request)
    }

    private fun encodeResponse(response: DailyMealReviewResponse): ByteArray {
        val output = ByteArrayOutputStream()
        writerFactory.createGenerator(output).use { json ->
            json.writeStartObject()
            json.writeStringField("source", response.source)
            json.writeStringField("reviewId", response.reviewId)
            json.writeStringField("day", response.day)
            json.writeStringField("generatedAt", response.generatedAt)
            json.writeStringField("model", response.model)
            json.writeStringField("policyVersion", response.policyVersion)
            json.writeStringField("summary", response.summary)
            json.writeStringField("benefit", response.benefit)
            json.writeArrayFieldStart("highlights")
            response.highlights.forEach { highlight ->
                json.writeStartObject()
                json.writeStringField("itemId", highlight.itemId)
                json.writeStringField("nutrient", highlight.nutrient)
                json.writeStringField("reason", highlight.reason)
                json.writeEndObject()
            }
            json.writeEndArray()
            json.writeStringField("caution", response.caution)
            json.writeStringField("tip", response.tip)
            json.writeEndObject()
        }
        return output.toByteArray()
    }

    private fun writeResponse(json: com.fasterxml.jackson.core.JsonGenerator, response: DailyMealReviewResponse) {
        json.writeObjectFieldStart("response")
        json.writeStringField("source", response.source)
        json.writeStringField("reviewId", response.reviewId)
        json.writeStringField("day", response.day)
        json.writeStringField("generatedAt", response.generatedAt)
        json.writeStringField("model", response.model)
        json.writeStringField("policyVersion", response.policyVersion)
        json.writeStringField("summary", response.summary)
        json.writeStringField("benefit", response.benefit)
        json.writeArrayFieldStart("highlights")
        response.highlights.forEach { highlight ->
            json.writeStartObject()
            json.writeStringField("itemId", highlight.itemId)
            json.writeStringField("nutrient", highlight.nutrient)
            json.writeStringField("reason", highlight.reason)
            json.writeEndObject()
        }
        json.writeEndArray()
        json.writeStringField("caution", response.caution)
        json.writeStringField("tip", response.tip)
        json.writeEndObject()
    }

    private fun encodeResponseMap(response: Map<String, Any?>): ByteArray {
        val output = ByteArrayOutputStream()
        writerFactory.createGenerator(output).use { json -> writeUntyped(json, response) }
        return output.toByteArray()
    }

    private fun writeUntyped(json: com.fasterxml.jackson.core.JsonGenerator, value: Any?) {
        when (value) {
            is Map<*, *> -> {
                json.writeStartObject()
                value.forEach { (key, child) -> json.writeFieldName(key as String); writeUntyped(json, child) }
                json.writeEndObject()
            }
            is List<*> -> { json.writeStartArray(); value.forEach { writeUntyped(json, it) }; json.writeEndArray() }
            is String -> json.writeString(value)
            is Long -> json.writeNumber(value)
            is Double -> json.writeNumber(value)
            is Boolean -> json.writeBoolean(value)
            null -> json.writeNull()
            else -> invalid()
        }
    }

    private fun invalid(): Nothing = throw DailyMealReviewProtocolException.InvalidPayload()

    internal const val MAX_REQUEST_BYTES = 8 * 1024
    internal const val MAX_RESPONSE_BYTES = 16 * 1024
    private val STORED_KEYS = setOf(
        "profileKey", "schoolKey", "date", "mealType", "mealFingerprint", "requestId", "wholeMeal",
        "menuSnapshot", "response",
    )
}

data class DailyMealReviewDevelopmentConfig(val endpoint: URL, val accessToken: String) {
    companion object {
        private const val FILENAME = "meal-coach-development.json"
        private const val MAX_CONFIG_BYTES = 4_096L
        private val allowedBases = setOf("http://10.0.2.2:64918", "http://127.0.0.1:64918")

        fun load(filesDir: File, isDebug: Boolean): DailyMealReviewDevelopmentConfig? {
            if (!isDebug) return null
            return try {
                val file = File(filesDir, FILENAME)
                if (!file.isFile || file.length() !in 1..MAX_CONFIG_BYTES) return null
                val root = MealJsonReader.parseObject(file.readBytes())
                if (root.keys != setOf("endpoint", "accessToken")) return null
                val oldEndpoint = URL(root["endpoint"] as? String ?: return null)
                val base = "${oldEndpoint.protocol}://${oldEndpoint.host}:${oldEndpoint.port}"
                val token = (root["accessToken"] as? String)?.trim() ?: return null
                if (base !in allowedBases || oldEndpoint.path != "/v1/meal-coach" || token.length < 32) return null
                DailyMealReviewDevelopmentConfig(URL("$base/v2/meal-coach/daily"), token)
            } catch (_: Exception) {
                null
            }
        }
    }
}

private class DailyMealReviewHttpException(val status: Int, val body: ByteArray) : IOException()

fun interface DailyMealReviewTransport {
    suspend fun post(endpoint: URL, accessToken: String, body: ByteArray): ByteArray
}

class HttpDailyMealReviewTransport : DailyMealReviewTransport {
    override suspend fun post(endpoint: URL, accessToken: String, body: ByteArray): ByteArray =
        withContext(Dispatchers.IO) {
            val connection = endpoint.openConnection() as HttpURLConnection
            suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { connection.disconnect() }
                try {
                    connection.requestMethod = "POST"
                    connection.connectTimeout = 15_000
                    connection.readTimeout = 15_000
                    connection.instanceFollowRedirects = false
                    connection.doOutput = true
                    connection.setRequestProperty("Authorization", "Bearer $accessToken")
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.setFixedLengthStreamingMode(body.size)
                    connection.outputStream.use { it.write(body) }
                    val status = connection.responseCode
                    val input = if (status in 200..299) connection.inputStream else connection.errorStream
                    val response = input?.use { stream ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(4_096)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            if (output.size() > DailyMealReviewJson.MAX_RESPONSE_BYTES) {
                                throw DailyMealReviewProtocolException.ResponseTooLarge()
                            }
                        }
                        output.toByteArray()
                    } ?: ByteArray(0)
                    if (status !in 200..299) throw DailyMealReviewHttpException(status, response)
                    if (continuation.isActive) continuation.resumeWith(Result.success(response))
                } catch (error: Throwable) {
                    if (continuation.isActive) continuation.resumeWith(Result.failure(error))
                } finally {
                    connection.disconnect()
                }
            }
        }
}

class DevelopmentDailyMealReviewClient(
    private val config: DailyMealReviewDevelopmentConfig,
    private val transport: DailyMealReviewTransport = HttpDailyMealReviewTransport(),
) : DailyMealReviewClient {
    override suspend fun generate(request: DailyMealReviewRequest): DailyMealReviewResponse {
        val response = try {
            withTimeout(TOTAL_TIMEOUT_MILLIS) {
                transport.post(config.endpoint, config.accessToken, DailyMealReviewJson.encodeRequest(request))
            }
        } catch (_: TimeoutCancellationException) {
            throw DailyMealReviewClientException(
                DailyMealReviewError.Timeout,
                "응답 시간이 지나 연결을 종료했어요. 같은 요청으로 다시 시도해 주세요.",
            )
        } catch (error: DailyMealReviewHttpException) {
            throw mapDailyMealReviewHttpError(error.status, error.body)
        }
        return DailyMealReviewJson.decodeResponse(response, request)
    }

    private companion object {
        const val TOTAL_TIMEOUT_MILLIS = 15_000L
    }
}

internal fun mapDailyMealReviewHttpError(
    status: Int,
    body: ByteArray,
): DailyMealReviewClientException {
    val code = runCatching {
        val root = MealJsonReader.parseObject(body)
        if (root.keys.any { it !in setOf("error", "reason") }) null else root["error"] as? String
    }.getOrNull()
    val mapped = when {
        status == 401 -> Triple(DailyMealReviewError.Unauthorized, "개발 인증을 확인해 주세요.", true)
        status == 409 && code == "request_conflict" -> Triple(
            DailyMealReviewError.RequestConflict,
            "요청 식별자가 다른 식단과 충돌해 오늘은 다시 생성할 수 없어요.",
            false,
        )
        status == 409 && code == "recovery_unavailable" -> Triple(
            DailyMealReviewError.RecoveryUnavailable,
            "전달이 불확실한 AI 응답을 복구할 수 없어 오늘은 다시 생성할 수 없어요.",
            false,
        )
        status == 409 && code == "daily_used" -> Triple(
            DailyMealReviewError.DailyUsed,
            "오늘 AI 해설은 이미 생성했어요. 저장된 평가를 확인해 주세요.",
            false,
        )
        status == 409 && code == "in_progress" -> Triple(
            DailyMealReviewError.InProgress,
            "같은 요청을 처리하고 있어요. 잠시 후 다시 확인해 주세요.",
            true,
        )
        status == 429 && code == "daily_attempt_limit" -> Triple(
            DailyMealReviewError.AttemptLimit,
            "오늘 AI 생성 시도 한도에 도달했어요.",
            false,
        )
        status == 429 -> Triple(DailyMealReviewError.UsageLimit, "현재 AI 사용 한도에 도달했어요.", true)
        status == 503 && code == "storage_unavailable" -> Triple(
            DailyMealReviewError.StorageUnavailable,
            "서버 저장소를 사용할 수 없어요.",
            true,
        )
        status == 503 -> Triple(DailyMealReviewError.NotConfigured, "개발 AI 연결이 준비되지 않았어요.", true)
        status == 502 -> Triple(
            DailyMealReviewError.AnswerUnavailable,
            "AI 답변을 확인하지 못해 기본 안내를 보여드려요.",
            true,
        )
        status == 400 -> Triple(DailyMealReviewError.InvalidRequest, "식단 요청을 만들지 못했어요.", false)
        else -> Triple(DailyMealReviewError.Network, "연결을 확인한 뒤 다시 시도해 주세요.", true)
    }
    return DailyMealReviewClientException(mapped.first, mapped.second, mapped.third)
}
