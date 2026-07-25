package com.h19h29.naymnaymlevelup.rebuild

import com.h19h29.naymnaymlevelup.BuildConfig
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RebuildFeatureGateTest {
    private val gateClass = Class.forName("com.h19h29.naymnaymlevelup.rebuild.foundation.RebuildFeatureGate")
    private val gate = gateClass.getField("INSTANCE").get(null)
    private val isEnabled = gateClass.getMethod(
        "isEnabled",
        Boolean::class.javaPrimitiveType,
        String::class.java,
    )

    @Test
    fun defaultsToBuildConfigValue() {
        assertFalse(isEnabled(BuildConfig.NATIVE_REBUILD_ENABLED, null))
    }

    @Test
    fun explicitTrueOverrideWins() {
        assertTrue(isEnabled(false, "true"))
    }

    @Test
    fun caseInsensitiveTrueOverrideWins() {
        assertTrue(isEnabled(false, "TrUe"))
    }

    @Test
    fun nonTrueOverrideDoesNotEnableTheRebuild() {
        listOf("false", "1", "yes", " true ", "", "TRUE!", "enabled").forEach { overrideValue ->
            assertFalse("$overrideValue must not enable the rebuild", isEnabled(false, overrideValue))
        }
    }

    @Test
    fun falseOverrideDoesNotDisableAnEnabledBuild() {
        assertTrue(isEnabled(true, "false"))
    }

    private fun isEnabled(defaultValue: Boolean, overrideValue: String?): Boolean =
        isEnabled.invoke(gate, defaultValue, overrideValue) as Boolean
}
