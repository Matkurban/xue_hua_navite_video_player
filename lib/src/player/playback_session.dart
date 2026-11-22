import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../cache/video_cache_manager.dart';
import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/cast_state.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';
import '../utils/live_photo_extractor.dart';
import '../utils/mime_detector.dart';
import 'brightness_controller.dart';
import 'channel_player_backend.dart';
import 'fullscreen_coordinator.dart';
import 'local_cast_http_server.dart';
import 'playback_session_state.dart';
import 'player_backend.dart';
import 'player_event.dart';

/// 管理单个播放器完整生命周期（open → ready → playing / paused / stopped / completed / error）
/// 的核心状态机模块。
///
/// 负责将 [PlayerBackend] 发出的原生事件流映射为 [PlaybackSessionState] 中的响应式信号，
/// 协调磁盘缓存固定（pin/unpin）、实况照片自动探测与提取、本地投屏代理、全屏/方向锁定、
/// 循环播放以及 Seek 稳定窗口去抖等逻辑。
///
/// 进程级约束：同一时刻仅允许存在一个活跃的原生 [ChannelPlayerBackend] 会话。
///
/// Deep module owning the `open -> ready -> playing/paused/stopped/completed/error`
/// lifecycle for one playback session. Projects [PlayerBackend] events into
/// reactive signals and enforces the process-wide single active native session
/// invariant.
class PlaybackSession {
  static PlaybackSession? _activeNativeSession;

  /// 当前进程中是否存在活跃的原生 [ChannelPlayerBackend] 会话。
  ///
  /// Whether a native [ChannelPlayerBackend] session is currently active in this process.
  static bool get hasActiveNativeSession => _activeNativeSession != null;

  final PlayerBackend _backend;
  final FullscreenCoordinator _fullscreen;
  final BrightnessController _brightness;
  final LocalCastHttpServer _localCastServer;
  final VideoCacheManager? _cacheManager;
  final PlaybackSessionState _state = PlaybackSessionState();

  StreamSubscription<PlayerEvent>? _eventSubscription;
  StreamSubscription<bool>? _fullscreenExternalSub;
  Timer? _readyFallbackTimer;

  bool _disposed = false;
  bool _holdsNativeSession = false;
  int _openEpoch = 0;
  int _activeEventEpoch = 0;

  bool _hasPlayedSinceOpen = false;
  bool _hasReadySinceOpen = false;
  bool _hasReceivedMetadata = false;
  bool _backendPlaying = false;
  bool _backendBuffering = false;
  bool _isCompleteLocalOrCachedMedia = false;
  Duration _backendDuration = Duration.zero;
  Duration _backendBufferedPosition = Duration.zero;
  String? _pinnedCacheKey;
  double _volumeBeforeMute = 1.0;
  bool _fullscreenLandscape = true;

  /// After [seek], ignore native position events that are still far from the
  /// target so a stale pre-seek tick cannot overwrite the optimistic position.
  int _seekGeneration = 0;
  Duration? _pendingSeekTarget;
  static const int _seekSettleToleranceMs = 900;

  /// 直播流或纯音频流可能永远不汇报正向时长，超过此兜底延迟后自动将加载态转为就绪。
  ///
  /// Fallback delay after which streams that never emit a positive duration
  /// (such as live or audio-only streams) transition out of loading into ready.
  @visibleForTesting
  static Duration readyFallbackDelay = const Duration(seconds: 3);

  /// 当前播放状态信号。
  ///
  /// Reactive signal of the current [PlayState].
  FlutterSignal<PlayState> get playState => _state.playState;

  /// 当前播放位置信号。
  ///
  /// Reactive signal of the current playback position.
  FlutterSignal<Duration> get position => _state.position;

  /// 当前已缓冲位置信号。
  ///
  /// Reactive signal of the buffered playback position.
  FlutterSignal<Duration> get bufferedPosition => _state.bufferedPosition;

  /// 当前媒体总时长信号。
  ///
  /// Reactive signal of the total media duration.
  FlutterSignal<Duration> get duration => _state.duration;

  /// 当前音量信号（`0.0` ~ `1.0`）。
  ///
  /// Reactive signal of the volume in `[0.0, 1.0]`.
  FlutterSignal<double> get volume => _state.volume;

  /// 当前播放倍速信号。
  ///
  /// Reactive signal of the playback speed multiplier.
  FlutterSignal<double> get speed => _state.speed;

  /// 当前是否处于缓冲状态的信号。
  ///
  /// Reactive signal indicating whether the player is buffering.
  FlutterSignal<bool> get isBuffering => _state.isBuffering;

  /// 最近一次错误信息信号；无错时为 `null`。
  ///
  /// Reactive signal holding the latest error message, or `null`.
  FlutterSignal<String?> get errorMessage => _state.errorMessage;

  /// 当前加载媒体源的标识 URL 或路径信号。
  ///
  /// Reactive signal of the currently loaded media URL or identifier.
  FlutterSignal<String?> get currentUrl => _state.currentUrl;

  /// 当前媒体 MIME 类型信号。
  ///
  /// Reactive signal of the detected media MIME type.
  FlutterSignal<String?> get mimeType => _state.mimeType;

