import '../bridge/video_player_host_bridge.dart';

/// Abstracts application brightness for testability.
abstract class BrightnessController {
  Future<double> get current;

  Future<void> setBrightness(double value);
}

/// Default [VideoPlayerHostBridge]-backed brightness controller.
///
/// Native brightness is implemented on Android, iOS, macOS, Windows, and Linux.
/// Web no-ops (get returns 1.0; set is ignored). Other failures are swallowed.
class ChannelBrightnessController implements BrightnessController {
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
