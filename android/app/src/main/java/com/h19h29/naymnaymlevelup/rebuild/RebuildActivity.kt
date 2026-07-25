package com.h19h29.naymnaymlevelup.rebuild

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildApp
import com.h19h29.naymnaymlevelup.rebuild.data.RebuildDatabase

class RebuildActivity : ComponentActivity() {
    private lateinit var database: RebuildDatabase

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        database = RebuildDatabase.open(applicationContext)
        setContent { RebuildApp(database) }
    }

    override fun onDestroy() {
        if (::database.isInitialized) {
            database.close()
        }
        super.onDestroy()
    }
}
