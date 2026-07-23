package com.h19h29.naymnaymlevelup;

final class ReadableColorPalette {
    static final int MIN_SUPPORTING_TEXT_SP = 14;
    static final int HOME_CONTENT_TOP_INSET_DP = 32;

    static final int WHITE = 0xFFFFFFFF;
    static final int CREAM = 0xFFFFF9E8;
    static final int MINT = 0xFFECF8DB;
    static final int TEXT = 0xFF1F2937;
    static final int MUTED = 0xFF4B5563;
    static final int GREEN = 0xFF2F6B2A;
    static final int DARK_GREEN = 0xFF1F5520;
    static final int ORANGE = 0xFF9A3F00;
    static final int WARNING = 0xFFB4232A;

    private ReadableColorPalette() {}

    static double contrastRatio(int foreground, int background) {
        double foregroundLuminance = relativeLuminance(foreground);
        double backgroundLuminance = relativeLuminance(background);
        double lighter = Math.max(foregroundLuminance, backgroundLuminance);
        double darker = Math.min(foregroundLuminance, backgroundLuminance);
        return (lighter + 0.05) / (darker + 0.05);
    }

    private static double relativeLuminance(int color) {
        double red = ((color >> 16) & 0xFF) / 255.0;
        double green = ((color >> 8) & 0xFF) / 255.0;
        double blue = (color & 0xFF) / 255.0;
        return 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue);
    }

    private static double linearized(double component) {
        return component <= 0.04045
            ? component / 12.92
            : Math.pow((component + 0.055) / 1.055, 2.4);
    }
}
