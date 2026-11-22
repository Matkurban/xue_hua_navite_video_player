import '../bridge/video_player_host_bridge.dart';

/// 屏幕亮度控制抽象接口（便于在单元测试中替换实现）。
///
/// Abstracts application screen brightness control for testability.
abstract class BrightnessController {
  /// 读取当前屏幕亮度值（范围 `0.0..1.0`）。
  ///
  /// Reads the current screen brightness normalized to `0.0..1.0`.
  Future<double> get current;

  /// 将屏幕亮度设置为 [value]（范围 `0.0..1.0`）。
  ///
  /// Sets the screen brightness to [value] (`0.0..1.0`).
  Future<void> setBrightness(double value);
}

/// 基于 [VideoPlayerHostBridge] 的默认屏幕亮度控制器实现。
///
/// Android、iOS、macOS、Windows 与 Linux 均提供原生亮度调节，并在播放器释放时自动恢复；
/// Web 平台为空操作（读取返回 `1.0`，写入静默忽略）。
///
/// Default [VideoPlayerHostBridge]-backed brightness controller. Native
/// brightness is implemented on Android, iOS, macOS, Windows, and Linux; Web no-ops.
class ChannelBrightnessController implements BrightnessController {
  /// 创建通道亮度控制器，可选传入测试用 [bridge]。
  ///
  /// Creates a [ChannelBrightnessController] with an optional [bridge] override.
  ChannelBrightnessController({this._bridge});

  final VideoPlayerHostBridge? _bridge;

  VideoPlayerHostBridge get _resolvedBridge => _bridge ?? VideoPlayerHostBridge.instance;

  @override
  Future<double> get current async {
    try {
      final value = await _resolvedBridge.getBrightness();
      return value.clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

  @override
  Future<void> setBrightness(double value) async {
    try {
      await _resolvedBridge.setBrightness(value.clamp(0.0, 1.0));
    } catch (_) {
      // Unsupported platforms — ignore.
    }
  }
}
