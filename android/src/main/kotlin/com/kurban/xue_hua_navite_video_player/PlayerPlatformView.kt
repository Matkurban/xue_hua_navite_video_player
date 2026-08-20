package com.kurban.xue_hua_navite_video_player

import android.content.Context
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Shared view type used by Dart PlatformView / [UiKitView]. */
const val PLAYER_PLATFORM_VIEW_TYPE = "plugins.xuehua/navite_video_player"

/**
 * Hosts Media3 [PlayerView] so resizeMode uses the official AspectRatioFrameLayout
 * property (fit / zoom / fill) instead of Flutter BoxFit.
 *
 * Inflated with `surface_type=texture_view` so Flutter chrome can overlay the
 * video; SurfaceView punches through the Flutter layer.
 */
class PlayerPlatformView(
    context: Context,
    private val plugin: XueHuaNaviteVideoPlayerPlugin,
) : PlatformView {
    private val playerView: PlayerView =
        (LayoutInflater.from(context).inflate(R.layout.xue_hua_player_view, null, false)
            as PlayerView).apply {
            useController = false
            setBackgroundColor(Color.BLACK)
            setShutterBackgroundColor(Color.BLACK)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        }

    init {
        plugin.attachPlayerView(playerView)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        plugin.detachPlayerView(playerView)
        playerView.player = null
    }
}

class PlayerPlatformViewFactory(
    private val plugin: XueHuaNaviteVideoPlayerPlugin,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return PlayerPlatformView(context, plugin)
    }
}
