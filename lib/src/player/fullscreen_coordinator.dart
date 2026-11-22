import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/video_player_host_bridge.dart';
import 'browser_fullscreen.dart';

/// 全屏宿主协调器抽象接口：负责应用与恢复系统栏/屏幕方向、桌面窗口全屏或浏览器全屏。
///
/// Abstracts platform fullscreen coordination so `PlaybackSession` can be
/// unit-tested with a fake coordinator.
abstract class FullscreenCoordinator {
  /// 进入平台全屏（[landscapeVideo] 决定移动端优先横屏还是竖屏）。
  ///
  /// Enters platform fullscreen; [landscapeVideo] selects landscape vs. portrait on mobile.
  Future<void> enter({required bool landscapeVideo});

  /// 退出平台全屏并恢复系统栏、屏幕方向或桌面窗口状态。
  ///
  /// Exits platform fullscreen and restores system UI, orientations, or window bounds.
  Future<void> exit();

  /// 在移动端使用 Flutter 官方 `SystemChrome.setPreferredOrientations` 锁定或解锁屏幕方向。
  ///
  /// - [locked] 为 `true` 时锁定到单一方向（[lockedOrientation]，默认按 [landscapeVideo] 选择）。
  /// - [locked] 为 `false` 时恢复按重力感应自动旋转的双向横屏或双向竖屏。
  ///
  /// Locks orientation to a single [DeviceOrientation] when [locked] is `true`,
  /// or restores gravity-driven bidirectional landscape / portrait rotation when `false`.
  Future<void> setOrientationLocked({
    required bool locked,
    required bool landscapeVideo,
    DeviceOrientation? lockedOrientation,
  }) async {}

  /// 来自操作系统或浏览器外部触发的全屏状态变化事件流（如 macOS 滑动退出全屏或浏览器按 Esc）。
  ///
  /// Stream of fullscreen changes initiated by the OS or browser outside [enter] / [exit].
  Stream<bool> get externalChanges => const Stream<bool>.empty();

  /// 释放内部订阅与流资源。
  ///
  /// Releases internal subscriptions and stream controllers.
  void dispose() {}
}

/// 浏览器 Fullscreen API 适配接口（可注入以便在 VM 单元测试中覆盖 Web 路径）。
///
/// Injectable wrapper around the browser Fullscreen API for VM testability.
abstract class BrowserFullscreenApplier {
  /// 请求进入浏览器全屏。
  ///
  /// Requests entering browser fullscreen.
  Future<void> enter();

  /// 退出浏览器全屏。
  ///
  /// Exits browser fullscreen.
  Future<void> exit();

  /// 浏览器全屏状态变更事件流。
  ///
  /// Stream of browser fullscreen state changes.
  Stream<bool> get changes;
}

/// 默认浏览器全屏执行器实现，转发至 [BrowserFullscreen]。
///
/// Default [BrowserFullscreenApplier] forwarding to [BrowserFullscreen].
class DefaultBrowserFullscreenApplier implements BrowserFullscreenApplier {
  /// 创建默认浏览器全屏执行器。
  ///
  /// Creates a [DefaultBrowserFullscreenApplier].
  const DefaultBrowserFullscreenApplier();

  @override
  Future<void> enter() => BrowserFullscreen.enter();

  @override
  Future<void> exit() => BrowserFullscreen.exit();

  @override
  Stream<bool> get changes => BrowserFullscreen.changes;
}

/// 默认全屏协调器实现：移动端基于 Flutter 官方 [SystemChrome]，桌面端基于原生窗口全屏，Web 端基于浏览器 Fullscreen API。
///
/// Default coordinator using [SystemChrome] on mobile, native window fullscreen
/// on desktop, and the browser Fullscreen API on Web.
class SystemChromeFullscreenCoordinator implements FullscreenCoordinator {
  /// 创建默认全屏协调器，可选注入测试用 [bridge]、[browser] 与 [isWeb] 标志。
  ///
  /// Creates a [SystemChromeFullscreenCoordinator] with optional test overrides.
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
