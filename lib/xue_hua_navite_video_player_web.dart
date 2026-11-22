import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as html;

import 'src/bridge/video_player_host_bridge.dart';
import 'src/pigeon/player_api.g.dart';
import 'src/web/web_media_probe_service.dart';
import 'src/web/web_remote_playback_controller.dart';

/// Web 平台视频播放器插件实现，基于 HTML5 `<video>` 元素与 W3C Remote Playback API。
///
/// 直接在 Dart 侧实现 [VideoPlayerHostBridge]，无需经过原生平台通道；同时复用单一长生命周期
/// `<video>` 元素以保证 `HtmlElementView` 工厂在多次 `dispose → create` 周期中始终有效。
///
/// Web platform plugin implementation backed by an HTML5 `<video>` element and
/// the W3C Remote Playback API. Implements [VideoPlayerHostBridge] directly in
/// Dart without platform channels.
class XueHuaNaviteVideoPlayerWeb implements VideoPlayerHostBridge {
  html.HTMLVideoElement? _videoElement;
  Timer? _positionTimer;
  final StreamController<PlayerEventData> _eventController =
      StreamController<PlayerEventData>.broadcast();
  bool _viewRegistered = false;

  late final WebRemotePlaybackController _remotePlayback = WebRemotePlaybackController(
    onStateChanged: (state, {deviceName}) {
      _sendEvent(
        PlayerEventData(
          kind: NativePlayerEventType.castState,
          castState: _toNativeCastState(state),
          castDeviceName: deviceName,
        ),
      );
    },
  );

  /// Flutter Web 插件自动注册入口，将 [VideoPlayerHostBridge.instance] 指向当前 Web 实现。
  ///
  /// - [registrar]：Flutter Web 插件注册器实例。
  ///
  /// Registers the Web plugin by assigning [XueHuaNaviteVideoPlayerWeb] to
  /// [VideoPlayerHostBridge.instance].
  static void registerWith(Registrar registrar) {
    VideoPlayerHostBridge.instance = XueHuaNaviteVideoPlayerWeb();
  }

  /// Web 播放器事件广播流（状态、进度、缓冲、时长、尺寸、错误、投屏状态）。
  ///
  /// Broadcast stream of [PlayerEventData] emitted by the HTML5 `<video>` element.
  @override
  Stream<PlayerEventData> get events => _eventController.stream;

  /// Web 端全屏事件由浏览器 Fullscreen API 协调器单独监听，此处返回空流。
  ///
  /// Empty stream on Web; browser fullscreen changes are observed by the Web fullscreen coordinator.
  @override
  Stream<bool> get fullscreenEvents => const Stream<bool>.empty();

