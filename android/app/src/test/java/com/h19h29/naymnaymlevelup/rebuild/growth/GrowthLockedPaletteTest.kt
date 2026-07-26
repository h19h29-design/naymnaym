package com.h19h29.naymnaymlevelup.rebuild.growth

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GrowthLockedPaletteTest {
    @Test
    fun lockedGrowthCopyMeetsNormalTextContrast() {
        assertTrue(
            contrastRatio(
                LockedGrowthTextArgb,
                LockedGrowthSurfaceArgb,
            ) >= 4.5,
        )
        assertNotEquals(
            WarmLockedMascotArgb,
            LockedGrowthTextArgb,
        )
    }

    private fun contrastRatio(foreground: Long, background: Long): Double {
        val foregroundLuminance = relativeLuminance(foreground)
        val backgroundLuminance = relativeLuminance(background)
        return (
            max(foregroundLuminance, backgroundLuminance) + 0.05
        ) / (
            min(foregroundLuminance, backgroundLuminance) + 0.05
        )
    }

    private fun relativeLuminance(color: Long): Double {
        val red = ((color shr 16) and 0xFF) / 255.0
        val green = ((color shr 8) and 0xFF) / 255.0
        val blue = (color and 0xFF) / 255.0
        return 0.2126 * linearized(red) +
            0.7152 * linearized(green) +
            0.0722 * linearized(blue)
    }

    private fun linearized(component: Double): Double =
        if (component <= 0.04045) {
            component / 12.92
        } else {
            ((component + 0.055) / 1.055).pow(2.4)
        }
}
