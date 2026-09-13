package com.h19h29.naymnaymlevelup.rebuild.mascot

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.drawable.AnimatedImageDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.View
import android.widget.ImageView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class CompanionClip(val file: String) {
    Greeting("greeting"), Eating("eating"), Growth("growth"),
    IdleBreathing("idleBreathing"), Listening("listening"), Thinking("thinking"), Encouraging("encouraging");
    companion object {
        fun supports(level: Int) = level == 1
        fun forMotion(state: MotionState): CompanionClip? = when (state) {
            MotionState.Idle, MotionState.TapReaction -> Greeting
            MotionState.MealSuccess -> Eating
            MotionState.LevelUp -> Growth
            MotionState.Comfort, MotionState.ReducedMotion -> null
        }
    }
}

@Composable
internal fun CompanionAnimation(
    clip: CompanionClip,
    reduced: Boolean,
    revision: Long,
    modifier: Modifier,
) {
    AndroidView(
        factory = { CompanionImageView(it) },
        modifier = modifier,
        update = { it.play(clip, reduced, revision) },
        onRelease = { it.release() },
    )
}

// Android 9+ decodes transparent animated WebP natively; older devices keep
// the matching still, without adding a WebView or changing file-access policy.
class CompanionImageView(context: Context) : ImageView(context) {
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var load: Job? = null
    private var request: Triple<CompanionClip, Boolean, Long>? = null
    private var reduced = false

    init {
        scaleType = ScaleType.FIT_CENTER
        contentDescription = "냠냠 다람쥐"
        setOnClickListener {
            request?.let { play(it.first, it.second, it.third + 1) }
        }
    }

    fun play(clip: CompanionClip, reduceMotion: Boolean, revision: Long) {
        val next = Triple(clip, reduceMotion, revision)
        if (request == next) return
        request = next
        reduced = reduceMotion
        stopAnimation()
        load?.cancel()
        load = scope.launch {
            val loaded = withContext(Dispatchers.IO) {
                val drawable: Drawable? = try {
                    if (Build.VERSION.SDK_INT >= 28 && !reduceMotion) {
                        ImageDecoder.decodeDrawable(ImageDecoder.createSource(context.assets, "companion/${clip.file}.webp"))
                    } else {
                        context.assets.open("companion/${clip.file}-rest.png").use {
                            BitmapFactory.decodeStream(it)?.let { bitmap -> BitmapDrawable(resources, bitmap) }
                        }
                    }
                } catch (_: Exception) {
                    try {
                        context.assets.open("companion/${clip.file}-rest.png").use {
                            BitmapFactory.decodeStream(it)?.let { bitmap -> BitmapDrawable(resources, bitmap) }
                        }
                    } catch (_: Exception) { null }
                }
                ensureActive()
                drawable
            }
            if (loaded != null) {
                setImageDrawable(loaded)
                startAnimation()
            }
        }
    }

    private fun startAnimation() {
        if (Build.VERSION.SDK_INT >= 28 && !reduced && isShown && isAttachedToWindow) {
            (drawable as? AnimatedImageDrawable)?.apply {
                repeatCount = if (request?.first == CompanionClip.IdleBreathing) AnimatedImageDrawable.REPEAT_INFINITE else 0
                start()
            }
        }
    }

    private fun stopAnimation() {
        if (Build.VERSION.SDK_INT >= 28) (drawable as? AnimatedImageDrawable)?.stop()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility == View.VISIBLE) startAnimation() else stopAnimation()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        val previous = request
        scope.cancel()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        request = null
        previous?.let { play(it.first, it.second, it.third) }
    }

    override fun onDetachedFromWindow() {
        release()
        super.onDetachedFromWindow()
    }

    fun release() {
        stopAnimation()
        load?.cancel()
        scope.cancel()
    }
}
