import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browser_fullscreen.dart';

/// Applies / restores system UI, window, or browser fullscreen.
///
/// Extracted so [PlaybackSession] can be unit-tested with a fake coordinator.
abstract class FullscreenCoordinator {
  Future<void> enter({required bool landscapeVideo});

  Future<void> exit();

  /// OS / browser entered or left fullscreen without [enter] / [exit].
  Stream<bool> get externalChanges => const Stream<bool>.empty();

  void dispose() {}
}

/// Applies browser Fullscreen API. Injectable so VM tests can cover the web path.
abstract class BrowserFullscreenApplier {
  Future<void> enter();

  Future<void> exit();

  Stream<bool> get changes;
}

/// Default [BrowserFullscreen] wrapper.
class DefaultBrowserFullscreenApplier implements BrowserFullscreenApplier {
  const DefaultBrowserFullscreenApplier();

  @override
  Future<void> enter() => BrowserFullscreen.enter();

  @override
  Future<void> exit() => BrowserFullscreen.exit();

  @override
  Stream<bool> get changes => BrowserFullscreen.changes;
}

/// Default coordinator: SystemChrome on mobile, window fullscreen on desktop,
/// browser Fullscreen API on web.
class SystemChromeFullscreenCoordinator implements FullscreenCoordinator {
  SystemChromeFullscreenCoordinator({
    MethodChannel? channel,
    BrowserFullscreenApplier? browser,
    bool? isWeb,
  }) : _channel = channel ?? const MethodChannel('xue_hua_navite_video_player/player'),
       _browser = browser ?? const DefaultBrowserFullscreenApplier(),
       _isWeb = isWeb ?? kIsWeb {
    _channel.setMethodCallHandler(_onMethodCall);
    _browserSub = _browser.changes.listen(_external.add);
  }

  final MethodChannel _channel;
  final BrowserFullscreenApplier _browser;
  final bool _isWeb;
  final StreamController<bool> _external = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _browserSub;

  @override
  Stream<bool> get externalChanges => _external.stream;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'onWindowFullscreen') {
      final value = call.arguments;
      if (value is bool) {
        _external.add(value);
      }
    }
  }

  @override
  Future<void> enter({required bool landscapeVideo}) async {
    if (_isWeb) {
      await _browser.enter();
      return;
    }

    if (_isMobile) {
      if (landscapeVideo) {
        await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }

    try {
      await _channel.invokeMethod<void>('setWindowFullscreen', {'value': true});
    } catch (_) {}
  }

  @override
  Future<void> exit() async {
    if (_isWeb) {
      await _browser.exit();
      return;
    }

    if (_isMobile) {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      return;
    }

    try {
      await _channel.invokeMethod<void>('setWindowFullscreen', {'value': false});
    } catch (_) {}
  }

  @override
  void dispose() {
    _browserSub?.cancel();
    _browserSub = null;
    _channel.setMethodCallHandler(null);
    if (!_external.isClosed) {
      _external.close();
    }
  }
}
