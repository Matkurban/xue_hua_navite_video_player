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
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.resume
import kotlin.math.abs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

private const val TAG = "XueHuaNaviteVideoPlayer"

/// 插件主类：ExoPlayer + CastPlayer（Google Cast）+ PlatformView + Pigeon JNI 宿主接口。
@UnstableApi
class XueHuaNaviteVideoPlayerPlugin :
    FlutterPlugin,
    PlayerHostApi,
    ActivityAware,
    DefaultLifecycleObserver {

    private var exoPlayer: ExoPlayer? = null
    private var castPlayer: CastPlayer? = null
    private var castContext: CastContext? = null
    private var activePlayer: Player? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var workerExecutor = Executors.newCachedThreadPool()
    private val engineGeneration = AtomicInteger(0)
    private val openGeneration = AtomicInteger(0)
    private var currentUrl: String? = null
    private var currentCastUrl: String? = null
    private var currentCacheKey: String? = null
    private var currentHeaders: Map<String, String>? = null
    private var lastCastState: NativeCastState = NativeCastState.UNAVAILABLE
    private var lastCastDeviceName: String? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var pluginScope: CoroutineScope? = null
    private var eventQueue: Channel<PlayerEventData>? = null
    private var eventConsumerJob: Job? = null
    private var playerView: PlayerView? = null
    private var resizeMode: Int = AspectRatioFrameLayout.RESIZE_MODE_FIT
    private var activity: Activity? = null
    private var lifecycleOwner: LifecycleOwner? = null
    private var savedBrightness: Float? = null
    private val orientationPlugin = OrientationPlugin()

    private var lastReportedDuration: Long = -1L
    private var lastReportedBuffered: Long = -1L

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
        startEventConsumer(binding)
        PlayerHostApiRegistrar().register(this, binding)
        orientationPlugin.attach(binding.applicationContext, binding.binaryMessenger)

        binding.platformViewRegistry.registerViewFactory(
            PLAYER_PLATFORM_VIEW_TYPE,
            PlayerPlatformViewFactory(this),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engineGeneration.incrementAndGet()
        openGeneration.incrementAndGet()
        orientationPlugin.detach(binding.binaryMessenger)
        PlayerHostApiRegistrar().unregister(this, binding)
        stopEventConsumer()
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

    private fun startEventConsumer(binding: FlutterPlugin.FlutterPluginBinding) {
        stopEventConsumer()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        pluginScope = scope
        val registrar = PlayerFlutterApiRegistrar()
        startEventLoop(scope) { event ->
            if (flutterPluginBinding == null) return@startEventLoop
            try {
                registrar.getInstance(binding)?.onPlayerEvent(event)
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to dispatch PlayerFlutterApi event: ${event.kind}", t)
            }
        }
    }

    internal fun startEventLoop(
        scope: CoroutineScope,
        dispatch: suspend (PlayerEventData) -> Unit,
    ): Job {
        eventConsumerJob?.cancel()
        eventQueue?.close()
        val queue = Channel<PlayerEventData>(Channel.UNLIMITED)
        eventQueue = queue
        val job = scope.launch {
            for (event in queue) {
                if (!isActive) break
                dispatch(event)
            }
        }
        eventConsumerJob = job
        return job
    }

    internal fun enqueueEventForTest(event: PlayerEventData) {
        emitEvent(event)
    }

    internal fun bumpOpenGenerationForTest(): Int = openGeneration.incrementAndGet()

    internal fun currentEngineGenerationForTest(): Int = engineGeneration.get()

    internal fun isOpenGenerationValid(targetOpenGen: Int, targetEngineGen: Int): Boolean {
        return targetOpenGen == openGeneration.get() && targetEngineGen == engineGeneration.get()
    }

    private fun stopEventConsumer() {
        eventConsumerJob?.cancel()
        eventConsumerJob = null
        pluginScope?.cancel()
        pluginScope = null
        eventQueue?.close()
        eventQueue = null
    }

    private inline fun runOnMainThread(crossinline block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }

    private fun bindActivity(act: Activity) {
        activity = act
        orientationPlugin.bindActivity(act)
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
        orientationPlugin.unbindActivity()
        activity = null
    }

    private fun requirePlayer(): Player {
        return activePlayer ?: exoPlayer ?: throw FlutterError(
            code = "NO_PLAYER",
            message = "Player not initialized",
        )
    }

    override suspend fun create(): Long {
        val generation = engineGeneration.get()
        val appContext = withContext(Dispatchers.Main.immediate) {
            val binding = flutterPluginBinding ?: throw FlutterError(
                code = "NO_ENGINE",
                message = "Flutter engine not attached",
            )
            if (generation != engineGeneration.get()) {
                throw FlutterError(
                    code = "CANCELLED",
                    message = "Engine detached before player creation completed",
                )
            }
            binding.applicationContext
        }

        // Pre-warm SimpleCache (SQLite + cache directory scan) off the merged UI/platform thread.
        val dataSourceFactory = withContext(Dispatchers.IO) {
            AndroidMediaCacheManager.buildDataSourceFactory(appContext)
        }

        return withContext(Dispatchers.Main.immediate) {
            if (flutterPluginBinding == null || generation != engineGeneration.get()) {
                throw FlutterError(
                    code = "CANCELLED",
                    message = "Engine detached before player creation completed",
                )
            }

            releasePlayer()

            val defaultAdapterFactory = DefaultMediaCodecAdapterFactory(appContext)

            // Align odd dimensions before MediaCodec configuration to avoid green stripes/failures.
            val renderersFactory = object : DefaultRenderersFactory(appContext) {
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

            val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

            val player = ExoPlayer.Builder(appContext)
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

            initCastSupport(appContext)

            0L
        }
    }

    private fun initCastSupport(context: android.content.Context) {
        val generation = engineGeneration.get()
        try {
            val task = CastContext.getSharedInstance(context, workerExecutor)
            task.addOnSuccessListener { ctx ->
                runOnMainThread {
                    if (generation != engineGeneration.get() || exoPlayer == null) return@runOnMainThread
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
                            sendCastState(NativeCastState.CONNECTED, currentCastDeviceName())
                        } else {
                            sendCastState(NativeCastState.NOT_CONNECTED, null)
                        }
                    } catch (_: Throwable) {
                        sendCastState(NativeCastState.UNAVAILABLE, null)
                    }
                }
            }.addOnFailureListener {
                runOnMainThread {
                    if (generation != engineGeneration.get()) return@runOnMainThread
                    sendCastState(NativeCastState.UNAVAILABLE, null)
                }
            }
        } catch (_: Throwable) {
            sendCastState(NativeCastState.UNAVAILABLE, null)
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
            sendCastState(NativeCastState.CONNECTING, session.castDevice?.friendlyName)
        }

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            sendCastState(NativeCastState.CONNECTED, session.castDevice?.friendlyName)
        }

        override fun onSessionStartFailed(session: CastSession, error: Int) {
            sendCastState(NativeCastState.NOT_CONNECTED, null)
        }

        override fun onSessionEnding(session: CastSession) {
            sendCastState(NativeCastState.DISCONNECTING, session.castDevice?.friendlyName)
        }

        override fun onSessionEnded(session: CastSession, error: Int) {
            sendCastState(NativeCastState.NOT_CONNECTED, null)
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) {
            sendCastState(NativeCastState.CONNECTING, session.castDevice?.friendlyName)
        }

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            sendCastState(NativeCastState.CONNECTED, session.castDevice?.friendlyName)
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            sendCastState(NativeCastState.NOT_CONNECTED, null)
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
            sendCastState(NativeCastState.CONNECTED, currentCastDeviceName() ?: "Cast Device")

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
            sendCastState(NativeCastState.NOT_CONNECTED, null)
            sendPlayingEvent(false)
            if (pos > 0L) {
                sendPositionEvent(pos)
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

    private fun normalizeHeaders(raw: Map<String, String>?): Map<String, String>? {
        if (raw.isNullOrEmpty()) return null
        val out = HashMap<String, String>()
        for ((k, v) in raw) {
            val key = k.trim()
            if (key.isNotEmpty()) {
                out[key] = v
            }
        }
        return out.takeIf { it.isNotEmpty() }
    }

    override suspend fun open(request: OpenMediaRequest) {
        val url = request.url
        if (url.isEmpty()) {
            throw FlutterError(
                code = "INVALID_ARG",
                message = "url is required",
            )
        }
        val targetOpenGen = openGeneration.incrementAndGet()
        val targetEngineGen = engineGeneration.get()
        val appContext = withContext(Dispatchers.Main.immediate) {
            if (exoPlayer == null) {
                throw FlutterError(
                    code = "NO_PLAYER",
                    message = "Player not initialized",
                )
            }
            flutterPluginBinding?.applicationContext
        }

        val headers = normalizeHeaders(request.headers)
        val dsFactory = appContext?.let { ctx ->
            withContext(Dispatchers.IO) {
                AndroidMediaCacheManager.buildDataSourceFactory(
                    context = ctx,
                    headers = headers,
                    enableCacheOverride = request.enableCache,
                )
            }
        }

        withContext(Dispatchers.Main.immediate) {
            if (!isOpenGenerationValid(targetOpenGen, targetEngineGen)) {
                return@withContext
            }
            val local = exoPlayer ?: throw FlutterError(
                code = "NO_PLAYER",
                message = "Player not initialized",
            )
            val cacheKey = request.cacheKey

            lastReportedDuration = -1L
            lastReportedBuffered = -1L
            currentUrl = url
            currentCastUrl = request.castUrl
            currentCacheKey = cacheKey
            currentHeaders = headers

            val mediaItem = MediaItem.Builder()
                .setUri(url)
                .apply {
                    if (!cacheKey.isNullOrBlank()) {
                        setCustomCacheKey(cacheKey)
                    }
                }
                .build()

            if (dsFactory != null) {
                val mediaSource = DefaultMediaSourceFactory(dsFactory).createMediaSource(mediaItem)
                local.setMediaSource(mediaSource)
            } else {
                local.setMediaItem(mediaItem)
            }
            local.playWhenReady = false
            local.prepare()

            val remote = castPlayer
            if (activePlayer === remote && remote != null) {
                val targetUrl = currentCastUrl ?: url
                remote.setMediaItem(buildCastMediaItem(targetUrl))
                remote.playWhenReady = false
                remote.prepare()
            }
        }
    }

    override fun play() {
        val player = requirePlayer()
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
        }
        player.play()
    }

    override fun pause() {
        val player = requirePlayer()
        player.pause()
    }

    override fun seek(positionMs: Long) {
        val player = requirePlayer()
        player.seekTo(positionMs)
        sendPositionEvent(positionMs)
    }

    override fun setVolume(volume: Double) {
        val player = requirePlayer()
        val clamped = volume.toFloat().coerceIn(0f, 1f)
        exoPlayer?.volume = clamped
        try {
            player.volume = clamped
        } catch (_: Throwable) {
        }
    }

    override fun setSpeed(speed: Double) {
        val player = requirePlayer()
        val playbackSpeed = speed.toFloat()
        exoPlayer?.setPlaybackSpeed(playbackSpeed)
        try {
            player.setPlaybackSpeed(playbackSpeed)
        } catch (_: Throwable) {
        }
    }

    override fun setAspectRatioMode(mode: NativeAspectRatioMode) {
        resizeMode = when (mode) {
            NativeAspectRatioMode.FILL -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            NativeAspectRatioMode.STRETCH -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            NativeAspectRatioMode.FIT -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        playerView?.resizeMode = resizeMode
    }

    override fun setVideoViewSize(width: Double, height: Double, devicePixelRatio: Double) {
        // Android PlatformView (PlayerView) resizes automatically with Flutter layout.
    }

    override fun showCastPicker() {
        val act = activity ?: return
        val ctx = castContext ?: return
        val selector = try {
            ctx.mergedSelector
        } catch (error: Throwable) {
            Log.e(TAG, "Cast route selector unavailable", error)
            null
        } ?: return

        runOnMainThread {
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
    }

    private fun castDialogContext(activity: Activity): ContextThemeWrapper {
        return ContextThemeWrapper(
            activity,
            androidx.appcompat.R.style.Theme_AppCompat_DayNight_NoActionBar,
        )
    }

    override fun stopCasting() {
        val ctx = castContext ?: return
        runOnMainThread {
            try {
                ctx.sessionManager.endCurrentSession(true)
            } catch (_: Throwable) {
            }
        }
    }

    override fun dispose() {
        openGeneration.incrementAndGet()
        restoreBrightness()
        releasePlayer()
    }

    override fun getBrightness(): Double {
        val window = activity?.window ?: return 1.0
        val override = window.attributes.screenBrightness
        if (override >= 0f) {
            return override.toDouble()
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
        return system.coerceIn(0.0, 1.0)
    }

    override fun setBrightness(value: Double) {
        val act = activity ?: return
        val window = act.window ?: return
        val clamped = value.toFloat().coerceIn(0f, 1f)
        runOnMainThread {
            val lp = window.attributes
            if (savedBrightness == null) {
                savedBrightness = lp.screenBrightness
            }
            lp.screenBrightness = clamped
            window.attributes = lp
        }
    }

    override fun setWindowFullscreen(value: Boolean) {
        // Android window fullscreen is managed via SystemChrome on the Dart side.
    }

    override suspend fun configureCache(request: CacheConfigRequest) {
        val appContext = flutterPluginBinding?.applicationContext ?: return
        withContext(Dispatchers.IO) {
            AndroidMediaCacheManager.configure(
                context = appContext,
                enabled = request.enabled,
                maxCacheBytes = request.maxCacheBytes,
                maxSingleFileBytes = request.maxSingleFileBytes,
                cacheDir = request.cacheDir,
            )
        }
    }

    override suspend fun precache(request: PrecacheRequest) {
        val appContext = flutterPluginBinding?.applicationContext ?: return
        val url = request.url
        if (url.isBlank()) return
        val cacheKey = request.cacheKey?.takeIf { it.isNotBlank() } ?: url
        val headers = normalizeHeaders(request.headers)
        suspendCancellableCoroutine { cont ->
            val resumed = AtomicBoolean(false)
            AndroidMediaCacheManager.precache(
                context = appContext,
                executor = workerExecutor,
                url = url,
                cacheKey = cacheKey,
                cacheDir = request.cacheDir,
                headers = headers,
                preloadBytes = request.preloadBytes,
            ) {
                if (resumed.compareAndSet(false, true) && cont.isActive) {
                    cont.resume(Unit)
                }
            }
            cont.invokeOnCancellation {
                AndroidMediaCacheManager.cancelPrecache(cacheKey)
            }
        }
    }

    override fun cancelPrecache(cacheKey: String) {
        if (cacheKey.isNotBlank()) {
            AndroidMediaCacheManager.cancelPrecache(cacheKey)
        }
    }

    override suspend fun isCached(request: CacheEntryRequest): Boolean {
        val appContext = flutterPluginBinding?.applicationContext ?: return false
        val cacheKey = request.cacheKey?.takeIf { it.isNotBlank() } ?: request.url
        if (cacheKey.isBlank()) return false
        return withContext(Dispatchers.IO) {
            AndroidMediaCacheManager.isCached(appContext, request.cacheDir, cacheKey)
        }
    }

    override suspend fun getCacheSize(cacheDir: String?): Long {
        val appContext = flutterPluginBinding?.applicationContext ?: return 0L
        return withContext(Dispatchers.IO) {
            AndroidMediaCacheManager.getCacheSize(appContext, cacheDir)
        }
    }

    override suspend fun removeCache(request: CacheEntryRequest) {
        val appContext = flutterPluginBinding?.applicationContext ?: return
        val cacheKey = request.cacheKey?.takeIf { it.isNotBlank() } ?: request.url
        if (cacheKey.isBlank()) return
        withContext(Dispatchers.IO) {
            AndroidMediaCacheManager.removeCache(appContext, request.cacheDir, cacheKey)
        }
    }

    override suspend fun clearCache(cacheDir: String?) {
        val appContext = flutterPluginBinding?.applicationContext ?: return
        withContext(Dispatchers.IO) {
            AndroidMediaCacheManager.clearCache(appContext, cacheDir)
        }
    }

    override fun pinCacheKey(cacheKey: String) {
        AndroidMediaCacheManager.pin(cacheKey)
    }

    override fun unpinCacheKey(cacheKey: String) {
        AndroidMediaCacheManager.unpin(cacheKey)
    }

    private fun restoreBrightness() {
        val original = savedBrightness ?: return
        savedBrightness = null
        val act = activity ?: return
        val window = act.window ?: return
        runOnMainThread {
            val lp = window.attributes
            lp.screenBrightness = original
            window.attributes = lp
        }
    }

    private fun releasePlayer() {
        lastReportedDuration = -1L
        lastReportedBuffered = -1L
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
        currentCacheKey = null
        currentHeaders = null
    }

    private fun emitEvent(event: PlayerEventData) {
        eventQueue?.trySend(event)
    }

    private fun sendCastState(state: NativeCastState, deviceName: String?) {
        lastCastState = state
        lastCastDeviceName = deviceName
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.CAST_STATE,
                castState = state,
                castDeviceName = deviceName?.takeIf { it.isNotBlank() },
            )
        )
    }

    private fun sendPositionEvent(positionMs: Long) {
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.POSITION,
                intValue = positionMs,
            )
        )
    }

    private fun sendBufferedEvent(bufferedMs: Long) {
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.BUFFERED,
                intValue = bufferedMs,
            )
        )
    }

    private fun sendDurationEvent(durationMs: Long) {
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.DURATION,
                intValue = durationMs,
            )
        )
    }

    private fun sendPlayingEvent(isPlaying: Boolean) {
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.PLAYING,
                boolValue = isPlaying,
            )
        )
    }

    private fun sendBufferingEvent(isBuffering: Boolean) {
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.BUFFERING,
                boolValue = isBuffering,
            )
        )
    }

    private fun sendErrorEvent(message: String) {
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.ERROR,
                message = message,
            )
        )
    }

    private fun sendCompletedEvent() {
        emitEvent(PlayerEventData(kind = NativePlayerEventType.COMPLETED))
    }

    private fun sendVideoSizeEvent(width: Double, height: Double, rotationDegrees: Int) {
        emitEvent(
            PlayerEventData(
                kind = NativePlayerEventType.VIDEO_SIZE,
                width = width,
                height = height,
                rotationDegrees = rotationDegrees.toLong(),
            )
        )
    }

    private fun checkAndSendDuration(sourcePlayer: Player?) {
        val player = sourcePlayer ?: activePlayer ?: return
        if (player !== activePlayer) return
        val dur = player.duration
        if (dur != C.TIME_UNSET && dur > 0L && dur != lastReportedDuration) {
            lastReportedDuration = dur
            sendDurationEvent(dur)
        }
    }

    private fun checkAndSendBuffered(sourcePlayer: Player?) {
        val player = sourcePlayer ?: activePlayer ?: return
        if (player !== activePlayer) return
        val buffered = player.bufferedPosition.coerceAtLeast(0L)
        if (buffered != lastReportedBuffered) {
            lastReportedBuffered = buffered
            sendBufferedEvent(buffered)
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
                sendPlayingEvent(isPlaying)
                if (isPlaying) {
                    sendPositionEvent(player.currentPosition)
                    startPositionPolling()
                } else {
                    sendPositionEvent(player.currentPosition)
                    stopPositionPolling()
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (!isCurrentActive()) return
                val player = playerProvider() ?: return
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingEvent(true)
                        stopPositionPolling()
                    }

                    Player.STATE_READY -> {
                        sendBufferingEvent(false)
                        checkAndSendDuration(player)
                        checkAndSendBuffered(player)
                        if (player.isPlaying) {
                            startPositionPolling()
                        }
                    }

                    Player.STATE_ENDED -> {
                        stopPositionPolling()
                        sendBufferingEvent(false)
                        player.duration.takeIf { it > 0 }?.let {
                            sendPositionEvent(it)
                            lastReportedBuffered = it
                            sendBufferedEvent(it)
                        }
                        sendCompletedEvent()
                    }

                    Player.STATE_IDLE -> {
                        stopPositionPolling()
                        sendBufferingEvent(false)
                    }
                }
            }

            override fun onIsLoadingChanged(isLoading: Boolean) {
                if (!isCurrentActive()) return
                checkAndSendBuffered(playerProvider())
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
                sendPositionEvent(newPosition.positionMs)
            }

            override fun onPlayerError(error: PlaybackException) {
                if (!isCurrentActive()) return
                stopPositionPolling()
                sendBufferingEvent(false)
                sendErrorEvent(error.message ?: "Unknown playback error")
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (!isCurrentActive()) return
                val rawW = videoSize.width
                val rawH = videoSize.height
                if (rawW <= 0 || rawH <= 0) return
                val par =
                    if (videoSize.pixelWidthHeightRatio > 0f) videoSize.pixelWidthHeightRatio else 1f
                val displayW = (rawW * par).toInt().coerceAtLeast(1)
                val rotationDegrees = exoPlayer?.videoFormat?.rotationDegrees ?: 0
                sendVideoSizeEvent(displayW.toDouble(), rawH.toDouble(), rotationDegrees)
            }
        }
    }

    private val exoPlayerListener = createPlayerListener { exoPlayer }
    private val castPlayerListener = createPlayerListener { castPlayer }

    override suspend fun takeSnapshot(): SnapshotData? {
        val generation = engineGeneration.get()
        // When casting remotely, capture frame context + active playhead on Main first, then decode off-UI.
        val snapshotInput = withContext(Dispatchers.Main.immediate) {
            val isRemoteCasting = activePlayer === castPlayer && castPlayer != null
            val positionUs = ((activePlayer ?: exoPlayer)?.currentPosition ?: 0L) * 1000L
            val surface = if (isRemoteCasting) null else playerView?.videoSurfaceView
            SnapshotInput(
                surface = surface,
                positionUs = positionUs,
                url = currentUrl,
                cacheKey = currentCacheKey,
                headers = currentHeaders,
            )
        }

        when (val surface = snapshotInput.surface) {
            is TextureView -> {
                val bmp = withContext(Dispatchers.Main.immediate) { surface.bitmap }
                if (bmp != null) {
                    val bytes = compressBitmapPng(bmp)
                    return SnapshotData(bytes = bytes)
                }
            }

            is SurfaceView -> {
                val bytes = captureSurfaceView(surface, generation)
                if (bytes != null) {
                    return SnapshotData(bytes = bytes)
                }
            }
        }

        val url = snapshotInput.url ?: throw FlutterError(
            code = "NO_MEDIA",
            message = "No media loaded",
        )
        val appContext = flutterPluginBinding?.applicationContext
        val bytes = withContext(Dispatchers.IO) {
            val retriever = MediaMetadataRetriever()
            try {
                setDataSourceForUrl(
                    retriever,
                    url,
                    appContext,
                    snapshotInput.cacheKey,
                    snapshotInput.headers,
                )
                val bmp = retriever.getFrameAtTime(
                    snapshotInput.positionUs,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                ) ?: throw FlutterError(
                    code = "NO_FRAME",
                    message = "Failed to extract frame",
                )
                compressBitmapPngSync(bmp)
            } catch (error: FlutterError) {
                throw error
            } catch (t: Throwable) {
                throw FlutterError(
                    code = "SNAPSHOT_FAIL",
                    message = t.message ?: "snapshot failed",
                )
            } finally {
                try {
                    retriever.release()
                } catch (_: Throwable) {
                }
            }
        }
        return SnapshotData(bytes = bytes)
    }

    private suspend fun captureSurfaceView(surface: SurfaceView, generation: Int): ByteArray? {
        val bmp = withContext(Dispatchers.Main.immediate) {
            val w = surface.width
            val h = surface.height
            if (w <= 0 || h <= 0 || surface.holder.surface?.isValid != true) {
                return@withContext null
            }
            val target = createBitmap(w, h)
            val copied = suspendCancellableCoroutine { cont ->
                try {
                    PixelCopy.request(surface, target, { copyResult ->
                        if (!cont.isActive) {
                            target.recycle()
                            return@request
                        }
                        cont.resume(copyResult == PixelCopy.SUCCESS)
                    }, mainHandler)
                } catch (_: Throwable) {
                    if (cont.isActive) {
                        cont.resume(false)
                    } else {
                        target.recycle()
                    }
                }
            }
            if (!copied || generation != engineGeneration.get() || flutterPluginBinding == null) {
                target.recycle()
                return@withContext null
            }
            target
        } ?: return null

        return compressBitmapPng(bmp)
    }

    private suspend fun compressBitmapPng(bmp: Bitmap): ByteArray =
        withContext(Dispatchers.Default) {
            compressBitmapPngSync(bmp)
        }

    private fun compressBitmapPngSync(bmp: Bitmap): ByteArray {
        val baos = ByteArrayOutputStream()
        try {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
            return baos.toByteArray()
        } finally {
            bmp.recycle()
        }
    }

    override suspend fun getDuration(request: DurationProbeRequest): Long? {
        val url = request.url
        if (url.isEmpty()) return null
        val appContext = flutterPluginBinding?.applicationContext
        val headers = normalizeHeaders(request.headers)
        val timeoutMs = request.timeoutMs.coerceAtLeast(1L)
        val future = workerExecutor.submit<Long?> {
            val retriever = MediaMetadataRetriever()
            try {
                setDataSourceForUrl(retriever, url, appContext, request.cacheKey, headers)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
            } finally {
                try {
                    retriever.release()
                } catch (_: Throwable) {
                }
            }
        }
        return try {
            withContext(Dispatchers.IO) {
                future.get(timeoutMs, TimeUnit.MILLISECONDS)
            }?.takeIf { it > 0L }
        } catch (_: TimeoutException) {
            future.cancel(true)
            null
        } catch (e: CancellationException) {
            future.cancel(true)
            throw e
        } catch (_: Throwable) {
            null
        }
    }

    override suspend fun extractCovers(request: CoverExtractRequest): List<CoverFrameData> {
        val url = request.url
        if (url.isEmpty()) return emptyList()
        val appContext = flutterPluginBinding?.applicationContext
        val headers = normalizeHeaders(request.headers)
        val count = request.count.toInt().coerceAtLeast(0)
        val candidates = request.candidates.toInt().coerceAtLeast(count)
        if (count == 0 || candidates == 0) return emptyList()

        return withContext(Dispatchers.IO) {
            val frames = ArrayList<CoverFrameData>()
            val retriever = MediaMetadataRetriever()
            try {
                setDataSourceForUrl(retriever, url, appContext, request.cacheKey, headers)
                val durMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
                if (durMs <= 0L) return@withContext emptyList()

                val dir = File(
                    request.outputDir.ifEmpty { appContext?.cacheDir?.absolutePath ?: "/tmp" }
                )
                if (!dir.exists()) dir.mkdirs()

                val lower = (durMs * 0.05).toLong()
                val upper = (durMs * 0.95).toLong()
                val span = (upper - lower).coerceAtLeast(1L)
                for (i in 0 until candidates) {
                    if (!isActive) break
                    val t = lower + (span * (i + 0.5) / candidates).toLong()
                    val bmp =
                        retriever.getFrameAtTime(t * 1000L, MediaMetadataRetriever.OPTION_CLOSEST)
                            ?: continue
                    val brightness = averageBrightness(bmp)
                    if (brightness < request.minBrightness) {
                        bmp.recycle()
                        continue
                    }
                    val outFile = File(dir, "cover-${abs(url.hashCode())}-$t.png")
                    try {
                        FileOutputStream(outFile).use { fos ->
                            bmp.compress(Bitmap.CompressFormat.PNG, 100, fos)
                        }
                        frames.add(
                            CoverFrameData(
                                path = outFile.absolutePath,
                                positionMs = t,
                                brightness = brightness,
                            )
                        )
                    } catch (_: Throwable) {
                        // Skip individual frame write failures.
                    } finally {
                        bmp.recycle()
                    }
                }
                trimCoverCache(dir)
                frames.sortByDescending { it.brightness }
                frames.take(count)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                emptyList()
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
        appContext: android.content.Context?,
        cacheKey: String? = null,
        headers: Map<String, String>? = null,
    ) {
        if (appContext != null && !cacheKey.isNullOrBlank()) {
            val cachedFile = AndroidMediaCacheManager.resolveCompleteCachedFile(appContext, cacheKey)
            if (cachedFile != null) {
                retriever.setDataSource(cachedFile.absolutePath)
                return
            }
        }
        val uri = url.toUri()
        when (uri.scheme?.lowercase()) {
            "file" -> {
                if (appContext != null) retriever.setDataSource(appContext, uri)
                else retriever.setDataSource(uri.path ?: url)
            }

            "http", "https" -> {
                val hdrs = HashMap<String, String>()
                if (headers != null) {
                    hdrs.putAll(headers)
                }
                retriever.setDataSource(url, hdrs)
            }

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
                sendPositionEvent(player.currentPosition)
                checkAndSendBuffered(player)
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
        if (!isPollingPosition) return
        isPollingPosition = false
        mainHandler.removeCallbacks(positionRunnable)
    }

    private data class SnapshotInput(
        val surface: android.view.View?,
        val positionUs: Long,
        val url: String?,
        val cacheKey: String?,
        val headers: Map<String, String>?,
    )
}
