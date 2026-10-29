import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as html;

import 'src/web/web_media_probe_service.dart';
import 'src/web/web_remote_playback_controller.dart';

/// Web 平台视频播放器插件实现，基于 HTML5 `<video>` 元素与 W3C Remote Playback API。
/// Web platform video player plugin implementation using HTML5 `<video>` element.
class XueHuaNaviteVideoPlayerWeb {
  html.HTMLVideoElement? _videoElement;
  Timer? _positionTimer;
  final _eventController = StreamController<dynamic>.broadcast();
  bool _viewRegistered = false;

  late final WebRemotePlaybackController _remotePlayback = WebRemotePlaybackController(
    onStateChanged: (state, {deviceName}) {
      _sendEvent('castState', <String, dynamic>{'state': state, 'deviceName': ?deviceName});
    },
  );

  /// 注册 Web 插件。 / Registers the web plugin.
  static void registerWith(Registrar registrar) {
    final instance = XueHuaNaviteVideoPlayerWeb();

    final methodChannel = MethodChannel(
      'xue_hua_navite_video_player/player',
      const StandardMethodCodec(),
      registrar,
    );
    methodChannel.setMethodCallHandler(instance._handleMethodCall);

    // ignore: deprecated_member_use
    final eventChannel = PluginEventChannel<dynamic>(
      'xue_hua_navite_video_player/player/events',
      const StandardMethodCodec(),
      registrar,
    );
    eventChannel.setController(instance._eventController);
  }

  void _sendEvent(String name, dynamic value) {
    _eventController.add(<String, dynamic>{'event': name, 'value': value});
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'create':
        return _create();
      case 'open':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _open(args['url'] as String);
        return null;
      case 'play':
        final video = _videoElement;
        if (video != null) {
          if (video.ended) {
            video.currentTime = 0;
          }
          video.play().toDart.catchError((Object error) {
            // If unmuted autoplay (e.g. LivePhoto hover / autoPlayOnce / loop)
            // is blocked by browser policy, automatically mute and retry so
            // Live Photos and inline previews still play smoothly on Web.
            final errStr = error.toString();
            if (!video.muted &&
                (errStr.contains('NotAllowedError') || errStr.contains('interact'))) {
              video.muted = true;
              return video.play().toDart.catchError((Object retryErr) {
                _sendEvent('playing', false);
                _sendEvent('buffering', false);
                _sendEvent('error', 'Autoplay blocked: $retryErr');
                return null;
              });
            }
            _sendEvent('playing', false);
            _sendEvent('buffering', false);
            _sendEvent('error', 'Autoplay blocked: $error');
            return null;
          });
        }
        return null;
      case 'pause':
        _videoElement?.pause();
        return null;
      case 'seek':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final ms = args['position'] as int;
        if (_videoElement != null) {
          _videoElement!.currentTime = ms / 1000.0;
        }
        return null;
      case 'setVolume':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final vol = (args['volume'] as num).toDouble().clamp(0.0, 1.0);
        if (_videoElement != null) {
          _videoElement!.volume = vol;
          // Sync the DOM `muted` property so muted playback satisfies browser autoplay policies.
          _videoElement!.muted = vol <= 0.0;
        }
        return null;
      case 'setSpeed':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final speed = (args['speed'] as num).toDouble();
        if (_videoElement != null) _videoElement!.playbackRate = speed;
        return null;
      case 'setAspectRatioMode':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _setAspectRatioMode(args['mode'] as String?);
        return null;
      case 'setVideoViewSize':
        // Web sizes via CSS 100%; no-op.
        return null;
      case 'showCastPicker':
        await _remotePlayback.showPicker(_videoElement);
        return null;
      case 'stopCasting':
        await _remotePlayback.stopCasting(_videoElement);
        return null;
      case 'dispose':
        _dispose();
        return null;
      case 'takeSnapshot':
        return WebMediaProbeService.takeSnapshot(_videoElement);
      case 'extractCovers':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        return WebMediaProbeService.extractCovers(args);
      case 'getDuration':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        return WebMediaProbeService.getDuration(args);
      case 'getBrightness':
        return 1.0;
      case 'setBrightness':
        return null;
      case 'setWindowFullscreen':
        // Browser fullscreen is applied from Dart via the Fullscreen API.
        return null;
      case 'configureCache':
      case 'precache':
      case 'cancelPrecache':
      case 'removeCache':
      case 'clearCache':
      case 'pinCacheKey':
      case 'unpinCacheKey':
        // Web cache lifecycle is managed in Dart via PlatformVideoCacheEngine (web).
        return null;
      case 'isCached':
        return false;
      case 'getCacheSize':
        return 0;
      case 'getPlatformVersion':
        return 'Web';
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: '${call.method} not implemented on web',
        );
    }
  }

  int _create() {
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

  void _setAspectRatioMode(String? mode) {
    final fit = switch (mode) {
      'fill' => 'cover',
      'stretch' => 'fill',
      _ => 'contain',
    };
    _videoElement?.style.setProperty('object-fit', fit);
  }

  void _setupListeners(html.HTMLVideoElement video) {
    video.addEventListener(
      'loadedmetadata',
      ((html.Event e) {
        if (video.duration.isFinite && video.duration > 0) {
          final durationMs = (video.duration * 1000).toInt();
          _sendEvent('duration', durationMs);
        }
        _sendEvent('buffering', false);
        final vw = video.videoWidth;
        final vh = video.videoHeight;
        if (vw > 0 && vh > 0) {
          _sendEvent('videoSize', {'width': vw, 'height': vh});
        }
        if (video.paused) {
          _sendEvent('playing', false);
        }
      }).toJS,
    );

    video.addEventListener(
      'play',
      ((html.Event e) {
        _sendEvent('playing', true);
        _startPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'pause',
      ((html.Event e) {
        _sendEvent('playing', false);
        _stopPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'ended',
      ((html.Event e) {
        _sendEvent('completed', null);
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
        _sendEvent('error', message);
      }).toJS,
    );

    video.addEventListener(
      'waiting',
      ((html.Event e) {
        _sendEvent('buffering', true);
      }).toJS,
    );

    video.addEventListener(
      'stalled',
      ((html.Event e) {
        _sendEvent('buffering', true);
      }).toJS,
    );

    video.addEventListener(
      'playing',
      ((html.Event e) {
        _sendEvent('buffering', false);
      }).toJS,
    );

    video.addEventListener(
      'canplay',
      ((html.Event e) {
        _sendEvent('buffering', false);
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
        _sendEvent('buffered', (endSeconds * 1000).round());
      }
    } catch (_) {}
  }

  void _open(String url) {
    final video = _videoElement;
    if (video == null) return;
    // Blob URLs and data: URLs do not need anonymous CORS mode, whereas remote
    // http(s) URLs keep crossOrigin='anonymous' for canvas snapshots.
    if (url.startsWith('blob:') || url.startsWith('data:')) {
      video.removeAttribute('crossorigin');
    } else {
      video.crossOrigin = 'anonymous';
    }
    video.src = url;
    video.load();
    _sendEvent('playing', false);
    _sendEvent('buffering', true);
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final video = _videoElement;
      if (video != null) {
        final ms = (video.currentTime * 1000).toInt();
        _sendEvent('position', ms);
        _emitBuffered(video);
      }
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _dispose() {
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
}
