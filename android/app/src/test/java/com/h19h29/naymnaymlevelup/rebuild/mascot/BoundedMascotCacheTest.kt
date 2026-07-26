package com.h19h29.naymnaymlevelup.rebuild.mascot

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BoundedMascotCacheTest {
    @Test
    fun byteCostEvictionIsDeterministicAndAccessOrdered() {
        val cache = BoundedMascotCache<Int, String>(
            maxEntries = 3,
            maxCost = 5,
            costOf = String::length,
        )

        cache.put(1, "aa")
        cache.put(2, "bbb")
        assertEquals("aa", cache[1])
        cache.put(3, "cc")

        assertEquals(listOf(1, 3), cache.keysInLruOrder())
        assertEquals(4, cache.totalCost)
        assertNull(cache[2])

        cache.put(4, "too-large")
        assertNull(cache[4])
        assertEquals(listOf(1, 3), cache.keysInLruOrder())
    }

    @Test
    fun countEvictionKeepsOnlyTheMostRecentlyUsedEntries() {
        val cache = BoundedMascotCache<Int, String>(
            maxEntries = 2,
            maxCost = 100,
            costOf = String::length,
        )

        cache.put(1, "one")
        cache.put(2, "two")
        assertEquals("one", cache[1])
        cache.put(3, "three")

        assertEquals(listOf(1, 3), cache.keysInLruOrder())
        assertNull(cache[2])
    }
}
