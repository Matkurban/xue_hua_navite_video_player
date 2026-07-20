import 'package:cross_file/cross_file.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import 'player_event.dart';

/// Session-transport seam for the single active native player.
///
/// Process-wide invariant: one native player behind the global channels.
/// [create] / [dispose] acquire and release that session — they are not a
/// multi-instance factory.
///
/// Does **not** include media probe (`getDuration` / `extractCovers`).
abstract class PlayerBackend {
  /// Flutter texture id after [create]; `null` before create or after dispose.
  ///
  /// On PlatformView platforms (iOS/macOS/Android) this may stay `null` while
  /// the native view is shown via [platformViewType].
  FlutterSignal<int?> get textureId;

  /// Typed events from the native (or fake) player.
  Stream<PlayerEvent> get events;

  /// Acquires the single native session and registers a texture / platform view.
  Future<int> create();

  /// Opens [url] on the active session.
  Future<void> open(String url);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(int positionMs);

  Future<void> setVolume(double volume);

  Future<void> setSpeed(double speed);

  /// Maps to each platform's official fit property (videoGravity / resizeMode /
  /// mpv keepaspect / object-fit).
  Future<void> setAspectRatioMode(AspectRatioMode mode);

  /// Updates the native render / output size (needed for mpv panscan relative
  /// to the Flutter view). No-op on PlatformView platforms that size themselves.
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  });

  Future<void> dispose();

  Future<XFile> takeSnapshot({String? savePath});
}
