import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/video_source.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/cast_state.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../utils/mime_detector.dart';
import 'brightness_controller.dart';
import 'channel_player_backend.dart';
import 'fullscreen_coordinator.dart';
import 'local_cast_http_server.dart';
import 'playback_session_state.dart';
import 'player_backend.dart';
import 'player_event.dart';

/// Deep module owning open→ready→playing/paused/stopped/completed/error for one session.
///
/// Projects [PlayerBackend] events into signals. Session reset on [openSource]
/// lives here (not in the transport backend).
///
/// Process-wide: one active native session (see [PlayerBackend]).
class PlaybackSession {
  static PlaybackSession? _activeNativeSession;

  final PlayerBackend _backend;
  final FullscreenCoordinator _fullscreen;
  final BrightnessController _brightness;
  final LocalCastHttpServer _localCastServer;
  final PlaybackSessionState _state = PlaybackSessionState();

  StreamSubscription<PlayerEvent>? _eventSubscription;
  StreamSubscription<bool>? _fullscreenExternalSub;
  Timer? _readyFallbackTimer;

  bool _disposed = false;
  bool _holdsNativeSession = false;
  int _openEpoch = 0;
  int _activeEventEpoch = 0;

  bool _hasPlayedSinceOpen = false;
  bool _hasReadySinceOpen = false;
  bool _hasReceivedMetadata = false;
  bool _backendPlaying = false;
  bool _backendBuffering = false;
  Duration _backendDuration = Duration.zero;
  double _volumeBeforeMute = 1.0;

  /// Live / audio-only streams may never emit a positive duration.
  @visibleForTesting
  static Duration readyFallbackDelay = const Duration(seconds: 3);

  FlutterSignal<PlayState> get playState => _state.playState;
  FlutterSignal<Duration> get position => _state.position;
  FlutterSignal<Duration> get duration => _state.duration;
  FlutterSignal<double> get volume => _state.volume;
  FlutterSignal<double> get speed => _state.speed;
  FlutterSignal<bool> get isBuffering => _state.isBuffering;
  FlutterSignal<String?> get errorMessage => _state.errorMessage;
  FlutterSignal<String?> get currentUrl => _state.currentUrl;
  FlutterSignal<String?> get mimeType => _state.mimeType;
  FlutterSignal<Size> get videoSize => _state.videoSize;
  FlutterSignal<int> get rotationDegrees => _state.rotationDegrees;
  FlutterSignal<bool> get muted => _state.muted;
  FlutterSignal<SkipSecondType> get skipSecondType => _state.skipSecondType;
  FlutterSignal<AspectRatioMode> get aspectRatioMode => _state.aspectRatioMode;
  FlutterSignal<bool> get isFullscreen => _state.isFullscreen;
  FlutterSignal<double> get brightness => _state.brightness;
  FlutterSignal<CastState> get castState => _state.castState;
  FlutterSignal<String?> get castDeviceName => _state.castDeviceName;

  FlutterComputed<double> get videoAspectRatio => _state.videoAspectRatio;
  FlutterComputed<bool> get isVideo => _state.isVideo;
  FlutterComputed<bool> get isAudio => _state.isAudio;
  FlutterComputed<bool> get isPlaying => _state.isPlaying;
  FlutterComputed<double> get progressPercent => _state.progressPercent;
  FlutterComputed<bool> get isCastSupported => _state.isCastSupported;
  FlutterComputed<bool> get isCasting => _state.isCasting;

  PlaybackSession({
    PlayerBackend? backend,
    FullscreenCoordinator? fullscreen,
    BrightnessController? brightness,
    LocalCastHttpServer? localCastServer,
  }) : _backend = backend ?? ChannelPlayerBackend(),
       _fullscreen = fullscreen ?? SystemChromeFullscreenCoordinator(),
       _brightness = brightness ?? ChannelBrightnessController(),
       _localCastServer = localCastServer ?? LocalCastHttpServer() {
    _fullscreenExternalSub = _fullscreen.externalChanges.listen(_onExternalFullscreen);
  }

