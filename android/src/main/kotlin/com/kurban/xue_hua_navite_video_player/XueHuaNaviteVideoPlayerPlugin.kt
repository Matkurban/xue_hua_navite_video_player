package com.kurban.xue_hua_navite_video_player

import android.app.Activity
import android.graphics.Bitmap
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.TextureView
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import androidx.core.net.toUri
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.media3.cast.CastPlayer
import androidx.media3.cast.SessionAvailabilityListener
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.DefaultMediaCodecAdapterFactory
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs

private const val TAG = "XueHuaNaviteVideoPlayer"

/// 插件主类：ExoPlayer + CastPlayer（Google Cast）+ PlatformView（PlayerView.resizeMode）。
@UnstableApi
class XueHuaNaviteVideoPlayerPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    DefaultLifecycleObserver {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var exoPlayer: ExoPlayer? = null
    private var castPlayer: CastPlayer? = null
    private var castContext: CastContext? = null
    private var activePlayer: Player? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var workerExecutor = Executors.newCachedThreadPool()
    private val engineGeneration = AtomicInteger(0)
    private var currentUrl: String? = null
    private var currentCastUrl: String? = null
    private var lastCastState: String = "unavailable"
    private var lastCastDeviceName: String? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var playerView: PlayerView? = null
    private var resizeMode: Int = AspectRatioFrameLayout.RESIZE_MODE_FIT
    private var activity: Activity? = null
    private var lifecycleOwner: LifecycleOwner? = null
    private var savedBrightness: Float? = null

    private var lastReportedDuration: Long = -1L

    private var isPollingPosition = false


    fun attachPlayerView(view: PlayerView) {
        playerView = view
        view.resizeMode = resizeMode
        view.player = exoPlayer
    }

    fun detachPlayerView(view: PlayerView) {
        if (playerView === view) {
            playerView = null
        }
    }


    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        if (workerExecutor.isShutdown || workerExecutor.isTerminated) {
            workerExecutor = Executors.newCachedThreadPool()
        }

        methodChannel = MethodChannel(binding.binaryMessenger, "xue_hua_navite_video_player/player")
        methodChannel.setMethodCallHandler(this)

        eventChannel =
            EventChannel(binding.binaryMessenger, "xue_hua_navite_video_player/player/events")
        eventChannel.setStreamHandler(this)

        binding.platformViewRegistry.registerViewFactory(
            PLAYER_PLATFORM_VIEW_TYPE,
            PlayerPlatformViewFactory(this),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engineGeneration.incrementAndGet()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        restoreBrightness()
        releasePlayer()
        flutterPluginBinding = null
        workerExecutor.shutdownNow()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        bindActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unbindActivity(restoreWindowBrightness = false)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        bindActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        unbindActivity(restoreWindowBrightness = true)
    }

    override fun onStop(owner: LifecycleOwner) {
        // When actively casting to a remote receiver, keep remote playback running
        // even if the phone screen turns off or the app enters the background.
        if (activePlayer === castPlayer && castPlayer != null) {
            return
        }
        stopPositionPolling()
        val player = exoPlayer ?: return
        if (player.isPlaying) {
            player.pause()
        }
    }

    private fun bindActivity(act: Activity) {
        activity = act
        val owner = act as? LifecycleOwner
        lifecycleOwner = owner
        owner?.lifecycle?.addObserver(this)
    }

