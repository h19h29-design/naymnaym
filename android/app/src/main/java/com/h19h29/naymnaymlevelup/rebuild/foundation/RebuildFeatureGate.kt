package com.h19h29.naymnaymlevelup.rebuild.foundation

import android.app.Instrumentation
import com.h19h29.naymnaymlevelup.BuildConfig

object RebuildFeatureGate {
    fun isEnabled(defaultValue: Boolean, overrideValue: String?): Boolean {
        return defaultValue || overrideValue?.equals("true", ignoreCase = true) == true
    }
}

object RebuildNativeGate {
    @Volatile
    private var instrumentationOverride = false

    @JvmStatic
    fun isEnabled(): Boolean {
        return BuildConfig.NATIVE_REBUILD_ENABLED ||
            (BuildConfig.DEBUG && instrumentationOverride)
    }

    @JvmStatic
    fun setInstrumentationOverride(
        instrumentation: Instrumentation,
        enabled: Boolean,
    ) {
        check(BuildConfig.DEBUG) {
            "The native rebuild override is unavailable in release builds"
        }
        check(
            instrumentation.targetContext.packageName ==
                BuildConfig.APPLICATION_ID,
        ) {
            "The override must target this application"
        }
        check(
            instrumentation.context.packageName ==
                "${BuildConfig.APPLICATION_ID}.test",
        ) {
            "The override is available only to this app's instrumentation"
        }
        instrumentationOverride = enabled
    }
}
