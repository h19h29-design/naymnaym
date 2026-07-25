package com.h19h29.naymnaymlevelup.rebuild;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import com.h19h29.naymnaymlevelup.BuildConfig;
import com.h19h29.naymnaymlevelup.rebuild.foundation.RebuildFeatureGate;
import java.util.List;
import org.junit.Test;

public final class RebuildFeatureGateTest {
    @Test
    public void defaultsToBuildConfigValue() {
        assertFalse(
                RebuildFeatureGate.INSTANCE.isEnabled(
                        BuildConfig.NATIVE_REBUILD_ENABLED,
                        null));
    }

    @Test
    public void explicitTrueOverrideWins() {
        assertTrue(RebuildFeatureGate.INSTANCE.isEnabled(false, "true"));
    }

    @Test
    public void caseInsensitiveTrueOverrideWins() {
        assertTrue(RebuildFeatureGate.INSTANCE.isEnabled(false, "TrUe"));
    }

    @Test
    public void nonTrueOverrideDoesNotEnableTheRebuild() {
        for (String overrideValue :
                List.of("false", "1", "yes", " true ", "", "TRUE!", "enabled")) {
            assertFalse(
                    overrideValue + " must not enable the rebuild",
                    RebuildFeatureGate.INSTANCE.isEnabled(false, overrideValue));
        }
    }

    @Test
    public void falseOverrideDoesNotDisableAnEnabledBuild() {
        assertTrue(RebuildFeatureGate.INSTANCE.isEnabled(true, "false"));
    }
}
