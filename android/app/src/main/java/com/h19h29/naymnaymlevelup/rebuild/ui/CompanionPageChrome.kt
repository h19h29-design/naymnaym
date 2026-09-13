package com.h19h29.naymnaymlevelup.rebuild.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.h19h29.naymnaymlevelup.R
import com.h19h29.naymnaymlevelup.rebuild.mascot.MascotRestArt

@Composable
fun CompanionSectionBanner(
    title: String,
    subtitle: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    accent: Color = Color(RebuildTokens.Forest700),
    showsLunch: Boolean = false,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White),
        border = BorderStroke(2.dp, Color.White),
    ) {
        Box {
            Image(painterResource(R.drawable.companion_forest_stage), null,
                Modifier.matchParentSize(), contentScale = ContentScale.Crop, alpha = 0.36f)
            Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(icon, null, tint = accent, modifier = Modifier.size(22.dp))
                        Text(title, style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.ExtraBold, color = accent, modifier = Modifier.semantics { heading() })
                    }
                    Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = Color(RebuildTokens.Ink900))
                }
                if (LocalDensity.current.fontScale < 1.5f) {
                    if (showsLunch) {
                        Image(painterResource(R.drawable.companion_lunch_tray), null, Modifier.size(width = 92.dp, height = 104.dp), contentScale = ContentScale.Fit)
                    } else {
                        MascotRestArt(level = 1, silhouetteColor = null, modifier = Modifier.size(width = 92.dp, height = 104.dp))
                    }
                }
            }
        }
    }
}
