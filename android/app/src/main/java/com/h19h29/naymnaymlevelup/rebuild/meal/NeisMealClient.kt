package com.h19h29.naymnaymlevelup.rebuild.meal

import android.util.Log
import com.h19h29.naymnaymlevelup.BuildConfig
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

fun interface NeisTransport {
    suspend fun get(url: URL): ByteArray
}

class HttpUrlConnectionNeisTransport : NeisTransport {
    override suspend fun get(url: URL): ByteArray = withContext(Dispatchers.IO) {
        val connection = url.openConnection() as HttpURLConnection
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation {
                connection.disconnect()
            }
            try {
                connection.requestMethod = "GET"
                connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
                connection.readTimeout = READ_TIMEOUT_MILLIS
                val status = connection.responseCode
                val stream = if (status in 200..299) {
                    connection.inputStream
                } else {
                    connection.errorStream
                }
                val body = stream?.use { it.readBytes() } ?: ByteArray(0)
                if (status !in 200..299) {
                    throw NeisMealClientException.HttpStatus(status)
                }
                if (continuation.isActive) {
                    continuation.resumeWith(Result.success(body))
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
        const val CONNECT_TIMEOUT_MILLIS = 15_000
        const val READ_TIMEOUT_MILLIS = 20_000
    }
}

sealed class NeisMealClientException(
    message: String,
    cause: Throwable? = null,
) : IOException(message, cause) {
    class InvalidDate(
        val value: String,
        cause: Throwable? = null,
    ) : NeisMealClientException("Invalid meal date: $value", cause)

    class MalformedResponse :
        NeisMealClientException("Malformed NEIS meal response")

    class ResultError(
        val code: String,
        val resultMessage: String?,
    ) : NeisMealClientException(
        listOfNotNull(code, resultMessage).joinToString(": "),
    )

    class HttpStatus(val status: Int) :
        NeisMealClientException("NEIS HTTP status $status")
}

class NeisMealClient(
    private val apiKey: String = BuildConfig.NEIS_API_KEY,
    private val transport: NeisTransport = HttpUrlConnectionNeisTransport(),
    private val logger: (String) -> Unit = { Log.d(LOG_TAG, it) },
) : MealClient {
    override suspend fun fetch(date: LocalDate, school: School): MealDay? =
        fetchValidated(date, school)

    suspend fun fetch(date: String, school: School): MealDay? {
        val parsed = try {
            LocalDate.parse(date, DateTimeFormatter.ISO_LOCAL_DATE)
        } catch (error: DateTimeParseException) {
            throw NeisMealClientException.InvalidDate(date, error)
        }
        if (parsed.toString() != date) {
            throw NeisMealClientException.InvalidDate(date)
        }
        return fetchValidated(parsed, school)
    }

    private suspend fun fetchValidated(
        date: LocalDate,
        school: School,
    ): MealDay? {
        val neisDate = date.format(NEIS_DATE_FORMAT)
        val url = buildUrl(
            linkedMapOf(
                "KEY" to apiKey,
                "Type" to "json",
                "pIndex" to "1",
                "pSize" to "100",
                "ATPT_OFCDC_SC_CODE" to school.officeCode,
                "SD_SCHUL_CODE" to school.schoolCode,
                "MMEAL_SC_CODE" to "2",
                "MLSV_FROM_YMD" to neisDate,
                "MLSV_TO_YMD" to neisDate,
            ),
        )
        logger(redacted(url))
        val root = try {
            MealJsonReader.parseObject(transport.get(url))
        } catch (_: MealJsonFormatException) {
            throw NeisMealClientException.MalformedResponse()
        }
        val mealSections = root.strictArrayIfPresent("mealServiceDietInfo")
        val rows = mealSections.orEmpty().flatMap { sectionValue ->
            val section = sectionValue.objectValue()
                ?: throw NeisMealClientException.MalformedResponse()
            section.strictArrayIfPresent("row").orEmpty()
        }
        val row = rows.map { rowValue ->
            rowValue.objectValue()
                ?: throw NeisMealClientException.MalformedResponse()
        }
            .firstOrNull { it.string("MLSV_YMD") == neisDate }

        if (row != null) {
            val dishText = row.string("DDISH_NM")
                ?: throw NeisMealClientException.MalformedResponse()
            val menuItems = parseMealItems(dishText)
            if (menuItems.isEmpty()) {
                throw NeisMealClientException.MalformedResponse()
            }
            return MealDay(
                date = date.toString(),
                menuItems = menuItems,
                calorie = row.string("CAL_INFO") ?: "정보 없음",
                nutrition = parseNutrition(row.string("NTR_INFO").orEmpty()),
            )
        }

        val result = root.objectValue("RESULT")
        val code = result?.string("CODE")
        if (code == "INFO-200") {
            return null
        }
        if (code != null) {
            throw NeisMealClientException.ResultError(
                code = code,
                resultMessage = result.string("MESSAGE"),
            )
        }
        if (mealSections != null) {
            return null
        }
        throw NeisMealClientException.MalformedResponse()
    }

    private fun buildUrl(query: Map<String, String>): URL {
        val encodedQuery = query.entries.joinToString("&") { (name, value) ->
            "${encode(name)}=${encode(value)}"
        }
        return URL("$BASE_URL?$encodedQuery")
    }

    private fun redacted(url: URL): String =
        url.toExternalForm().replace(
            Regex("([?&]KEY=)[^&]*"),
            "$1<redacted>",
        )

    private companion object {
        const val BASE_URL =
            "https://open.neis.go.kr/hub/mealServiceDietInfo"
        const val LOG_TAG = "NeisMealClient"
        val NEIS_DATE_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyyMMdd")
        fun encode(value: String): String =
            URLEncoder.encode(value, StandardCharsets.UTF_8.name())

        fun parseMealItems(raw: String): List<MealItem> =
            raw.replace("&amp;", "&")
                .split(Regex("(?i)<br\\s*/?>"))
                .map(String::trim)
                .filter(String::isNotEmpty)
                .map { source ->
                    MealItem(
                        name = source
                            .replace(Regex("\\([0-9.,\\s]+\\)"), "")
                            .replace(Regex("[0-9]+\\."), "")
                            .replace("*", "")
                            .trim(),
                        allergyCodes = ALLERGY_PATTERN
                            .findAll(source)
                            .map { it.groupValues[1].toInt() }
                            .distinct()
                            .sorted()
                            .toList(),
                        nutrients = emptyList(),
                        tags = emptyList(),
                        sourceRawText = source,
                    )
                }

        val ALLERGY_PATTERN =
            Regex("(?<!\\d)([1-9]|1[0-9])(?=\\.|\\)|,|\\s|$)")

        fun parseNutrition(raw: String): NutritionInfo = NutritionInfo(
            carbs = nutritionValue(raw, "탄수화물", "carbohydrate"),
            protein = nutritionValue(raw, "단백질", "protein"),
            fat = nutritionValue(raw, "지방", "fat"),
            calcium = nutritionValue(raw, "칼슘", "calcium"),
            iron = nutritionValue(raw, "철", "iron"),
            vitamin = nutritionValue(raw, "비타민", "vitamin"),
        )

        fun nutritionValue(raw: String, vararg keywords: String): Double {
            keywords.forEach { keyword ->
                val match = Regex(
                    "(?i)${Regex.escape(keyword)}[^0-9]*([0-9]+(?:\\.[0-9]+)?)",
                ).find(raw)
                if (match != null) {
                    return match.groupValues[1].toDouble()
                }
            }
            return 0.0
        }

        @Suppress("UNCHECKED_CAST")
        fun Map<String, Any?>.strictArrayIfPresent(
            name: String,
        ): List<Any?>? {
            if (!containsKey(name)) {
                return null
            }
            return this[name] as? List<Any?>
                ?: throw NeisMealClientException.MalformedResponse()
        }

        @Suppress("UNCHECKED_CAST")
        fun Any?.objectValue(): Map<String, Any?>? =
            this as? Map<String, Any?>

        @Suppress("UNCHECKED_CAST")
        fun Map<String, Any?>.objectValue(name: String): Map<String, Any?>? =
            this[name] as? Map<String, Any?>

        fun Map<String, Any?>.string(name: String): String? =
            this[name] as? String
    }
}
