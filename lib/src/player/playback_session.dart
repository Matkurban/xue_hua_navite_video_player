import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/video_source.dart';
import '../data/enums/aspect_ratio_mode.dart';
import '../data/enums/play_state.dart';
import '../data/enums/skip_second_type.dart';
import '../utils/mime_detector.dart';
import 'brightness_controller.dart';
import 'channel_player_backend.dart';
import 'fullscreen_coordinator.dart';
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

  StreamSubscription<PlayerEvent>? _eventSubscription;
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

  final FlutterSignal<PlayState> playState = signal(PlayState.idle);
  final FlutterSignal<Duration> position = signal(Duration.zero);
  final FlutterSignal<Duration> duration = signal(Duration.zero);
  final FlutterSignal<double> volume = signal(1.0);
  final FlutterSignal<double> speed = signal(1.0);
  final FlutterSignal<bool> isBuffering = signal(false);
  final FlutterSignal<String?> errorMessage = signal<String?>(null);
  final FlutterSignal<String?> currentUrl = signal<String?>(null);
  final FlutterSignal<String?> mimeType = signal<String?>(null);
  final FlutterSignal<Size> videoSize = signal<Size>(Size.zero);
  final FlutterSignal<int> rotationDegrees = signal<int>(0);
  final FlutterSignal<bool> muted = signal(false);
  final FlutterSignal<SkipSecondType> skipSecondType = signal(SkipSecondType.second10);
  final FlutterSignal<AspectRatioMode> aspectRatioMode = signal(AspectRatioMode.fit);
  final FlutterSignal<bool> isFullscreen = signal(false);
  final FlutterSignal<double> brightness = signal(1.0);

  late final FlutterComputed<double> videoAspectRatio = computed(() {
    final size = videoSize.value;
    if (size.width <= 0 || size.height <= 0) return 16 / 9;
    final rot = rotationDegrees.value % 360;
    if (rot == 90 || rot == 270) {
      return size.height / size.width;
    }
    return size.width / size.height;
  });

  late final FlutterComputed<bool> isVideo = computed(() {
    return mimeType.value?.startsWith('video/') ?? false;
  });

  late final FlutterComputed<bool> isAudio = computed(() {
    return mimeType.value?.startsWith('audio/') ?? false;
  });

  late final FlutterComputed<bool> isPlaying = computed(() {
    return playState.value == PlayState.playing;
  });

  late final FlutterComputed<double> progressPercent = computed(() {
    if (duration.value.inMilliseconds == 0) return 0.0;
    return position.value.inMilliseconds / duration.value.inMilliseconds;
  });

  PlaybackSession({
    PlayerBackend? backend,
    FullscreenCoordinator? fullscreen,
    BrightnessController? brightness,
  }) : _backend = backend ?? ChannelPlayerBackend(),
       _fullscreen = fullscreen ?? SystemChromeFullscreenCoordinator(),
       _brightness = brightness ?? ChannelBrightnessController();

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
    if (_activeEventEpoch != _openEpoch) return;
    switch (event) {
      case PlayerPlayingEvent(:final playing):
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
          // Live / audio-only: native may report paused after metadata without
          // a positive duration.
          if (_hasReceivedMetadata) {
            _markReadySinceOpen();
          }
          return;
        }
        // Keep explicit stop / natural EOS; do not collapse into paused.
        if (playState.value == PlayState.stopped || playState.value == PlayState.completed) {
          return;
        }
        // Buffering stalls (e.g. 4K network) may emit playing=false while the
        // session still intends to play — keep PlayState.playing.
        if (_backendBuffering || isBuffering.value) {
          if (playState.value == PlayState.playing) {
            return;
          }
        }
        playState.value = PlayState.paused;
      case PlayerPositionEvent(:final position):
        if (!_hasReadySinceOpen) return;
        this.position.value = position;
      case PlayerDurationEvent(:final duration):
        _hasReceivedMetadata = true;
        _backendDuration = duration;
        if (!_hasReadySinceOpen) {
          _markReadySinceOpen();
        }
        if (!_hasReadySinceOpen) return;
        this.duration.value = duration;
      case PlayerBufferingEvent(:final buffering):
        _backendBuffering = buffering;
        if (!_hasReadySinceOpen) return;
        isBuffering.value = buffering;
      case PlayerErrorEvent(:final message):
        errorMessage.value = message;
        playState.value = PlayState.error;
      case PlayerCompletedEvent():
        if (!_hasPlayedSinceOpen) {
          return;
        }
        playState.value = PlayState.completed;
      case PlayerVideoSizeEvent(:final size, :final rotationDegrees):
        videoSize.value = size;
        this.rotationDegrees.value = rotationDegrees;
        if (size.width > 0 && size.height > 0) {
          _hasReceivedMetadata = true;
          if (!_hasReadySinceOpen) {
            _markReadySinceOpen();
          }
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

  Future<void> playNetwork(String url) {
    return openSource(VideoSource.network(url), autoPlay: true);
  }

  Future<void> openNetwork(String url) {
    return openSource(VideoSource.network(url), autoPlay: false);
  }

  Future<void> playFile(String path) {
    return openSource(VideoSource.file(path), autoPlay: true);
  }

  Future<void> openFile(String path) {
    return openSource(VideoSource.file(path), autoPlay: false);
  }

  Future<void> playAsset(String assetPath, {AssetBundle? bundle}) {
    return openSource(VideoSource.asset(assetPath, bundle: bundle), autoPlay: true);
  }

  Future<void> openAsset(String assetPath, {AssetBundle? bundle}) {
    return openSource(VideoSource.asset(assetPath, bundle: bundle), autoPlay: false);
  }

  Future<void> playSource(VideoSource source) {
    return openSource(source, autoPlay: true);
  }

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

      await _backend.open(mediaUrl);
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

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    await _backend.seek(position.inMilliseconds);
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

  /// See [VideoPlayerController.enterFullscreen] for the UI contract.
  Future<void> enterFullscreen() async {
    if (_disposed || isFullscreen.value) return;
    final landscape = videoAspectRatio.value > 1.0;
    // Signal UI first so OverlayPortal can reparent the PlatformView before
    // the orientation change queues a VirtualDisplay resize.
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
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _backend.dispose();
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
    batch(() {
      playState.value = PlayState.idle;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      isBuffering.value = false;
      errorMessage.value = null;
      currentUrl.value = null;
      mimeType.value = null;
      videoSize.value = Size.zero;
      rotationDegrees.value = 0;
    });
  }
}
