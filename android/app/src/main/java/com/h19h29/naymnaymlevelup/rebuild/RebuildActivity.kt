package com.h19h29.naymnaymlevelup.rebuild

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.h19h29.naymnaymlevelup.rebuild.migration.LegacyPreferencesReader
import com.h19h29.naymnaymlevelup.rebuild.migration.RebuildMigrationCoordinator
import com.h19h29.naymnaymlevelup.rebuild.migration.RoomMigrationTarget
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildApp
import kotlinx.coroutines.runBlocking

class RebuildActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val database = (application as RebuildApplication).rebuildDatabase
        runBlocking {
            runCatching {
                RebuildMigrationCoordinator(
                    source = LegacyPreferencesReader(applicationContext),
                    target = RoomMigrationTarget(database),
                ).runIfNeeded()
            }
        }
        setContent { RebuildApp(database) }
    }
}
