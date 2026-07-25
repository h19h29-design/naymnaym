package com.h19h29.naymnaymlevelup.rebuild.meal

import com.fasterxml.jackson.core.JsonFactory
import com.fasterxml.jackson.core.JsonParser
import com.fasterxml.jackson.core.JsonToken

class MealJsonFormatException(
    message: String,
    cause: Throwable? = null,
) : IllegalArgumentException(message, cause)

object MealJsonReader {
    private val factory = JsonFactory()

    fun parseObject(bytes: ByteArray): Map<String, Any?> =
        factory.createParser(bytes).use(::parseObject)

    fun parseObject(raw: String): Map<String, Any?> =
        factory.createParser(raw).use(::parseObject)

    private fun parseObject(parser: JsonParser): Map<String, Any?> =
        try {
            if (parser.nextToken() != JsonToken.START_OBJECT) {
                throw MealJsonFormatException(
                    "JSON payload must start with an object",
                )
            }
            val root = readValue(parser).objectValue()
                ?: throw MealJsonFormatException(
                    "JSON payload must be an object",
                )
            if (parser.nextToken() != null) {
                throw MealJsonFormatException(
                    "JSON payload must contain exactly one root object",
                )
            }
            root
        } catch (error: MealJsonFormatException) {
            throw error
        } catch (error: Exception) {
            throw MealJsonFormatException("Invalid JSON payload", error)
        }

    private fun readValue(parser: JsonParser): Any? =
        when (parser.currentToken()) {
            JsonToken.START_OBJECT -> buildMap<String, Any?> {
                while (parser.nextToken() != JsonToken.END_OBJECT) {
                    val fieldName = parser.currentName()
                    parser.nextToken()
                    put(fieldName, readValue(parser))
                }
            }
            JsonToken.START_ARRAY -> buildList {
                while (parser.nextToken() != JsonToken.END_ARRAY) {
                    add(readValue(parser))
                }
            }
            JsonToken.VALUE_STRING -> parser.text
            JsonToken.VALUE_NUMBER_INT -> parser.longValue
            JsonToken.VALUE_NUMBER_FLOAT -> parser.doubleValue
            JsonToken.VALUE_TRUE -> true
            JsonToken.VALUE_FALSE -> false
            JsonToken.VALUE_NULL -> null
            else -> throw MealJsonFormatException("Unsupported JSON token")
        }

    @Suppress("UNCHECKED_CAST")
    private fun Any?.objectValue(): Map<String, Any?>? =
        this as? Map<String, Any?>
}
