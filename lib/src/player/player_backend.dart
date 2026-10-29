import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import '../data/models/navite_file.dart';
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
  /// On PlatformView platforms (iOS/macOS/Android) native `create` returns `0`
  /// (not a Flutter [Texture] id). The picture is shown via the registered
  /// PlatformView (`plugins.xuehua/navite_video_player`).
  FlutterSignal<int?> get textureId;

  /// Typed events from the native (or fake) player.
  Stream<PlayerEvent> get events;

  /// Acquires the single native session and registers a texture / platform view.
  Future<int> create();

  /// Opens [url] on the active session.
  ///
  /// [castUrl] is an optional HTTP(S) URL used by remote cast receivers when
  /// [url] is a local `file://` path, loopback proxy, or custom cache scheme.
  /// [cacheKey], [headers], and [enableCache] forward media cache parameters to
  /// native backends that manage disk caching directly.
  Future<void> open(
    String url, {
    String? castUrl,
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  });

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

  /// Presents the operating system's native wireless cast / route picker.
  Future<void> showCastPicker() async {}

  /// Disconnects the active wireless cast session and returns playback locally.
  Future<void> stopCasting() async {}

  Future<void> dispose();

  Future<NaviteFile> takeSnapshot({String? savePath});
}