    private fun unbindActivity(restoreWindowBrightness: Boolean) {
        lifecycleOwner?.lifecycle?.removeObserver(this)
        lifecycleOwner = null
        if (restoreWindowBrightness) {
            restoreBrightness()
        }
        activity = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        sendCastState(lastCastState, lastCastDeviceName)
        activePlayer?.let { player ->
            val dur = player.duration
            if (dur != C.TIME_UNSET && dur > 0L) {
                lastReportedDuration = dur
                sendEvent("duration", dur)
            }
            sendEvent("position", player.currentPosition)
            sendEvent("playing", player.isPlaying)
            sendEvent("buffering", player.playbackState == Player.STATE_BUFFERING)
        }
    }


    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "create" -> handleCreate(result)
            "open" -> handleOpen(call, result)
            "play" -> handlePlay(result)
            "pause" -> handlePause(result)
            "seek" -> handleSeek(call, result)
            "setVolume" -> handleSetVolume(call, result)
            "setSpeed" -> handleSetSpeed(call, result)
            "setAspectRatioMode" -> handleSetAspectRatioMode(call, result)
            "setVideoViewSize" -> result.success(null)
            "showCastPicker" -> handleShowCastPicker(result)
            "stopCasting" -> handleStopCasting(result)
            "dispose" -> handleDispose(result)
            "takeSnapshot" -> handleTakeSnapshot(result)
            "extractCovers" -> handleExtractCovers(call, result)
            "getDuration" -> handleGetDuration(call, result)
            "getBrightness" -> handleGetBrightness(result)
            "setBrightness" -> handleSetBrightness(call, result)
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            else -> result.notImplemented()
        }
    }

    private fun requirePlayer(result: Result): Player? {
        val player = activePlayer ?: exoPlayer
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return null
        }
        return player
    }

    private fun handleCreate(result: Result) {
        val binding = flutterPluginBinding ?: run {
            result.error("NO_ENGINE", "Flutter engine not attached", null)
            return
        }

        releasePlayer()

        val context = binding.applicationContext
        val defaultAdapterFactory = DefaultMediaCodecAdapterFactory(context)

        // 1. 动态对齐奇数分辨率
        val renderersFactory = object : DefaultRenderersFactory(context) {
            override fun getCodecAdapterFactory(): MediaCodecAdapter.Factory {
                return MediaCodecAdapter.Factory { configuration ->
                    val mediaFormat = configuration.mediaFormat

                    fun makeEven(key: String) {
                        if (mediaFormat.containsKey(key)) {
                            val value = mediaFormat.getInteger(key)
                            if (value % 2 != 0) {
                                mediaFormat.setInteger(key, value + 1)
                            }
                        }
                    }

                    makeEven(MediaFormat.KEY_WIDTH)
                    makeEven(MediaFormat.KEY_MAX_WIDTH)
                    makeEven(MediaFormat.KEY_HEIGHT)
                    makeEven(MediaFormat.KEY_MAX_HEIGHT)

                    defaultAdapterFactory.createAdapter(configuration)
                }
            }
        }.apply {
            setEnableDecoderFallback(true)
        }

        // 2. 配置 HttpDataSource，添加标准浏览器 User-Agent，允许跨协议 302 重定向
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)

        val dataSourceFactory = DefaultDataSource.Factory(context, httpDataSourceFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        // 3. 构建 ExoPlayer
        val player = ExoPlayer.Builder(context)
            .setRenderersFactory(renderersFactory)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()

        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            /* handleAudioFocus= */ true,
        )
        player.addListener(exoPlayerListener)
        exoPlayer = player
        activePlayer = player
        playerView?.player = player
        playerView?.resizeMode = resizeMode

        // 4. 初始化 Google Cast (Media3 CastPlayer)，无 GMS 环境安全降级
        initCastSupport(context)

        result.success(0)
    }

    private fun initCastSupport(context: android.content.Context) {
        val generation = engineGeneration.get()
        try {
            val task = CastContext.getSharedInstance(context, workerExecutor)
            task.addOnSuccessListener { ctx ->
                mainHandler.post {
                    if (generation != engineGeneration.get() || exoPlayer == null) return@post
                    try {
                        castContext = ctx
                        ctx.sessionManager.addSessionManagerListener(
                            castSessionManagerListener,
                            CastSession::class.java,
                        )
                        val cp = CastPlayer(ctx)
                        cp.addListener(castPlayerListener)
                        cp.setSessionAvailabilityListener(castSessionAvailabilityListener)
                        castPlayer = cp
                        if (cp.isCastSessionAvailable) {
                            activePlayer = cp
                            sendCastState("connected", currentCastDeviceName())
                        } else {
                            sendCastState("notConnected", null)
                        }
                    } catch (_: Throwable) {
                        sendCastState("unavailable", null)
                    }
                }
            }.addOnFailureListener {
                mainHandler.post {
                    if (generation != engineGeneration.get()) return@post
                    sendCastState("unavailable", null)
                }
            }
        } catch (_: Throwable) {
            sendCastState("unavailable", null)
        }
    }

    private fun currentCastDeviceName(): String? {
        return try {
            castContext?.sessionManager?.currentCastSession?.castDevice?.friendlyName
        } catch (_: Throwable) {
            null
        }
    }

    private val castSessionManagerListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {
            sendCastState("connecting", session.castDevice?.friendlyName)
        }

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            sendCastState("connected", session.castDevice?.friendlyName)
        }

        override fun onSessionStartFailed(session: CastSession, error: Int) {
            sendCastState("notConnected", null)
        }

        override fun onSessionEnding(session: CastSession) {
            sendCastState("disconnecting", session.castDevice?.friendlyName)
        }

        override fun onSessionEnded(session: CastSession, error: Int) {
            sendCastState("notConnected", null)
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) {
            sendCastState("connecting", session.castDevice?.friendlyName)
        }

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            sendCastState("connected", session.castDevice?.friendlyName)
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            sendCastState("notConnected", null)
        }

        override fun onSessionSuspended(session: CastSession, reason: Int) {}
    }

    private val castSessionAvailabilityListener = object : SessionAvailabilityListener {
        override fun onCastSessionAvailable() {
            val local = exoPlayer
            val remote = castPlayer ?: return
            val pos = (local?.currentPosition ?: 0L).coerceAtLeast(0L)
            val wasPlaying = local?.isPlaying == true
            val currentVolume = local?.volume ?: 1f

            local?.pause()
            activePlayer = remote
            sendCastState("connected", currentCastDeviceName() ?: "Cast Device")

            val targetUrl = currentCastUrl ?: currentUrl
            if (!targetUrl.isNullOrEmpty()) {
                val mediaItem = buildCastMediaItem(targetUrl)
                remote.setMediaItem(mediaItem, pos)
                remote.volume = currentVolume
                remote.playWhenReady = wasPlaying
                remote.prepare()
            }
        }

        override fun onCastSessionUnavailable() {
            val local = exoPlayer
            val remote = castPlayer
            val pos = (remote?.currentPosition ?: 0L).coerceAtLeast(0L)

            stopPositionPolling()
            activePlayer = local
            local?.let { player ->
                player.playWhenReady = false
                player.pause()
                if (pos > 0L) {
                    player.seekTo(pos)
                }
            }
            sendCastState("notConnected", null)
            sendEvent("playing", false)
            if (pos > 0L) {
                sendEvent("position", pos)
            }
        }
    }

    private fun buildCastMediaItem(url: String): MediaItem {
        val lower = url.lowercase()
        val mimeType = when {
            lower.contains(".m3u8") -> MimeTypes.APPLICATION_M3U8
            lower.contains(".mpd") -> MimeTypes.APPLICATION_MPD
            lower.contains(".webm") -> MimeTypes.VIDEO_WEBM
            lower.contains(".mkv") -> MimeTypes.VIDEO_MATROSKA
            lower.contains(".mp3") -> MimeTypes.AUDIO_MPEG
            lower.contains(".aac") || lower.contains(".m4a") -> MimeTypes.AUDIO_AAC
            else -> MimeTypes.VIDEO_MP4
        }
        return MediaItem.Builder()
            .setUri(url)
            .setMimeType(mimeType)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setMediaType(MediaMetadata.MEDIA_TYPE_MOVIE)
                    .build()
            )
            .build()
    }


    /// 打开媒体 URL。
    private fun handleOpen(call: MethodCall, result: Result) {
        val url = call.argument<String>("url") ?: run {
            result.error("INVALID_ARG", "url is required", null)
            return
        }
        val local = exoPlayer ?: run {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }
        lastReportedDuration = -1L
        currentUrl = url
        currentCastUrl = call.argument<String>("castUrl")

        val mediaItem = MediaItem.fromUri(url)
        local.setMediaItem(mediaItem)
        local.playWhenReady = false
        local.prepare()

        // If currently casting, also load the new source onto the remote CastPlayer
        // without dropping the active Cast session.
        val remote = castPlayer
        if (activePlayer === remote && remote != null) {
            val targetUrl = currentCastUrl ?: url
            remote.setMediaItem(buildCastMediaItem(targetUrl))
            remote.playWhenReady = false
            remote.prepare()
        }

        result.success(null)
    }

    private fun handlePlay(result: Result) {
        val player = requirePlayer(result) ?: return
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
        }
        player.play()
        result.success(null)
    }

    private fun handlePause(result: Result) {
        val player = requirePlayer(result) ?: return
        player.pause()
        result.success(null)
    }

    private fun handleSeek(call: MethodCall, result: Result) {
        val player = requirePlayer(result) ?: return
        val position = call.argument<Number>("position")?.toLong() ?: 0L
        player.seekTo(position)
        // 拖动时直接主动发一次
        sendEvent("position", position)
        result.success(null)
    }


    private fun handleSetVolume(call: MethodCall, result: Result) {
        val player = requirePlayer(result) ?: return
        val volume = call.argument<Double>("volume") ?: 1.0
        val clamped = volume.toFloat().coerceIn(0f, 1f)
        exoPlayer?.volume = clamped
        try {
            player.volume = clamped
        } catch (_: Throwable) {
        }
        result.success(null)
    }

    private fun handleSetSpeed(call: MethodCall, result: Result) {
        val player = requirePlayer(result) ?: return
        val speed = (call.argument<Double>("speed") ?: 1.0).toFloat()
        exoPlayer?.setPlaybackSpeed(speed)
        try {
            player.setPlaybackSpeed(speed)
        } catch (_: Throwable) {
        }
        result.success(null)
    }

    private fun handleSetAspectRatioMode(call: MethodCall, result: Result) {
        val mode = call.argument<String>("mode") ?: "fit"
        resizeMode = when (mode) {
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "stretch" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        playerView?.resizeMode = resizeMode
        result.success(null)
    }

    private fun handleShowCastPicker(result: Result) {
        val act = activity
        val ctx = castContext
        if (act == null || ctx == null) {
            result.success(null)
            return
        }
        val selector = try {
            ctx.mergedSelector
        } catch (error: Throwable) {
            Log.e(TAG, "Cast route selector unavailable", error)
            null
        }
        if (selector == null) {
            result.success(null)
            return
        }
        act.runOnUiThread {
            try {
                // FlutterActivity uses a platform theme. MediaRoute dialogs extend
                // AppCompatDialog and require windowActionBar on the context theme.
                val dialogContext = castDialogContext(act)
                if (castPlayer?.isCastSessionAvailable == true) {
                    MediaRouteControllerDialog(dialogContext).show()
                } else {
                    MediaRouteChooserDialog(dialogContext).apply {
                        routeSelector = selector
                    }.show()
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to show cast route dialog", error)
            }
        }
        result.success(null)
    }

    private fun castDialogContext(activity: Activity): ContextThemeWrapper {
        return ContextThemeWrapper(
            activity,
            androidx.appcompat.R.style.Theme_AppCompat_DayNight_NoActionBar,
        )
    }

    private fun handleStopCasting(result: Result) {
        val ctx = castContext
        if (ctx == null) {
            result.success(null)
            return
        }
        mainHandler.post {
            try {
                ctx.sessionManager.endCurrentSession(true)
            } catch (_: Throwable) {
            }
        }
        result.success(null)
    }

    private fun handleDispose(result: Result) {
        restoreBrightness()
        releasePlayer()
        result.success(null)
    }

    private fun handleGetBrightness(result: Result) {
        val window = activity?.window
        if (window == null) {
            result.success(1.0)
            return
        }
        val override = window.attributes.screenBrightness
        if (override >= 0f) {
            result.success(override.toDouble())
            return
        }
        val system = try {
            val resolver = activity?.contentResolver
            if (resolver == null) {
                1.0
            } else {
                Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
            }
        } catch (_: Exception) {
            1.0
        }
        result.success(system.coerceIn(0.0, 1.0))
    }

    private fun handleSetBrightness(call: MethodCall, result: Result) {
        val value = call.argument<Double>("value") ?: run {
            result.error("INVALID_ARG", "value is required", null)
            return
        }
        val act = activity
        val window = act?.window
        if (act == null || window == null) {
            result.success(null)
            return
        }
        val clamped = value.toFloat().coerceIn(0f, 1f)
        act.runOnUiThread {
            val lp = window.attributes
            if (savedBrightness == null) {
                savedBrightness = lp.screenBrightness
            }
            lp.screenBrightness = clamped
            window.attributes = lp
        }
        result.success(null)
    }

    private fun restoreBrightness() {
        val original = savedBrightness ?: return
        savedBrightness = null
        val act = activity
        val window = act?.window ?: return
        act.runOnUiThread {
            val lp = window.attributes
            lp.screenBrightness = original
            window.attributes = lp
        }
    }

    private fun releasePlayer() {
        lastReportedDuration = -1L
        stopPositionPolling()
        playerView?.player = null
        try {
            castContext?.sessionManager?.removeSessionManagerListener(
                castSessionManagerListener,
                CastSession::class.java,
            )
        } catch (_: Throwable) {
        }
        castPlayer?.setSessionAvailabilityListener(null)
        castPlayer?.removeListener(castPlayerListener)
        try {
            castPlayer?.release()
        } catch (_: Throwable) {
        }
        castPlayer = null
        castContext = null
        exoPlayer?.removeListener(exoPlayerListener)
        exoPlayer?.release()
        exoPlayer = null
        activePlayer = null
        currentUrl = null
        currentCastUrl = null
    }

    private fun sendCastState(state: String, deviceName: String?) {
        lastCastState = state
        lastCastDeviceName = deviceName
        val payload = HashMap<String, Any?>()
        payload["state"] = state
        if (!deviceName.isNullOrBlank()) {
            payload["deviceName"] = deviceName
        }
        sendEvent("castState", payload)
    }

    private fun sendEvent(event: String, value: Any?) {
        mainHandler.post {
            val data = HashMap<String, Any?>()
            data["event"] = event
            data["value"] = value
            eventSink?.success(data)
        }
    }

    private fun postWorkerResult(generation: Int, block: () -> Unit) {
        mainHandler.post {
            if (generation != engineGeneration.get()) return@post
            if (flutterPluginBinding == null) return@post
            block()
        }
    }

    private fun checkAndSendDuration(sourcePlayer: Player?) {
        val player = sourcePlayer ?: activePlayer ?: return
        if (player !== activePlayer) return
        val dur = player.duration
        if (dur != C.TIME_UNSET && dur > 0L && dur != lastReportedDuration) {
            lastReportedDuration = dur
            sendEvent("duration", dur)
        }
    }

    private fun createPlayerListener(playerProvider: () -> Player?): Player.Listener {
        return object : Player.Listener {
            private fun isCurrentActive(): Boolean {
                val p = playerProvider()
                return p != null && p === activePlayer
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isCurrentActive()) return
                val player = playerProvider() ?: return
                sendEvent("playing", isPlaying)
                if (isPlaying) {
                    sendEvent("position", player.currentPosition)
                    startPositionPolling()
                } else {
                    sendEvent("position", player.currentPosition)
                    stopPositionPolling()
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (!isCurrentActive()) return
                val player = playerProvider() ?: return
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendEvent("buffering", true)
                        stopPositionPolling()
                    }

                    Player.STATE_READY -> {
                        sendEvent("buffering", false)
                        checkAndSendDuration(player)
                        if (player.isPlaying) {
                            startPositionPolling()
                        }
                    }

                    Player.STATE_ENDED -> {
                        stopPositionPolling()
                        sendEvent("buffering", false)
                        player.duration.takeIf { it > 0 }?.let { sendEvent("position", it) }
                        sendEvent("completed", null)
                    }

                    Player.STATE_IDLE -> {
                        stopPositionPolling()
                        sendEvent("buffering", false)
                    }
                }
            }

            override fun onTimelineChanged(timeline: androidx.media3.common.Timeline, reason: Int) {
                if (!isCurrentActive()) return
                checkAndSendDuration(playerProvider())
            }

            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int
            ) {
                if (!isCurrentActive()) return
                sendEvent("position", newPosition.positionMs)
            }

            override fun onPlayerError(error: PlaybackException) {
                if (!isCurrentActive()) return
                stopPositionPolling()
                sendEvent("buffering", false)
                sendEvent("error", error.message ?: "Unknown playback error")
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (!isCurrentActive()) return
                val rawW = videoSize.width
                val rawH = videoSize.height
                if (rawW <= 0 || rawH <= 0) return
                val par =
                    if (videoSize.pixelWidthHeightRatio > 0f) videoSize.pixelWidthHeightRatio else 1f
                val displayW = (rawW * par).toInt().coerceAtLeast(1)

                val size = HashMap<String, Any>()
                size["width"] = displayW
                size["height"] = rawH
                size["rotationDegrees"] = exoPlayer?.videoFormat?.rotationDegrees ?: 0
                sendEvent("videoSize", size)
            }
        }
    }

    private val exoPlayerListener = createPlayerListener { exoPlayer }
    private val castPlayerListener = createPlayerListener { castPlayer }


    // region Snapshot / Covers

    private fun handleTakeSnapshot(result: Result) {
        val generation = engineGeneration.get()
        // When casting remotely, local surface has no live frame; extract via retriever at remote playhead.
        if (activePlayer === castPlayer && castPlayer != null) {
            snapshotViaRetriever(result, generation)
            return
        }
        when (val surface = playerView?.videoSurfaceView) {
            is TextureView -> {
                val bmp = surface.bitmap
                if (bmp != null) {
                    val baos = ByteArrayOutputStream()
                    bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                    bmp.recycle()
                    result.success(baos.toByteArray())
                    return
                }
            }

            is SurfaceView -> {
                val w = surface.width
                val h = surface.height
                if (w > 0 && h > 0 && surface.holder.surface?.isValid == true) {
                    val bmp = createBitmap(w, h)
                    PixelCopy.request(surface, bmp, { copyResult ->
                        if (generation != engineGeneration.get() || flutterPluginBinding == null) {
                            bmp.recycle()
                            return@request
                        }
                        if (copyResult == PixelCopy.SUCCESS) {
                            val baos = ByteArrayOutputStream()
                            bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                            bmp.recycle()
                            result.success(baos.toByteArray())
                        } else {
                            bmp.recycle()
                            snapshotViaRetriever(result, generation)
                        }
                    }, mainHandler)
                    return
                }
            }
        }
        snapshotViaRetriever(result, generation)
    }

    private fun snapshotViaRetriever(result: Result, generation: Int) {
        val url = currentUrl
        val positionUs = ((activePlayer ?: exoPlayer)?.currentPosition ?: 0L) * 1000L
        val appContext = flutterPluginBinding?.applicationContext
        if (url == null) {
            result.error("NO_MEDIA", "No media loaded", null)
            return
        }
        workerExecutor.execute {
            val retriever = MediaMetadataRetriever()
            try {
                setDataSourceForUrl(retriever, url, appContext)
                val bmp =
                    retriever.getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST)
                if (bmp == null) {
                    postWorkerResult(generation) {
                        result.error("NO_FRAME", "Failed to extract frame", null)
                    }
                    return@execute
                }
                val baos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                bmp.recycle()
                val bytes = baos.toByteArray()
                postWorkerResult(generation) { result.success(bytes) }
            } catch (t: Throwable) {
                postWorkerResult(generation) {
                    result.error("SNAPSHOT_FAIL", t.message ?: "snapshot failed", null)
                }
            } finally {
                try {
                    retriever.release()
                } catch (_: Throwable) {
                }
            }
        }
    }

    private fun handleGetDuration(call: MethodCall, result: Result) {
        val url = call.argument<String>("url")
        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 15_000L
        val appContext = flutterPluginBinding?.applicationContext
        if (url.isNullOrEmpty()) {
            result.success(null)
            return
        }
        val generation = engineGeneration.get()
        workerExecutor.execute {
            val future = workerExecutor.submit<Long?> {
                val retriever = MediaMetadataRetriever()
                try {
                    setDataSourceForUrl(retriever, url, appContext)
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull()
                } finally {
                    try {
                        retriever.release()
                    } catch (_: Throwable) {
                    }
                }
            }
            val durMs = try {
                future.get(timeoutMs.coerceAtLeast(1L), TimeUnit.MILLISECONDS)
            } catch (_: TimeoutException) {
                future.cancel(true)
                null
            } catch (_: Throwable) {
                null
            }
            postWorkerResult(generation) {
                if (durMs == null || durMs <= 0) result.success(null)
                else result.success(durMs)
            }
        }
    }

    private fun handleExtractCovers(call: MethodCall, result: Result) {
        val url = call.argument<String>("url")
        val count = call.argument<Int>("count") ?: 5
        val candidates = call.argument<Int>("candidates") ?: (count * 3)
        val minBrightness = call.argument<Double>("minBrightness") ?: 0.08
        val outputDir = call.argument<String>("outputDir") ?: ""
        val appContext = flutterPluginBinding?.applicationContext
        if (url == null) {
            result.success(emptyList<Any>())
            return
        }
        val generation = engineGeneration.get()
        workerExecutor.execute {
            val frames = ArrayList<Map<String, Any>>()
            val retriever = MediaMetadataRetriever()
            try {
                setDataSourceForUrl(retriever, url, appContext)
                val durMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
                if (durMs <= 0) {
                    postWorkerResult(generation) { result.success(emptyList<Any>()) }
                    return@execute
                }
                val dir = File(outputDir.ifEmpty { appContext?.cacheDir?.absolutePath ?: "/tmp" })
                if (!dir.exists()) dir.mkdirs()

                val lower = (durMs * 0.05).toLong()
                val upper = (durMs * 0.95).toLong()
                val span = (upper - lower).coerceAtLeast(1L)
                val n = maxOf(candidates, count)
                for (i in 0 until n) {
                    val t = lower + (span * (i + 0.5) / n).toLong()
                    val bmp =
                        retriever.getFrameAtTime(t * 1000L, MediaMetadataRetriever.OPTION_CLOSEST)
                            ?: continue
                    val brightness = averageBrightness(bmp)
                    if (brightness < minBrightness) {
                        bmp.recycle()
                        continue
                    }
                    val outFile = File(dir, "cover-${abs(url.hashCode())}-$t.png")
                    try {
                        FileOutputStream(outFile).use { fos ->
                            bmp.compress(Bitmap.CompressFormat.PNG, 100, fos)
                        }
                        frames.add(
                            mapOf(
                                "path" to outFile.absolutePath,
                                "positionMs" to t,
                                "brightness" to brightness
                            )
                        )
                    } catch (_: Throwable) {
                        // skip
                    } finally {
                        bmp.recycle()
                    }
                }
                trimCoverCache(dir)
                frames.sortByDescending { (it["brightness"] as? Double) ?: 0.0 }
                val trimmed = frames.take(count)
                postWorkerResult(generation) { result.success(trimmed) }
            } catch (_: Throwable) {
                postWorkerResult(generation) { result.success(emptyList<Any>()) }
            } finally {
                try {
                    retriever.release()
                } catch (_: Throwable) {
                }
            }
        }
    }

    private fun trimCoverCache(dir: File, keep: Int = 40) {
        val files = dir.listFiles { f ->
            f.isFile && f.name.startsWith("cover-") && f.name.endsWith(".png")
        } ?: return
        if (files.size <= keep) return
        files.sortedBy { it.lastModified() }
            .take(files.size - keep)
            .forEach { it.delete() }
    }

    private fun setDataSourceForUrl(
        retriever: MediaMetadataRetriever,
        url: String,
        appContext: android.content.Context?
    ) {
        val uri = url.toUri()
        when (uri.scheme?.lowercase()) {
            "file" -> {
                if (appContext != null) retriever.setDataSource(appContext, uri)
                else retriever.setDataSource(uri.path ?: url)
            }

            "http", "https" -> retriever.setDataSource(url, HashMap())
            "content" -> {
                if (appContext != null) retriever.setDataSource(appContext, uri)
                else retriever.setDataSource(url, HashMap())
            }

            else -> retriever.setDataSource(url)
        }
    }

    private fun averageBrightness(bmp: Bitmap): Double {
        val w = 64
        val h = 64
        val scaled = bmp.scale(w, h, false)
        val pixels = IntArray(w * h)
        scaled.getPixels(pixels, 0, w, 0, 0, w, h)
        var total = 0.0
        for (p in pixels) {
            val r = ((p shr 16) and 0xff) / 255.0
            val g = ((p shr 8) and 0xff) / 255.0
            val b = (p and 0xff) / 255.0
            total += 0.299 * r + 0.587 * g + 0.114 * b
        }
        if (scaled != bmp) scaled.recycle()
        return total / pixels.size
    }

    private val positionRunnable = object : Runnable {
        override fun run() {
            val player = activePlayer
            if (player != null && player.isPlaying) {
                sendEvent("position", player.currentPosition)
                mainHandler.postDelayed(this, 200)
            } else {
                isPollingPosition = false
            }
        }
    }

    private fun startPositionPolling() {
        if (!isPollingPosition) {
            isPollingPosition = true
            mainHandler.removeCallbacks(positionRunnable)
            mainHandler.post(positionRunnable)
        }
    }

    private fun stopPositionPolling() {
        isPollingPosition = false
        mainHandler.removeCallbacks(positionRunnable)
    }
}
