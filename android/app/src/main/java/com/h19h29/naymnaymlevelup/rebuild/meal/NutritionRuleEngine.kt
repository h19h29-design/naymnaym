package com.h19h29.naymnaymlevelup.rebuild.meal

import android.content.res.AssetManager
import java.util.Locale

class ContractLoadException(
    val contractName: String,
) : IllegalArgumentException("Invalid or missing rebuild contract: $contractName")

data class NutritionNutrient(
    val id: String,
    val childName: String,
    val alternatives: List<String>,
)

data class NutritionInsight(
    val ruleVersion: Int,
    val nutrients: List<NutritionNutrient>,
    val omissionCopy: String,
    val educationNotice: String,
)

class NutritionRuleEngine(
    ruleBytes: ByteArray,
) {
    private val rules = NutritionRulesDocument.decode(ruleBytes)

    constructor(assetManager: AssetManager) : this(
        RebuildContractReader.readAsset(
            assetManager,
            NUTRITION_RULES_FILENAME,
        ),
    )

    fun insight(menuName: String): NutritionInsight {
        val comparableName = menuName.lowercase(Locale.ROOT)
        val seen = linkedSetOf<String>()
        rules.rules.forEach { rule ->
            if (rule.keywords.any(comparableName::contains)) {
                rule.nutrients.forEach(seen::add)
            }
        }
        val nutrientIds = rules.nutrientOrder.filter(seen::contains)
        return NutritionInsight(
            ruleVersion = rules.version,
            nutrients = nutrientIds.map { id ->
                val nutrient = requireNotNull(rules.nutrients[id])
                NutritionNutrient(
                    id = id,
                    childName = nutrient.childName,
                    alternatives = nutrient.alternatives,
                )
            },
            omissionCopy = rules.omissionCopy,
            educationNotice = rules.educationNotice,
        )
    }

    private companion object {
        const val NUTRITION_RULES_FILENAME = "nutrition-rules.json"
    }
}

private data class NutritionRulesDocument(
    val version: Int,
    val nutrientOrder: List<String>,
    val nutrients: Map<String, NutritionDefinition>,
    val rules: List<NutritionRule>,
    val omissionCopy: String,
    val educationNotice: String,
) {
    companion object {
        fun decode(bytes: ByteArray): NutritionRulesDocument =
            try {
                val root = RebuildContractReader.parse(bytes)
                val version = root.requiredInt("version")
                val matching = root.requiredString("matching")
                val deduplicate = root.requiredBoolean("deduplicateNutrientIds")
                val omissionCopy = root.requiredString("omissionCopy")
                val educationNotice = root.requiredString("educationNotice")
                val nutrientOrder = root.requiredStringList("nutrientOrder")
                val nutrientObjects = root.requiredObject("nutrients")
                val nutrients = nutrientOrder.associateWith { id ->
                    val definition = RebuildContractReader.asObject(
                        nutrientObjects[id],
                    )
                        ?: throw ContractLoadException("nutrition-rules.json")
                    NutritionDefinition(
                        childName = definition.requiredString("childName"),
                        alternatives = definition.requiredStringList("alternatives"),
                    )
                }
                val rules = root.requiredObjectList("rules").map { rule ->
                    NutritionRule(
                        keywords = rule.requiredStringList("keywords"),
                        nutrients = rule.requiredStringList("nutrients"),
                    )
                }

                val valid = version == 1 &&
                    matching == "caseInsensitiveSubstring" &&
                    deduplicate &&
                    omissionCopy == "영양소를 조금 놓칠 수 있어요." &&
                    educationNotice ==
                        "영양소 정보는 의학 진단이나 치료를 대신하지 않는 교육용 참고 정보예요." &&
                    nutrientOrder.isNotEmpty() &&
                    nutrientOrder.isUnique() &&
                    nutrientObjects.keys == nutrientOrder.toSet() &&
                    nutrients.values.all { nutrient ->
                        nutrient.childName.isNotEmpty() &&
                            nutrient.alternatives.isNotEmpty() &&
                            nutrient.alternatives.isUnique() &&
                            nutrient.alternatives.all(String::isNotEmpty)
                    } &&
                    rules.isNotEmpty() &&
                    rules.all { rule ->
                        rule.keywords.isNotEmpty() &&
                            rule.keywords.isUnique() &&
                            rule.keywords.all(String::isNotEmpty) &&
                            rule.nutrients.isNotEmpty() &&
                            rule.nutrients.isUnique() &&
                            rule.nutrients.all(nutrients::containsKey)
                    }
                if (!valid) {
                    throw ContractLoadException("nutrition-rules.json")
                }

                NutritionRulesDocument(
                    version = version,
                    nutrientOrder = nutrientOrder,
                    nutrients = nutrients,
                    rules = rules,
                    omissionCopy = omissionCopy,
                    educationNotice = educationNotice,
                )
            } catch (error: ContractLoadException) {
                throw error
            } catch (_: Exception) {
                throw ContractLoadException("nutrition-rules.json")
            }
    }
}

private data class NutritionDefinition(
    val childName: String,
    val alternatives: List<String>,
)

private data class NutritionRule(
    val keywords: List<String>,
    val nutrients: List<String>,
)

object RebuildContractReader {
    fun parse(bytes: ByteArray): Map<String, Any?> =
        MealJsonReader.parseObject(bytes)

    fun readAsset(
        assetManager: AssetManager,
        filename: String,
    ): ByteArray =
        try {
            assetManager.open("rebuild-contracts/$filename").use { it.readBytes() }
        } catch (_: Exception) {
            throw ContractLoadException(filename)
        }

    @Suppress("UNCHECKED_CAST")
    fun asObject(value: Any?): Map<String, Any?>? {
        return value as? Map<String, Any?>
    }
}

internal fun Map<String, Any?>.requiredString(name: String): String =
    (this[name] as? String)?.takeIf(String::isNotEmpty)
        ?: throw ContractLoadException("nutrition-rules.json")

internal fun Map<String, Any?>.requiredBoolean(name: String): Boolean =
    this[name] as? Boolean
        ?: throw ContractLoadException("nutrition-rules.json")

internal fun Map<String, Any?>.requiredInt(name: String): Int {
    val value = this[name] as? Long
        ?: throw ContractLoadException("nutrition-rules.json")
    return value.toInt().takeIf { it.toLong() == value }
        ?: throw ContractLoadException("nutrition-rules.json")
}

internal fun Map<String, Any?>.requiredObject(name: String): Map<String, Any?> =
    RebuildContractReader.asObject(this[name])
        ?: throw ContractLoadException("nutrition-rules.json")

internal fun Map<String, Any?>.requiredStringList(name: String): List<String> {
    val values = this[name] as? List<*>
        ?: throw ContractLoadException("nutrition-rules.json")
    return values.map {
        it as? String ?: throw ContractLoadException("nutrition-rules.json")
    }
}

internal fun Map<String, Any?>.requiredObjectList(
    name: String,
): List<Map<String, Any?>> {
    val values = this[name] as? List<*>
        ?: throw ContractLoadException("nutrition-rules.json")
    return values.map {
        RebuildContractReader.asObject(it)
            ?: throw ContractLoadException("nutrition-rules.json")
    }
}

private fun List<String>.isUnique(): Boolean =
    size == toSet().size
