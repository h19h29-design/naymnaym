package com.h19h29.naymnaymlevelup.rebuild.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp

object RebuildTokens {
    const val Forest700 = 0xFF1F5E43
    const val Forest500 = 0xFF2F8A61
    const val Leaf300 = 0xFFCBEA78
    const val Cream50 = 0xFFFFF9EC
    const val Cream100 = 0xFFF5EEDC
    const val Ink900 = 0xFF183127
    const val Muted600 = 0xFF627168
    const val Danger700 = 0xFFA33A35

    val spacing = listOf(4, 8, 12, 16, 24, 32)
    val radii = listOf(12, 20, 28)
    const val minimumActionSize = 48
    const val fontPolicy = "system-scalable"
}

private val RebuildColorScheme = lightColorScheme(
    primary = Color(RebuildTokens.Forest700),
    onPrimary = Color(RebuildTokens.Cream50),
    primaryContainer = Color(RebuildTokens.Leaf300),
    onPrimaryContainer = Color(RebuildTokens.Ink900),
    secondary = Color(RebuildTokens.Forest500),
    onSecondary = Color(RebuildTokens.Cream50),
    background = Color(RebuildTokens.Cream50),
    onBackground = Color(RebuildTokens.Ink900),
    surface = Color(RebuildTokens.Cream100),
    onSurface = Color(RebuildTokens.Ink900),
    error = Color(RebuildTokens.Danger700),
)

private val RebuildTypography = Typography(
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 28.sp,
        lineHeight = 36.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontSize = 16.sp,
        lineHeight = 20.sp,
    ),
)

@Composable
fun RebuildTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = RebuildColorScheme,
        typography = RebuildTypography,
        content = content,
    )
}
