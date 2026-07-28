package com.h19h29.naymnaymlevelup.rebuild.onboarding

import org.junit.Assert.assertEquals
import org.junit.Test

class AllergyCatalogTest {
    @Test
    fun labelsPairEachOfficialCodeWithItsFoodName() {
        assertEquals(19, AllergyCatalog.options.size)
        assertEquals("1. 난류", AllergyCatalog.label(1))
        assertEquals("18. 조개류", AllergyCatalog.label(18))
        assertEquals("19. 잣", AllergyCatalog.label(19))
    }

    @Test
    fun summaryUsesNamesWhileKeepingCanonicalCodeOrder() {
        assertEquals(
            "1. 난류, 5. 대두",
            AllergyCatalog.summary(listOf(5, 1, 5)),
        )
    }
}
