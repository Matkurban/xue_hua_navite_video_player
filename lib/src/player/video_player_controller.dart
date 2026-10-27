import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/cast_state.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';
import 'brightness_controller.dart';
import 'fullscreen_coordinator.dart';
import 'local_cast_http_server.dart';
import 'playback_session.dart';
import 'player_backend.dart';

/// Public facade over [PlaybackSession] (stable call-site name).
///
/// Playback state rules live in [PlaybackSession]; this type forwards the
/// public surface used by UI and apps.
class VideoPlayerController {
  VideoPlayerController({
    PlayerBackend? backend,
    FullscreenCoordinator? fullscreen,
    BrightnessController? brightness,
    LocalCastHttpServer? localCastServer,
  }) : _session = PlaybackSession(
         backend: backend,
         fullscreen: fullscreen,
         brightness: brightness,
         localCastServer: localCastServer,
       );

  final PlaybackSession _session;

  FlutterSignal<PlayState> get playState => _session.playState;
  FlutterSignal<Duration> get position => _session.position;
  FlutterSignal<Duration> get duration => _session.duration;
  FlutterSignal<double> get volume => _session.volume;
  FlutterSignal<double> get speed => _session.speed;
  FlutterSignal<bool> get isBuffering => _session.isBuffering;
  FlutterSignal<String?> get errorMessage => _session.errorMessage;
  FlutterSignal<String?> get currentUrl => _session.currentUrl;
  FlutterSignal<String?> get mimeType => _session.mimeType;
  FlutterSignal<Size> get videoSize => _session.videoSize;
  FlutterSignal<int> get rotationDegrees => _session.rotationDegrees;
  FlutterComputed<double> get videoAspectRatio => _session.videoAspectRatio;
  FlutterComputed<bool> get isVideo => _session.isVideo;
  FlutterComputed<bool> get isAudio => _session.isAudio;
  FlutterComputed<bool> get isPlaying => _session.isPlaying;
  FlutterComputed<double> get progressPercent => _session.progressPercent;

  FlutterSignal<bool> get muted => _session.muted;
  FlutterSignal<bool> get isLooping => _session.isLooping;
  FlutterSignal<SkipSecondType> get skipSecondType => _session.skipSecondType;
  FlutterSignal<AspectRatioMode> get aspectRatioMode => _session.aspectRatioMode;
  FlutterSignal<bool> get isFullscreen => _session.isFullscreen;
  FlutterSignal<double> get brightness => _session.brightness;

  /// Resolved Live Photo / Motion Photo bundle for the currently loaded media, if any.
  FlutterSignal<LivePhotoBundle?> get livePhotoBundle => _session.livePhotoBundle;

  /// True when the currently loaded media is a Live Photo / Motion Photo.
  FlutterComputed<bool> get isLivePhoto => _session.isLivePhoto;

  /// Parsed metadata for the currently loaded Live Photo / Motion Photo, if any.
  FlutterComputed<LivePhotoMetadata?> get livePhotoMetadata => _session.livePhotoMetadata;

  /// Extracted or paired still cover image file for the active Live Photo, if any.
  FlutterComputed<NaviteFile?> get livePhotoStillImage => _session.livePhotoStillImage;

  /// Current wireless casting state.
  FlutterSignal<CastState> get castState => _session.castState;

  /// Friendly name of the connected or connecting remote cast device, if any.
  FlutterSignal<String?> get castDeviceName => _session.castDeviceName;

  /// True when the current platform/environment supports wireless casting.
  FlutterComputed<bool> get isCastSupported => _session.isCastSupported;

  /// True when a cast session is currently connecting or connected.
  FlutterComputed<bool> get isCasting => _session.isCasting;

  FlutterSignal<int?> get textureId => _session.textureId;

  Future<void> initialize() => _session.initialize();

  Future<void> playNetwork(String url) => _session.playNetwork(url);

  Future<void> openNetwork(String url) => _session.openNetwork(url);

  Future<void> playFile(String path) => _session.playFile(path);

  Future<void> openFile(String path) => _session.openFile(path);

  Future<void> playAsset(String assetPath, {AssetBundle? bundle}) =>
      _session.playAsset(assetPath, bundle: bundle);

  Future<void> openAsset(String assetPath, {AssetBundle? bundle}) =>
      _session.openAsset(assetPath, bundle: bundle);

  /// Opens and starts playing a [LivePhotoSource] (paired image+video or single-file Motion Photo).
  Future<void> playLivePhoto(LivePhotoSource source, {bool? loop}) =>
      _session.playLivePhoto(source, loop: loop);

  /// Opens a [LivePhotoSource] without starting playback immediately.
  Future<void> openLivePhoto(LivePhotoSource source, {bool? loop}) =>
      _session.openLivePhoto(source, loop: loop);

  Future<void> playSource(VideoSource source) => _session.playSource(source);

  Future<void> openSource(VideoSource source) => _session.openSource(source);

  Future<void> play() => _session.play();

  Future<void> pause() => _session.pause();

  Future<void> playOrPause() => _session.playOrPause();

  Future<void> seek(Duration position) => _session.seek(position);

  Future<void> setVolume(double value) => _session.setVolume(value);

  Future<void> setMuted(bool value) => _session.setMuted(value);

  Future<void> toggleMuted() => _session.toggleMuted();

  /// Enables or disables automatic replay at end-of-stream.
  void setLooping(bool looping) => _session.setLooping(looping);

  /// Toggles [isLooping].
  void toggleLooping() => _session.toggleLooping();

  void setSkipSecondType(SkipSecondType type) => _session.setSkipSecondType(type);

  Future<void> seekForward() => _session.seekForward();

  Future<void> seekBackward() => _session.seekBackward();

  Future<void> setAspectRatioMode(AspectRatioMode mode) => _session.setAspectRatioMode(mode);

  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) => _session.setVideoViewSize(width: width, height: height, devicePixelRatio: devicePixelRatio);

  /// Presents the operating system's native wireless cast / route picker.
  Future<void> showCastPicker() => _session.showCastPicker();

  /// Disconnects the active wireless cast session and returns playback locally.
  Future<void> stopCasting() => _session.stopCasting();

  /// Enters fullscreen mode: updates [isFullscreen], then applies the platform
  /// host (mobile orientation / immersive UI, desktop window fullscreen, or
  /// the browser Fullscreen API).
  ///
  /// Visual fullscreen (edge-to-edge Overlay + chrome / gestures) requires a
  /// mounted [VideoPlayer] under an [Overlay] ancestor. Calling this with only
  /// a [CorePlayer] (or no UI) still changes the window / browser / orientation.
  Future<void> enterFullscreen() => _session.enterFullscreen();

  /// Leaves fullscreen: restores the window / browser / system UI and clears
  /// [isFullscreen].
  Future<void> exitFullscreen() => _session.exitFullscreen();

  Future<void> toggleFullscreen() => _session.toggleFullscreen();

  Future<void> setBrightness(double value) => _session.setBrightness(value);

  Future<void> setSpeed(double value) => _session.setSpeed(value);

  Future<void> stop() => _session.stop();

  /// Captures the current playback frame as PNG.
  ///
  /// On iOS/macOS this uses `AVAssetImageGenerator` at the current time (does
  /// not require Texture frame pushing). Other platforms use their native
  /// snapshot path.
  Future<NaviteFile> takeSnapshot({String? savePath}) => _session.takeSnapshot(savePath: savePath);

  Future<void> dispose() => _session.dispose();

  void reset() => _session.reset();
}
