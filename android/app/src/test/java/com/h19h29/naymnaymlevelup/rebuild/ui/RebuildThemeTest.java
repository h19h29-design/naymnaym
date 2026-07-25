package com.h19h29.naymnaymlevelup.rebuild.ui;

import static org.junit.Assert.assertEquals;

import java.util.List;
import org.junit.Test;

public final class RebuildThemeTest {
    @Test
    public void approvedTokensAreExact() {
        assertEquals(48, RebuildTokens.minimumActionSize);
        assertEquals(List.of(4, 8, 12, 16, 24, 32), RebuildTokens.INSTANCE.getSpacing());
        assertEquals(0xFF1F5E43L, RebuildTokens.Forest700);
        assertEquals(0xFFFFF9ECL, RebuildTokens.Cream50);
    }

    @Test
    public void everyApprovedTokenMatchesTheCanonicalContract() {
        assertEquals(0xFF2F8A61L, RebuildTokens.Forest500);
        assertEquals(0xFFCBEA78L, RebuildTokens.Leaf300);
        assertEquals(0xFFF5EEDCL, RebuildTokens.Cream100);
        assertEquals(0xFF183127L, RebuildTokens.Ink900);
        assertEquals(0xFF627168L, RebuildTokens.Muted600);
        assertEquals(0xFFA33A35L, RebuildTokens.Danger700);
        assertEquals(List.of(12, 20, 28), RebuildTokens.INSTANCE.getRadii());
        assertEquals("system-scalable", RebuildTokens.fontPolicy);
    }
}