  /// 当前视频逻辑分辨率尺寸信号。
  ///
  /// Reactive signal of the decoded video dimensions.
  FlutterSignal<Size> get videoSize => _state.videoSize;

  /// 当前视频旋转角度信号（度）。
  ///
  /// Reactive signal of the video rotation angle in degrees.
  FlutterSignal<int> get rotationDegrees => _state.rotationDegrees;

  /// 当前是否静音的信号。
  ///
  /// Reactive signal indicating whether audio is muted.
  FlutterSignal<bool> get muted => _state.muted;

  /// 当前是否循环播放的信号。
  ///
  /// Reactive signal indicating whether end-of-stream looping is enabled.
  FlutterSignal<bool> get isLooping => _state.isLooping;

  /// 快进/快退步进时长配置信号。
  ///
  /// Reactive signal of the active [SkipSecondType].
  FlutterSignal<SkipSecondType> get skipSecondType => _state.skipSecondType;

  /// 当前画面宽高比填充模式信号。
  ///
  /// Reactive signal of the active [AspectRatioMode].
  FlutterSignal<AspectRatioMode> get aspectRatioMode => _state.aspectRatioMode;

  /// 当前是否全屏的信号。
  ///
  /// Reactive signal indicating whether fullscreen mode is active.
  FlutterSignal<bool> get isFullscreen => _state.isFullscreen;

  /// 当前全屏界面与方向是否已锁定的信号。
  ///
  /// Reactive signal indicating whether fullscreen controls and orientation are locked.
  FlutterSignal<bool> get isLocked => _state.isLocked;

  /// 当前屏幕亮度信号（`0.0` ~ `1.0`）。
  ///
  /// Reactive signal of the screen brightness in `[0.0, 1.0]`.
  FlutterSignal<double> get brightness => _state.brightness;

  /// 当前无线投屏状态信号。
  ///
  /// Reactive signal of the active [CastState].
  FlutterSignal<CastState> get castState => _state.castState;

  /// 当前无线投屏目标设备名称信号。
  ///
  /// Reactive signal of the remote cast device name, if any.
  FlutterSignal<String?> get castDeviceName => _state.castDeviceName;

  /// 当前解析出的实况照片数据包信号。
  ///
  /// Reactive signal of the resolved [LivePhotoBundle], if any.
  FlutterSignal<LivePhotoBundle?> get livePhotoBundle => _state.livePhotoBundle;

  /// 当前加载媒体是否为实况照片的计算信号。
  ///
  /// Computed signal indicating whether the active media is a Live Photo.
  FlutterComputed<bool> get isLivePhoto => _state.isLivePhoto;

  /// 当前实况照片元数据计算信号。
  ///
  /// Computed signal of the active [LivePhotoMetadata], if any.
  FlutterComputed<LivePhotoMetadata?> get livePhotoMetadata => _state.livePhotoMetadata;

  /// 当前实况照片静态封面图计算信号。
  ///
  /// Computed signal of the active Live Photo still image [NaviteFile], if any.
  FlutterComputed<NaviteFile?> get livePhotoStillImage => _state.livePhotoStillImage;

  /// 结合旋转角度计算得到的有效视频显示宽高比信号。
  ///
  /// Computed effective display aspect ratio of the video.
  FlutterComputed<double> get videoAspectRatio => _state.videoAspectRatio;

  /// 当前媒体是否为视频的计算信号。
  ///
  /// Computed signal indicating whether the active media is video.
  FlutterComputed<bool> get isVideo => _state.isVideo;

  /// 当前媒体是否为纯音频的计算信号。
  ///
  /// Computed signal indicating whether the active media is audio-only.
  FlutterComputed<bool> get isAudio => _state.isAudio;

  /// 当前是否处于播放中状态的计算信号。
  ///
  /// Computed signal indicating whether [playState] is [PlayState.playing].
  FlutterComputed<bool> get isPlaying => _state.isPlaying;

  /// 当前播放进度百分比（`0.0` ~ `1.0`）计算信号。
  ///
  /// Computed playback progress percentage in `[0.0, 1.0]`.
  FlutterComputed<double> get progressPercent => _state.progressPercent;

  /// 当前缓冲进度百分比（`0.0` ~ `1.0`）计算信号。
  ///
  /// Computed buffered progress percentage in `[0.0, 1.0]`.
  FlutterComputed<double> get bufferedPercent => _state.bufferedPercent;

  /// 当前环境是否支持无线投屏的计算信号。
  ///
  /// Computed signal indicating whether wireless casting is supported.
  FlutterComputed<bool> get isCastSupported => _state.isCastSupported;

  /// 当前是否处于投屏连接中或已连接状态的计算信号。
  ///
  /// Computed signal indicating whether a cast session is active or connecting.
  FlutterComputed<bool> get isCasting => _state.isCasting;

