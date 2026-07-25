package com.h19h29.naymnaymlevelup.rebuild.foundation

object RebuildFeatureGate {
    fun isEnabled(defaultValue: Boolean, overrideValue: String?): Boolean {
        return defaultValue || overrideValue?.equals("true", ignoreCase = true) == true
    }
}
