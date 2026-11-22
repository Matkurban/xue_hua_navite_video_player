package com.kurban.xue_hua_navite_video_player

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.OrientationEventListener
import android.view.Surface
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.plugin.common.BinaryMessenger
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Android 原生设备方向控制与物理重力传感器插件实现。
 *
 * 使用 [OrientationEventListener] 监听 0° ~ 360° 物理旋转角度，内置 ±20° 滞回死区与 300ms
 * 防抖以过滤躺卧观看抖动、倒置与平放干扰；通过 [Activity.setRequestedOrientation] 无视系统
 * 自动旋转锁定强制切换方向，并支持通过 [WindowInsetsControllerCompat] 控制沉浸式全屏。
 */
class OrientationPlugin : OrientationHostApi {
    private var appContext: Context? = null
    private var activity: Activity? = null
    private var flutterApi: OrientationFlutterApi? = null
    private var pluginScope: CoroutineScope? = null
    private var orientationListener: OrientationEventListener? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var isListening = false
    private var lastEmittedOrientation: DevicePhysicalOrientation = DevicePhysicalOrientation.UNKNOWN
    private var pendingOrientation: DevicePhysicalOrientation? = null
    private var debounceRunnable: Runnable? = null

    fun attach(context: Context, binaryMessenger: BinaryMessenger) {
        appContext = context.applicationContext
        flutterApi = OrientationFlutterApi(binaryMessenger)
        pluginScope?.cancel()
        pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        OrientationHostApi.setUp(binaryMessenger, this)
    }

    fun detach(binaryMessenger: BinaryMessenger) {
        stopSensorListeningInternal()
        OrientationHostApi.setUp(binaryMessenger, null)
        pluginScope?.cancel()
        pluginScope = null
        flutterApi = null
        activity = null
        appContext = null
    }

    fun bindActivity(act: Activity) {
        activity = act
    }

    fun unbindActivity() {
        activity = null
    }

    // MARK: - OrientationHostApi

    override suspend fun setTargetOrientation(orientation: DevicePhysicalOrientation) {
        val act = activity ?: return
        val requested = when (orientation) {
            DevicePhysicalOrientation.PORTRAIT_UP -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            DevicePhysicalOrientation.LANDSCAPE_LEFT -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            DevicePhysicalOrientation.LANDSCAPE_RIGHT -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            DevicePhysicalOrientation.UNKNOWN -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        runOnMainThread {
            act.requestedOrientation = requested
        }
    }

    override suspend fun getCurrentOrientation(): DevicePhysicalOrientation {
        val act = activity ?: return DevicePhysicalOrientation.UNKNOWN
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            act.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            act.windowManager.defaultDisplay.rotation
        }
        return when (rotation) {
            Surface.ROTATION_0 -> DevicePhysicalOrientation.PORTRAIT_UP
            Surface.ROTATION_90 -> DevicePhysicalOrientation.LANDSCAPE_LEFT
            Surface.ROTATION_270 -> DevicePhysicalOrientation.LANDSCAPE_RIGHT
            else -> DevicePhysicalOrientation.UNKNOWN
        }
    }

    override fun startSensorListening() {
        if (isListening) return
        val ctx = appContext ?: return
        isListening = true

        val listener = object : OrientationEventListener(ctx, SensorManager.SENSOR_DELAY_UI) {
            override fun onOrientationChanged(orientation: Int) {
                if (orientation == ORIENTATION_UNKNOWN) return
                handleRawAngle(orientation.toDouble())
            }
        }
        if (listener.canDetectOrientation()) {
            orientationListener = listener
            listener.enable()
        } else {
            isListening = false
        }
    }

    override fun stopSensorListening() {
        stopSensorListeningInternal()
    }

