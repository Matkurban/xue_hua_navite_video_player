// 生成命令 / Generation command:
// dart run pigeon --input pigeons/orientation_api.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/pigeon/orientation_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/com/kurban/xue_hua_navite_video_player/OrientationApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.kurban.xue_hua_navite_video_player',
      errorClassName: 'OrientationFlutterError',
    ),
    swiftOut: 'ios/xue_hua_navite_video_player/Sources/xue_hua_navite_video_player/OrientationApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'OrientationPigeonError'),
    dartPackageName: 'xue_hua_navite_video_player',
  ),
)
/// 设备真实物理朝向枚举（主动过滤倒置 `portraitDown` 与平放干扰）。
///
/// Physical device orientation enum with upside-down (`portraitDown`) and flat
/// postures actively filtered out.
enum DevicePhysicalOrientation {
  /// 竖屏正向（听筒/顶部朝上）。
  ///
  /// Upright portrait (device top facing up).
  portraitUp,

  /// 横屏正向（设备顶部朝左、充电口/Home 指示条朝右，相对竖屏逆时针 90°）。
  ///
  /// Standard landscape (device top on the left, 90° counter-clockwise from portrait).
  landscapeLeft,

  /// 横屏反向（设备顶部朝右、充电口/Home 指示条朝左，相对竖屏顺时针 90°）。
  ///
  /// Reverse landscape (device top on the right, 90° clockwise from portrait).
  landscapeRight,

  /// 未知、平放或被过滤的倒置姿态。
  ///
  /// Unknown, flat, or filtered upside-down posture.
  unknown,
}

/// 原生重力传感器上报的物理朝向事件载荷。
///
/// Physical orientation event payload emitted by native gravity/orientation sensors.
class OrientationSensorEvent {
  OrientationSensorEvent({
    required this.orientation,
    required this.confidence,
    required this.angleDegrees,
  });

  /// 解析后的真实物理朝向。
  ///
  /// Resolved physical device orientation.
  DevicePhysicalOrientation orientation;

  /// 传感器角度置信度（`0.0` ~ `1.0`，平放或处于临界滞回区时更低）。
  ///
  /// Sensor confidence score in `[0.0, 1.0]`.
  double confidence;

  /// 物理平面旋转角度（`0.0` ~ `360.0`，未知时为 `-1.0`）。
  ///
  /// Planar rotation angle in degrees (`0.0..360.0`, or `-1.0` when unknown).
  double angleDegrees;
}

/// Dart 调用原生平台（iOS / Android）进行屏幕方向控制与重力传感器管理的宿主接口。
///
/// Host API invoked by Dart to control screen orientation, immersive fullscreen,
/// and physical gravity sensor listening on iOS and Android.
@HostApi()
abstract class OrientationHostApi {
  /// 设置目标屏幕显示方向（无视系统控制中心竖屏锁定 / 自动旋转开关）。
  ///
  /// Sets the target interface orientation, overriding system orientation lock.
  @async
  void setTargetOrientation(DevicePhysicalOrientation orientation);

  /// 读取当前界面实际所处的方向（用于锁屏时精准锁定当前方向，避免 iOS 180° 翻转）。
  ///
  /// Returns the current active interface orientation so locking pins the exact
  /// current direction without triggering a spurious rotation.
  @async
  DevicePhysicalOrientation getCurrentOrientation();

  /// 开启原生平台物理重力传感器监听（iOS `CMMotionManager` / Android `OrientationEventListener`）。
  ///
  /// Starts native physical gravity sensor listening.
  void startSensorListening();

  /// 停止原生平台物理重力传感器监听并释放硬件采样。
  ///
  /// Stops native physical gravity sensor listening.
  void stopSensorListening();

  /// 进入或退出原生沉浸式全屏模式（隐藏/恢复状态栏与系统导航栏）。
  ///
  /// Enters or exits native immersive fullscreen (system bars / home indicator).
  @async
  void setImmersiveFullscreen(bool enabled);
}

/// 原生平台主动向 Dart 推送物理朝向变化事件的回调接口。
///
/// Flutter API called by native platforms to push debounced physical orientation
/// updates to Dart.
@FlutterApi()
abstract class OrientationFlutterApi {
  /// 当原生重力传感器经过滞回与防抖确认物理朝向变更时触发。
  ///
  /// Invoked when the native gravity sensor confirms a debounced physical
  /// orientation change.
  void onPhysicalOrientationChanged(OrientationSensorEvent event);
}
