package com.h19h29.naymnaymlevelup.rebuild.mascot

import android.content.res.Resources
import android.graphics.BitmapFactory
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.h19h29.naymnaymlevelup.R
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val MASCOT_CANVAS_SIZE = 1_254f

@Composable
fun MascotRig(
    level: Int,
    state: MotionState,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val controller = remember { MascotMotionController(MotionSpec.fixture) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val systemReduceMotion = scope.coroutineContext[MotionDurationScale]?.scaleFactor == 0f
    val effectiveReduceMotion = reduceMotion || systemReduceMotion
    var assets by remember(level) { mutableStateOf<MascotRigAssets?>(null) }
    var progress by remember(state, effectiveReduceMotion) { mutableFloatStateOf(0f) }

    LaunchedEffect(level) {
        assets = withContext(Dispatchers.IO) {
            MascotRigAssetStore.load(context.resources, level)
        }
    }
    LaunchedEffect(state, effectiveReduceMotion) {
        if (!controller.isPlaybackActive(state, effectiveReduceMotion)) {
            progress = if (effectiveReduceMotion) 0.5f else 0f
            return@LaunchedEffect
        }
        var startedAtNanos = 0L
        do {
            withFrameNanos { frameNanos ->
                if (startedAtNanos == 0L) startedAtNanos = frameNanos
                progress = controller.progress(state, (frameNanos - startedAtNanos) / 1_000_000L)
            }
        } while (progress < 1f)
    }

    val pose = controller.pose(state, progress, effectiveReduceMotion)
    val projection = MascotRenderProjection.from(state, pose)
    val blinkAlpha by animateFloatAsState(
        targetValue = if (projection.eyesClosed) 1f else 0f,
        animationSpec = tween(if (effectiveReduceMotion) 125 else 80),
        label = "mascot-blink-crossfade",
    )
    val celebrateAlpha by animateFloatAsState(
        targetValue = projection.celebrationBlend,
        animationSpec = tween(if (effectiveReduceMotion) 0 else 80),
        label = "mascot-celebrate-crossfade",
    )

    BoxWithConstraints(
        modifier = modifier
            .aspectRatio(1f)
            .semantics { contentDescription = "레벨 $level 냠냠 다람쥐" },
    ) {
        val translationYPx = constraints.maxHeight * projection.bodyOffsetY / MASCOT_CANVAS_SIZE
        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = projection.bodyScaleX
                    scaleY = projection.bodyScaleY
                    rotationZ = projection.wholeCharacterRotationDegrees
                    translationY = translationYPx
                    transformOrigin = TransformOrigin(0.5f, 0.62f)
                },
        ) {
            when (val loadedAssets = assets) {
                is MascotRigAssets.Keyframes -> ApprovedKeyframes(
                    assets = loadedAssets,
                    blinkAlpha = blinkAlpha,
                    celebrateAlpha = celebrateAlpha,
                )
                is MascotRigAssets.Fallback -> SemanticFallback(
                    assets = loadedAssets,
                    eyesClosed = projection.eyesClosed,
                    smiling = projection.smiling,
                )
                null -> Unit
            }
        }
    }
}

@Composable
private fun ApprovedKeyframes(
    assets: MascotRigAssets.Keyframes,
    blinkAlpha: Float,
    celebrateAlpha: Float,
) {
    Box(Modifier.fillMaxSize().testTag("mascot_rig_approved_keyframes")) {
        RigImage(assets.rest, Modifier.fillMaxSize().graphicsLayer { alpha = (1f - celebrateAlpha) * (1f - blinkAlpha) })
        RigImage(assets.blink, Modifier.fillMaxSize().graphicsLayer { alpha = (1f - celebrateAlpha) * blinkAlpha })
        RigImage(assets.celebrate, Modifier.fillMaxSize().graphicsLayer { alpha = celebrateAlpha })
    }
}

@Composable
private fun SemanticFallback(
    assets: MascotRigAssets.Fallback,
    eyesClosed: Boolean,
    smiling: Boolean,
) {
    assets.layers.forEach { (part, bitmap) ->
        val visible = when (part) {
            MascotRigSemanticPart.EyesOpen -> !eyesClosed
            MascotRigSemanticPart.EyesClosed -> eyesClosed
            MascotRigSemanticPart.MouthNeutral -> !smiling
            MascotRigSemanticPart.MouthSmile -> smiling
            else -> true
        }
        if (visible) RigImage(bitmap, Modifier.fillMaxSize())
    }
}

@Composable
private fun RigImage(bitmap: ImageBitmap, modifier: Modifier) {
    Image(
        bitmap = bitmap,
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = modifier,
    )
}

