import 'package:screen_brightness/screen_brightness.dart';

/// Abstracts application brightness for testability.
abstract class BrightnessController {
  Future<double> get current;

  Future<void> setBrightness(double value);
}

/// Default [ScreenBrightness]-backed controller.
class ScreenBrightnessController implements BrightnessController {
  @override
  Future<double> get current async {
    try {
      return await ScreenBrightness.instance.application;
    } catch (_) {
      return 1.0;
    }
  }

  @override
  Future<void> setBrightness(double value) async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(value.clamp(0.0, 1.0));
    } catch (_) {
      // Unsupported platforms (e.g. some desktops) — ignore.
    }
  }
}
