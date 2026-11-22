import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../pigeon/orientation_api.g.dart';
import 'player_orientation_platform.dart';

@JS('DeviceOrientationEvent')
extension type _JsDeviceOrientationEventCtor._(JSObject _) implements JSObject {
  external JSPromise<JSString>? requestPermission();
}

extension type _JsScreenOrientation._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> lock(String orientation);
  external void unlock();
  external String get type;
}

/// 移动端 Web 方向控制与重力传感器实现（基于最新 `package:web` 与 `dart:js_interop`）。
///
/// - **Android Chrome / 支持 Screen Orientation API 的浏览器**：
///   进入全屏后调用 `screen.orientation.lock('landscape-primary' / 'landscape-secondary')`，
///   并监听 `window` 的 `deviceorientation`（Beta / Gamma 倾角算法）实现锁屏与解锁后反向旋转。
/// - **iOS Safari 降级策略**：
///   自动识别不支持 `screen.orientation.lock()` 的 iOS Safari，通过
///   `DeviceOrientationEvent.requestPermission()`（iOS 13+ 用户手势授权）获取重力倾角，
///   并启用 [usesCssFallbackRotation] 驱动 `WebOrientationViewport` 通过 CSS Transform
///   无缝模拟全屏横屏与 180° 反向旋转。
///
/// Mobile Web implementation of [PlayerOrientationPlatform] using `package:web`
/// and `dart:js_interop`, with full Android Chrome Screen Orientation API support
/// and iOS Safari permission + CSS fallback rotation.
class WebPlayerOrientation extends PlayerOrientationPlatform {
  final StreamController<OrientationSensorEvent> _sensorController =
      StreamController<OrientationSensorEvent>.broadcast();

  JSFunction? _deviceOrientationListener;
  Timer? _debounceTimer;
  bool _listening = false;
  bool _permissionGranted = false;

  DevicePhysicalOrientation _currentOrientation = DevicePhysicalOrientation.portraitUp;
  DevicePhysicalOrientation _lastEmittedOrientation = DevicePhysicalOrientation.unknown;
  DevicePhysicalOrientation? _pendingOrientation;

  static const Duration _debounceDuration = Duration(milliseconds: 300);
  static const double _enterTiltThresholdDegrees = 45.0;
  static const double _exitTiltThresholdDegrees = 25.0;

  bool get _isIosSafari {
    final String ua = web.window.navigator.userAgent;
    final int maxTouchPoints = web.window.navigator.maxTouchPoints;
    final bool isIosDevice =
        ua.contains('iPhone') ||
        ua.contains('iPad') ||
        ua.contains('iPod') ||
        (ua.contains('Macintosh') && maxTouchPoints > 1);
    return isIosDevice;
  }