private sealed interface MascotRigAssets {
    data class Keyframes(
        val rest: ImageBitmap,
        val blink: ImageBitmap,
        val celebrate: ImageBitmap,
    ) : MascotRigAssets

    data class Fallback(val layers: List<Pair<MascotRigSemanticPart, ImageBitmap>>) : MascotRigAssets
}

private object MascotRigAssetStore {
    private data class Descriptor(val resourceId: Int, val sha256: String)

    private val keyframes = mapOf(
        1 to listOf(
            Descriptor(R.drawable.mascot_l01_composite_rest, "ab0e53ee0d330490efa9dd4c3eaf3138ec6ef4d44a93079e928cf5a415fa9f60"),
            Descriptor(R.drawable.mascot_l01_composite_blink, "8f751b950d36776865c026564cb3460eaab0b1fcde3efb71d27f62006f4b9c3e"),
            Descriptor(R.drawable.mascot_l01_composite_celebrate, "d22f37412faed68e14eb5fe96a6798846ddc1c90940fa23108b4f53864dbcd95"),
        ),
    )
    private val semanticParts = listOf(
        MascotRigSemanticPart.TailBack to Descriptor(R.drawable.mascot_l01_tail_back, "ca6ab285e97b48cffc3cbc9e150d339e4038de7342a8066ac912586a663ef430"),
        MascotRigSemanticPart.Body to Descriptor(R.drawable.mascot_l01_body, "172d92553ad92f6f3f62ecd0ea32840797b41a16f252f47196bdb81ab71ece6e"),
        MascotRigSemanticPart.Scarf to Descriptor(R.drawable.mascot_l01_scarf, "d6c797b034967d730149e1e080219f377ba1025350e8007ff7333bb0afbf6573"),
        MascotRigSemanticPart.Head to Descriptor(R.drawable.mascot_l01_head, "7bf20a006e56ad2f293b6570866d94886afe4166c66b26245ceab6a3ea52acc9"),
        MascotRigSemanticPart.ArmLeft to Descriptor(R.drawable.mascot_l01_arm_left, "12d48cb3c2b2e8412e98c799b75c7aa2bbbdd4f767cc5315825740d55e216d4a"),
        MascotRigSemanticPart.ArmRight to Descriptor(R.drawable.mascot_l01_arm_right, "c66643c2c4e22cb6ad599b62b1c62df13cf5a80e6754cc27d961480c0c77470c"),
        MascotRigSemanticPart.EyesOpen to Descriptor(R.drawable.mascot_l01_eyes_open, "26128c66d978b4ce3a107eed82193d6f50805c0bcf23fceaf7bd01f785df59ac"),
        MascotRigSemanticPart.EyesClosed to Descriptor(R.drawable.mascot_l01_eyes_closed, "6a12e0427b844d67c126904e49b0bd65f0c01cbabba3ba57bc37b7892330c0bc"),
        MascotRigSemanticPart.MouthNeutral to Descriptor(R.drawable.mascot_l01_mouth_neutral, "0234f8509bb923252182165799703f86a32bc4f366c4002194df3dda1d2649df"),
        MascotRigSemanticPart.MouthSmile to Descriptor(R.drawable.mascot_l01_mouth_smile, "27e1a3e31935b9a737cbe0cf99f9e5dca6b0ebede13413cd2a39198b67cc9304"),
        MascotRigSemanticPart.Sprout to Descriptor(R.drawable.mascot_l01_sprout, "ce444e770a05ebabf9db431c56c90985644be32eb6327b0c66403794b86100b6"),
    )
    private val cache = mutableMapOf<Int, MascotRigAssets>()

    @Synchronized
    fun load(resources: Resources, level: Int): MascotRigAssets = cache.getOrPut(level) {
        val approved = keyframes[level] ?: error("Unsupported mascot level: $level")
        runCatching {
            val (rest, blink, celebrate) = approved.map { resources.decodeVerified(it) }
            MascotRigAssets.Keyframes(rest, blink, celebrate)
        }.getOrElse {
            MascotRigAssets.Fallback(semanticParts.map { (part, descriptor) -> part to resources.decodeVerified(descriptor) })
        }
    }

    private fun Resources.decodeVerified(descriptor: Descriptor): ImageBitmap {
        val bytes = openRawResource(descriptor.resourceId).use { it.readBytes() }
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        check(digest == descriptor.sha256) { "Mascot checksum mismatch: ${descriptor.resourceId}" }
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size)) { "Mascot decode failed: ${descriptor.resourceId}" }
        check(bitmap.width == MASCOT_CANVAS_SIZE.toInt() && bitmap.height == MASCOT_CANVAS_SIZE.toInt()) { "Mascot dimensions are invalid: ${descriptor.resourceId}" }
        return bitmap.asImageBitmap()
    }
}
