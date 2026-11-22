import '../pigeon/orientation_api.g.dart';
import 'player_orientation_platform.dart';

/// 非 Web 平台下的 [WebPlayerOrientation] 占位实现，保持跨平台条件导入安全编译。
///
/// Non-Web stub for [WebPlayerOrientation] keeping conditional imports safe.
class WebPlayerOrientation extends PlayerOrientationPlatform {
  @override
  Stream<OrientationSensorEvent> get physicalOrientationStream =>
      const Stream<OrientationSensorEvent>.empty();

  @override
  Future<void> setTargetOrientation(DevicePhysicalOrientation orientation) async {}

  @override
  Future<DevicePhysicalOrientation> getCurrentOrientation() async =>
      DevicePhysicalOrientation.unknown;

  @override
  Future<void> startSensorListening() async {}

  @override
  Future<void> stopSensorListening() async {}

  @override
  Future<void> setImmersiveFullscreen(bool enabled) async {}

  @override
  void dispose() {}
}
