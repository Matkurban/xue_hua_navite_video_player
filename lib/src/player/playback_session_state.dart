import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/cast_state.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';

/// 集中持有 `PlaybackSession` 的全部响应式 [FlutterSignal] 与派生 [FlutterComputed] 状态。
///
/// Holds all reactive [FlutterSignal] and [FlutterComputed] properties for a
/// `PlaybackSession`.
class PlaybackSessionState {
  /// 当前高层播放状态（空闲 / 加载中 / 播放中 / 暂停 / 停止 / 播完 / 错误）。
  ///
  /// High-level playback state.
  final FlutterSignal<PlayState> playState = signal(PlayState.idle);

  /// 当前播放进度时间点。
  ///
  /// Current playhead position.
  final FlutterSignal<Duration> position = signal(Duration.zero);

  /// 已缓冲到的媒体时间位置（本地文件或完整缓存命中时等于总时长）。
  ///
  /// Buffered media timeline position.
  final FlutterSignal<Duration> bufferedPosition = signal(Duration.zero);

  /// 媒体总时长（直播或未知时长时为 [Duration.zero]）。
  ///
  /// Total media duration ([Duration.zero] for live or unknown streams).
  final FlutterSignal<Duration> duration = signal(Duration.zero);

  /// 当前播放音量（`0.0..1.0`）。
  ///
  /// Current audio output volume (`0.0..1.0`).
  final FlutterSignal<double> volume = signal(1.0);

  /// 当前播放倍速（默认 `1.0`）。
  ///
  /// Current playback speed multiplier (defaults to `1.0`).
  final FlutterSignal<double> speed = signal(1.0);

  /// 当前是否正在缓冲媒体数据。
  ///
  /// Whether playback is currently buffering.
  final FlutterSignal<bool> isBuffering = signal(false);

  /// 最近一次播放错误的可读描述信息（无错误时为 `null`）。
  ///
  /// Human-readable error message when [playState] is [PlayState.error].
  final FlutterSignal<String?> errorMessage = signal<String?>(null);

  /// 当前加载媒体源的唯一身份标识（网络 URL、`file://` 或 `asset://`）。
  ///
  /// Source identity of the currently opened media.
  final FlutterSignal<String?> currentUrl = signal<String?>(null);

  /// 推断出的媒体 MIME 类型（例如 `'video/mp4'`、`'audio/mpeg'`）。
  ///
  /// Inferred MIME type of the active media source.
  final FlutterSignal<String?> mimeType = signal<String?>(null);

  /// 原生解码器上报的视频画面像素尺寸。
  ///
  /// Decoded video dimensions reported by the native player.
  final FlutterSignal<Size> videoSize = signal<Size>(Size.zero);

  /// 视频元数据的顺时针旋转角度（`0`、`90`、`180`、`270`）。
  ///
  /// Video rotation in degrees reported by the native player.
  final FlutterSignal<int> rotationDegrees = signal<int>(0);

  /// 当前是否处于静音状态。
  ///
  /// Whether audio output is muted.
  final FlutterSignal<bool> muted = signal(false);

  /// 播放结束后是否自动从头循环播放。
  ///
  /// Whether playback automatically loops on completion.
  final FlutterSignal<bool> isLooping = signal(false);

  /// 快进/快退的单次步进时长预设。
  ///
  /// Step duration used by seek-forward and seek-backward operations.
  final FlutterSignal<SkipSecondType> skipSecondType = signal(SkipSecondType.second10);

  /// 画面适应模式（适应 / 铺满 / 拉伸）。
  ///
  /// Native video display scaling mode.
  final FlutterSignal<AspectRatioMode> aspectRatioMode = signal(AspectRatioMode.fit);

  /// 当前是否处于全屏模式。
  ///
  /// Whether fullscreen mode is active.
  final FlutterSignal<bool> isFullscreen = signal(false);

  /// 全屏模式下是否已锁定控件交互与屏幕方向。
  ///
  /// Whether fullscreen controls and screen orientation are currently locked.
  final FlutterSignal<bool> isLocked = signal(false);

  /// 当前屏幕亮度值（`0.0..1.0`）。
  ///
  /// Current normalized screen brightness (`0.0..1.0`).
  final FlutterSignal<double> brightness = signal(1.0);

  /// 当前无线投屏连接状态。
  ///
  /// Current wireless casting connection state.
  final FlutterSignal<CastState> castState = signal(CastState.unavailable);

  /// 正在连接或已连接的远端投屏设备名称。
  ///
  /// Friendly name of the connecting or connected cast receiver.
  final FlutterSignal<String?> castDeviceName = signal<String?>(null);