    override suspend fun setImmersiveFullscreen(enabled: Boolean) {
        val act = activity ?: return
        runOnMainThread {
            val window = act.window ?: return@runOnMainThread
            val controller = WindowCompat.getInsetsController(window, window.decorView)
            if (enabled) {
                controller.systemBarsBehavior =
                    WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsetsCompat.Type.systemBars())
            } else {
                controller.show(WindowInsetsCompat.Type.systemBars())
            }
        }
    }

    // MARK: - Sensor Hysteresis & Debounce

    private fun handleRawAngle(angleDegrees: Double) {
        // 主动过滤 portraitDown（135° ~ 225° 倒置姿态）
        if (angleDegrees in 135.0..225.0) {
            return
        }

        val resolved = resolveWithHysteresis(angleDegrees, lastEmittedOrientation)
        if (resolved == DevicePhysicalOrientation.UNKNOWN) {
            return
        }

        val confidence = computeConfidence(angleDegrees, resolved)
        scheduleDebouncedEmit(resolved, confidence, angleDegrees)
    }

    private fun resolveWithHysteresis(
        angleDegrees: Double,
        previous: DevicePhysicalOrientation,
    ): DevicePhysicalOrientation {
        // Android OrientationEventListener 顺时针角度约定：
        // 0° = 竖屏正向（PORTRAIT_UP）
        // 90° = 顺时针旋转 90°，顶部朝右（LANDSCAPE_RIGHT -> SCREEN_ORIENTATION_REVERSE_LANDSCAPE）
        // 270° = 逆时针旋转 90°，顶部朝左（LANDSCAPE_LEFT -> SCREEN_ORIENTATION_LANDSCAPE）
        if (angularDistance(angleDegrees, 0.0) <= ENTER_HALF_RANGE_DEGREES) {
            return DevicePhysicalOrientation.PORTRAIT_UP
        }
        if (angularDistance(angleDegrees, 270.0) <= ENTER_HALF_RANGE_DEGREES) {
            return DevicePhysicalOrientation.LANDSCAPE_LEFT
        }
        if (angularDistance(angleDegrees, 90.0) <= ENTER_HALF_RANGE_DEGREES) {
            return DevicePhysicalOrientation.LANDSCAPE_RIGHT
        }

        // 滞回死区（±20° 缓冲区间，25° ~ 45°）：维持上一次稳定方向
        return when (previous) {
            DevicePhysicalOrientation.PORTRAIT_UP ->
                if (angularDistance(angleDegrees, 0.0) <= RETAIN_HALF_RANGE_DEGREES) previous
                else DevicePhysicalOrientation.UNKNOWN
            DevicePhysicalOrientation.LANDSCAPE_LEFT ->
                if (angularDistance(angleDegrees, 270.0) <= RETAIN_HALF_RANGE_DEGREES) previous
                else DevicePhysicalOrientation.UNKNOWN
            DevicePhysicalOrientation.LANDSCAPE_RIGHT ->
                if (angularDistance(angleDegrees, 90.0) <= RETAIN_HALF_RANGE_DEGREES) previous
                else DevicePhysicalOrientation.UNKNOWN
            DevicePhysicalOrientation.UNKNOWN -> DevicePhysicalOrientation.UNKNOWN
        }
    }

    private fun computeConfidence(
        angleDegrees: Double,
        orientation: DevicePhysicalOrientation,
    ): Double {
        val targetAngle = when (orientation) {
            DevicePhysicalOrientation.PORTRAIT_UP -> 0.0
            DevicePhysicalOrientation.LANDSCAPE_LEFT -> 270.0
            DevicePhysicalOrientation.LANDSCAPE_RIGHT -> 90.0
            DevicePhysicalOrientation.UNKNOWN -> return 0.0
        }
        val dist = angularDistance(angleDegrees, targetAngle)
        return (1.0 - dist / 45.0).coerceIn(0.0, 1.0)
    }

    private fun scheduleDebouncedEmit(
        orientation: DevicePhysicalOrientation,
        confidence: Double,
        angleDegrees: Double,
    ) {
        runOnMainThread {
            if (!isListening) return@runOnMainThread
            if (orientation == lastEmittedOrientation) {
                pendingOrientation = null
                debounceRunnable?.let { mainHandler.removeCallbacks(it) }
                debounceRunnable = null
                return@runOnMainThread
            }
            if (pendingOrientation == orientation) {
                return@runOnMainThread
            }

            pendingOrientation = orientation
            debounceRunnable?.let { mainHandler.removeCallbacks(it) }
            val runnable = Runnable {
                if (!isListening) return@Runnable
                lastEmittedOrientation = orientation
                pendingOrientation = null
                debounceRunnable = null
                val event = OrientationSensorEvent(
                    orientation = orientation,
                    confidence = confidence,
                    angleDegrees = angleDegrees,
                )
                pluginScope?.launch {
                    try {
                        flutterApi?.onPhysicalOrientationChanged(event)
                    } catch (_: Throwable) {
                    }
                }
            }
            debounceRunnable = runnable
            mainHandler.postDelayed(runnable, DEBOUNCE_DELAY_MS)
        }
    }

    private fun stopSensorListeningInternal() {
        isListening = false
        orientationListener?.disable()
        orientationListener = null
        debounceRunnable?.let { mainHandler.removeCallbacks(it) }
        debounceRunnable = null
        pendingOrientation = null
    }

    private inline fun runOnMainThread(crossinline block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }

    companion object {
        private const val ENTER_HALF_RANGE_DEGREES = 25.0
        private const val RETAIN_HALF_RANGE_DEGREES = 45.0
        private const val DEBOUNCE_DELAY_MS = 300L

        private fun angularDistance(a: Double, b: Double): Double {
            val diff = abs(a - b) % 360.0
            return if (diff > 180.0) 360.0 - diff else diff
        }
    }
}
