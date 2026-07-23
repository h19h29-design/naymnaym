package com.h19h29.naymnaymlevelup;

import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class ReadableColorPaletteTest {
    @Test
    public void supportingTextNeverDropsBelowFourteenSp() {
        assertTrue(ReadableColorPalette.MIN_SUPPORTING_TEXT_SP >= 14);
    }

    @Test
    public void homeContentTopInsetKeepsLogoClearOfStatusBar() {
        assertTrue(ReadableColorPalette.HOME_CONTENT_TOP_INSET_DP >= 32);
    }

    @Test
    public void semanticTextColorsMeetContrastOnLightSurfaces() {
        int[] foregrounds = {
            ReadableColorPalette.TEXT,
            ReadableColorPalette.MUTED,
            ReadableColorPalette.DARK_GREEN,
            ReadableColorPalette.ORANGE,
            ReadableColorPalette.WARNING
        };
        int[] backgrounds = {
            ReadableColorPalette.WHITE,
            ReadableColorPalette.CREAM,
            ReadableColorPalette.MINT
        };

        for (int foreground : foregrounds) {
            for (int background : backgrounds) {
                assertTrue(
                    "Expected readable contrast for " + Integer.toHexString(foreground)
                        + " on " + Integer.toHexString(background),
                    ReadableColorPalette.contrastRatio(foreground, background) >= 4.5
                );
            }
        }
    }

    @Test
    public void primaryButtonGreenSupportsWhiteText() {
        assertTrue(
            ReadableColorPalette.contrastRatio(
                ReadableColorPalette.WHITE,
                ReadableColorPalette.GREEN
            ) >= 4.5
        );
    }
}
