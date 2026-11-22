import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/bridge_env.dart';
import '../pigeon/orientation_api.g.dart';
import 'player_orientation_platform.dart';

/// Android / iOS 原生方向控制与重力传感器平台实现（基于 Pigeon 类型安全通道）。
///
/// 负责在切换方向时同步 Flutter [SystemChrome.setPreferredOrientations] 与原生
/// [OrientationHostApi.setTargetOrientation]：
/// - iOS 上将 `DevicePhysicalOrientation.landscapeLeft`（顶部朝左、Home 在右）正确映射到
///   Flutter 的 `DeviceOrientation.landscapeRight`（对应 `UIInterfaceOrientationMask.landscapeRight`），
///   避免 `FlutterViewController.supportedInterfaceOrientations` 与 `UIWindowScene.requestGeometryUpdate`
///   冲突或发生 180° 反向翻转。
/// - Android 上直接映射至 `SCREEN_ORIENTATION_LANDSCAPE` / `SCREEN_ORIENTATION_REVERSE_LANDSCAPE` /
///   `SCREEN_ORIENTATION_PORTRAIT`。
///
/// Native Android/iOS implementation of [PlayerOrientationPlatform] backed by
/// Pigeon [OrientationHostApi] and [OrientationFlutterApi].
class MethodChannelPlayerOrientation extends PlayerOrientationPlatform
    implements OrientationFlutterApi {
  /// 创建基于 Pigeon 通道的方向平台实现，支持在单元测试中注入 [hostApi] 与 [binaryMessenger]。
  ///
  /// Creates a [MethodChannelPlayerOrientation] with optional test overrides.
  MethodChannelPlayerOrientation({
    @visibleForTesting OrientationHostApi? hostApi,
    @visibleForTesting BinaryMessenger? binaryMessenger,
  }) : _hostApiOverride = hostApi,
       // ignore: prefer_initializing_formals
       _binaryMessenger = binaryMessenger;

  final OrientationHostApi? _hostApiOverride;
  final BinaryMessenger? _binaryMessenger;
  OrientationHostApi? _hostApi;
  bool _flutterApiSetUp = false;
  bool _sensorListening = false;

  late final StreamController<OrientationSensorEvent> _sensorController =
      StreamController<OrientationSensorEvent>.broadcast(onListen: _ensureFlutterApiSetUp);

  bool get _isMobileNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  OrientationHostApi _resolveHostApi() {
    final OrientationHostApi? override = _hostApiOverride;
    if (override != null) {
      return override;
    }
    return _hostApi ??= OrientationHostApi(binaryMessenger: _binaryMessenger);
  }

  void _ensureFlutterApiSetUp() {
    if (kIsWeb || _flutterApiSetUp) {
      return;
    }
    _flutterApiSetUp = true;
    try {
      OrientationFlutterApi.setUp(this, binaryMessenger: _binaryMessenger);
    } catch (_) {
      if (!isFlutterTestEnvironment) {
        _flutterApiSetUp = false;
        rethrow;
      }
    }
  }

  /// 将逻辑物理朝向映射为当前平台对应的 Flutter [DeviceOrientation] 列表，
  /// 确保 iOS `FlutterViewController` 的方向掩码与 `UIWindowScene` 保持一致。
  ///
  /// Maps [orientation] to platform-aligned [DeviceOrientation] preferences for
  /// [SystemChrome.setPreferredOrientations].
  @visibleForTesting
  static List<DeviceOrientation> toPreferredSystemOrientations(
    DevicePhysicalOrientation orientation, {
    required TargetPlatform platform,
  }) {
    if (platform == TargetPlatform.iOS) {
      // 在 Flutter iOS 引擎中：
      // DeviceOrientation.landscapeRight -> UIInterfaceOrientationMaskLandscapeRight（顶部朝左、Home 在右）
      // DeviceOrientation.landscapeLeft  -> UIInterfaceOrientationMaskLandscapeLeft（顶部朝右、Home 在左）
      return switch (orientation) {
        DevicePhysicalOrientation.portraitUp => const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ],
        DevicePhysicalOrientation.landscapeLeft => const <DeviceOrientation>[
          DeviceOrientation.landscapeRight,
        ],
        DevicePhysicalOrientation.landscapeRight => const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
        ],
        DevicePhysicalOrientation.unknown => const <DeviceOrientation>[],
      };
    }

    // Android：
    // DeviceOrientation.landscapeLeft  -> SCREEN_ORIENTATION_LANDSCAPE（顶部朝左）
    // DeviceOrientation.landscapeRight -> SCREEN_ORIENTATION_REVERSE_LANDSCAPE（顶部朝右）
    return switch (orientation) {
      DevicePhysicalOrientation.portraitUp => const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ],
      DevicePhysicalOrientation.landscapeLeft => const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
      ],
      DevicePhysicalOrientation.landscapeRight => const <DeviceOrientation>[
        DeviceOrientation.landscapeRight,
      ],
      DevicePhysicalOrientation.unknown => const <DeviceOrientation>[],
    };
  }

  /// 将 Flutter [DeviceOrientation] 反向映射为统一的 [DevicePhysicalOrientation]。
  ///
  /// Converts a Flutter [DeviceOrientation] to [DevicePhysicalOrientation] for [platform].
  static DevicePhysicalOrientation fromDeviceOrientation(
    DeviceOrientation orientation, {
    required TargetPlatform platform,
  }) {
    if (platform == TargetPlatform.iOS) {
      return switch (orientation) {
        DeviceOrientation.portraitUp => DevicePhysicalOrientation.portraitUp,
        DeviceOrientation.landscapeRight => DevicePhysicalOrientation.landscapeLeft,
        DeviceOrientation.landscapeLeft => DevicePhysicalOrientation.landscapeRight,
        DeviceOrientation.portraitDown => DevicePhysicalOrientation.unknown,
      };
    }
    return switch (orientation) {
      DeviceOrientation.portraitUp => DevicePhysicalOrientation.portraitUp,
      DeviceOrientation.landscapeLeft => DevicePhysicalOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight => DevicePhysicalOrientation.landscapeRight,
      DeviceOrientation.portraitDown => DevicePhysicalOrientation.unknown,
    };
  }

  @override
  Stream<OrientationSensorEvent> get physicalOrientationStream => _sensorController.stream;

  @override
  void onPhysicalOrientationChanged(OrientationSensorEvent event) {
    if (!_sensorController.isClosed) {
      _sensorController.add(event);
    }
  }

  @override
  Future<void> setTargetOrientation(DevicePhysicalOrientation orientation) async {
    if (!_isMobileNative) return;
    final List<DeviceOrientation> preferred = toPreferredSystemOrientations(
      orientation,
      platform: defaultTargetPlatform,
    );
    try {
      await SystemChrome.setPreferredOrientations(preferred);
    } catch (_) {}
    try {
      await _resolveHostApi().setTargetOrientation(orientation);
    } on MissingPluginException {
      // Fall back gracefully in unit tests or hosts without native registration.
    } catch (_) {}
  }

  @override
  Future<DevicePhysicalOrientation> getCurrentOrientation() async {
    if (!_isMobileNative) {
      return DevicePhysicalOrientation.unknown;
    }
    try {
      return await _resolveHostApi().getCurrentOrientation();
    } on MissingPluginException {
      return DevicePhysicalOrientation.unknown;
    } catch (_) {
      return DevicePhysicalOrientation.unknown;
    }
  }

  @override
  Future<void> startSensorListening() async {
    if (!_isMobileNative || _sensorListening) return;
    _ensureFlutterApiSetUp();
    _sensorListening = true;
    try {
      await _resolveHostApi().startSensorListening();
    } on MissingPluginException {
      _sensorListening = false;
    } catch (_) {
      _sensorListening = false;
    }
  }

  @override
  Future<void> stopSensorListening() async {
    if (!_isMobileNative || !_sensorListening) return;
    _sensorListening = false;
    try {
      await _resolveHostApi().stopSensorListening();
    } on MissingPluginException {
      // Ignore in test environments.
    } catch (_) {}
  }

  @override
  Future<void> setImmersiveFullscreen(bool enabled) async {
    if (!_isMobileNative) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {}
    try {
      await _resolveHostApi().setImmersiveFullscreen(enabled);
    } on MissingPluginException {
      // Ignore in test environments.
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(stopSensorListening());
    if (_flutterApiSetUp) {
      try {
        OrientationFlutterApi.setUp(null, binaryMessenger: _binaryMessenger);
      } catch (_) {}
      _flutterApiSetUp = false;
    }
    if (!_sensorController.isClosed) {
      unawaited(_sensorController.close());
    }
  }
}
