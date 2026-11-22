import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/video_player_host_bridge.dart';
import 'browser_fullscreen.dart';

/// Applies / restores system UI, window, or browser fullscreen.
///
/// Extracted so [PlaybackSession] can be unit-tested with a fake coordinator.
abstract class FullscreenCoordinator {
  Future<void> enter({required bool landscapeVideo});

  Future<void> exit();

  /// Locks orientation to a single [DeviceOrientation] when [locked] is true,
  /// or restores gravity-driven bidirectional landscape / portrait rotation
  /// when [locked] is false.
  Future<void> setOrientationLocked({
    required bool locked,
    required bool landscapeVideo,
    DeviceOrientation? lockedOrientation,
  }) async {}

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
  SystemChromeFullscreenCoordinator({this._bridge, BrowserFullscreenApplier? browser, bool? isWeb})
    : _browser = browser ?? const DefaultBrowserFullscreenApplier(),
      _isWeb = isWeb ?? kIsWeb {
    if (!_isWeb) {
      _bridgeSub = _resolvedBridge.fullscreenEvents.listen(_external.add);
    }
    _browserSub = _browser.changes.listen(_external.add);
  }

  final VideoPlayerHostBridge? _bridge;
  final BrowserFullscreenApplier _browser;
  final bool _isWeb;
  final StreamController<bool> _external = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _bridgeSub;
  StreamSubscription<bool>? _browserSub;

  VideoPlayerHostBridge get _resolvedBridge => _bridge ?? VideoPlayerHostBridge.instance;

  @override
  Stream<bool> get externalChanges => _external.stream;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

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
      await _resolvedBridge.setWindowFullscreen(true);
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
      await _resolvedBridge.setWindowFullscreen(false);
    } catch (_) {}
  }

  @override
  Future<void> setOrientationLocked({
    required bool locked,
    required bool landscapeVideo,
    DeviceOrientation? lockedOrientation,
  }) async {
    if (_isWeb || !_isMobile) {
      return;
    }

    if (locked) {
      final DeviceOrientation target =
          lockedOrientation ??
          (landscapeVideo ? DeviceOrientation.landscapeLeft : DeviceOrientation.portraitUp);
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[target]);
      return;
    }

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
  }

  @override
  void dispose() {
    _bridgeSub?.cancel();
    _bridgeSub = null;
    _browserSub?.cancel();
    _browserSub = null;
    if (!_external.isClosed) {
      _external.close();
    }
  }
}