  /// 创建一个 [PlaybackSession] 实例。
  ///
  /// - [backend]：底层播放传输后端，默认使用 [ChannelPlayerBackend]。
  /// - [fullscreen]：全屏协调器，默认使用 [SystemChromeFullscreenCoordinator]。
  /// - [brightness]：屏幕亮度控制器，默认使用 [ChannelBrightnessController]。
  /// - [localCastServer]：本地文件投屏代理服务，默认创建新的 [LocalCastHttpServer]。
  /// - [cacheManager]：磁盘缓存管理器；当使用默认原生后端且未传入时自动绑定 [VideoCacheManager.instance]。
  ///
  /// Creates a [PlaybackSession] with optional injected collaborators for
  /// [backend], [fullscreen], [brightness], [localCastServer], and [cacheManager].
  PlaybackSession({
    PlayerBackend? backend,
    FullscreenCoordinator? fullscreen,
    BrightnessController? brightness,
    LocalCastHttpServer? localCastServer,
    VideoCacheManager? cacheManager,
  }) : _backend = backend ?? ChannelPlayerBackend(),
       _fullscreen = fullscreen ?? SystemChromeFullscreenCoordinator(),
       _brightness = brightness ?? ChannelBrightnessController(),
       _localCastServer = localCastServer ?? LocalCastHttpServer(),
       _cacheManager =
           cacheManager ??
           (backend == null || backend is ChannelPlayerBackend
               ? VideoCacheManager.instance
               : null) {
    _fullscreenExternalSub = _fullscreen.externalChanges.listen(_onExternalFullscreen);
  }

  /// 原生视频渲染纹理 ID 信号。
  ///
  /// Reactive signal of the native video texture ID provided by [_backend].
  FlutterSignal<int?> get textureId => _backend.textureId;

