package com.h19h29.naymnaymlevelup.rebuild.onboarding

data class AllergyOption(
    val code: Int,
    val name: String,
) {
    val label: String
        get() = "$code. $name"
}

object AllergyCatalog {
    val options: List<AllergyOption> = listOf(
        AllergyOption(1, "난류"),
        AllergyOption(2, "우유"),
        AllergyOption(3, "메밀"),
        AllergyOption(4, "땅콩"),
        AllergyOption(5, "대두"),
        AllergyOption(6, "밀"),
        AllergyOption(7, "고등어"),
        AllergyOption(8, "게"),
        AllergyOption(9, "새우"),
        AllergyOption(10, "돼지고기"),
        AllergyOption(11, "복숭아"),
        AllergyOption(12, "토마토"),
        AllergyOption(13, "아황산류"),
        AllergyOption(14, "호두"),
        AllergyOption(15, "닭고기"),
        AllergyOption(16, "쇠고기"),
        AllergyOption(17, "오징어"),
        AllergyOption(18, "조개류"),
        AllergyOption(19, "잣"),
    )

    private val optionsByCode = options.associateBy(AllergyOption::code)

    fun label(code: Int): String = optionsByCode[code]?.label ?: "${code}번"

    fun summary(codes: List<Int>): String = codes
        .distinct()
        .sorted()
        .joinToString(separator = ", ", transform = ::label)
}
