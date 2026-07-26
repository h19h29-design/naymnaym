package com.h19h29.naymnaymlevelup.rebuild.child

import androidx.annotation.DrawableRes
import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.h19h29.naymnaymlevelup.R
import com.h19h29.naymnaymlevelup.rebuild.ui.RebuildTokens
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext

@Composable
fun ForestScene(
    reduceMotion: Boolean,
    isPaused: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    ForestScene(
        reduceMotion = reduceMotion,
        activity = ForestSceneActivity(
            isSheetPresented = isPaused,
            isTabActive = true,
            isAppActive = true,
        ),
        modifier = modifier,
        content = content,
    )
}

@Composable
fun ForestScene(
    reduceMotion: Boolean,
    activity: ForestSceneActivity,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    val resources = LocalContext.current.resources
    val systemReduceMotion =
        scope.coroutineContext[MotionDurationScale]?.scaleFactor == 0f
    val effectiveReduceMotion = reduceMotion || systemReduceMotion
    val clock = remember { ForestSceneMotionClock(System.nanoTime()) }
    val layerImages = remember(resources) {
        mutableStateMapOf<ForestSceneLayer, ImageBitmap>()
    }
    var elapsedMillis by remember { mutableLongStateOf(0L) }

    LaunchedEffect(resources) {
        ForestSceneLayer.entries.forEach { layer ->
            if (layerImages[layer] == null) {
                layerImages[layer] = withContext(Dispatchers.IO) {
                    ForestSceneAssets.decode(resources, layer)
                }
                withFrameNanos { }
            }
        }
    }

    LaunchedEffect(effectiveReduceMotion, activity) {
        val now = System.nanoTime()
        clock.update(activity, now)
        elapsedMillis = clock.elapsedMillis(now)
        if (
            ForestSceneMotionSpec.shouldScheduleFrameCallback(
                reduceMotion = effectiveReduceMotion,
                activity = activity,
            )
        ) {
            while (isActive) {
                withInfiniteAnimationFrameNanos { frameTimeNanos ->
                    elapsedMillis = clock.elapsedMillis(frameTimeNanos)
                }
            }
        }
    }

    val frame = ForestSceneMotionSpec.frameAt(
        elapsedMillis = elapsedMillis,
        reduceMotion = effectiveReduceMotion,
    )
    val density = LocalDensity.current

    Box(
        modifier = modifier
            .background(Color(RebuildTokens.Cream50))
            .clip(RectangleShape)
            .testTag("forest_scene"),
    ) {
        ForestSceneLayer.entries.forEach { layer ->
            layerImages[layer]?.let { bitmap ->
                val transform = frame[layer]
                Image(
                    bitmap = bitmap,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            translationX = with(density) { transform.x.dp.toPx() }
                            translationY = with(density) { transform.y.dp.toPx() }
                            if (layer == ForestSceneLayer.ForegroundLeaves) {
                                scaleX = 1.04f
                                scaleY = 1.04f
                            }
                        }
                        .zIndex(layer.zIndex)
                        .testTag("forest_layer_${layer.name}"),
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .zIndex(ForestSceneLayer.ContentZIndex),
            content = content,
        )
    }
}

internal class ForestSceneProcessCache<Value> {
    private val values = mutableMapOf<ForestSceneLayer, Value>()

    @Synchronized
    fun getOrLoad(
        layer: ForestSceneLayer,
        loader: () -> Value,
    ): Value = values.getOrPut(layer, loader)
}

private object ForestSceneAssets {
    private val cache = ForestSceneProcessCache<ImageBitmap>()

    fun decode(
        resources: Resources,
        layer: ForestSceneLayer,
    ): ImageBitmap = cache.getOrLoad(layer) {
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inScaled = false
        }
        requireNotNull(
            BitmapFactory.decodeResource(
                resources,
                layer.drawableResource(),
                options,
            ),
        ) {
            "Validated forest scene asset is missing: ${layer.name}"
        }.asImageBitmap()
    }
}

@DrawableRes
private fun ForestSceneLayer.drawableResource(): Int =
    when (this) {
        ForestSceneLayer.Sky -> R.drawable.forest_home_sky
        ForestSceneLayer.DistantTrees -> R.drawable.forest_home_distant_trees
        ForestSceneLayer.MidgroundTrees -> R.drawable.forest_home_midground_trees
        ForestSceneLayer.ForegroundLeaves -> R.drawable.forest_home_foreground_leaves
        ForestSceneLayer.Ground -> R.drawable.forest_home_ground
    }
