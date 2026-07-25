package com.h19h29.naymnaymlevelup.rebuild

import com.h19h29.naymnaymlevelup.rebuild.foundation.RebuildFeatureGate
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens

internal object RebuildKotlinCompileContract {
    val isEnabledByDefault = RebuildFeatureGate.isEnabled(defaultValue = false, overrideValue = null)
    val minimumActionSize = RebuildTokens.minimumActionSize
}