  FlutterSignal<int?> get textureId => _backend.textureId;

  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('PlaybackSession has been disposed.');
    }
    _acquireNativeSession();
    // Listen before create() so broadcast events emitted during create are not lost.
    await _eventSubscription?.cancel();
    _eventSubscription = _backend.events.listen(_onPlayerEvent);
    try {
      await _backend.create();
    } catch (_) {
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _releaseNativeSession();
      rethrow;
    }
    if (_disposed) return;
    // Sync initial aspect mode to native.
    await _backend.setAspectRatioMode(aspectRatioMode.value);
    try {
      brightness.value = await _brightness.current;
    } catch (_) {}
  }

  void _acquireNativeSession() {
    if (_backend is! ChannelPlayerBackend) return;
    if (_holdsNativeSession) return;
    if (_activeNativeSession != null && _activeNativeSession != this) {
      throw StateError(
        'Process-wide invariant: only one native PlaybackSession may be active. '
        'Dispose the existing controller before creating another.',
      );
    }
    _activeNativeSession = this;
    _holdsNativeSession = true;
  }

  void _releaseNativeSession() {
    if (!_holdsNativeSession) return;
    _holdsNativeSession = false;
    if (_activeNativeSession == this) {
      _activeNativeSession = null;
    }
  }

  void _onPlayerEvent(PlayerEvent event) {
    if (_disposed) return;
    // Cast capability & session state events can arrive during create() before
    // any media is opened, or across openSource() transitions.
    if (event is PlayerCastStateEvent) {
      batch(() {
        castState.value = event.state;
        if (event.state == CastState.notConnected || event.state == CastState.unavailable) {
          castDeviceName.value = null;
        } else if (event.deviceName != null) {
          castDeviceName.value = event.deviceName;
        }
      });
      return;
    }
    // Ignore native events before the first open (e.g. mpv's initial
    // `pause=no` property notification) so a fresh session stays idle.
    if (_openEpoch == 0 || _activeEventEpoch != _openEpoch) return;

    switch (event) {
      case PlayerPlayingEvent(:final playing):
        _handlePlayingEvent(playing);
      case PlayerPositionEvent(:final position):
        if (_hasReadySinceOpen && playState.value != PlayState.error) {
          this.position.value = position;
        }
      case PlayerDurationEvent(:final duration):
        _handleDurationEvent(duration);
      case PlayerBufferingEvent(:final buffering):
        if (playState.value != PlayState.error) {
          _backendBuffering = buffering;
          if (_hasReadySinceOpen) {
            isBuffering.value = buffering;
          }
        }
      case PlayerErrorEvent(:final message):
        isBuffering.value = false;
        errorMessage.value = message;
        playState.value = PlayState.error;
      case PlayerCompletedEvent():
        if (_hasPlayedSinceOpen && playState.value != PlayState.error) {
          playState.value = PlayState.completed;
        }
      case PlayerVideoSizeEvent(:final size, :final rotationDegrees):
        _handleVideoSizeEvent(size, rotationDegrees);
      case PlayerCastStateEvent():
        break;
    }
  }

  void _handlePlayingEvent(bool playing) {
    if (playState.value == PlayState.error) return;
    _backendPlaying = playing;
    if (playing) {
      final wasFirstPlay = !_hasPlayedSinceOpen;
      _hasPlayedSinceOpen = true;
      _markReadySinceOpen();
      if (wasFirstPlay && _backendDuration > Duration.zero) {
        duration.value = _backendDuration;
      }
      playState.value = PlayState.playing;
      return;
    }
    if (!_hasReadySinceOpen) {
      if (_hasReceivedMetadata) {
        _markReadySinceOpen();
      }
      return;
    }
    if (playState.value == PlayState.stopped || playState.value == PlayState.completed) {
      return;
    }
    if ((_backendBuffering || isBuffering.value) && playState.value == PlayState.playing) {
      return;
    }
    playState.value = PlayState.paused;
  }

  void _handleDurationEvent(Duration reportedDuration) {
    if (playState.value == PlayState.error) return;
    _hasReceivedMetadata = true;
    _backendDuration = reportedDuration;
    if (!_hasReadySinceOpen) {
      _markReadySinceOpen();
    }
    if (_hasReadySinceOpen) {
      duration.value = reportedDuration;
    }
  }

  void _handleVideoSizeEvent(Size size, int rotationDegrees) {
    if (playState.value == PlayState.error) return;
    videoSize.value = size;
    this.rotationDegrees.value = rotationDegrees;
    if (size.width > 0 && size.height > 0) {
      _hasReceivedMetadata = true;
      if (!_hasReadySinceOpen) {
        _markReadySinceOpen();
      }
    }
  }

  void _markReadySinceOpen() {
    if (_hasReadySinceOpen) return;
    _hasReadySinceOpen = true;

    if (_backendDuration > Duration.zero) {
      duration.value = _backendDuration;
    }
    isBuffering.value = _backendBuffering;

    if (!_backendPlaying && playState.value == PlayState.loading) {
      playState.value = PlayState.paused;
    }
  }

  Future<void> playNetwork(String url) => openSource(VideoSource.network(url), autoPlay: true);

  Future<void> openNetwork(String url) => openSource(VideoSource.network(url), autoPlay: false);

  Future<void> playFile(String path) => openSource(VideoSource.file(path), autoPlay: true);

  Future<void> openFile(String path) => openSource(VideoSource.file(path), autoPlay: false);

  Future<void> playAsset(String assetPath, {AssetBundle? bundle}) =>
      openSource(VideoSource.asset(assetPath, bundle: bundle), autoPlay: true);

  Future<void> openAsset(String assetPath, {AssetBundle? bundle}) =>
      openSource(VideoSource.asset(assetPath, bundle: bundle), autoPlay: false);

  Future<void> playSource(VideoSource source) => openSource(source, autoPlay: true);

  Future<void> openSource(VideoSource source, {bool autoPlay = false}) async {
    if (_disposed) return;

    final epoch = ++_openEpoch;
    try {
      reset();

      final identity = source.identity;
      currentUrl.value = identity;
      mimeType.value = MimeDetector.detect(identity);
      playState.value = PlayState.loading;

      final mediaUrl = await source.resolveToNativeUrl();
      if (_disposed || epoch != _openEpoch) return;

      final castUrl = await _resolveCastUrl(source, mediaUrl);
      if (_disposed || epoch != _openEpoch) return;

      await _backend.open(mediaUrl, castUrl: castUrl);
      if (_disposed || epoch != _openEpoch) return;
      _activeEventEpoch = epoch;
      _scheduleReadyFallback(epoch);

      // Re-apply session volume/speed/aspect; native players usually reset on open.
      await _backend.setVolume(muted.value ? 0 : volume.value);
      if (_disposed || epoch != _openEpoch) return;
      await _backend.setSpeed(speed.value);
      if (_disposed || epoch != _openEpoch) return;
      await _backend.setAspectRatioMode(aspectRatioMode.value);
      if (_disposed || epoch != _openEpoch) return;

      if (autoPlay) {
        await _backend.play();
      }
    } catch (e) {
      if (_disposed || epoch != _openEpoch) return;
      errorMessage.value = e.toString();
      playState.value = PlayState.error;
    }
  }

  Future<String?> _resolveCastUrl(VideoSource source, String mediaUrl) async {
    try {
      if (!source.isNetwork) {
        return await _localCastServer.serveLocalFileUrl(mediaUrl, mimeType: mimeType.value);
      }
      await _localCastServer.stop();
    } catch (_) {
      // Never allow local cast HTTP server setup to block normal video playback.
    }
    return null;
  }

  Future<void> play() async {
    if (_disposed) return;
    if (playState.value == PlayState.completed) {
      await _backend.seek(0);
      if (_disposed) return;
      position.value = Duration.zero;
    }
    await _backend.play();
  }

  Future<void> pause() async {
    if (_disposed) return;
    await _backend.pause();
  }

  Future<void> playOrPause() async {
    if (_disposed) return;
    if (isPlaying.value) {
      await _backend.pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration targetPosition) async {
    if (_disposed) return;
    final total = duration.value;
    var clamped = targetPosition < Duration.zero ? Duration.zero : targetPosition;
    if (total > Duration.zero && clamped > total) {
      clamped = total;
    }
    await _backend.seek(clamped.inMilliseconds);
    if (_disposed) return;
    position.value = clamped;
    // If the user seeks away from the end while in completed state, transition
    // to paused so that subsequent play() resumes from the seeked position
    // instead of resetting back to 00:00.
    if (playState.value == PlayState.completed && (total == Duration.zero || clamped < total)) {
      playState.value = _backendPlaying ? PlayState.playing : PlayState.paused;
    }
  }

  Future<void> setVolume(double value) async {
    if (_disposed) return;
    final clamped = value.clamp(0.0, 1.0);
    await _backend.setVolume(clamped);
    volume.value = clamped;
    if (clamped > 0 && muted.value) {
      muted.value = false;
    } else if (clamped == 0) {
      muted.value = true;
    }
  }

  Future<void> setMuted(bool value) async {
    if (_disposed) return;
    if (value) {
      if (!muted.value) {
        _volumeBeforeMute = volume.value > 0 ? volume.value : 1.0;
      }
      muted.value = true;
      await _backend.setVolume(0);
      volume.value = 0;
    } else {
      muted.value = false;
      final restore = _volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0;
      await _backend.setVolume(restore);
      volume.value = restore;
    }
  }

  Future<void> toggleMuted() => setMuted(!muted.value);

  void setSkipSecondType(SkipSecondType type) {
    skipSecondType.value = type;
  }

  Future<void> seekForward() => _seekBy(skipSecondType.value.duration);

  Future<void> seekBackward() => _seekBy(-skipSecondType.value.duration);

  Future<void> _seekBy(Duration delta) async {
    if (_disposed) return;
    var target = position.value + delta;
    if (target < Duration.zero) target = Duration.zero;
    final total = duration.value;
    if (total > Duration.zero && target > total) target = total;
    await seek(target);
  }

  Future<void> setAspectRatioMode(AspectRatioMode mode) async {
    if (_disposed) return;
    aspectRatioMode.value = mode;
    await _backend.setAspectRatioMode(mode);
  }

  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  }) async {
    if (_disposed) return;
    if (width <= 0 || height <= 0) return;
    await _backend.setVideoViewSize(
      width: width,
      height: height,
      devicePixelRatio: devicePixelRatio,
    );
  }

  /// Presents the operating system's native wireless cast / route picker.
  Future<void> showCastPicker() async {
    if (_disposed) return;
    await _backend.showCastPicker();
  }

  /// Disconnects the active wireless cast session and returns playback locally.
  Future<void> stopCasting() async {
    if (_disposed) return;
    await _backend.stopCasting();
  }

  /// See [VideoPlayerController.enterFullscreen] for the UI contract.
  Future<void> enterFullscreen() async {
    if (_disposed || isFullscreen.value) return;
    final landscape = videoAspectRatio.value > 1.0;
    isFullscreen.value = true;
    await _fullscreen.enter(landscapeVideo: landscape);
  }

  Future<void> exitFullscreen() async {
    if (_disposed || !isFullscreen.value) return;
    isFullscreen.value = false;
    await _fullscreen.exit();
  }

  Future<void> toggleFullscreen() async {
    if (isFullscreen.value) {
      await exitFullscreen();
    } else {
      await enterFullscreen();
    }
  }

  Future<void> setBrightness(double value) async {
    if (_disposed) return;
    final clamped = value.clamp(0.0, 1.0);
    await _brightness.setBrightness(clamped);
    brightness.value = clamped;
  }

  Future<void> setSpeed(double value) async {
    if (_disposed) return;
    await _backend.setSpeed(value);
    speed.value = value;
  }

  Future<void> stop() async {
    if (_disposed) return;
    await _backend.pause();
    playState.value = PlayState.stopped;
  }

  Future<XFile> takeSnapshot({String? savePath}) async {
    if (_disposed) {
      throw StateError('PlaybackSession has been disposed.');
    }
    if (currentUrl.value == null) {
      throw StateError('No media is currently loaded.');
    }
    return _backend.takeSnapshot(savePath: savePath);
  }

  void _onExternalFullscreen(bool fullscreen) {
    if (_disposed) return;
    if (isFullscreen.value == fullscreen) return;
    isFullscreen.value = fullscreen;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    if (isFullscreen.value) {
      try {
        await _fullscreen.exit();
      } catch (_) {}
      isFullscreen.value = false;
    }
    _disposed = true;
    _openEpoch++;
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = null;
    await _fullscreenExternalSub?.cancel();
    _fullscreenExternalSub = null;
    _fullscreen.dispose();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _localCastServer.stop();
    await _backend.dispose();
    castState.value = CastState.unavailable;
    castDeviceName.value = null;
    _releaseNativeSession();
  }

  void _scheduleReadyFallback(int epoch) {
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = Timer(readyFallbackDelay, () {
      if (_disposed || epoch != _openEpoch) return;
      if (!_hasReadySinceOpen && playState.value == PlayState.loading) {
        _markReadySinceOpen();
      }
    });
  }

  void reset() {
    _readyFallbackTimer?.cancel();
    _readyFallbackTimer = null;
    _hasPlayedSinceOpen = false;
    _hasReadySinceOpen = false;
    _hasReceivedMetadata = false;
    _backendPlaying = false;
    _backendBuffering = false;
    _backendDuration = Duration.zero;
    _state.resetMediaSignals();
  }
}
