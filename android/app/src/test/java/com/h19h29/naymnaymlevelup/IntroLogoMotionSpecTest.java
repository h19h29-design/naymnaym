package com.h19h29.naymnaymlevelup;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class IntroLogoMotionSpecTest {
    @Test
    public void splitFallsInsideVerifiedSourceTransparentGap() {
        int splitX = IntroLogoMotionSpec.splitX(357, 86, 357, 86);

        assertEquals(143, splitX);
        assertTrue(splitX > 138);
        assertTrue(splitX < 146);
    }

    @Test
    public void splitUsesActualFitCenterContentBounds() {
        assertEquals(149, IntroLogoMotionSpec.splitX(360, 74, 357, 86));
    }

    @Test
    public void timingMatchesApprovedOneShotSequence() {
        assertEquals(10f, IntroLogoMotionSpec.INITIAL_Y_DP, 0.001f);
        assertEquals(0.988f, IntroLogoMotionSpec.INITIAL_SCALE, 0.001f);
        assertEquals(40L, IntroLogoMotionSpec.NYAM_START_MS);
        assertEquals(340L, IntroLogoMotionSpec.LEVEL_UP_START_MS);
        assertEquals(760L, IntroLogoMotionSpec.RISE_DURATION_MS);
        assertEquals(1_180L, IntroLogoMotionSpec.SHINE_START_MS);
        assertEquals(820L, IntroLogoMotionSpec.SHINE_DURATION_MS);
        assertEquals(2_000L, IntroLogoMotionSpec.SHINE_START_MS + IntroLogoMotionSpec.SHINE_DURATION_MS);
        assertEquals(250L, IntroLogoMotionSpec.REDUCE_MOTION_FADE_DURATION_MS);
    }
}
