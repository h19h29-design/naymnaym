package com.h19h29.naymnaymlevelup.rebuild

import com.h19h29.naymnaymlevelup.BuildConfig
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RebuildRootInvariantTest {
    @Test
    fun generatedBuildConfigKeepsTheRebuildDisabledByDefault() {
        assertFalse(BuildConfig.NATIVE_REBUILD_ENABLED)
    }

    @Test
    fun manifestKeepsLegacyLauncherAndMakesRebuildActivityPrivate() {
        val manifest = File("src/main/AndroidManifest.xml").readText()

        assertTrue(
            Regex(
                """<activity\s+android:name=\"\.rebuild\.RebuildActivity\"\s+android:exported=\"false\"\s*/>""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(manifest),
        )
        assertTrue(
            Regex(
                """<activity\s+android:name=\"\.MainActivity\"\s+android:exported=\"true\">.*?android\.intent\.action\.MAIN.*?android\.intent\.category\.LAUNCHER""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(manifest),
        )
    }

    @Test
    fun mainActivityUsesOnlyTheCompiledFlagToEnterTheRebuild() {
        val mainActivity = File("src/main/java/com/h19h29/naymnaymlevelup/MainActivity.java").readText()

        assertTrue(
            Regex(
                """if\s*\(BuildConfig\.NATIVE_REBUILD_ENABLED\)\s*\{\s*startActivity\(new Intent\(this, RebuildActivity\.class\)\);\s*finish\(\);\s*return;""",
                RegexOption.DOT_MATCHES_ALL,
            ).containsMatchIn(mainActivity),
        )
        assertFalse(
            Regex("""(?:getBooleanExtra|getStringExtra|hasExtra)\([^)]*NATIVE_REBUILD_ENABLED""")
                .containsMatchIn(mainActivity),
        )
    }
}
