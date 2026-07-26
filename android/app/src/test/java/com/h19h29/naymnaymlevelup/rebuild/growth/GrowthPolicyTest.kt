package com.h19h29.naymnaymlevelup.rebuild.growth

import com.h19h29.naymnaymlevelup.rebuild.meal.ContractLoadException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class GrowthPolicyTest {
    private val policy = GrowthPolicy.decode(CANONICAL_POLICY)

    @Test
    fun everyLevelBoundaryMatchesTheSharedContract() {
        val cases = listOf(
            -1 to 1,
            0 to 1,
            79 to 1,
            80 to 2,
            179 to 2,
            180 to 3,
            319 to 3,
            320 to 4,
            499 to 4,
            500 to 5,
            719 to 5,
            720 to 6,
            999 to 6,
            1_000 to 7,
            Int.MAX_VALUE to 7,
        )

        cases.forEach { (totalXp, expectedLevel) ->
            assertEquals(
                "Unexpected level for $totalXp XP",
                expectedLevel,
                policy.level(totalXp),
            )
        }
    }

    @Test
    fun bundledDocumentKeepsTheExactThresholdsAndTitles() {
        assertEquals(
            listOf(0, 80, 180, 320, 500, 720, 1_000),
            policy.thresholds,
        )
        assertEquals(
            listOf(
                "냠냠 새싹",
                "한 입 탐험가",
                "냠냠 용사",
                "편식 몬스터 사냥꾼",
                "급식 히어로",
                "영양 마스터",
                "레전드 냠냠러",
            ),
            policy.titles,
        )
    }

    @Test
    fun malformedOrMissingPolicyNeverSilentlyFallsBack() {
        assertThrows(ContractLoadException::class.java) {
            GrowthPolicy.decode(
                """
                {
                  "version": 1,
                  "thresholds": [0, 80, 80, 320, 500, 720, 1000],
                  "titles": ["1", "2", "3", "4", "5", "6", "7"]
                }
                """.trimIndent().encodeToByteArray(),
            )
        }
        assertThrows(ContractLoadException::class.java) {
            GrowthPolicyLoader.load {
                throw IllegalStateException("missing asset")
            }
        }
    }

    private companion object {
        val CANONICAL_POLICY = """
            {
              "version": 1,
              "thresholds": [0, 80, 180, 320, 500, 720, 1000],
              "titles": [
                "냠냠 새싹",
                "한 입 탐험가",
                "냠냠 용사",
                "편식 몬스터 사냥꾼",
                "급식 히어로",
                "영양 마스터",
                "레전드 냠냠러"
              ]
            }
        """.trimIndent().encodeToByteArray()
    }
}