  /// 当前加载的动态照片解析包（非动态照片时为 `null`）。
  ///
  /// Resolved Live Photo / Motion Photo bundle for the currently loaded media, if any.
  final FlutterSignal<LivePhotoBundle?> livePhotoBundle = signal<LivePhotoBundle?>(null);

  /// 当前加载媒体是否为动态照片（Live Photo / Motion Photo）。
  ///
  /// Whether the currently loaded media is a Live Photo / Motion Photo.
  late final FlutterComputed<bool> isLivePhoto = computed(() {
    return livePhotoBundle.value != null;
  });

  /// 当前动态照片的解析元数据（若有）。
  ///
  /// Parsed metadata for the currently loaded Live Photo / Motion Photo, if any.
  late final FlutterComputed<LivePhotoMetadata?> livePhotoMetadata = computed(() {
    return livePhotoBundle.value?.metadata;
  });

  /// 当前动态照片的静态封面图文件（若有）。
  ///
  /// Extracted or paired still cover image file for the active Live Photo, if any.
  late final FlutterComputed<NaviteFile?> livePhotoStillImage = computed(() {
    return livePhotoBundle.value?.imageFile;
  });

  /// 结合 [rotationDegrees] 计算后的视频展示宽高比（尺寸未知时回退为 `16/9`）。
  ///
  /// Effective display aspect ratio accounting for [rotationDegrees] (defaults to `16/9`).
  late final FlutterComputed<double> videoAspectRatio = computed(() {
    final size = videoSize.value;
    if (size.width <= 0 || size.height <= 0) return 16 / 9;
    final rot = rotationDegrees.value % 360;
    if (rot == 90 || rot == 270) {
      return size.height / size.width;
    }
    return size.width / size.height;
  });

  /// 根据 [mimeType] 判断当前媒体是否为视频类型。
  ///
  /// Whether [mimeType] indicates a video stream.
  late final FlutterComputed<bool> isVideo = computed(() {
    return mimeType.value?.startsWith('video/') ?? false;
  });

  /// 根据 [mimeType] 判断当前媒体是否为纯音频类型。
  ///
  /// Whether [mimeType] indicates an audio stream.
  late final FlutterComputed<bool> isAudio = computed(() {
    return mimeType.value?.startsWith('audio/') ?? false;
  });

  /// 当前是否正处于 [PlayState.playing] 播放态。
  ///
  /// Whether [playState] is currently [PlayState.playing].
  late final FlutterComputed<bool> isPlaying = computed(() {
    return playState.value == PlayState.playing;
  });

  /// 当前已播放进度比例（`position / duration`，总时长为 0 时返回 `0.0`）。
  ///
  /// Playback progress fraction (`0.0` when duration is zero).
  late final FlutterComputed<double> progressPercent = computed(() {
    if (duration.value.inMilliseconds == 0) return 0.0;
    return position.value.inMilliseconds / duration.value.inMilliseconds;
  });

  /// 当前已缓冲进度比例（裁剪至 `0.0..1.0`，供双层缓冲进度条渲染）。
  ///
  /// Buffered progress fraction clamped to `0.0..1.0`.
  late final FlutterComputed<double> bufferedPercent = computed(() {
    if (duration.value.inMilliseconds <= 0) return 0.0;
    return (bufferedPosition.value.inMilliseconds / duration.value.inMilliseconds).clamp(0.0, 1.0);
  });

  /// 当前平台与运行环境是否支持无线投屏。
  ///
  /// Whether the current platform/environment supports wireless casting.
  late final FlutterComputed<bool> isCastSupported = computed(() {
    return castState.value != CastState.unavailable;
  });

  /// 当前是否处于投屏连接中或已连接状态。
  ///
  /// Whether a wireless cast session is currently connecting or connected.
  late final FlutterComputed<bool> isCasting = computed(() {
    final s = castState.value;
    return s == CastState.connecting || s == CastState.connected;
  });

  /// 在单次信号批处理中重置媒体相关状态，同时保留会话级设置（音量、倍速、静音、循环、画面模式、投屏会话等）。
  ///
  /// Resets media-specific signals in a single batch while preserving session
  /// settings (`volume`, `speed`, `muted`, `isLooping`, `aspectRatioMode`, `castState`).
  void resetMediaSignals() {
    batch(() {
      playState.value = PlayState.idle;
      position.value = Duration.zero;
      bufferedPosition.value = Duration.zero;
      duration.value = Duration.zero;
      isBuffering.value = false;
      errorMessage.value = null;
      currentUrl.value = null;
      mimeType.value = null;
      videoSize.value = Size.zero;
      rotationDegrees.value = 0;
      livePhotoBundle.value = null;
    });
  }
}
