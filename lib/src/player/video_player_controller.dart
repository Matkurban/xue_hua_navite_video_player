import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/video_source.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import 'brightness_controller.dart';
import 'fullscreen_coordinator.dart';
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
  }) : _session = PlaybackSession(backend: backend, fullscreen: fullscreen, brightness: brightness);

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
  FlutterSignal<SkipSecondType> get skipSecondType => _session.skipSecondType;
  FlutterSignal<AspectRatioMode> get aspectRatioMode => _session.aspectRatioMode;
  FlutterSignal<bool> get isFullscreen => _session.isFullscreen;
  FlutterSignal<double> get brightness => _session.brightness;

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

  Future<void> playSource(VideoSource source) => _session.playSource(source);

  Future<void> openSource(VideoSource source) => _session.openSource(source);

  Future<void> play() => _session.play();

  Future<void> pause() => _session.pause();

  Future<void> playOrPause() => _session.playOrPause();

  Future<void> seek(Duration position) => _session.seek(position);

  Future<void> setVolume(double value) => _session.setVolume(value);

  Future<void> setMuted(bool value) => _session.setMuted(value);

  Future<void> toggleMuted() => _session.toggleMuted();

  void setSkipSecondType(SkipSecondType type) => _session.setSkipSecondType(type);

  Future<void> seekForward() => _session.seekForward();

  Future<void> seekBackward() => _session.seekBackward();

  Future<void> setAspectRatioMode(AspectRatioMode mode) => _session.setAspectRatioMode(mode);

  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) => _session.setVideoViewSize(width: width, height: height, devicePixelRatio: devicePixelRatio);

  /// Enters fullscreen mode: updates [isFullscreen] and applies system chrome /
  /// preferred orientation (based on [videoAspectRatio]).
  ///
  /// Visual fullscreen (edge-to-edge Overlay + chrome / gestures) requires a
  /// mounted [VideoPlayer] under an [Overlay] ancestor. Calling this with only
  /// a [CorePlayer] (or no UI) still changes orientation / immersive UI.
  Future<void> enterFullscreen() => _session.enterFullscreen();

  /// Leaves fullscreen: restores system UI and clears [isFullscreen].
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
  Future<XFile> takeSnapshot({String? savePath}) => _session.takeSnapshot(savePath: savePath);

  Future<void> dispose() => _session.dispose();

  void reset() => _session.reset();
}
