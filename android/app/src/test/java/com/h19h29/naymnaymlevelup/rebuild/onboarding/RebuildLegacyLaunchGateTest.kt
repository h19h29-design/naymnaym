package com.h19h29.naymnaymlevelup.rebuild.onboarding

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RebuildLegacyLaunchGateTest {
    @Test
    fun nativeRebuildBlocksMissingUnknownAndForgedRoutes() {
        assertTrue(
            RebuildLegacyLaunchGate.shouldHandoffToRebuild(
                nativeEnabled = true,
                consumedRoute = null,
            ),
        )
        assertTrue(
            RebuildLegacyLaunchGate.shouldHandoffToRebuild(
                nativeEnabled = true,
                consumedRoute = "forged",
            ),
        )
    }

    @Test
    fun nativeRebuildAllowsOnlyRecognizedConsumedCapabilities() {
        assertFalse(
            RebuildLegacyLaunchGate.shouldHandoffToRebuild(
                nativeEnabled = true,
                consumedRoute = RebuildLegacyDestinationLauncher.ROUTE_TODAY_MEAL,
            ),
        )
        assertFalse(
            RebuildLegacyLaunchGate.shouldHandoffToRebuild(
                nativeEnabled = true,
                consumedRoute = RebuildLegacyDestinationLauncher.ROUTE_PARENT_CONNECTION,
            ),
        )
    }

    @Test
    fun legacyBuildKeepsItsExistingHomeEntryPoint() {
        assertFalse(
            RebuildLegacyLaunchGate.shouldHandoffToRebuild(
                nativeEnabled = false,
                consumedRoute = null,
            ),
        )
    }
}
