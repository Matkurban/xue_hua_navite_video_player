import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/video_player_host_bridge.dart';
import '../orientation/method_channel_player_orientation.dart';
import '../orientation/player_orientation_controller.dart';
import '../pigeon/orientation_api.g.dart';
import 'browser_fullscreen.dart';

/// 全屏宿主协调器抽象接口：负责应用与恢复系统栏/屏幕方向、原生重力传感器联动、
/// 桌面窗口全屏或浏览器全屏。
///
/// Abstracts platform fullscreen and orientation coordination so `PlaybackSession`
/// can be unit-tested with a fake coordinator.
abstract class FullscreenCoordinator {
  /// 进入平台全屏（[landscapeVideo] 决定移动端优先横屏还是竖屏）。
  ///
  /// Enters platform fullscreen; [landscapeVideo] selects landscape vs. portrait on mobile.
  Future<void> enter({required bool landscapeVideo});

  /// 退出平台全屏并恢复系统栏、屏幕方向或桌面窗口状态。
  ///
  /// Exits platform fullscreen and restores system UI, orientations, or window bounds.
  Future<void> exit();

  /// 锁定或解锁屏幕方向，并联动原生重力传感器自动旋转状态机。
  ///
  /// - [locked] 为 `true` 时锁定到当前真实方向（或显式指定的 [lockedOrientation]），
  ///   暂停响应重力传感器且绝不触发多余的 180° 翻转。
  /// - [locked] 为 `false` 时立即恢复物理重力传感器联动（全屏下左右翻转自动 180° 切换）。
  ///
  /// Locks orientation to the current active direction (or [lockedOrientation]) when
  /// [locked] is `true`, or resumes gravity-driven rotation when `false`.
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

/// 默认全屏协调器实现：
/// - 移动端（iOS / Android）：通过 [PlayerOrientationController] 与 Pigeon 原生方向插件
///   控制强制横竖屏切换、物理重力传感器 180° 自动反向旋转、精准锁定当前方向与防回弹恢复。
/// - Web 端：结合 [BrowserFullscreenApplier] 与 [PlayerOrientationController] 支持桌面浏览器全屏、
///   Android Chrome `screen.orientation.lock` 以及 iOS Safari CSS 降级横屏容器。
/// - 桌面端（macOS / Windows / Linux）：基于原生窗口全屏。
///
/// Default coordinator combining [PlayerOrientationController] (mobile & mobile Web),
/// native desktop window fullscreen, and the browser Fullscreen API.
class SystemChromeFullscreenCoordinator implements FullscreenCoordinator {
  /// 创建默认全屏协调器，可选注入测试用 [bridge]、[browser]、[orientationController] 与 [isWeb]。
  ///
  /// Creates a [SystemChromeFullscreenCoordinator] with optional test overrides.
  SystemChromeFullscreenCoordinator({
    this._bridge,
    BrowserFullscreenApplier? browser,
    PlayerOrientationController? orientationController,
    bool? isWeb,
  }) : _browser = browser ?? const DefaultBrowserFullscreenApplier(),
       _isWeb = isWeb ?? kIsWeb,
       _ownsOrientationController = orientationController == null,
       _orientationController = orientationController ?? PlayerOrientationController() {
    if (!_isWeb) {
      _bridgeSub = _resolvedBridge.fullscreenEvents.listen(_external.add);
    }
    _browserSub = _browser.changes.listen(_external.add);
  }

  final VideoPlayerHostBridge? _bridge;
  final BrowserFullscreenApplier _browser;
  final bool _isWeb;
  final bool _ownsOrientationController;
  final PlayerOrientationController _orientationController;
  final StreamController<bool> _external = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _bridgeSub;
  StreamSubscription<bool>? _browserSub;

  VideoPlayerHostBridge get _resolvedBridge => _bridge ?? VideoPlayerHostBridge.instance;

  /// 关联的设备方向与重力传感器控制器。
  ///
  /// Associated [PlayerOrientationController] driving gravity rotation and lock.
  PlayerOrientationController get orientationController => _orientationController;

  @override
  Stream<bool> get externalChanges => _external.stream;

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> enter({required bool landscapeVideo}) async {
    if (_isWeb) {
      await _browser.enter();
      await _orientationController.enterFullscreen(landscapeVideo: landscapeVideo);
      return;
    }

    if (_isMobile) {
      await _orientationController.enterFullscreen(landscapeVideo: landscapeVideo);
      return;
    }

    try {
      await _resolvedBridge.setWindowFullscreen(true);
    } catch (_) {}
  }

  @override
  Future<void> exit() async {
    if (_isWeb) {
      await _orientationController.exitFullscreen();
      await _browser.exit();
      return;
    }

    if (_isMobile) {
      await _orientationController.exitFullscreen();
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
    if (!_isWeb && !_isMobile) {
      return;
    }

    if (locked) {
      final DevicePhysicalOrientation? mapped = lockedOrientation == null
          ? null
          : MethodChannelPlayerOrientation.fromDeviceOrientation(
              lockedOrientation,
              platform: defaultTargetPlatform,
            );
      await _orientationController.lock(orientation: mapped);
      return;
    }

    await _orientationController.unlock();
  }

  @override
  void dispose() {
    _bridgeSub?.cancel();
    _bridgeSub = null;
    _browserSub?.cancel();
    _browserSub = null;
    if (_ownsOrientationController) {
      _orientationController.dispose();
    }
    if (!_external.isClosed) {
      _external.close();
    }
  }
}
