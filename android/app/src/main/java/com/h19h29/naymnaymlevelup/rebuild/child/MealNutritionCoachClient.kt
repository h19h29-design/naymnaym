package com.h19h29.naymnaymlevelup.rebuild.child

import com.fasterxml.jackson.core.JsonFactory
import com.fasterxml.jackson.core.JsonToken
import com.fasterxml.jackson.core.StreamReadFeature
import com.h19h29.naymnaymlevelup.rebuild.meal.MealJsonReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

sealed class MealCoachProtocolException(message: String, cause: Throwable? = null) :
    IOException(message, cause) {
    class InvalidPayload(cause: Throwable? = null) :
        MealCoachProtocolException("Invalid meal coach payload", cause)

    class HttpStatus(val status: Int) :
        MealCoachProtocolException("Meal coach HTTP status $status")

    class ResponseTooLarge :
        MealCoachProtocolException("Meal coach response exceeds 16 KB")
}

object MealCoachJson {
    private val writerFactory = JsonFactory()
    private val strictReaderFactory = JsonFactory.builder()
        .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION)
        .build()

    fun encodeRequest(request: MealCoachRequest): String {
        val output = ByteArrayOutputStream()
        writerFactory.createGenerator(output).use { json ->
            json.writeStartObject()
            json.writeStringField("question", request.question.wireValue)
            json.writeArrayFieldStart("nutrients")
            request.nutrients.forEach(json::writeString)
            json.writeEndArray()
            json.writeObjectFieldStart("wholeMeal")
            request.wholeMeal.protein?.let { json.writeNumberField("protein", it) }
            request.wholeMeal.carbs?.let { json.writeNumberField("carbs", it) }
            request.wholeMeal.fat?.let { json.writeNumberField("fat", it) }
            json.writeEndObject()
            json.writeStringField("sessionId", request.sessionId)
            json.writeEndObject()
        }
        return output.toString(Charsets.UTF_8.name())
    }

    fun decodeResponse(bytes: ByteArray): MealCoachResponse {
        if (bytes.size > MAX_RESPONSE_BYTES) {
            throw MealCoachProtocolException.ResponseTooLarge()
        }
        val values = try {
            strictReaderFactory.createParser(bytes).use { parser ->
                if (parser.nextToken() != JsonToken.START_OBJECT) {
                    throw MealCoachProtocolException.InvalidPayload()
                }
                buildMap<String, String> {
                    while (parser.nextToken() != JsonToken.END_OBJECT) {
                        if (parser.currentToken() != JsonToken.FIELD_NAME) {
                            throw MealCoachProtocolException.InvalidPayload()
                        }
                        val name = parser.currentName()
                        if (parser.nextToken() != JsonToken.VALUE_STRING) {
                            throw MealCoachProtocolException.InvalidPayload()
                        }
                        put(name, parser.text)
                    }
                    if (parser.nextToken() != null) {
                        throw MealCoachProtocolException.InvalidPayload()
                    }
                }
            }
        } catch (error: MealCoachProtocolException) {
            throw error
        } catch (error: Exception) {
            throw MealCoachProtocolException.InvalidPayload(error)
        }
        if (values.keys != RESPONSE_KEYS || values["source"] != "ai") {
            throw MealCoachProtocolException.InvalidPayload()
        }
        val textValues = listOf("summary", "benefit", "caution", "tip").map { key ->
            values.getValue(key).takeIf { it.isNotBlank() && it.length <= MAX_FIELD_CHARACTERS }
                ?: throw MealCoachProtocolException.InvalidPayload()
        }
        if (values.values.sumOf(String::length) > MAX_TOTAL_CHARACTERS) {
            throw MealCoachProtocolException.InvalidPayload()
        }
        return MealCoachResponse(
            source = "ai",
            summary = textValues[0],
            benefit = textValues[1],
            caution = textValues[2],
            tip = textValues[3],
        )
    }

    internal const val MAX_RESPONSE_BYTES = 16 * 1024
    private const val MAX_FIELD_CHARACTERS = 240
    private const val MAX_TOTAL_CHARACTERS = 1_200
    private val RESPONSE_KEYS = setOf("source", "summary", "benefit", "caution", "tip")
}

data class MealCoachDevelopmentConfig(
    val endpoint: URL,
    val accessToken: String,
) {
    companion object {
        private const val FILENAME = "meal-coach-development.json"
        private const val MAX_CONFIG_BYTES = 4_096L
        private val allowedEndpoints = setOf(
            "http://10.0.2.2:64918/v1/meal-coach",
            "http://127.0.0.1:64918/v1/meal-coach",
        )

        fun load(filesDir: File, isDebug: Boolean): MealCoachDevelopmentConfig? {
            if (!isDebug) return null
            return try {
                val file = File(filesDir, FILENAME)
                if (!file.isFile || file.length() !in 1..MAX_CONFIG_BYTES) return null
                val root = MealJsonReader.parseObject(file.readBytes())
                if (root.keys != setOf("endpoint", "accessToken")) return null
                val endpointValue = root["endpoint"] as? String ?: return null
                val accessToken = (root["accessToken"] as? String)?.trim() ?: return null
                if (endpointValue !in allowedEndpoints || accessToken.length < 32) return null
                MealCoachDevelopmentConfig(URL(endpointValue), accessToken)
            } catch (_: Exception) {
                null
            }
        }
    }
}

fun interface MealCoachTransport {
    suspend fun post(
        endpoint: URL,
        accessToken: String,
        body: ByteArray,
    ): ByteArray
}

class HttpUrlConnectionMealCoachTransport : MealCoachTransport {
    override suspend fun post(
        endpoint: URL,
        accessToken: String,
        body: ByteArray,
    ): ByteArray = withContext(Dispatchers.IO) {
        val connection = endpoint.openConnection() as HttpURLConnection
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { connection.disconnect() }
            try {
                connection.requestMethod = "POST"
                connection.connectTimeout = TIMEOUT_MILLIS
                connection.readTimeout = TIMEOUT_MILLIS
                connection.instanceFollowRedirects = false
                connection.doOutput = true
                connection.setRequestProperty("Authorization", "Bearer $accessToken")
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
                val status = connection.responseCode
                val stream = if (status in 200..299) {
                    connection.inputStream
                } else {
                    connection.errorStream
                }
                val response = stream?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(4_096)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        if (output.size() > MealCoachJson.MAX_RESPONSE_BYTES) {
                            throw MealCoachProtocolException.ResponseTooLarge()
                        }
                    }
                    output.toByteArray()
                } ?: ByteArray(0)
                if (status !in 200..299) {
                    throw MealCoachProtocolException.HttpStatus(status)
                }
                if (continuation.isActive) {
                    continuation.resumeWith(Result.success(response))
                }
            } catch (error: Throwable) {
                if (continuation.isActive) {
                    continuation.resumeWith(Result.failure(error))
                }
            } finally {
                connection.disconnect()
            }
        }
    }

    private companion object {
        const val TIMEOUT_MILLIS = 15_000
    }
}

class DevelopmentMealCoachClient(
    private val config: MealCoachDevelopmentConfig,
    private val transport: MealCoachTransport = HttpUrlConnectionMealCoachTransport(),
) : MealCoachClient {
    override suspend fun ask(request: MealCoachRequest): MealCoachResponse {
        val response = transport.post(
            endpoint = config.endpoint,
            accessToken = config.accessToken,
            body = MealCoachJson.encodeRequest(request).encodeToByteArray(),
        )
        return MealCoachJson.decodeResponse(response)
    }
}
