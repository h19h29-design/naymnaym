package com.h19h29.naymnaymlevelup.rebuild.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class RebuildThemeTest {
    private val tokenClass = Class.forName("com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens")
    private val tokens = tokenClass.getField("INSTANCE").get(null)

    @Test
    fun approvedTokensAreExact() {
        assertEquals(48, intToken("minimumActionSize"))
        assertEquals(listOf(4, 8, 12, 16, 24, 32), listToken("getSpacing"))
        assertEquals(0xFF1F5E43, colorToken("Forest700"))
        assertEquals(0xFFFFF9EC, colorToken("Cream50"))
    }

    @Test
    fun everyApprovedTokenMatchesTheCanonicalContract() {
        assertEquals(0xFF2F8A61, colorToken("Forest500"))
        assertEquals(0xFFCBEA78, colorToken("Leaf300"))
        assertEquals(0xFFF5EEDC, colorToken("Cream100"))
        assertEquals(0xFF183127, colorToken("Ink900"))
        assertEquals(0xFF627168, colorToken("Muted600"))
        assertEquals(0xFFA33A35, colorToken("Danger700"))
        assertEquals(listOf(12, 20, 28), listToken("getRadii"))
        assertEquals("system-scalable", tokenClass.getField("fontPolicy").get(null))
    }

    private fun colorToken(name: String): Long = tokenClass.getField(name).getLong(null)

    private fun intToken(name: String): Int = tokenClass.getField(name).getInt(null)

    @Suppress("UNCHECKED_CAST")
    private fun listToken(getter: String): List<Int> = tokenClass.getMethod(getter).invoke(tokens) as List<Int>
}
