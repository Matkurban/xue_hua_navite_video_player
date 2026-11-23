import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../pigeon/orientation_api.g.dart';
import 'player_orientation_platform.dart';

/// 播放器级设备方向与重力传感器联动状态机控制器。
///
/// 基于 `signals_flutter` 暴露全响应式方向状态，核心能力包括：
/// 1. **手动全屏**：若传感器已知左/右横握则优先进入对应方向，否则默认 `landscapeLeft`，
///    完全无视系统控制中心竖屏锁定；若在竖握状态下手动全屏，会进入防回弹过渡态避免立刻退出。
/// 2. **全屏下自动 180° 反向旋转**：全屏未锁定时，手机左右翻转 180° 自动在
///    `landscapeLeft` 与 `landscapeRight` 之间丝滑切换。
/// 3. **屏幕锁定（修复 iOS 锁定/解锁误旋转 Bug）**：锁定时读取并死锁当前真实界面方向
///    （绝不硬编码覆盖为 `landscapeLeft`），暂停响应传感器；解锁后仅在物理朝向确实变化时
///    才响应旋转，彻底消除“锁一次转一次、解一次转一次”的问题。
/// 4. **退出全屏防回弹（Auto-Reset）**：点击退出全屏时强制切回 `portraitUp` 并进入
///    [isAwaitingPortraitReset] 保护态，直到物理传感器检测到用户真正将手机竖起后才恢复
///    横屏自动全屏触发权限。
/// 5. **生命周期安全恢复**：通过 [WidgetsBindingObserver] 在应用退后台时暂停传感器采样，
///    回到前台时按需恢复监听。
///
/// Player-grade reactive orientation and gravity-sensor state machine controller
/// powered by `signals_flutter`.
class PlayerOrientationController with WidgetsBindingObserver {
  /// 创建 [PlayerOrientationController]。
  ///
  /// - [platform]：底层平台实现，默认使用 [PlayerOrientationPlatform.instance]。
  /// - [autoRotateEnabled]：是否启用重力传感器自动旋转（默认 `true`）。
  /// - [autoExitFullscreenOnPortrait]：全屏未锁定时竖起手机是否自动退出全屏（默认 `false`）。
  /// - [minConfidence]：接受传感器事件的最小置信度阈值（默认 `0.35`）。
  /// - [debounceDuration]：Dart 侧二次防抖间隔（默认 `Duration.zero`，由原生层完成 300ms 防抖；
  ///   可在测试或自定义平台中显式设置）。
  /// - [onAutoEnterFullscreen]：非全屏状态下重力传感器检测到横握时触发的回调。
  /// - [onAutoExitFullscreen]：全屏未锁定且 [autoExitFullscreenOnPortrait] 为 `true` 时，
  ///   传感器检测到竖握时触发的回调。
  ///
  /// Creates a [PlayerOrientationController] with optional dependency overrides.
  PlayerOrientationController({
    PlayerOrientationPlatform? platform,
    bool autoRotateEnabled = true,
    this.autoExitFullscreenOnPortrait = false,
    this.minConfidence = 0.35,
    this.debounceDuration = Duration.zero,
    this.onAutoEnterFullscreen,
    this.onAutoExitFullscreen,
  }) : _platform = platform ?? PlayerOrientationPlatform.instance,
       autoRotateEnabled = signal<bool>(autoRotateEnabled) {
    _sensorSubscription = _platform.physicalOrientationStream.listen(_handleRawSensorEvent);
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    } catch (_) {
      _observerRegistered = false;
    }
  }

  final PlayerOrientationPlatform _platform;

  /// 全屏未锁定时，当重力传感器检测到竖屏正向是否自动回调退出全屏。
  ///
  /// Whether turning the phone upright while unlocked in fullscreen triggers auto-exit.
  final bool autoExitFullscreenOnPortrait;

  /// 接受物理传感器事件的最小置信度阈值（`0.0` ~ `1.0`）。
  ///
  /// Minimum confidence required to act on an [OrientationSensorEvent].
  final double minConfidence;

  /// Dart 侧可选防抖时长（原生与 Web 平台已内置 300ms 防抖）。
  ///
  /// Optional Dart-side debounce interval on top of native/Web debouncing.
  final Duration debounceDuration;

  /// 非全屏且未处于防回弹保护态时，重力感应检测到横握方向触发的回调。
  ///
  /// Callback invoked when gravity sensor detects landscape while not fullscreen.
  final FutureOr<void> Function(DevicePhysicalOrientation orientation)? onAutoEnterFullscreen;

  /// 全屏未锁定且开启 [autoExitFullscreenOnPortrait] 时，传感器检测到竖屏触发的回调。
  ///
  /// Callback invoked when gravity sensor detects upright portrait while unlocked in fullscreen.
  final FutureOr<void> Function()? onAutoExitFullscreen;

  /// 当前已应用到界面的目标显示方向信号。
  ///
  /// Reactive signal of the currently applied display orientation.
  final FlutterSignal<DevicePhysicalOrientation> currentOrientation =
      signal<DevicePhysicalOrientation>(DevicePhysicalOrientation.portraitUp);

  /// 物理重力传感器最新上报的设备真实物理朝向信号。
  ///
  /// Reactive signal of the latest confirmed physical orientation from sensors.
  final FlutterSignal<DevicePhysicalOrientation> physicalOrientation =
      signal<DevicePhysicalOrientation>(DevicePhysicalOrientation.unknown);

  /// 最新一次传感器事件的置信度信号（`0.0` ~ `1.0`）。
  ///
  /// Reactive signal of the latest sensor confidence score in `[0.0, 1.0]`.
  final FlutterSignal<double> sensorConfidence = signal<double>(0.0);

  /// 当前是否处于全屏模式信号。
  ///
  /// Reactive signal indicating whether fullscreen mode is active.
  final FlutterSignal<bool> isFullscreen = signal<bool>(false);

  /// 当前是否处于方向锁定状态信号（锁定时暂停响应传感器旋转事件）。
  ///
  /// Reactive signal indicating whether orientation rotation is locked.
  final FlutterSignal<bool> isLocked = signal<bool>(false);

  /// 退出全屏防回弹保护态信号：`true` 表示已强制切回竖屏，正等待用户将手机真正竖起。
  ///
  /// Auto-reset guard active after exiting fullscreen while holding horizontally.
  final FlutterSignal<bool> isAwaitingPortraitReset = signal<bool>(false);

  /// 竖握手动全屏保护态信号：`true` 表示竖握时手动点了全屏，等待用户横向握持后才允许竖握退出。
  ///
  /// Symmetric guard active after manually entering fullscreen while holding upright.
  final FlutterSignal<bool> isAwaitingLandscapeSettle = signal<bool>(false);

  /// 是否允许重力传感器驱动自动旋转的开关信号。
  ///
  /// Reactive toggle enabling or disabling gravity-driven auto-rotation.
  final FlutterSignal<bool> autoRotateEnabled;

  /// 是否启用了 iOS Safari CSS Transform 降级全屏旋转。
  ///
  /// Whether the underlying platform uses CSS transform fallback rotation.
  bool get usesCssFallbackRotation => _platform.usesCssFallbackRotation;

  /// 供 `WebOrientationViewport` 使用的 CSS 降级旋转弧度计算信号。
  ///
  /// Computed rotation angle in radians for `WebOrientationViewport` on iOS Safari.
  late final FlutterComputed<double> cssRotationRadians = computed<double>(() {
    if (!usesCssFallbackRotation || !isFullscreen.value) {
      return 0.0;
    }
    return switch (currentOrientation.value) {
      DevicePhysicalOrientation.landscapeLeft => math.pi / 2.0,
      DevicePhysicalOrientation.landscapeRight => -math.pi / 2.0,
      DevicePhysicalOrientation.portraitUp || DevicePhysicalOrientation.unknown => 0.0,
    };
  });

  StreamSubscription<OrientationSensorEvent>? _sensorSubscription;
  Timer? _dartDebounceTimer;
  bool _observerRegistered = false;
  bool _sensorDesired = false;
  bool _sensorPausedByLifecycle = false;
  bool _landscapeFullscreen = true;
  bool _disposed = false;

  /// 开启物理重力传感器监听（应在播放器挂载或进入全屏时调用）。
  ///
  /// Starts listening to physical gravity sensor updates.
  Future<void> startSensorListening() async {
    if (_disposed) return;
    _sensorDesired = true;
    await _platform.startSensorListening();
  }

  /// 停止物理重力传感器监听。
  ///
  /// Stops listening to physical gravity sensor updates.
  Future<void> stopSensorListening() async {
    if (_disposed) return;
    _sensorDesired = false;
    await _platform.stopSensorListening();
  }

  /// 在用户手势回调中请求传感器授权（专用于 iOS 13+ Safari）。
  ///
  /// Requests sensor permission (for iOS 13+ Safari user-gesture requirement).
  Future<bool> requestSensorPermission() => _platform.requestSensorPermission();

  /// 进入全屏模式。
  ///
  /// - [landscapeVideo] 为 `true` 时，若传感器已探测到 `landscapeLeft` 或 `landscapeRight`
  ///   则优先进入对应方向，否则默认进入 `landscapeLeft`（无视系统竖屏锁定）。
  /// - [preferredOrientation] 可显式指定进入全屏的目标方向。
  ///
  /// Enters fullscreen, preferring the current physical landscape grip when known
  /// (defaulting to `landscapeLeft`) and overriding system orientation lock.
  Future<void> enterFullscreen({
    bool landscapeVideo = true,
    DevicePhysicalOrientation? preferredOrientation,
  }) async {
    if (_disposed) return;
    _landscapeFullscreen = landscapeVideo;

    final DevicePhysicalOrientation target;
    if (preferredOrientation != null && preferredOrientation != DevicePhysicalOrientation.unknown) {
      target = preferredOrientation;
    } else if (!landscapeVideo) {
      target = DevicePhysicalOrientation.portraitUp;
    } else if (_isLandscape(physicalOrientation.value)) {
      target = physicalOrientation.value;
    } else {
      target = DevicePhysicalOrientation.landscapeLeft;
    }

    batch(() {
      isLocked.value = false;
      isFullscreen.value = true;
      isAwaitingPortraitReset.value = false;
      isAwaitingLandscapeSettle.value =
          landscapeVideo && physicalOrientation.value == DevicePhysicalOrientation.portraitUp;
      currentOrientation.value = target;
    });

    await _platform.setImmersiveFullscreen(true);
    await _platform.setTargetOrientation(target);
    if (autoRotateEnabled.value && !_sensorDesired) {
      await startSensorListening();
    }
  }

  /// 退出全屏模式并启用防回弹保护（Auto-Reset）。
  ///
  /// 先强制切回 `portraitUp` 并退出沉浸式全屏；若此时物理传感器仍处于横握姿态，则进入
  /// [isAwaitingPortraitReset] 保护态，直到传感器检测到用户把手机竖起后才解除保护，
  /// 彻底杜绝刚退出全屏又被横握姿势弹回全屏的 Bug。
  ///
  /// Exits fullscreen, forces `portraitUp`, and enables [isAwaitingPortraitReset]
  /// if the phone is still physically held sideways.
  Future<void> exitFullscreen() async {
    if (_disposed) return;

    final bool stillHoldingLandscape = _isLandscape(physicalOrientation.value);
    batch(() {
      isLocked.value = false;
      isFullscreen.value = false;
      isAwaitingLandscapeSettle.value = false;
      isAwaitingPortraitReset.value = stillHoldingLandscape;
      currentOrientation.value = DevicePhysicalOrientation.portraitUp;
    });

    await _platform.setImmersiveFullscreen(false);
    await _platform.setTargetOrientation(DevicePhysicalOrientation.portraitUp);
  }

  /// 锁定当前方向并暂停响应传感器旋转事件。
  ///
  /// 若未显式传入 [orientation]，会自动向原生层查询当前真实界面方向（再回退到
  /// [currentOrientation]），死锁在当前精确方向上而不触发任何多余旋转，彻底修复 iOS
  /// 点击锁屏时发生 180° 旋转的 Bug。
  ///
  /// Locks to the exact current interface orientation without triggering a
  /// spurious rotation, pausing sensor-driven orientation updates.
  Future<void> lock({DevicePhysicalOrientation? orientation}) async {
    if (_disposed) return;

    final DevicePhysicalOrientation? explicit =
        (orientation != null && orientation != DevicePhysicalOrientation.unknown)
        ? orientation
        : null;

    DevicePhysicalOrientation resolved = explicit ?? DevicePhysicalOrientation.unknown;
    if (resolved == DevicePhysicalOrientation.unknown) {
      final DevicePhysicalOrientation actual = await _platform.getCurrentOrientation();
      if (_disposed) return;
      if (actual != DevicePhysicalOrientation.unknown) {
        resolved = actual;
      } else if (currentOrientation.value != DevicePhysicalOrientation.unknown) {
        resolved = currentOrientation.value;
      } else {
        resolved = _landscapeFullscreen
            ? DevicePhysicalOrientation.landscapeLeft
            : DevicePhysicalOrientation.portraitUp;
      }
    }

    final bool needsApply = explicit != null || resolved != currentOrientation.value;

    batch(() {
      isLocked.value = true;
      currentOrientation.value = resolved;
    });

    if (needsApply) {
      await _platform.setTargetOrientation(resolved);
    }
  }

  /// 解锁屏幕方向并立即恢复重力传感器联动。
  ///
  /// 解锁本身绝不强行重置或翻转当前方向；仅在全屏横屏下、物理传感器已经明确处于
  /// 另一侧横握且置信度达标时，才平滑跟随传感器翻转。
  ///
  /// Unlocks orientation and resumes gravity sensor responsiveness without
  /// triggering a spurious rotation when the physical grip already matches.
  Future<void> unlock() async {
    if (_disposed) return;
    if (!isLocked.value) return;

    isLocked.value = false;

    if (isFullscreen.value &&
        _landscapeFullscreen &&
        autoRotateEnabled.value &&
        sensorConfidence.value >= minConfidence) {
      final DevicePhysicalOrientation phys = physicalOrientation.value;
      if (_isLandscape(phys) && phys != currentOrientation.value) {
        currentOrientation.value = phys;
        await _platform.setTargetOrientation(phys);
      }
    }
  }

  /// 切换锁定 / 解锁状态。
  ///
  /// Toggles orientation lock state.
  Future<void> toggleLock({DevicePhysicalOrientation? orientation}) {
    if (isLocked.value) {
      return unlock();
    }
    return lock(orientation: orientation);
  }

  void _handleRawSensorEvent(OrientationSensorEvent event) {
    if (_disposed) return;
    if (event.orientation == DevicePhysicalOrientation.unknown ||
        event.confidence < minConfidence) {
      return;
    }

    if (debounceDuration > Duration.zero) {
      _dartDebounceTimer?.cancel();
      _dartDebounceTimer = Timer(debounceDuration, () {
        if (!_disposed) {
          _processConfirmedSensorEvent(event);
        }
      });
      return;
    }

    _processConfirmedSensorEvent(event);
  }

  void _processConfirmedSensorEvent(OrientationSensorEvent event) {
    final DevicePhysicalOrientation next = event.orientation;

    batch(() {
      physicalOrientation.value = next;
      sensorConfidence.value = event.confidence;
    });

    // 1. 退出全屏防回弹保护：只有传感器真正检测到竖屏正向后，才解除保护态
    if (isAwaitingPortraitReset.value) {
      if (next == DevicePhysicalOrientation.portraitUp) {
        isAwaitingPortraitReset.value = false;
      }
      return;
    }

    // 2. 竖握手动进全屏保护：当用户真正横握手机后解除保护态
    if (isAwaitingLandscapeSettle.value && _isLandscape(next)) {
      isAwaitingLandscapeSettle.value = false;
    }

    // 3. 锁屏或关闭自动旋转时，仅记录物理朝向，不触发任何界面旋转
    if (isLocked.value || !autoRotateEnabled.value) {
      return;
    }

    // 4. 全屏状态下：支持左右横屏 180° 自动反向旋转，以及可选的竖屏自动退出全屏
    if (isFullscreen.value) {
      if (_landscapeFullscreen && _isLandscape(next) && next != currentOrientation.value) {
        currentOrientation.value = next;
        unawaited(_platform.setTargetOrientation(next));
      } else if (next == DevicePhysicalOrientation.portraitUp &&
          !isAwaitingLandscapeSettle.value &&
          autoExitFullscreenOnPortrait) {
        final FutureOr<void> Function()? callback = onAutoExitFullscreen;
        if (callback != null) {
          unawaited(Future<void>.sync(callback));
        } else {
          unawaited(exitFullscreen());
        }
      }
      return;
    }

    // 5. 非全屏状态下：横握时自动通知宿主进入对应方向全屏
    if (_isLandscape(next)) {
      final FutureOr<void> Function(DevicePhysicalOrientation)? callback = onAutoEnterFullscreen;
      if (callback != null) {
        unawaited(Future<void>.sync(() => callback(next)));
      }
    }
  }

  static bool _isLandscape(DevicePhysicalOrientation orientation) =>
      orientation == DevicePhysicalOrientation.landscapeLeft ||
      orientation == DevicePhysicalOrientation.landscapeRight;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_sensorDesired && !_sensorPausedByLifecycle) {
        _sensorPausedByLifecycle = true;
        unawaited(_platform.stopSensorListening());
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_sensorDesired && _sensorPausedByLifecycle) {
        _sensorPausedByLifecycle = false;
        unawaited(_platform.startSensorListening());
      }
    }
  }

  /// 释放所有传感器订阅、定时器与生命周期监听。
  ///
  /// Disposes sensor subscriptions, debounce timers, and lifecycle observers.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dartDebounceTimer?.cancel();
    _dartDebounceTimer = null;
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    unawaited(_sensorSubscription?.cancel());
    _sensorSubscription = null;
    if (_sensorDesired) {
      _sensorDesired = false;
      unawaited(_platform.stopSensorListening());
    }
  }
}