  void _sendEvent(PlayerEventData event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  static NativeCastState _toNativeCastState(String raw) {
    return switch (raw) {
      'notConnected' => NativeCastState.notConnected,
      'connecting' => NativeCastState.connecting,
      'connected' => NativeCastState.connected,
      'disconnecting' => NativeCastState.disconnecting,
      _ => NativeCastState.unavailable,
    };
  }

  /// 创建或复用 HTML5 `<video>` 元素并注册 `xue-hua-navite-video-player-web` 平台视图工厂。
  ///
  /// - 返回值：固定返回纹理占位 ID `0`。
  ///
  /// Creates or reuses the `<video>` element, registers the platform view
  /// factory once, and returns `0`.
  @override
  Future<int> create() async {
    // Reuse a long-lived <video> so the registered platform-view factory
    // always returns a live element across dispose → create cycles.
    _videoElement ??= html.HTMLVideoElement()
      ..crossOrigin = 'anonymous'
      ..playsInline = true
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.setProperty('object-fit', 'contain')
      ..style.setProperty('pointer-events', 'none')
      ..style.backgroundColor = 'black'
      ..autoplay = false;

    if (!_viewRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(
        'xue-hua-navite-video-player-web',
        (int viewId) => _videoElement!,
      );
      _viewRegistered = true;
      _setupListeners(_videoElement!);
    } else {
      // Re-emit current cast state on subsequent session creation.
      _remotePlayback.emitCurrentState();
    }

    return 0;
  }

  /// 将媒体地址加载到 HTML5 `<video>` 元素并触发重新加载。
  ///
  /// 对 `blob:` 与 `data:` URL 自动移除 `crossorigin` 属性，对远程 HTTP(S) URL 保持
  /// `crossOrigin = 'anonymous'` 以支持 Canvas 截图。
  /// - [request]：包含媒体 URL 等信息的打开请求对象。
  ///
  /// Loads [request] into the `<video>` element, adjusting CORS attributes for
  /// `blob:`/`data:` URLs versus remote HTTP(S) streams.
  @override
  Future<void> open(OpenMediaRequest request) async {
    final video = _videoElement;
    if (video == null) return;
    final url = request.url;
    // Blob URLs and data: URLs do not need anonymous CORS mode, whereas remote
    // http(s) URLs keep crossOrigin='anonymous' for canvas snapshots.
    if (url.startsWith('blob:') || url.startsWith('data:')) {
      video.removeAttribute('crossorigin');
    } else {
      video.crossOrigin = 'anonymous';
    }
    video.src = url;
    video.load();
    _sendEvent(PlayerEventData(kind: NativePlayerEventType.playing, boolValue: false));
    _sendEvent(PlayerEventData(kind: NativePlayerEventType.buffering, boolValue: true));
  }

  /// 开始或恢复 HTML5 `<video>` 播放；若因浏览器自动播放策略被拦截，会自动尝试静音降级重试。
  ///
  /// Starts or resumes playback on `<video>`, automatically retrying muted if
  /// blocked by browser autoplay policies.
  @override
  Future<void> play() async {
    final video = _videoElement;
    if (video == null) return;
    if (video.ended) {
      video.currentTime = 0;
    }
    unawaited(
      video.play().toDart.catchError((Object error) {
        // If unmuted autoplay (e.g. LivePhoto hover / autoPlayOnce / loop)
        // is blocked by browser policy, automatically mute and retry so
        // Live Photos and inline previews still play smoothly on Web.
        final errStr = error.toString();
        if (!video.muted && (errStr.contains('NotAllowedError') || errStr.contains('interact'))) {
          video.muted = true;
          return video.play().toDart.catchError((Object retryErr) {
            _emitAutoplayFailure('Autoplay blocked: $retryErr');
            return null;
          });
        }
        _emitAutoplayFailure('Autoplay blocked: $error');
        return null;
      }),
    );
  }

  void _emitAutoplayFailure(String message) {
    _sendEvent(PlayerEventData(kind: NativePlayerEventType.playing, boolValue: false));
    _sendEvent(PlayerEventData(kind: NativePlayerEventType.buffering, boolValue: false));
    _sendEvent(PlayerEventData(kind: NativePlayerEventType.error, message: message));
  }

  /// 暂停 HTML5 `<video>` 播放。
  ///
  /// Pauses the `<video>` element.
  @override
  Future<void> pause() async {
    _videoElement?.pause();
  }

  /// 跳转到指定毫秒位置 [positionMs]。
  ///
  /// Seeks `<video>.currentTime` to [positionMs] milliseconds.
  @override
  Future<void> seek(int positionMs) async {
    final video = _videoElement;
    if (video != null) {
      video.currentTime = positionMs / 1000.0;
    }
  }

  /// 设置音量 [volume]（`0.0` ~ `1.0`）并同步 DOM `muted` 属性。
  ///
  /// Sets `<video>.volume` (clamped to `[0.0, 1.0]`) and syncs `<video>.muted`.
  @override
  Future<void> setVolume(double volume) async {
    final video = _videoElement;
    if (video != null) {
      final clamped = volume.clamp(0.0, 1.0);
      video.volume = clamped;
      // Sync the DOM `muted` property so muted playback satisfies browser autoplay policies.
      video.muted = clamped <= 0.0;
    }
  }

  /// 设置播放倍速 [speed]。
  ///
  /// Sets `<video>.playbackRate` to [speed].
  @override
  Future<void> setSpeed(double speed) async {
    final video = _videoElement;
    if (video != null) {
      video.playbackRate = speed;
    }
  }

  /// 通过 CSS `object-fit` 应用视频宽高比填充模式 [mode]。
  ///
  /// Maps [mode] to CSS `object-fit` (`contain`, `cover`, or `fill`).
  @override
  Future<void> setAspectRatioMode(NativeAspectRatioMode mode) async {
    final fit = switch (mode) {
      NativeAspectRatioMode.fill => 'cover',
      NativeAspectRatioMode.stretch => 'fill',
      NativeAspectRatioMode.fit => 'contain',
    };
    _videoElement?.style.setProperty('object-fit', fit);
  }

  /// Web 端由浏览器 CSS 自适应布局，此方法为空实现。
  ///
  /// No-op on Web because CSS sizing manages the `<video>` viewport.
  @override
  Future<void> setVideoViewSize(double width, double height, double devicePixelRatio) async {}

  /// 调起浏览器 W3C Remote Playback 投屏设备选择器。
  ///
  /// Prompts the browser's W3C Remote Playback picker.
  @override
  Future<void> showCastPicker() => _remotePlayback.showPicker(_videoElement);

  /// 断开浏览器 W3C Remote Playback 投屏连接。
  ///
  /// Disconnects an active W3C Remote Playback session.
  @override
  Future<void> stopCasting() => _remotePlayback.stopCasting(_videoElement);

  /// 停止播放与进度轮询并清空 `src`（保留 `<video>` 元素供后续会话复用）。
  ///
  /// Stops playback and timers and clears `src` while keeping the `<video>`
  /// element alive for future sessions.
  @override
  Future<void> dispose() async {
    _stopPositionTimer();
    final video = _videoElement;
    if (video == null) return;
    video.pause();
    video.removeAttribute('src');
    // Keep the element alive for the registered HtmlElementView factory.
    try {
      video.load();
    } catch (_) {}
  }

  /// Web 浏览器不支持读取系统屏幕亮度，固定返回 `1.0`。
  ///
  /// Returns `1.0` on Web where OS screen brightness is inaccessible.
  @override
  Future<double> getBrightness() async => 1.0;

  /// Web 浏览器不支持修改系统屏幕亮度，为空实现。
  ///
  /// No-op on Web where OS screen brightness cannot be modified.
  @override
  Future<void> setBrightness(double value) async {}

  /// Web 端全屏由浏览器 Fullscreen API 协调器管理，此方法为空实现。
  ///
  /// No-op on Web; handled by the browser fullscreen coordinator.
  @override
  Future<void> setWindowFullscreen(bool value) async {}

  /// 使用 HTML5 Canvas 截取当前 `<video>` 画面帧。
  ///
  /// Captures the current `<video>` frame via [WebMediaProbeService.takeSnapshot].
  @override
  Future<SnapshotData?> takeSnapshot() async => WebMediaProbeService.takeSnapshot(_videoElement);

  /// 使用离屏 `<video>` 探测指定媒体的总时长（毫秒）。
  ///
  /// Probes total duration in milliseconds via [WebMediaProbeService.getDuration].
  @override
  Future<int?> getDuration(DurationProbeRequest request) =>
      WebMediaProbeService.getDuration(request);

  /// 使用离屏 `<video>` 与 Canvas 抽取封面候选帧列表。
  ///
  /// Extracts candidate cover frames via [WebMediaProbeService.extractCovers].
  @override
  Future<List<CoverFrameData>> extractCovers(CoverExtractRequest request) =>
      WebMediaProbeService.extractCovers(request);

  /// Web 端缓存由内存 Blob 引擎处理，原生侧缓存配置为空实现。
  ///
  /// No-op on Web; handled by the Dart-side Web Blob cache engine.
  @override
  Future<void> configureCache(CacheConfigRequest request) async {}

  /// Web 端预热由内存 Blob 引擎处理，此处为空实现。
  ///
  /// No-op on Web; handled by the Dart-side Web Blob cache engine.
  @override
  Future<void> precache(PrecacheRequest request) async {}

  /// Web 端取消预热由内存 Blob 引擎处理，此处为空实现。
  ///
  /// No-op on Web; handled by the Dart-side Web Blob cache engine.
  @override
  Future<void> cancelPrecache(String cacheKey) async {}

  /// Web 端缓存命中判断由内存 Blob 引擎处理，原生桥接固定返回 `false`。
  ///
  /// Always returns `false` on Web; cache lookups run in the Web Blob cache engine.
  @override
  Future<bool> isCached(CacheEntryRequest request) async => false;

  /// Web 端缓存体积统计由内存 Blob 引擎处理，原生桥接固定返回 `0`。
  ///
  /// Always returns `0` on Web; cache sizing runs in the Web Blob cache engine.
  @override
  Future<int> getCacheSize(String? cacheDir) async => 0;

  /// Web 端单条缓存删除由内存 Blob 引擎处理，此处为空实现。
  ///
  /// No-op on Web; handled by the Dart-side Web Blob cache engine.
  @override
  Future<void> removeCache(CacheEntryRequest request) async {}

  /// Web 端清空缓存由内存 Blob 引擎处理，此处为空实现。
  ///
  /// No-op on Web; handled by the Dart-side Web Blob cache engine.
  @override
  Future<void> clearCache(String? cacheDir) async {}

  /// Web 端缓存键固定由内存 Blob 引擎处理，此处为空实现。
  ///
  /// No-op on Web; handled by the Dart-side Web Blob cache engine.
  @override
  Future<void> pinCacheKey(String cacheKey) async {}

  /// Web 端解除缓存键固定由内存 Blob 引擎处理，此处为空实现。
  ///
  /// No-op on Web; handled by the Dart-side Web Blob cache engine.
  @override
  Future<void> unpinCacheKey(String cacheKey) async {}

  void _setupListeners(html.HTMLVideoElement video) {
    video.addEventListener(
      'loadedmetadata',
      ((html.Event e) {
        if (video.duration.isFinite && video.duration > 0) {
          _sendEvent(
            PlayerEventData(
              kind: NativePlayerEventType.duration,
              intValue: (video.duration * 1000).toInt(),
            ),
          );
        }
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.buffering, boolValue: false));
        final vw = video.videoWidth;
        final vh = video.videoHeight;
        if (vw > 0 && vh > 0) {
          _sendEvent(
            PlayerEventData(
              kind: NativePlayerEventType.videoSize,
              width: vw.toDouble(),
              height: vh.toDouble(),
              rotationDegrees: 0,
            ),
          );
        }
        if (video.paused) {
          _sendEvent(PlayerEventData(kind: NativePlayerEventType.playing, boolValue: false));
        }
      }).toJS,
    );

