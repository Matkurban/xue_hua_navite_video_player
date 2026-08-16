import 'package:flutter/services.dart';

/// Abstracts application brightness for testability.
abstract class BrightnessController {
  Future<double> get current;

  Future<void> setBrightness(double value);
}

/// Default MethodChannel-backed controller.
///
/// Native brightness is implemented on Android, iOS, macOS, Windows, and Linux.
/// Web no-ops (get returns 1.0; set is ignored). Other failures are swallowed.
class ChannelBrightnessController implements BrightnessController {
  ChannelBrightnessController({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('xue_hua_navite_video_player/player');

  final MethodChannel _channel;

  @override
  Future<double> get current async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getBrightness');
      final value = switch (raw) {
        final double v => v,
        final num v => v.toDouble(),
        _ => 1.0,
      };
      return value.clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

  @override
  Future<void> setBrightness(double value) async {
    try {
      await _channel.invokeMethod('setBrightness', {'value': value.clamp(0.0, 1.0)});
    } catch (_) {
      // Unsupported platforms — ignore.
    }
  }
}
