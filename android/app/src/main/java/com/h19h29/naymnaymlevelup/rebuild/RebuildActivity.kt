package com.h19h29.naymnaymlevelup.rebuild

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildApp

class RebuildActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val database = (application as RebuildApplication).rebuildDatabase
        setContent { RebuildApp(database) }
    }
}
