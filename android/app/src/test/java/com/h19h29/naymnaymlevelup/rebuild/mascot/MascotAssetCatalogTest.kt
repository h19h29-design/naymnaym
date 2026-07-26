package com.h19h29.naymnaymlevelup.rebuild.mascot

import org.junit.Assert.assertEquals
import org.junit.Test

class MascotAssetCatalogTest {
    @Test
    fun allSevenLevelsHaveExplicitDistinctKeyframesAndSemanticFallbacks() {
        val definitions = MascotRigAssetCatalog.definitions

        assertEquals((1..7).toList(), definitions.keys.toList())
        assertEquals(
            7,
            definitions.values.map { it.rest.sha256 }.toSet().size,
        )
        assertEquals(
            7,
            definitions.values.map { it.blink.sha256 }.toSet().size,
        )
        assertEquals(
            7,
            definitions.values.map { it.celebrate.sha256 }.toSet().size,
        )
        MascotRigSemanticPart.entries.forEach { part ->
            assertEquals(
                "Every growth level needs a distinct $part fallback",
                7,
                definitions.values
                    .map { definition -> definition.semanticParts.getValue(part).sha256 }
                    .toSet()
                    .size,
            )
        }
    }
}
