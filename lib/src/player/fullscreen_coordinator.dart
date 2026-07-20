import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Applies / restores system UI and orientation for fullscreen.
///
/// Extracted so [PlaybackSession] can be unit-tested with a fake coordinator.
abstract class FullscreenCoordinator {
  Future<void> enter({required bool landscapeVideo});

  Future<void> exit();
}

/// Default [SystemChrome]-backed coordinator.
class SystemChromeFullscreenCoordinator implements FullscreenCoordinator {
  @override
  Future<void> enter({required bool landscapeVideo}) async {
    if (kIsWeb) return;

    final isMobile =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;

    if (isMobile) {
      if (landscapeVideo) {
        await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Future<void> exit() async {
    if (kIsWeb) return;

    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
