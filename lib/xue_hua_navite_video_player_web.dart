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
/// Implements [VideoPlayerHostBridge] directly in Dart without platform channels.
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

  /// 注册 Web 插件，将 [VideoPlayerHostBridge.instance] 指向当前 Web 实现。
  static void registerWith(Registrar registrar) {
    VideoPlayerHostBridge.instance = XueHuaNaviteVideoPlayerWeb();
  }

  @override
  Stream<PlayerEventData> get events => _eventController.stream;

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

  @override
  Future<void> pause() async {
    _videoElement?.pause();
  }

  @override
  Future<void> seek(int positionMs) async {
    final video = _videoElement;
    if (video != null) {
      video.currentTime = positionMs / 1000.0;
    }
  }

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

  @override
  Future<void> setSpeed(double speed) async {
    final video = _videoElement;
    if (video != null) {
      video.playbackRate = speed;
    }
  }

  @override
  Future<void> setAspectRatioMode(NativeAspectRatioMode mode) async {
    final fit = switch (mode) {
      NativeAspectRatioMode.fill => 'cover',
      NativeAspectRatioMode.stretch => 'fill',
      NativeAspectRatioMode.fit => 'contain',
    };
    _videoElement?.style.setProperty('object-fit', fit);
  }

  @override
  Future<void> setVideoViewSize(double width, double height, double devicePixelRatio) async {}

  @override
  Future<void> showCastPicker() => _remotePlayback.showPicker(_videoElement);

  @override
  Future<void> stopCasting() => _remotePlayback.stopCasting(_videoElement);

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

  @override
  Future<double> getBrightness() async => 1.0;

  @override
  Future<void> setBrightness(double value) async {}

  @override
  Future<void> setWindowFullscreen(bool value) async {}

  @override
  Future<SnapshotData?> takeSnapshot() async => WebMediaProbeService.takeSnapshot(_videoElement);

  @override
  Future<int?> getDuration(DurationProbeRequest request) =>
      WebMediaProbeService.getDuration(request);

  @override
  Future<List<CoverFrameData>> extractCovers(CoverExtractRequest request) =>
      WebMediaProbeService.extractCovers(request);

  @override
  Future<void> configureCache(CacheConfigRequest request) async {}

  @override
  Future<void> precache(PrecacheRequest request) async {}

  @override
  Future<void> cancelPrecache(String cacheKey) async {}

  @override
  Future<bool> isCached(CacheEntryRequest request) async => false;

  @override
  Future<int> getCacheSize(String? cacheDir) async => 0;

  @override
  Future<void> removeCache(CacheEntryRequest request) async {}

  @override
  Future<void> clearCache(String? cacheDir) async {}

  @override
  Future<void> pinCacheKey(String cacheKey) async {}

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
