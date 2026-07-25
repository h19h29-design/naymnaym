package com.h19h29.naymnaymlevelup.rebuild

import android.app.Application
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase

class RebuildApplication : Application() {
    val rebuildDatabase: RebuildDatabase by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        RebuildDatabase.open(applicationContext)
    }
}