  bool get _supportsNativeOrientationLock {
    if (_isIosSafari) return false;
    try {
      final JSObject screenObj = web.window.screen as JSObject;
      if (!screenObj.hasProperty('orientation'.toJS).toDart) {
        return false;
      }
      final JSAny? orientationProp = screenObj.getProperty('orientation'.toJS);
      if (orientationProp == null || !orientationProp.isA<JSObject>()) {
        return false;
      }
      return (orientationProp as JSObject).hasProperty('lock'.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get usesCssFallbackRotation => _isIosSafari || !_supportsNativeOrientationLock;

  @override
  Stream<OrientationSensorEvent> get physicalOrientationStream => _sensorController.stream;

  @override
  Future<bool> requestSensorPermission() async {
    if (_permissionGranted) return true;
    try {
      final JSAny? ctor = globalContext.getProperty('DeviceOrientationEvent'.toJS);
      if (ctor != null && ctor.isA<JSObject>()) {
        final JSObject ctorObj = ctor as JSObject;
        if (ctorObj.hasProperty('requestPermission'.toJS).toDart) {
          final JSPromise<JSString>? promise =
              (ctorObj as _JsDeviceOrientationEventCtor).requestPermission();
          if (promise != null) {
            final JSString result = await promise.toDart;
            _permissionGranted = result.toDart == 'granted';
            return _permissionGranted;
          }
        }
      }
      _permissionGranted = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setTargetOrientation(DevicePhysicalOrientation orientation) async {
    _currentOrientation = orientation;
    if (usesCssFallbackRotation) {
      // iOS Safari 无法调用 screen.orientation.lock()，由 WebOrientationViewport
      // 响应 PlayerOrientationController.currentOrientation 完成 CSS 旋转渲染。
      return;
    }

    try {
      final JSObject screenObj = web.window.screen as JSObject;
      final JSAny? orientationProp = screenObj.getProperty('orientation'.toJS);
      if (orientationProp == null || !orientationProp.isA<JSObject>()) return;
      final _JsScreenOrientation screenOrientation = orientationProp as _JsScreenOrientation;

      if (orientation == DevicePhysicalOrientation.unknown) {
        screenOrientation.unlock();
        return;
      }

      final String lockType = switch (orientation) {
        DevicePhysicalOrientation.portraitUp => 'portrait-primary',
        DevicePhysicalOrientation.landscapeLeft => 'landscape-primary',
        DevicePhysicalOrientation.landscapeRight => 'landscape-secondary',
        DevicePhysicalOrientation.unknown => 'any',
      };
      await screenOrientation.lock(lockType).toDart;
    } catch (_) {
      // 部分移动端浏览器在非全屏态调用 lock() 会被拒绝，静默降级即可。
    }
  }

  @override
  Future<DevicePhysicalOrientation> getCurrentOrientation() async {
    if (usesCssFallbackRotation) {
      return _currentOrientation;
    }
    try {
      final JSObject screenObj = web.window.screen as JSObject;
      final JSAny? orientationProp = screenObj.getProperty('orientation'.toJS);
      if (orientationProp != null && orientationProp.isA<JSObject>()) {
        final String type = (orientationProp as _JsScreenOrientation).type;
        return switch (type) {
          'portrait-primary' => DevicePhysicalOrientation.portraitUp,
          'landscape-primary' => DevicePhysicalOrientation.landscapeLeft,
          'landscape-secondary' => DevicePhysicalOrientation.landscapeRight,
          _ => _currentOrientation,
        };
      }
    } catch (_) {}
    return _currentOrientation;
  }

  @override
  Future<void> startSensorListening() async {
    if (_listening) return;
    if (_isIosSafari && !_permissionGranted) {
      // 若尚未授权则尝试请求（必须在用户手势上下文中才会被 iOS Safari 允许）。
      await requestSensorPermission();
    }
    _listening = true;
    _deviceOrientationListener = ((web.Event rawEvent) {
      _handleDeviceOrientationEvent(rawEvent as web.DeviceOrientationEvent);
    }).toJS;
    web.window.addEventListener('deviceorientation', _deviceOrientationListener!);
  }

  @override
  Future<void> stopSensorListening() async {
    if (!_listening) return;
    _listening = false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingOrientation = null;
    final JSFunction? listener = _deviceOrientationListener;
    if (listener != null) {
      web.window.removeEventListener('deviceorientation', listener);
      _deviceOrientationListener = null;
    }
  }

  @override
  Future<void> setImmersiveFullscreen(bool enabled) async {
    if (usesCssFallbackRotation) {
      // iOS Safari 限制 documentElement.requestFullscreen()，交由全屏 Overlay + CSS 容器实现。
      return;
    }
    try {
      if (enabled) {
        final web.Element? el = web.document.documentElement;
        if (el != null && web.document.fullscreenElement == null) {
          await el.requestFullscreen().toDart;
        }
      } else if (web.document.fullscreenElement != null) {
        await web.document.exitFullscreen().toDart;
      }
    } catch (_) {}
  }

  void _handleDeviceOrientationEvent(web.DeviceOrientationEvent event) {
    if (!_listening) return;
    final double? beta = event.beta;
    final double? gamma = event.gamma;
    if (beta == null || gamma == null) return;

    // 过滤平放（beta 与 gamma 均接近 0°）及倒置（beta < -45°）
    final double absBeta = beta.abs();
    final double absGamma = gamma.abs();
    if (absBeta < 20.0 && absGamma < 20.0) {
      return;
    }
    if (beta < -45.0 && absGamma < 35.0) {
      return;
    }

    final DevicePhysicalOrientation resolved = _resolveFromBetaGamma(
      beta: beta,
      gamma: gamma,
      previous: _lastEmittedOrientation,
    );
    if (resolved == DevicePhysicalOrientation.unknown) {
      return;
    }

    final double confidence = _computeConfidence(
      beta: beta,
      gamma: gamma,
      orientation: resolved,
    );
    final double angleDegrees = switch (resolved) {
      DevicePhysicalOrientation.portraitUp => 0.0,
      DevicePhysicalOrientation.landscapeLeft => 270.0,
      DevicePhysicalOrientation.landscapeRight => 90.0,
      DevicePhysicalOrientation.unknown => -1.0,
    };

    _scheduleDebouncedEmit(
      OrientationSensorEvent(
        orientation: resolved,
        confidence: confidence,
        angleDegrees: angleDegrees,
      ),
    );
  }

  DevicePhysicalOrientation _resolveFromBetaGamma({
    required double beta,
    required double gamma,
    required DevicePhysicalOrientation previous,
  }) {
    final double absBeta = beta.abs();
    final double absGamma = gamma.abs();

    // 竖屏正向：beta 为正且明显大于横向倾角
    if (beta >= _enterTiltThresholdDegrees && absGamma <= _exitTiltThresholdDegrees) {
      return DevicePhysicalOrientation.portraitUp;
    }
    // 左横握（顶部朝左，逆时针 90°）：gamma < -45°
    if (gamma <= -_enterTiltThresholdDegrees && absBeta <= _enterTiltThresholdDegrees) {
      return DevicePhysicalOrientation.landscapeLeft;
    }
    // 右横握（顶部朝右，顺时针 90°）：gamma > 45°
    if (gamma >= _enterTiltThresholdDegrees && absBeta <= _enterTiltThresholdDegrees) {
      return DevicePhysicalOrientation.landscapeRight;
    }

    // 滞回区间内保持上一次稳定朝向
    return previous;
  }

  double _computeConfidence({
    required double beta,
    required double gamma,
    required DevicePhysicalOrientation orientation,
  }) {
    final double raw = switch (orientation) {
      DevicePhysicalOrientation.portraitUp => beta / 90.0,
      DevicePhysicalOrientation.landscapeLeft => (-gamma) / 90.0,
      DevicePhysicalOrientation.landscapeRight => gamma / 90.0,
      DevicePhysicalOrientation.unknown => 0.0,
    };
    return raw.clamp(0.0, 1.0);
  }

  void _scheduleDebouncedEmit(OrientationSensorEvent event) {
    if (event.orientation == _lastEmittedOrientation) {
      _pendingOrientation = null;
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return;
    }
    if (_pendingOrientation == event.orientation) {
      return;
    }

    _pendingOrientation = event.orientation;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (!_listening) return;
      _lastEmittedOrientation = event.orientation;
      _pendingOrientation = null;
      _debounceTimer = null;
      if (!_sensorController.isClosed) {
        _sensorController.add(event);
      }
    });
  }

  @override
  void dispose() {
    unawaited(stopSensorListening());
    if (!_sensorController.isClosed) {
      unawaited(_sensorController.close());
    }
  }
}