  /// 初始化原生播放会话、订阅后端事件流并同步初始画面比例与屏幕亮度。
  ///
  /// 若会话已销毁或进程内已有其他活跃原生会话，将抛出 [StateError]。
  ///
  /// Initializes the native backend, subscribes to events, and syncs initial
  /// aspect ratio and brightness. Throws [StateError] if disposed or if another
  /// native session is already active.
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('PlaybackSession has been disposed.');
    }
    _acquireNativeSession();
    // Listen before create() so broadcast events emitted during create are not lost.
    _eventSubscription?.cancel();
    _eventSubscription = _backend.events.listen(_onPlayerEvent);
    try {
      await _backend.create();
    } catch (_) {
      _eventSubscription?.cancel();
      _eventSubscription = null;
      _releaseNativeSession();
      rethrow;
    }
    if (_disposed) return;
    // Sync initial aspect mode to native.
    await _backend.setAspectRatioMode(aspectRatioMode.value);
    try {
      brightness.value = await _brightness.current;
    } catch (_) {}
  }

  void _acquireNativeSession() {
    if (_backend is! ChannelPlayerBackend) return;
    if (_holdsNativeSession) return;
    if (_activeNativeSession != null && _activeNativeSession != this) {
      throw StateError(
        'Process-wide invariant: only one native PlaybackSession may be active. '
        'Dispose the existing controller before creating another.',
      );
    }
    _activeNativeSession = this;
    _holdsNativeSession = true;
  }

  void _releaseNativeSession() {
    if (!_holdsNativeSession) return;
    _holdsNativeSession = false;
    if (_activeNativeSession == this) {
      _activeNativeSession = null;
    }
  }

  void _onPlayerEvent(PlayerEvent event) {
    if (_disposed) return;
    // Cast capability & session state events can arrive during create() before
    // any media is opened, or across openSource() transitions.
    if (event is PlayerCastStateEvent) {
      batch(() {
        castState.value = event.state;
        if (event.state == CastState.notConnected || event.state == CastState.unavailable) {
          castDeviceName.value = null;
        } else if (event.deviceName != null) {
          castDeviceName.value = event.deviceName;
        }
      });
      return;
    }
    // Ignore native events before the first open (e.g. mpv's initial
    // `pause=no` property notification) so a fresh session stays idle.
    if (_openEpoch == 0 || _activeEventEpoch != _openEpoch) return;

    switch (event) {
      case PlayerPlayingEvent(:final playing):
        _handlePlayingEvent(playing);
      case PlayerPositionEvent(:final position):
        if (_hasReadySinceOpen && playState.value != PlayState.error) {
          final pending = _pendingSeekTarget;
          if (pending != null) {
            final deltaMs = (position - pending).inMilliseconds.abs();
            if (deltaMs > _seekSettleToleranceMs) {
              // Stale tick from before the seek completed — drop it.
              break;
            }
            _pendingSeekTarget = null;
          }
          this.position.value = position;
        }
      case PlayerBufferedEvent(:final bufferedPosition):
        if (playState.value != PlayState.error) {
          _backendBufferedPosition = bufferedPosition;
          if (_hasReadySinceOpen) {
            if (_isCompleteLocalOrCachedMedia && duration.value > bufferedPosition) {
              this.bufferedPosition.value = duration.value;
            } else {
              this.bufferedPosition.value = bufferedPosition;
            }
          }
        }
      case PlayerDurationEvent(:final duration):
        _handleDurationEvent(duration);
      case PlayerBufferingEvent(:final buffering):
        if (playState.value != PlayState.error) {
          _backendBuffering = buffering;
          if (_hasReadySinceOpen) {
            isBuffering.value = buffering;
          }
        }
      case PlayerErrorEvent(:final message):
        isBuffering.value = false;
        errorMessage.value = message;
        playState.value = PlayState.error;
      case PlayerCompletedEvent():
        if (_hasPlayedSinceOpen && playState.value != PlayState.error) {
          if (isLooping.value) {
            position.value = Duration.zero;
            playState.value = PlayState.playing;
            unawaited(_restartForLoop(_openEpoch));
          } else {
            playState.value = PlayState.completed;
          }
        }
      case PlayerVideoSizeEvent(:final size, :final rotationDegrees):
        _handleVideoSizeEvent(size, rotationDegrees);
      case PlayerCastStateEvent():
        break;
    }
  }

  Future<void> _restartForLoop(int epoch) async {
    if (_disposed || epoch != _openEpoch) return;
    await _backend.seek(0);
    if (_disposed || epoch != _openEpoch || !isLooping.value) return;
    await _backend.play();
  }

  void _handlePlayingEvent(bool playing) {
    if (playState.value == PlayState.error) return;
    _backendPlaying = playing;
    if (playing) {
      final wasFirstPlay = !_hasPlayedSinceOpen;
      _hasPlayedSinceOpen = true;
      _markReadySinceOpen();
      if (wasFirstPlay && _backendDuration > Duration.zero) {
        duration.value = _backendDuration;
      }
      playState.value = PlayState.playing;
      return;
    }
    if (!_hasReadySinceOpen) {
      if (_hasReceivedMetadata) {
        _markReadySinceOpen();
      }
      return;
    }
    if (playState.value == PlayState.stopped || playState.value == PlayState.completed) {
      return;
    }
    if (isLooping.value && playState.value == PlayState.playing && _hasPlayedSinceOpen) {
      final total = duration.value;
      final pos = position.value;
      if (total > Duration.zero && (total - pos).inMilliseconds <= 150) {
        // Ignore transient playing=false emitted right before PlayerCompletedEvent during loop.
        return;
      }
    }
    if ((_backendBuffering || isBuffering.value) && playState.value == PlayState.playing) {
      return;
    }
    playState.value = PlayState.paused;
  }

  void _handleDurationEvent(Duration reportedDuration) {
    if (playState.value == PlayState.error) return;
    _hasReceivedMetadata = true;
    _backendDuration = reportedDuration;
    if (!_hasReadySinceOpen) {
      _markReadySinceOpen();
    }
    if (_hasReadySinceOpen) {
      duration.value = reportedDuration;
      if (_isCompleteLocalOrCachedMedia && reportedDuration > bufferedPosition.value) {
        bufferedPosition.value = reportedDuration;
      }
    }
  }

  void _handleVideoSizeEvent(Size size, int rotationDegrees) {
    if (playState.value == PlayState.error) return;
    videoSize.value = size;
    this.rotationDegrees.value = rotationDegrees;
    if (size.width > 0 && size.height > 0) {
      _hasReceivedMetadata = true;
      if (!_hasReadySinceOpen) {
        _markReadySinceOpen();
      }
    }
  }

  void _markReadySinceOpen() {
    if (_hasReadySinceOpen) return;
    _hasReadySinceOpen = true;

    if (_backendDuration > Duration.zero) {
      duration.value = _backendDuration;
      if (_isCompleteLocalOrCachedMedia) {
        bufferedPosition.value = _backendDuration;
      }
    }
    if (_backendBufferedPosition > bufferedPosition.value) {
      bufferedPosition.value = _backendBufferedPosition;
    }
    isBuffering.value = _backendBuffering;

    if (!_backendPlaying && playState.value == PlayState.loading) {
      playState.value = PlayState.paused;
    }
  }

  /// 打开并自动播放网络媒体流 [url]。
  ///
  /// Opens and auto-plays a network stream at [url] with optional [cacheKey],
  /// HTTP [headers], and [enableCache] flag.
  Future<void> playNetwork(
    String url, {
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) => openSource(
    VideoSource.network(url, cacheKey: cacheKey, headers: headers, enableCache: enableCache),
    autoPlay: true,
  );

  /// 打开网络媒体流 [url]（不自动播放）。
  ///
  /// Opens a network stream at [url] without starting playback immediately.
  Future<void> openNetwork(
    String url, {
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) => openSource(
    VideoSource.network(url, cacheKey: cacheKey, headers: headers, enableCache: enableCache),
    autoPlay: false,
  );

  /// 打开并自动播放本地文件路径 [path]。
  ///
  /// Opens and auto-plays a local media file at [path].
  Future<void> playFile(String path) => openSource(VideoSource.file(path), autoPlay: true);

  /// 打开本地文件路径 [path]（不自动播放）。
  ///
  /// Opens a local media file at [path] without starting playback immediately.
  Future<void> openFile(String path) => openSource(VideoSource.file(path), autoPlay: false);

  /// 打开并自动播放 Flutter Asset 资源 [assetPath]。
  ///
  /// Opens and auto-plays a Flutter asset at [assetPath] from optional [bundle].
  Future<void> playAsset(String assetPath, {AssetBundle? bundle}) =>
      openSource(VideoSource.asset(assetPath, bundle: bundle), autoPlay: true);

  /// 打开 Flutter Asset 资源 [assetPath]（不自动播放）。
  ///
  /// Opens a Flutter asset at [assetPath] without starting playback immediately.
  Future<void> openAsset(String assetPath, {AssetBundle? bundle}) =>
      openSource(VideoSource.asset(assetPath, bundle: bundle), autoPlay: false);

  /// 打开并自动播放实况照片源 [source]，可选通过 [loop] 覆盖循环状态。
  ///
  /// Opens and auto-plays a [LivePhotoSource], optionally setting [isLooping] via [loop].
  Future<void> playLivePhoto(LivePhotoSource source, {bool? loop}) async {
    if (loop != null) {
      isLooping.value = loop;
    }
    await openSource(VideoSource.livePhoto(source), autoPlay: true);
  }

  /// 打开实况照片源 [source]（不自动播放），可选通过 [loop] 覆盖循环状态。
  ///
  /// Opens a [LivePhotoSource] without auto-playing, optionally setting [isLooping].
  Future<void> openLivePhoto(LivePhotoSource source, {bool? loop}) async {
    if (loop != null) {
      isLooping.value = loop;
    }
    await openSource(VideoSource.livePhoto(source), autoPlay: false);
  }

  /// 打开并自动播放任意 [VideoSource]。
  ///
  /// Opens and auto-plays any [VideoSource].
  Future<void> playSource(VideoSource source) => openSource(source, autoPlay: true);

  /// 打开并加载任意 [VideoSource]：执行会话重置、实况照片解析、磁盘缓存/本地投屏路由解析，
  /// 随后通知原生后端打开并在 [autoPlay] 为 `true` 时开始播放。
  ///
  /// 使用递增的 `_openEpoch` 防护并发切源竞态，确保旧请求的异步结果不会污染新会话状态。
  ///
  /// Opens any [VideoSource]: resets media signals, resolves Live Photo bundles
  /// or cache/cast URLs, configures the backend, and starts playback when
  /// [autoPlay] is `true`. Uses an epoch counter to guard against concurrent opens.
  Future<void> openSource(VideoSource source, {bool autoPlay = false}) async {
    if (_disposed) return;

    final epoch = ++_openEpoch;
    try {
      reset();

      final identity = source.identity;
      currentUrl.value = identity;
      mimeType.value = MimeDetector.detect(identity);
      playState.value = PlayState.loading;

      LivePhotoBundle? resolvedBundle;
      String mediaUrl;
      VideoSource effectiveMediaSource = source;

      if (source is LivePhotoVideoSource) {
        resolvedBundle = await LivePhotoExtractor.resolve(source.livePhoto);
        if (_disposed || epoch != _openEpoch) return;
        livePhotoBundle.value = resolvedBundle;
        effectiveMediaSource = resolvedBundle.videoSource;
        mediaUrl = resolvedBundle.nativeVideoUrl;
        final detectedVideoMime = MimeDetector.detect(mediaUrl);
        mimeType.value = detectedVideoMime == 'application/octet-stream'
            ? 'video/mp4'
            : detectedVideoMime;
      } else if (MimeDetector.isCandidateLivePhotoContainer(identity)) {
        // Automatically detect if a .jpg/.jpeg/.heic/.pvt source is a Motion Photo / Live Photo.
        resolvedBundle = await LivePhotoExtractor.tryExtractFromVideoSource(source);
        if (_disposed || epoch != _openEpoch) return;
        if (resolvedBundle != null) {
          livePhotoBundle.value = resolvedBundle;
          effectiveMediaSource = resolvedBundle.videoSource;
          mediaUrl = resolvedBundle.nativeVideoUrl;
          final detectedVideoMime = MimeDetector.detect(mediaUrl);
          mimeType.value = detectedVideoMime == 'application/octet-stream'
              ? 'video/mp4'
              : detectedVideoMime;
        } else {
          // Align with historical behavior: open the container URL and let the
          // native player decide (Apple AVPlayer can display HEIC stills).
          mediaUrl = await source.resolveToNativeUrl();
        }
      } else {
        mediaUrl = await source.resolveToNativeUrl();
      }
      if (_disposed || epoch != _openEpoch) return;

      String? castUrl;
      String? cacheKey;
      Map<String, String>? headers;
      bool? enableCache;

      if (effectiveMediaSource is NetworkVideoSource) {
        await _stopLocalCastServerQuietly();
        final cacheMgr = _cacheManager;
        if (cacheMgr != null) {
          final cacheTarget = await cacheMgr.resolveForPlayback(effectiveMediaSource);
          if (_disposed || epoch != _openEpoch) return;
          mediaUrl = cacheTarget.playUrl;
          castUrl = cacheTarget.castUrl;
          cacheKey = cacheTarget.cacheKey;
          headers = cacheTarget.headers;
          enableCache = cacheTarget.enableCache;
          _isCompleteLocalOrCachedMedia =
              cacheTarget.isCompleteFileHit || mediaUrl.startsWith('file://');
          if (cacheKey != null && cacheKey.isNotEmpty) {
            _pinnedCacheKey = cacheKey;
            cacheMgr.pin(cacheKey);
          }
        } else {
          mediaUrl = await effectiveMediaSource.resolveToNativeUrl();
          castUrl = effectiveMediaSource.url;
          cacheKey = effectiveMediaSource.cacheKey;
          headers = effectiveMediaSource.headers;
          enableCache = effectiveMediaSource.enableCache;
          _isCompleteLocalOrCachedMedia = false;
        }
      } else {
        _isCompleteLocalOrCachedMedia = mediaUrl.startsWith('file://');
        castUrl = await _resolveCastUrl(effectiveMediaSource, mediaUrl);
        if (_disposed || epoch != _openEpoch) return;
      }

      await _backend.open(
        mediaUrl,
        castUrl: castUrl,
        cacheKey: cacheKey,
        headers: headers,
        enableCache: enableCache,
      );
      if (_disposed || epoch != _openEpoch) return;
      _activeEventEpoch = epoch;
      _scheduleReadyFallback(epoch);

      // Re-apply session volume/speed/aspect; native players usually reset on open.
      await _backend.setVolume(muted.value ? 0 : volume.value);
      if (_disposed || epoch != _openEpoch) return;
      await _backend.setSpeed(speed.value);
      if (_disposed || epoch != _openEpoch) return;
      await _backend.setAspectRatioMode(aspectRatioMode.value);
      if (_disposed || epoch != _openEpoch) return;

      if (autoPlay) {
        await _backend.play();
      }
    } catch (e) {
      if (_disposed || epoch != _openEpoch) return;
      errorMessage.value = e.toString();
      playState.value = PlayState.error;
    }
  }

  Future<String?> _resolveCastUrl(VideoSource source, String mediaUrl) async {
    try {
      if (!source.isNetwork) {
        return await _localCastServer.serveLocalFileUrl(mediaUrl, mimeType: mimeType.value);
      }
      await _localCastServer.stop();
    } catch (_) {
      // Never allow local cast HTTP server setup to block normal video playback.
    }
    return null;
  }

  Future<void> _stopLocalCastServerQuietly() async {
    try {
      await _localCastServer.stop();
    } catch (_) {}
  }

  void _releasePinnedCacheKey() {
    final key = _pinnedCacheKey;
    if (key != null) {
      _pinnedCacheKey = null;
      _cacheManager?.unpin(key);
    }
  }

  /// 开始或恢复播放；若已播完则先跳转至 `0` 再播放。
  ///
  /// Starts or resumes playback, rewinding to zero first if [playState] is [PlayState.completed].
  Future<void> play() async {
    if (_disposed) return;
    if (playState.value == PlayState.completed) {
      await _backend.seek(0);
      if (_disposed) return;
      position.value = Duration.zero;
    }
    await _backend.play();
  }

  /// 暂停播放。
  ///
  /// Pauses playback.
  Future<void> pause() async {
    if (_disposed) return;
    await _backend.pause();
  }

  /// 切换播放或暂停状态。
  ///
  /// Toggles between playing and paused states.
  Future<void> playOrPause() async {
    if (_disposed) return;
    if (isPlaying.value) {
      await _backend.pause();
    } else {
      await play();
    }
  }

  /// 跳转到目标位置 [targetPosition]，并启用代际与稳定容差窗口防止旧进度回调回跳。
  ///
  /// Seeks to [targetPosition] (clamped to `[Duration.zero, duration]`) while
  /// filtering stale pre-seek native ticks until the backend settles near target.
  Future<void> seek(Duration targetPosition) async {
    if (_disposed) return;
    final total = duration.value;
    var clamped = targetPosition < Duration.zero ? Duration.zero : targetPosition;
    if (total > Duration.zero && clamped > total) {
      clamped = total;
    }
    final generation = ++_seekGeneration;
    _pendingSeekTarget = clamped;
    await _backend.seek(clamped.inMilliseconds);
    if (_disposed) return;
    // A newer seek may have started while we awaited the backend.
    if (generation != _seekGeneration) return;
    position.value = clamped;
    // If the user seeks away from the end while in completed state, transition
    // to paused so that subsequent play() resumes from the seeked position
    // instead of resetting back to 00:00.
    if (playState.value == PlayState.completed && (total == Duration.zero || clamped < total)) {
      playState.value = _backendPlaying ? PlayState.playing : PlayState.paused;
    }
  }

  /// 设置播放音量 [value]（自动钳制到 `0.0..1.0`）并同步更新静音状态。
  ///
  /// Sets volume to [value] clamped in `[0.0, 1.0]` and synchronizes [muted].
  Future<void> setVolume(double value) async {
    if (_disposed) return;
    final clamped = value.clamp(0.0, 1.0);
    await _backend.setVolume(clamped);
    volume.value = clamped;
    if (clamped > 0 && muted.value) {
      muted.value = false;
    } else if (clamped == 0) {
      muted.value = true;
    }
  }

  /// 设置静音状态 [value]；取消静音时自动恢复静音前的有效音量。
  ///
  /// Sets mute state to [value], restoring the last non-zero volume on unmute.
  Future<void> setMuted(bool value) async {
    if (_disposed) return;
    if (value) {
      if (!muted.value) {
        _volumeBeforeMute = volume.value > 0 ? volume.value : 1.0;
      }
      muted.value = true;
      await _backend.setVolume(0);
      volume.value = 0;
    } else {
      muted.value = false;
      final restore = _volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0;
      await _backend.setVolume(restore);
      volume.value = restore;
    }
  }

  /// 切换静音状态。
  ///
  /// Toggles [muted].
  Future<void> toggleMuted() => setMuted(!muted.value);

  /// 设置播完自动循环开关 [looping]。
  ///
  /// Sets whether playback loops automatically upon completion.
  void setLooping(bool looping) {
    if (_disposed) return;
    isLooping.value = looping;
  }

  /// 切换播完自动循环开关。
  ///
  /// Toggles [isLooping].
  void toggleLooping() => setLooping(!isLooping.value);

  /// 更新快进/快退步进时长枚举 [type]。
  ///
  /// Updates [skipSecondType] to [type].
  void setSkipSecondType(SkipSecondType type) {
    skipSecondType.value = type;
  }

  /// 向前快进一个 [skipSecondType] 步长。
  ///
  /// Seeks forward by [skipSecondType].
  Future<void> seekForward() => _seekBy(skipSecondType.value.duration);

  /// 向后快退一个 [skipSecondType] 步长。
  ///
  /// Seeks backward by [skipSecondType].
  Future<void> seekBackward() => _seekBy(-skipSecondType.value.duration);

  Future<void> _seekBy(Duration delta) async {
    if (_disposed) return;
    var target = position.value + delta;
    if (target < Duration.zero) target = Duration.zero;
    final total = duration.value;
    if (total > Duration.zero && target > total) target = total;
    await seek(target);
  }

  /// 设置画面填充比例模式 [mode] 并下发至原生后端。
  ///
  /// Sets the video [AspectRatioMode] and forwards it to the backend.
  Future<void> setAspectRatioMode(AspectRatioMode mode) async {
    if (_disposed) return;
    aspectRatioMode.value = mode;
    await _backend.setAspectRatioMode(mode);
  }

  /// 将当前视频渲染视图尺寸与像素密度同步至原生后端。
  ///
  /// - [width]：逻辑宽度（需大于 0）。
  /// - [height]：逻辑高度（需大于 0）。
  /// - [devicePixelRatio]：设备像素比。
  ///
  /// Reports the rendered viewport [width], [height], and [devicePixelRatio] to the backend.
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) async {
    if (_disposed) return;
    if (width <= 0 || height <= 0) return;
    await _backend.setVideoViewSize(
      width: width,
      height: height,
      devicePixelRatio: devicePixelRatio,
    );
  }

  /// 弹出操作系统原生无线投屏 / 路由选择器。
  ///
  /// Presents the operating system's native wireless cast / route picker.
  Future<void> showCastPicker() async {
    if (_disposed) return;
    await _backend.showCastPicker();
  }

  /// 断开当前无线投屏会话并恢复本地播放。
  ///
  /// Disconnects the active wireless cast session and returns playback locally.
  Future<void> stopCasting() async {
    if (_disposed) return;
    await _backend.stopCasting();
  }

  /// 进入全屏模式，同步当前屏幕亮度并通知 [_fullscreen] 协调器执行平台切换。
  /// UI 契约详见 [VideoPlayerController.enterFullscreen]。
  ///
  /// Enters fullscreen mode, refreshes [brightness], and delegates platform
  /// fullscreen transitions to [_fullscreen]. See [VideoPlayerController.enterFullscreen].
  Future<void> enterFullscreen() async {
    if (_disposed || isFullscreen.value) return;
    final bool landscape = videoAspectRatio.value > 1.0;
    _fullscreenLandscape = landscape;
    isLocked.value = false;
    isFullscreen.value = true;
    try {
      brightness.value = await _brightness.current;
    } catch (_) {}
    await _fullscreen.enter(landscapeVideo: landscape);
  }

  /// 退出全屏模式并重置锁定状态。
  ///
  /// Exits fullscreen mode and clears [isLocked].
  Future<void> exitFullscreen() async {
    if (_disposed || !isFullscreen.value) return;
    isLocked.value = false;
    isFullscreen.value = false;
    await _fullscreen.exit();
  }

  /// 切换全屏状态。
  ///
  /// Toggles between [enterFullscreen] and [exitFullscreen].
  Future<void> toggleFullscreen() async {
    if (isFullscreen.value) {
      await exitFullscreen();
    } else {
      await enterFullscreen();
    }
  }

  /// 锁定或解锁全屏控制界面及设备方向；非全屏状态下始终保持未锁定。
  ///
  /// - [locked]：是否锁定。
  /// - [lockedOrientation]：锁定时可选指定的固定方向。
  ///
  /// Locks or unlocks fullscreen controls and device orientation.
  Future<void> setLocked(bool locked, {DeviceOrientation? lockedOrientation}) async {
    if (_disposed) return;
    if (!isFullscreen.value) {
      isLocked.value = false;
      return;
    }
    if (isLocked.value == locked) return;
    isLocked.value = locked;
    await _fullscreen.setOrientationLocked(
      locked: locked,
      landscapeVideo: _fullscreenLandscape,
      lockedOrientation: lockedOrientation,
    );
  }

  /// 锁定全屏控制与屏幕方向，可选指定 [lockedOrientation]。
  ///
  /// Locks fullscreen controls and orientation, optionally pinning [lockedOrientation].
  Future<void> lock({DeviceOrientation? lockedOrientation}) =>
      setLocked(true, lockedOrientation: lockedOrientation);

  /// 解锁全屏控制并恢复双向重力感应旋转。
  ///
  /// Unlocks fullscreen controls and restores gravity-driven bidirectional rotation.
  Future<void> unlock() => setLocked(false);

  /// 在全屏状态下切换锁定状态。
  ///
  /// Toggles [isLocked] while in fullscreen.
  Future<void> toggleLocked({DeviceOrientation? lockedOrientation}) =>
      setLocked(!isLocked.value, lockedOrientation: lockedOrientation);

  /// 设置屏幕亮度 [value]（自动钳制在 `0.0..1.0`）并更新 [brightness] 信号。
  ///
  /// Sets screen brightness to [value] (clamped to `[0.0, 1.0]`).
  Future<void> setBrightness(double value) async {
    if (_disposed) return;
    final double clamped = value.clamp(0.0, 1.0);
    await _brightness.setBrightness(clamped);
    brightness.value = clamped;
  }

  /// 设置播放倍速 [value] 并更新 [speed] 信号。
  ///
  /// Sets the playback speed multiplier to [value].
  Future<void> setSpeed(double value) async {
    if (_disposed) return;
    await _backend.setSpeed(value);
    speed.value = value;
  }

  /// 暂停播放并将 [playState] 置为 [PlayState.stopped]。
  ///
  /// Pauses playback and sets [playState] to [PlayState.stopped].
  Future<void> stop() async {
    if (_disposed) return;
    await _backend.pause();
    playState.value = PlayState.stopped;
  }

  /// 截取当前播放帧为 PNG 格式的 [NaviteFile]。
  ///
  /// - [savePath]：可选保存路径。
  /// - 异常：会话已销毁或尚未加载媒体时抛出 [StateError]。
  ///
  /// Captures the current playback frame as a PNG [NaviteFile]. Throws
  /// [StateError] if disposed or if no media is currently loaded.
  Future<NaviteFile> takeSnapshot({String? savePath}) async {
    if (_disposed) {
      throw StateError('PlaybackSession has been disposed.');
    }
    if (currentUrl.value == null) {
      throw StateError('No media is currently loaded.');
    }
    return _backend.takeSnapshot(savePath: savePath);
  }

  void _onExternalFullscreen(bool fullscreen) {
    if (_disposed) return;
    if (isFullscreen.value == fullscreen) return;
    if (!fullscreen) {
      isLocked.value = false;
    }
    isFullscreen.value = fullscreen;
  }

  /// 销毁当前会话、释放进程级原生槽位、退出全屏、取消全部订阅与定时器并释放后端资源。
  ///
  /// Disposes this session, synchronously frees the process-wide native slot,
  /// exits fullscreen if active, cancels subscriptions/timers, and tears down the backend.
  Future<void> dispose() async {
    if (_disposed) return;
    // Mark disposed and free the process-wide native slot synchronously so a
    // newly pushed route can initialize even while this Future still awaits
    // fullscreen exit / backend teardown (Widget.dispose cannot await).
    _disposed = true;
    _openEpoch++;
    _releasePinnedCacheKey();
    _releaseNativeSession();
    isLocked.value = false;
    if (isFullscreen.value) {
      try {
        await _fullscreen.exit();
      } catch (_) {}
      isFullscreen.value = false;
    }
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = null;
    _fullscreenExternalSub?.cancel();
    _fullscreenExternalSub = null;
    _fullscreen.dispose();
    _eventSubscription?.cancel();
    _eventSubscription = null;
    await _localCastServer.stop();
    await _backend.dispose();
    castState.value = CastState.unavailable;
    castDeviceName.value = null;
  }

  void _scheduleReadyFallback(int epoch) {
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = Timer(readyFallbackDelay, () {
      if (_disposed || epoch != _openEpoch) return;
      if (!_hasReadySinceOpen && playState.value == PlayState.loading) {
        _markReadySinceOpen();
      }
    });
  }

  /// 重置媒体级状态信号、取消就绪兜底定时器并解除当前缓存键固定。
  ///
  /// Resets media-scoped signals, cancels pending fallback timers, and unpins
  /// any active cache key.
  void reset() {
    _releasePinnedCacheKey();
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = null;
    _hasPlayedSinceOpen = false;
    _hasReadySinceOpen = false;
    _hasReceivedMetadata = false;
    _backendPlaying = false;
    _backendBuffering = false;
    _isCompleteLocalOrCachedMedia = false;
    _backendDuration = Duration.zero;
    _backendBufferedPosition = Duration.zero;
    _state.resetMediaSignals();
  }
}
