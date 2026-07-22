package com.h19h29.naymnaymlevelup;

final class IntroLogoMotionSpec {
    static final float SPLIT_FRACTION = 0.40f;
    static final float INITIAL_Y_DP = 10f;
    static final float INITIAL_SCALE = 0.988f;

    static final long NYAM_START_MS = 40L;
    static final long LEVEL_UP_START_MS = 340L;
    static final long RISE_DURATION_MS = 760L;
    static final long SHINE_START_MS = 1_180L;
    static final long SHINE_DURATION_MS = 820L;
    static final long REDUCE_MOTION_FADE_DURATION_MS = 250L;

    private IntroLogoMotionSpec() {}

    static int contentWidth(int viewWidth, int viewHeight, int drawableWidth, int drawableHeight) {
        if (viewWidth <= 0 || viewHeight <= 0 || drawableWidth <= 0 || drawableHeight <= 0) {
            return 0;
        }
        float scale = Math.min(
            (float) viewWidth / drawableWidth,
            (float) viewHeight / drawableHeight
        );
        return Math.round(drawableWidth * scale);
    }

    static int contentLeft(int viewWidth, int viewHeight, int drawableWidth, int drawableHeight) {
        return (viewWidth - contentWidth(viewWidth, viewHeight, drawableWidth, drawableHeight)) / 2;
    }

    static int splitX(int viewWidth, int viewHeight, int drawableWidth, int drawableHeight) {
        int width = contentWidth(viewWidth, viewHeight, drawableWidth, drawableHeight);
        int left = contentLeft(viewWidth, viewHeight, drawableWidth, drawableHeight);
        return left + Math.round(width * SPLIT_FRACTION);
    }
}
