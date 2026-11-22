import '../pigeon/orientation_api.g.dart';
import 'method_channel_player_orientation.dart';

/// 跨平台播放器设备方向控制与物理重力传感器抽象平台接口。
///
/// Android / iOS 默认由 [MethodChannelPlayerOrientation]（基于 Pigeon 类型安全通道）实现，
/// Web 平台在插件注册时替换为 `WebPlayerOrientation`（基于 `package:web` 与 `dart:js_interop`）。
///
/// Platform interface for cross-platform player orientation control and physical
/// gravity sensor streaming across Android, iOS, and Mobile Web.
abstract class PlayerOrientationPlatform {
  /// 当前进程活跃的平台方向实现实例。
  ///
  /// Active process-wide [PlayerOrientationPlatform] instance.
  static PlayerOrientationPlatform instance = MethodChannelPlayerOrientation();

  /// 原生或浏览器重力传感器上报的物理朝向变化事件流（已经过滞回与防抖过滤）。
  ///
  /// Broadcast stream of debounced physical orientation events from gravity sensors.
  Stream<OrientationSensorEvent> get physicalOrientationStream;

  /// 当前平台是否需要通过 CSS Transform（`WebOrientationViewport`）降级模拟全屏横屏旋转。
  ///
  /// 仅在不支持 `screen.orientation.lock()` 的 iOS Safari 移动端 Web 环境中为 `true`。
  ///
  /// Whether this platform requires CSS transform fallback rotation (e.g. iOS Safari).
  bool get usesCssFallbackRotation => false;

  /// 强制切换至目标显示方向（无视系统控制中心竖屏锁定 / 自动旋转开关）。
  ///
  /// Forces the display to [orientation], overriding system orientation lock.
  Future<void> setTargetOrientation(DevicePhysicalOrientation orientation);

  /// 读取当前界面实际所处的方向（锁屏时据此锁定当前方向，彻底避免 iOS 180° 翻转）。
  ///
  /// Queries the current active interface orientation.
  Future<DevicePhysicalOrientation> getCurrentOrientation();

  /// 开启物理重力传感器监听。
  ///
  /// Starts listening to physical gravity/orientation sensor updates.
  Future<void> startSensorListening();

  /// 停止物理重力传感器监听。
  ///
  /// Stops listening to physical gravity/orientation sensor updates.
  Future<void> stopSensorListening();

  /// 进入或退出沉浸式全屏（系统栏 / 浏览器全屏）。
  ///
  /// Enters or exits immersive fullscreen mode.
  Future<void> setImmersiveFullscreen(bool enabled);

  /// 请求传感器授权（主要用于 iOS 13+ Safari 的 `DeviceOrientationEvent.requestPermission()`）。
  ///
  /// Requests sensor permission where required (iOS 13+ Safari). Returns `true` when granted.
  Future<bool> requestSensorPermission() async => true;

  /// 释放内部监听与流资源。
  ///
  /// Disposes internal subscriptions and stream controllers.
  void dispose();
}
