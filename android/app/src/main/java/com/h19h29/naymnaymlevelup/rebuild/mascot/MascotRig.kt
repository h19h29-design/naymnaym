package com.h19h29.naymnaymlevelup.rebuild.mascot

import android.content.res.Resources
import android.graphics.Bitmap
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
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
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
private const val MASCOT_THUMBNAIL_SIZE = 256
private const val MASCOT_REST_CACHE_BYTES = 2 * 1_024 * 1_024

@Composable
fun MascotRig(
    level: Int,
    state: MotionState,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    MascotRig(
        level = level,
        state = state,
        reduceMotion = reduceMotion,
        playbackRevision = 0,
        modifier = modifier,
    )
}

@Composable
fun MascotRig(
    level: Int,
    state: MotionState,
    reduceMotion: Boolean,
    playbackRevision: Long,
    modifier: Modifier = Modifier,
) {
    val controller = remember { MascotMotionController(MotionSpec.fixture) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val systemReduceMotion = scope.coroutineContext[MotionDurationScale]?.scaleFactor == 0f
    val effectiveReduceMotion = reduceMotion || systemReduceMotion
    var assets by remember(level) { mutableStateOf<MascotRigAssets?>(null) }
    val playback = remember(state, playbackRevision, effectiveReduceMotion) {
        controller.playback(
            state = state,
            eventRevision = playbackRevision,
            reduceMotion = effectiveReduceMotion,
        )
    }
    var elapsedMs by remember(playback.key) { mutableLongStateOf(0) }

    LaunchedEffect(level) {
        assets = withContext(Dispatchers.IO) {
            MascotRigAssetStore.load(context.resources, level)
        }
    }
    LaunchedEffect(playback.key) {
        elapsedMs = 0
        if (!playback.isActive) {
            return@LaunchedEffect
        }
        var startedAtNanos = 0L
        do {
            withFrameNanos { frameNanos ->
                if (startedAtNanos == 0L) startedAtNanos = frameNanos
                elapsedMs = ((frameNanos - startedAtNanos) / 1_000_000L)
                    .coerceAtMost(playback.durationMs)
            }
        } while (elapsedMs < playback.durationMs)
    }

    val pose = playback.poseAt(elapsedMs)
    val projection = MascotRenderProjection.from(state, pose)
    val animatedBlinkAlpha by animateFloatAsState(
        targetValue = if (projection.eyesClosed) 1f else 0f,
        animationSpec = tween(80),
        label = "mascot-blink-crossfade",
    )
    val blinkAlpha = if (effectiveReduceMotion) {
        playback.expressionBlendAt(elapsedMs)
    } else {
        animatedBlinkAlpha
    }
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

@Composable
fun MascotRestArt(
    level: Int,
    modifier: Modifier = Modifier,
    silhouetteColor: Color? = null,
) {
    val resources = LocalContext.current.resources
    var bitmap by remember(level) { mutableStateOf<ImageBitmap?>(null) }

    LaunchedEffect(level) {
        bitmap = withContext(Dispatchers.IO) {
            MascotRigAssetStore.loadRest(resources, level)
        }
    }

    bitmap?.let { loaded ->
        Image(
            bitmap = loaded,
            contentDescription = null,
            contentScale = ContentScale.Fit,
            colorFilter = silhouetteColor?.let(ColorFilter::tint),
            modifier = modifier,
        )
    }
}

internal sealed interface MascotRigAssets {
    data class Keyframes(
        val rest: ImageBitmap,
        val blink: ImageBitmap,
        val celebrate: ImageBitmap,
    ) : MascotRigAssets

    data class Fallback(val layers: List<Pair<MascotRigSemanticPart, ImageBitmap>>) : MascotRigAssets
}

internal data class MascotAssetDescriptor(
    val resourceId: Int,
    val sha256: String,
)

internal data class MascotRigLevelDefinition(
    val rest: MascotAssetDescriptor,
    val blink: MascotAssetDescriptor,
    val celebrate: MascotAssetDescriptor,
    val semanticParts: Map<MascotRigSemanticPart, MascotAssetDescriptor>,
)

internal object MascotRigAssetCatalog {
    val definitions: Map<Int, MascotRigLevelDefinition> = linkedMapOf(
        1 to definition(
            rest = MascotAssetDescriptor(R.drawable.mascot_l01_composite_rest, "ab0e53ee0d330490efa9dd4c3eaf3138ec6ef4d44a93079e928cf5a415fa9f60"),
            blink = MascotAssetDescriptor(R.drawable.mascot_l01_composite_blink, "8f751b950d36776865c026564cb3460eaab0b1fcde3efb71d27f62006f4b9c3e"),
            celebrate = MascotAssetDescriptor(R.drawable.mascot_l01_composite_celebrate, "d22f37412faed68e14eb5fe96a6798846ddc1c90940fa23108b4f53864dbcd95"),
            tailBack = MascotAssetDescriptor(R.drawable.mascot_l01_tail_back, "ca6ab285e97b48cffc3cbc9e150d339e4038de7342a8066ac912586a663ef430"),
            body = MascotAssetDescriptor(R.drawable.mascot_l01_body, "172d92553ad92f6f3f62ecd0ea32840797b41a16f252f47196bdb81ab71ece6e"),
            scarf = MascotAssetDescriptor(R.drawable.mascot_l01_scarf, "d6c797b034967d730149e1e080219f377ba1025350e8007ff7333bb0afbf6573"),
            head = MascotAssetDescriptor(R.drawable.mascot_l01_head, "7bf20a006e56ad2f293b6570866d94886afe4166c66b26245ceab6a3ea52acc9"),
            armLeft = MascotAssetDescriptor(R.drawable.mascot_l01_arm_left, "12d48cb3c2b2e8412e98c799b75c7aa2bbbdd4f767cc5315825740d55e216d4a"),
            armRight = MascotAssetDescriptor(R.drawable.mascot_l01_arm_right, "c66643c2c4e22cb6ad599b62b1c62df13cf5a80e6754cc27d961480c0c77470c"),
            eyesOpen = MascotAssetDescriptor(R.drawable.mascot_l01_eyes_open, "26128c66d978b4ce3a107eed82193d6f50805c0bcf23fceaf7bd01f785df59ac"),
            eyesClosed = MascotAssetDescriptor(R.drawable.mascot_l01_eyes_closed, "6a12e0427b844d67c126904e49b0bd65f0c01cbabba3ba57bc37b7892330c0bc"),
            mouthNeutral = MascotAssetDescriptor(R.drawable.mascot_l01_mouth_neutral, "0234f8509bb923252182165799703f86a32bc4f366c4002194df3dda1d2649df"),
            mouthSmile = MascotAssetDescriptor(R.drawable.mascot_l01_mouth_smile, "27e1a3e31935b9a737cbe0cf99f9e5dca6b0ebede13413cd2a39198b67cc9304"),
            sprout = MascotAssetDescriptor(R.drawable.mascot_l01_sprout, "ce444e770a05ebabf9db431c56c90985644be32eb6327b0c66403794b86100b6"),
        ),
        2 to definition(
            rest = MascotAssetDescriptor(R.drawable.mascot_l02_composite_rest, "e99fe61d9fe6aaf6a4b85d6390f96a47de74d0420cb181dae75bc890dea90878"),
            blink = MascotAssetDescriptor(R.drawable.mascot_l02_composite_blink, "7dd5b5d5a4f759669a27426b63f9c11c80dd86b7c1f37b63cef2ccff543cfb05"),
            celebrate = MascotAssetDescriptor(R.drawable.mascot_l02_composite_celebrate, "b15d29cb486e1000ab799af5f019cd4b8660b31b8330f640e7dd2673f308b502"),
            tailBack = MascotAssetDescriptor(R.drawable.mascot_l02_tail_back, "65f512f9b61ca037247d6052cd3d8b5ed3ce2563e76e5351acc3ef51f1f445f6"),
            body = MascotAssetDescriptor(R.drawable.mascot_l02_body, "ca5da65aaf7c48a2e52c51a0a1b56de7ea1f5c5db28979d6e47524d7874fb9af"),
            scarf = MascotAssetDescriptor(R.drawable.mascot_l02_scarf, "1fedc78c46ee9180771f16d9e7744a6d80bdce4cac330a3cee660c5a4a6e5e44"),
            head = MascotAssetDescriptor(R.drawable.mascot_l02_head, "28aeec40445187d5a3199f909090a95d68e19e0e3ca74ceef6f5b86120c32127"),
            armLeft = MascotAssetDescriptor(R.drawable.mascot_l02_arm_left, "fa0ae0de5718e29f321949c518c8a62f1b42d45662f2b88b800484a49c718576"),
            armRight = MascotAssetDescriptor(R.drawable.mascot_l02_arm_right, "cf3291c0e0bbc1196cdbfdd195773d97a588ce7a0bf8b7dfd5cd7abcf38fe879"),
            eyesOpen = MascotAssetDescriptor(R.drawable.mascot_l02_eyes_open, "baf4beaac11e26316005688abcff2500822a546ecc5514ebeb6c8171d801be94"),
            eyesClosed = MascotAssetDescriptor(R.drawable.mascot_l02_eyes_closed, "da830918750959e29820cd0baab9c1d528dd6b210fcccb4af445c21e4c357e94"),
            mouthNeutral = MascotAssetDescriptor(R.drawable.mascot_l02_mouth_neutral, "ebf01703e435e7c720a405cdcd84c9308eaf1a6d3089040e1f870552de6a791c"),
            mouthSmile = MascotAssetDescriptor(R.drawable.mascot_l02_mouth_smile, "b24dca5b6f1074881e7bde4215b3cccf6c2f9f9eaa2e60966b3cfbe77f390360"),
            sprout = MascotAssetDescriptor(R.drawable.mascot_l02_sprout, "4fed1cfaf44fb9ce5e58d7f885c8a4da7b71a620b39b5a532d69a798b009d71d"),
        ),
        3 to definition(
            rest = MascotAssetDescriptor(R.drawable.mascot_l03_composite_rest, "4206e8ad0fd2b4822805ac1cb9468f6779af6d25e36a00137e4289d399e65ae5"),
            blink = MascotAssetDescriptor(R.drawable.mascot_l03_composite_blink, "1f887a111aa37d2d9516e1473f3a0f31ec82b4246344d719e5b38157927da46c"),
            celebrate = MascotAssetDescriptor(R.drawable.mascot_l03_composite_celebrate, "228bdde37c3b6558f02fbc34c7c41c789691bc4df5e0c4f68c239f386e43f586"),
            tailBack = MascotAssetDescriptor(R.drawable.mascot_l03_tail_back, "a947d147d762b5a6e1f50057da134902716e807d11c4f22f6ffc0cde5f7cf1d1"),
            body = MascotAssetDescriptor(R.drawable.mascot_l03_body, "725fdd572f8b6f8580675902cb5c9416e0d409f2981fa5f183b72af6939cf0f0"),
            scarf = MascotAssetDescriptor(R.drawable.mascot_l03_scarf, "9a84c9d891b7d3ecb9388caeebcd440c3109f74cecefd20ee0eb0fa74b358aec"),
            head = MascotAssetDescriptor(R.drawable.mascot_l03_head, "a120468a8534af27cf610340dd87a05b57bbfa8e2b1c4fd4d82eed7590085ce6"),
            armLeft = MascotAssetDescriptor(R.drawable.mascot_l03_arm_left, "55c032d79e74ec67fcb40aeb9be92a2f79dd833eebfc7d94470043d030700b88"),
            armRight = MascotAssetDescriptor(R.drawable.mascot_l03_arm_right, "a75fb9592c5a24d5cc7edaaac7762c27c602c5e359449b101dce556b934e89b7"),
            eyesOpen = MascotAssetDescriptor(R.drawable.mascot_l03_eyes_open, "2963be9b10b5c84b372d6396c5cda7307588efeb1d62d7c624568b4011d24fe6"),
            eyesClosed = MascotAssetDescriptor(R.drawable.mascot_l03_eyes_closed, "1bbfc527b5fa39d4aa9e12d255c556f8da9b417751492077e715bd1d34d85298"),
            mouthNeutral = MascotAssetDescriptor(R.drawable.mascot_l03_mouth_neutral, "06d7cfb2024fb69a33af4d6db5b0436e1227e73cca162ad03dec36282ab03295"),
            mouthSmile = MascotAssetDescriptor(R.drawable.mascot_l03_mouth_smile, "e8e2939d90147f4076b45680e1860f9f9487da57f74b0aae163d76bd3cd9c6b1"),
            sprout = MascotAssetDescriptor(R.drawable.mascot_l03_sprout, "c4069cfbad90e2093dc4db97494ea12278f42db322bf12ae3cc1a2cd8a22f701"),
        ),
        4 to definition(
            rest = MascotAssetDescriptor(R.drawable.mascot_l04_composite_rest, "a24f6a94115ceabb67cf547b7d2934de7bc9244f0c97ffdbabf1b20d76010dd1"),
            blink = MascotAssetDescriptor(R.drawable.mascot_l04_composite_blink, "1b51c6a4b3c3ce50c342075b0ca70c83ba3e91f42eca02c5d44f80a3671cdebd"),
            celebrate = MascotAssetDescriptor(R.drawable.mascot_l04_composite_celebrate, "abc3f8c6b695a7dedbc68d2b31992fb449b88a2ea2616be4123059190aee516d"),
            tailBack = MascotAssetDescriptor(R.drawable.mascot_l04_tail_back, "ade2b07ec9045b32a6cd06ffd1c5267f0b168d217488b585220b7ffaa36cdea0"),
            body = MascotAssetDescriptor(R.drawable.mascot_l04_body, "18bbad6ab4c65ef65c84dfddd29d9c56d08818b4a293fbad395b04821636de58"),
            scarf = MascotAssetDescriptor(R.drawable.mascot_l04_scarf, "de38a816bf8dd9dee3f62d19542dce7805d306e7a88ba02536ad8c985aff1d80"),
            head = MascotAssetDescriptor(R.drawable.mascot_l04_head, "878c6c8e0a88593142c22c1e3c954e0897f9e6d663d45e9933362b6724dee6d3"),
            armLeft = MascotAssetDescriptor(R.drawable.mascot_l04_arm_left, "386d1cef17327c18abe6341ae15173e69cff57a9e5b92431cd17891524d34035"),
            armRight = MascotAssetDescriptor(R.drawable.mascot_l04_arm_right, "06001b100ad4850b4b894ac3d99b61c4f174d5459294a9f5dc9ef8f78c360449"),
            eyesOpen = MascotAssetDescriptor(R.drawable.mascot_l04_eyes_open, "478cf67960652d74659e24bd6dd3612c11a174c6ffd3bac684a2ed4343f7bd35"),
            eyesClosed = MascotAssetDescriptor(R.drawable.mascot_l04_eyes_closed, "d9b6895adc6e369d4a93f7742d3a1da9a2a4fdadbb10b9245d1528c96958920c"),
            mouthNeutral = MascotAssetDescriptor(R.drawable.mascot_l04_mouth_neutral, "d18d2d92eaded1a558e1dbbb072ed362d8b5258487bfe7d9183904e10ec7eb1b"),
            mouthSmile = MascotAssetDescriptor(R.drawable.mascot_l04_mouth_smile, "e2cb52dd52897a51afcac958c68a284f0da65d3a6b57a3cf1f1543a6285137c4"),
            sprout = MascotAssetDescriptor(R.drawable.mascot_l04_sprout, "117bd677ac490f517bde2d89c58e6381ff7cee44ea7a40f7e6939ef3de81724c"),
        ),
        5 to definition(
            rest = MascotAssetDescriptor(R.drawable.mascot_l05_composite_rest, "4d7518d077ef0c07b884337b2646972ab03b03353a463b394c5957510238b4d2"),
            blink = MascotAssetDescriptor(R.drawable.mascot_l05_composite_blink, "e78dadf2f4145ce181468e48cfc0146e08abf70c6e1f8d4fb2dae12393a8d387"),
            celebrate = MascotAssetDescriptor(R.drawable.mascot_l05_composite_celebrate, "483741d8b7beac6a76fe9b84be054f3de6ac1a5dd7f97aa55be0029b91ab998c"),
            tailBack = MascotAssetDescriptor(R.drawable.mascot_l05_tail_back, "d4a447541dc9bb4608301303baca79fa05900e413d64dd0673501e234a246262"),
            body = MascotAssetDescriptor(R.drawable.mascot_l05_body, "eb7eb5f850e609af972cc7d04b7ade6bba3eeaf960610b71ad620e790bddbf6b"),
            scarf = MascotAssetDescriptor(R.drawable.mascot_l05_scarf, "7fbf8cc0dad904c87e12f17681f70acd33d9584348b1a5de239a7137ff54dfff"),
            head = MascotAssetDescriptor(R.drawable.mascot_l05_head, "865ecd410a4a29d9018a14bca326ace9281e9ec3d3683212f8c6e596bfd57122"),
            armLeft = MascotAssetDescriptor(R.drawable.mascot_l05_arm_left, "71752e68b93632fb76f6b5703aacbec2453f653988b19ec9224db89c155db62d"),
            armRight = MascotAssetDescriptor(R.drawable.mascot_l05_arm_right, "3283a95c669bbcb1308ba15cc589abd65a0d645cc66a052d264c55661703fa18"),
            eyesOpen = MascotAssetDescriptor(R.drawable.mascot_l05_eyes_open, "e38f71c880cfbf5dc16dd94b3a0d6afbace288e5463f132be365d4a828a7df4e"),
            eyesClosed = MascotAssetDescriptor(R.drawable.mascot_l05_eyes_closed, "8581d7d7cba61bab9c144e6efd40bffabf8f4c5e210ae126ed3bd7e899211def"),
            mouthNeutral = MascotAssetDescriptor(R.drawable.mascot_l05_mouth_neutral, "6aa7f70c9260d99bf2d4ad4cecfab3b38c973178bbdb5b725652e209e5c7f284"),
            mouthSmile = MascotAssetDescriptor(R.drawable.mascot_l05_mouth_smile, "150953cc1260c60831c4a045478917f219012b70d651e5d12bacd0c20898f4a0"),
            sprout = MascotAssetDescriptor(R.drawable.mascot_l05_sprout, "43538889f5ca8f029bfb170468bc23a6f82105c257141eb4461a011bf9f9ed3f"),
        ),
        6 to definition(
            rest = MascotAssetDescriptor(R.drawable.mascot_l06_composite_rest, "5351093f343254da3c36f53e15030d81bba9655749df0c94754c028944efc188"),
            blink = MascotAssetDescriptor(R.drawable.mascot_l06_composite_blink, "a9f451057ffbcb951e5643628fb9a3c773c6e2113f53711e3c8f2fe0ccca56d5"),
            celebrate = MascotAssetDescriptor(R.drawable.mascot_l06_composite_celebrate, "2b6e14ed32d11b48097c7c732de81a586ca4d12b260e71c197a4b6c822e95322"),
            tailBack = MascotAssetDescriptor(R.drawable.mascot_l06_tail_back, "80639d87e274206e40230b82138ff12583c68dfe7e272ec4415f974a1ace0a71"),
            body = MascotAssetDescriptor(R.drawable.mascot_l06_body, "72687ec0c018df1230b49dffe114080e0b995617e7e3f4d3c8794276a6ad4439"),
            scarf = MascotAssetDescriptor(R.drawable.mascot_l06_scarf, "6173bd6b01a1e1bdc9c46af98242c6ee23a07381ccf406373b53a14a2f290cde"),
            head = MascotAssetDescriptor(R.drawable.mascot_l06_head, "3d22e35a6331ccbf9efb5548d78c1765c0395b1e2f6a39f6579015e22c8d0299"),
            armLeft = MascotAssetDescriptor(R.drawable.mascot_l06_arm_left, "8b159d9cefca889d774e6a24a0a1b3f45d7ceef387b3cf323e14d6d05cd90085"),
            armRight = MascotAssetDescriptor(R.drawable.mascot_l06_arm_right, "98f63e856f463f5065d82ce0ce79c71258634ad3ca4843330f72e20d0559ec4b"),
            eyesOpen = MascotAssetDescriptor(R.drawable.mascot_l06_eyes_open, "4691ff24ad39babb51920a6691535e3a8e69543dd24baa6f294d38524131ad6a"),
            eyesClosed = MascotAssetDescriptor(R.drawable.mascot_l06_eyes_closed, "84c659cfd9cb81deeb593d194e0134002bf41a4aa009b6235ceb0ba9137f79f4"),
            mouthNeutral = MascotAssetDescriptor(R.drawable.mascot_l06_mouth_neutral, "8db30ee467e8b10978f5219fb412cd1495c75cc8de2db40363ce2473744524b2"),
            mouthSmile = MascotAssetDescriptor(R.drawable.mascot_l06_mouth_smile, "9b303b7db481d602e5f65c15b9788e323d38507b5fa147db29f943766705472a"),
            sprout = MascotAssetDescriptor(R.drawable.mascot_l06_sprout, "e0f92f1dbacdd2fedeb507718f91b4adf2cb18e828448b7c5a92d6a70c27bc3e"),
        ),
        7 to definition(
            rest = MascotAssetDescriptor(R.drawable.mascot_l07_composite_rest, "bd68b019f9a9bf3a1d149bdd1735ac7d0dc063aad6eefa3a9d0311c5f7b09ccb"),
            blink = MascotAssetDescriptor(R.drawable.mascot_l07_composite_blink, "f33d5dd292fca15a61a8108d58ac86c6b843995b5c44c7ec59cafc742c193f8d"),
            celebrate = MascotAssetDescriptor(R.drawable.mascot_l07_composite_celebrate, "c8bb0c3e254ff5cdc5a77ca56d84ca6465f7600378692f02c1a6df43422ffa45"),
            tailBack = MascotAssetDescriptor(R.drawable.mascot_l07_tail_back, "ffc908c582b6cdaf2c974012ffb29a33a695b2c13b3debf573e0db74239ae5ff"),
            body = MascotAssetDescriptor(R.drawable.mascot_l07_body, "f7e0bd19db763389d7890e8ce3dc0fa53d948d4bcfc02adc053b6ae1e8841dc2"),
            scarf = MascotAssetDescriptor(R.drawable.mascot_l07_scarf, "1dc3672000fe13177d94a41b89e5c1dac6457e309ca710d7e54201a34bc1cf25"),
            head = MascotAssetDescriptor(R.drawable.mascot_l07_head, "fcc62ec0d05be6f33e6730a30614070be4d6d71ec220563b3867f9e9706602b6"),
            armLeft = MascotAssetDescriptor(R.drawable.mascot_l07_arm_left, "57386f6eb602a916e185f4d355ed72ee326c0aadaa7a3a5e6316124cf06f31fb"),
            armRight = MascotAssetDescriptor(R.drawable.mascot_l07_arm_right, "2d7dfff1dde9310ce239c803bcdf1c65666ad43a4fe66738f0dce630c65b6ce3"),
            eyesOpen = MascotAssetDescriptor(R.drawable.mascot_l07_eyes_open, "e457727a3af48735faaa34f19d9f771c687502efe6d7473c425f2a71897b97ed"),
            eyesClosed = MascotAssetDescriptor(R.drawable.mascot_l07_eyes_closed, "bfa65b302aba6653a03439c42f46f1bfd7a97b201d8437fc49a3318d6b68be43"),
            mouthNeutral = MascotAssetDescriptor(R.drawable.mascot_l07_mouth_neutral, "86c23a570163cc0f0c88326fc7487813687873d93022606931571047230db57f"),
            mouthSmile = MascotAssetDescriptor(R.drawable.mascot_l07_mouth_smile, "e05f2beb992dcf67602d977ffc4505fe08c485657a3d2893580857bf9b93af9e"),
            sprout = MascotAssetDescriptor(R.drawable.mascot_l07_sprout, "49b49b093d3b3580b4396cc9a37555db94000d93c3e06e802cf5ec731a107472"),
        ),
    )

    private fun definition(
        rest: MascotAssetDescriptor,
        blink: MascotAssetDescriptor,
        celebrate: MascotAssetDescriptor,
        tailBack: MascotAssetDescriptor,
        body: MascotAssetDescriptor,
        scarf: MascotAssetDescriptor,
        head: MascotAssetDescriptor,
        armLeft: MascotAssetDescriptor,
        armRight: MascotAssetDescriptor,
        eyesOpen: MascotAssetDescriptor,
        eyesClosed: MascotAssetDescriptor,
        mouthNeutral: MascotAssetDescriptor,
        mouthSmile: MascotAssetDescriptor,
        sprout: MascotAssetDescriptor,
    ) = MascotRigLevelDefinition(
        rest = rest,
        blink = blink,
        celebrate = celebrate,
        semanticParts = linkedMapOf(
            MascotRigSemanticPart.TailBack to tailBack,
            MascotRigSemanticPart.Body to body,
            MascotRigSemanticPart.Scarf to scarf,
            MascotRigSemanticPart.Head to head,
            MascotRigSemanticPart.ArmLeft to armLeft,
            MascotRigSemanticPart.ArmRight to armRight,
            MascotRigSemanticPart.EyesOpen to eyesOpen,
            MascotRigSemanticPart.EyesClosed to eyesClosed,
            MascotRigSemanticPart.MouthNeutral to mouthNeutral,
            MascotRigSemanticPart.MouthSmile to mouthSmile,
            MascotRigSemanticPart.Sprout to sprout,
        ),
    )
}

internal class BoundedMascotCache<Key, Value>(
    private val maxEntries: Int,
    private val maxCost: Int,
    private val costOf: (Value) -> Int,
) {
    private data class Entry<Value>(
        val value: Value,
        val cost: Int,
    )

    private val entries = LinkedHashMap<Key, Entry<Value>>(
        16,
        0.75f,
        true,
    )
    private var currentCost = 0

    val totalCost: Int
        @Synchronized get() = currentCost

    @Synchronized
    operator fun get(key: Key): Value? = entries[key]?.value

    @Synchronized
    fun put(key: Key, value: Value) {
        entries.remove(key)?.let { currentCost -= it.cost }
        val cost = costOf(value).coerceAtLeast(0)
        if (maxEntries <= 0 || maxCost <= 0 || cost > maxCost) return

        entries[key] = Entry(value, cost)
        currentCost += cost
        while (
            entries.size > maxEntries ||
            currentCost > maxCost
        ) {
            val eldest = entries.entries.first()
            entries.remove(eldest.key)
            currentCost -= eldest.value.cost
        }
    }

    @Synchronized
    fun keysInLruOrder(): List<Key> = entries.keys.toList()
}

internal object MascotRigAssetStore {
    private val cache = BoundedMascotCache<Int, MascotRigAssets>(
        maxEntries = 1,
        maxCost = Int.MAX_VALUE,
        costOf = ::assetCost,
    )
    private val restCache = BoundedMascotCache<Int, ImageBitmap>(
        maxEntries = MascotRigAssetCatalog.definitions.size,
        maxCost = MASCOT_REST_CACHE_BYTES,
        costOf = ::imageCost,
    )

    @Synchronized
    fun load(resources: Resources, level: Int): MascotRigAssets {
        cache[level]?.let { return it }
        val definition = MascotRigAssetCatalog.definitions[level]
            ?: error("Unsupported mascot level: $level")
        val loaded = runCatching {
            MascotRigAssets.Keyframes(
                rest = resources.decodeVerified(definition.rest),
                blink = resources.decodeVerified(definition.blink),
                celebrate = resources.decodeVerified(definition.celebrate),
            )
        }.getOrElse {
            MascotRigAssets.Fallback(
                definition.semanticParts.map { (part, descriptor) ->
                    part to resources.decodeVerified(descriptor)
                },
            )
        }
        cache.put(level, loaded)
        return loaded
    }

    @Synchronized
    fun loadRest(resources: Resources, level: Int): ImageBitmap {
        restCache[level]?.let { return it }
        val definition = MascotRigAssetCatalog.definitions[level]
            ?: error("Unsupported mascot level: $level")
        val loaded = resources.decodeVerified(
            descriptor = definition.rest,
            thumbnailMaxPixelSize = MASCOT_THUMBNAIL_SIZE,
        )
        restCache.put(level, loaded)
        return loaded
    }

    private fun Resources.decodeVerified(
        descriptor: MascotAssetDescriptor,
        thumbnailMaxPixelSize: Int? = null,
    ): ImageBitmap {
        val bytes = openRawResource(descriptor.resourceId).use { it.readBytes() }
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        check(digest == descriptor.sha256) { "Mascot checksum mismatch: ${descriptor.resourceId}" }

        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        check(
            bounds.outWidth == MASCOT_CANVAS_SIZE.toInt() &&
                bounds.outHeight == MASCOT_CANVAS_SIZE.toInt(),
        ) {
            "Mascot dimensions are invalid: ${descriptor.resourceId}"
        }

        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = thumbnailMaxPixelSize?.let {
                sampleSize(
                    width = bounds.outWidth,
                    height = bounds.outHeight,
                    maxPixelSize = it,
                )
            } ?: 1
        }
        val decoded = requireNotNull(
            BitmapFactory.decodeByteArray(
                bytes,
                0,
                bytes.size,
                options,
            ),
        ) {
            "Mascot decode failed: ${descriptor.resourceId}"
        }
        val bitmap = thumbnailMaxPixelSize?.let {
            downsample(decoded, it)
        } ?: decoded
        return bitmap.asImageBitmap()
    }

    private fun sampleSize(
        width: Int,
        height: Int,
        maxPixelSize: Int,
    ): Int {
        var sample = 1
        while (
            width / (sample * 2) >= maxPixelSize &&
            height / (sample * 2) >= maxPixelSize
        ) {
            sample *= 2
        }
        return sample
    }

    private fun downsample(bitmap: Bitmap, maxPixelSize: Int): Bitmap {
        val largestSide = maxOf(bitmap.width, bitmap.height)
        if (largestSide <= maxPixelSize) return bitmap
        val scale = maxPixelSize.toFloat() / largestSide
        val scaled = Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * scale).toInt().coerceAtLeast(1),
            (bitmap.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (scaled !== bitmap) bitmap.recycle()
        return scaled
    }

    private fun assetCost(assets: MascotRigAssets): Int =
        when (assets) {
            is MascotRigAssets.Keyframes ->
                imageCost(assets.rest) +
                    imageCost(assets.blink) +
                    imageCost(assets.celebrate)
            is MascotRigAssets.Fallback ->
                assets.layers.sumOf { (_, image) -> imageCost(image) }
        }

    private fun imageCost(image: ImageBitmap): Int =
        image.width * image.height * 4
}
