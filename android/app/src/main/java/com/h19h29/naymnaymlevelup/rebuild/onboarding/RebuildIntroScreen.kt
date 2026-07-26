package com.h19h29.naymnaymlevelup.rebuild.onboarding

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.h19h29.naymnaymlevelup.R
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun RebuildIntroScreen(
    onCompleted: suspend () -> Boolean,
    reduceMotionOverride: Boolean? = null,
) {
    val scope = rememberCoroutineScope()
    val systemReduceMotion =
        scope.coroutineContext[MotionDurationScale]?.scaleFactor == 0f
    val reduceMotion = systemReduceMotion || reduceMotionOverride == true
    val controller = remember { RebuildIntroMotionController() }
    var completionFailed by remember { mutableStateOf(false) }
    var completionAttemptInFlight by remember { mutableStateOf(false) }
    val currentOnCompleted by rememberUpdatedState(onCompleted)
    val effectiveReduceMotion = controller.effectiveReduceMotion
        ?: reduceMotion

    fun attemptCompletion() {
        if (completionAttemptInFlight) return
        completionAttemptInFlight = true
        scope.launch {
            try {
                completionFailed = !currentOnCompleted()
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                completionFailed = true
            } finally {
                completionAttemptInFlight = false
            }
        }
    }

    LaunchedEffect(controller) {
        controller.start(
            reduceMotion = reduceMotion,
            onCompleted = ::attemptCompletion,
        )
    }
    DisposableEffect(controller) {
        onDispose(controller::cancel)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color(0xFFFFF9EC),
                        Color(0xFFF5EEDC),
                    ),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = (RebuildIntroMotionSpec.SourceWidth + 16).dp)
                .fillMaxWidth()
                .padding(8.dp),
        ) {
            RebuildIntroLogoCanvas(
                frame = RebuildIntroMotionSpec.frameAt(
                    elapsedMillis = controller.elapsedMillis,
                    reduceMotion = effectiveReduceMotion,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(RebuildIntroMotionSpec.SourceAspectRatio)
                    .testTag("rebuild_intro_logo_viewport")
                    .semantics {
                        contentDescription = "냠냠레벨업"
                    },
            )
        }

        if (completionFailed) {
            Button(
                onClick = ::attemptCompletion,
                enabled = !completionAttemptInFlight,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 32.dp),
            ) {
                Text("저장 다시 시도")
            }
        }
    }
}

@Composable
internal fun RebuildIntroLogoCanvas(
    frame: RebuildIntroLogoFrame,
    modifier: Modifier = Modifier,
) {
    val logo = painterResource(R.drawable.logo_naym_levelup)
    val logoBitmap = ImageBitmap.imageResource(R.drawable.logo_naym_levelup)
    BoxWithConstraints(modifier) {
        val logoWidth = maxWidth
        val logoHeight = maxHeight
        if (frame.rendersWholeLogo) {
            Image(
                painter = logo,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer { alpha = frame.wholeLogoOpacity }
                    .testTag("rebuild_intro_logo_whole"),
            )
        } else {
            Row(
                modifier = Modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                RebuildIntroWordClip(
                    painter = logo,
                    word = frame.leftWord,
                    logoWidth = logoWidth,
                    logoHeight = logoHeight,
                    alignment = Alignment.CenterStart,
                    modifier = Modifier
                        .weight(RebuildIntroMotionSpec.SplitFraction)
                        .fillMaxHeight()
                        .testTag("rebuild_intro_logo_left"),
                )
                RebuildIntroWordClip(
                    painter = logo,
                    word = frame.rightWord,
                    logoWidth = logoWidth,
                    logoHeight = logoHeight,
                    alignment = Alignment.CenterEnd,
                    modifier = Modifier
                        .weight(1f - RebuildIntroMotionSpec.SplitFraction)
                        .fillMaxHeight()
                        .testTag("rebuild_intro_logo_right"),
                )
            }

            frame.shineProgress?.let { progress ->
                RebuildIntroShine(
                    logoBitmap = logoBitmap,
                    progress = progress,
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("rebuild_intro_logo_shine"),
                )
            }
        }
    }
}

@Composable
private fun RebuildIntroWordClip(
    painter: Painter,
    word: RebuildIntroWordFrame,
    logoWidth: Dp,
    logoHeight: Dp,
    alignment: Alignment,
    modifier: Modifier,
) {
    val translationYPixels = with(LocalDensity.current) {
        word.translationY.dp.toPx()
    }
    Box(
        modifier = modifier.clipToBounds(),
        contentAlignment = alignment,
    ) {
        Image(
            painter = painter,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .requiredWidth(logoWidth)
                .requiredHeight(logoHeight)
                .graphicsLayer {
                    alpha = word.opacity
                    translationY = translationYPixels
                    scaleX = word.scale
                    scaleY = word.scale
                    transformOrigin = TransformOrigin.Center
                },
        )
    }
}

@Composable
private fun RebuildIntroShine(
    logoBitmap: ImageBitmap,
    progress: Float,
    modifier: Modifier = Modifier,
) {
    Canvas(
        modifier = modifier.graphicsLayer {
            compositingStrategy = CompositingStrategy.Offscreen
        },
    ) {
        val center = size.width * (-0.30f + (1.60f * progress))
        val halfWidth = size.width * 0.17f
        drawRect(
            brush = Brush.linearGradient(
                colors = listOf(
                    Color.Transparent,
                    Color.White.copy(alpha = .90f),
                    Color.Transparent,
                ),
                start = Offset(center - halfWidth, 0f),
                end = Offset(center + halfWidth, 0f),
            ),
        )
        drawImage(
            image = logoBitmap,
            srcOffset = IntOffset.Zero,
            srcSize = IntSize(logoBitmap.width, logoBitmap.height),
            dstOffset = IntOffset.Zero,
            dstSize = IntSize(
                size.width.roundToInt(),
                size.height.roundToInt(),
            ),
            blendMode = BlendMode.DstIn,
        )
    }
}