    video.addEventListener(
      'play',
      ((html.Event e) {
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.playing, boolValue: true));
        _startPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'pause',
      ((html.Event e) {
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.playing, boolValue: false));
        _stopPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'ended',
      ((html.Event e) {
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.completed));
        _stopPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'error',
      ((html.Event e) {
        final code = video.error?.code;
        final message = switch (code) {
          1 => 'MEDIA_ERR_ABORTED',
          2 => 'MEDIA_ERR_NETWORK',
          3 => 'MEDIA_ERR_DECODE',
          4 => 'MEDIA_ERR_SRC_NOT_SUPPORTED',
          _ => 'Video playback error',
        };
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.error, message: message));
      }).toJS,
    );

    video.addEventListener(
      'waiting',
      ((html.Event e) {
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.buffering, boolValue: true));
      }).toJS,
    );

    video.addEventListener(
      'stalled',
      ((html.Event e) {
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.buffering, boolValue: true));
      }).toJS,
    );

    video.addEventListener(
      'playing',
      ((html.Event e) {
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.buffering, boolValue: false));
      }).toJS,
    );

    video.addEventListener(
      'canplay',
      ((html.Event e) {
        _sendEvent(PlayerEventData(kind: NativePlayerEventType.buffering, boolValue: false));
        _emitBuffered(video);
      }).toJS,
    );

    video.addEventListener(
      'progress',
      ((html.Event e) {
        _emitBuffered(video);
      }).toJS,
    );

    _remotePlayback.attach(video);
  }

  void _emitBuffered(html.HTMLVideoElement video) {
    try {
      final ranges = video.buffered;
      if (ranges.length <= 0) return;
      final endSeconds = ranges.end(ranges.length - 1);
      if (endSeconds.isFinite && endSeconds >= 0) {
        _sendEvent(
          PlayerEventData(
            kind: NativePlayerEventType.buffered,
            intValue: (endSeconds * 1000).round(),
          ),
        );
      }
    } catch (_) {}
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final video = _videoElement;
      if (video != null) {
        _sendEvent(
          PlayerEventData(
            kind: NativePlayerEventType.position,
            intValue: (video.currentTime * 1000).toInt(),
          ),
        );
        _emitBuffered(video);
      }
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }
}
