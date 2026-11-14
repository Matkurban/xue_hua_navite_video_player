import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../pigeon/player_api.g.dart';
import 'bridge_env.dart';

/// Unified host bridge over Pigeon Native Interop (Android JNI, Apple FFI),
/// Pigeon channel hosts (Windows C++, Linux GObject), and direct Dart Web host.
abstract interface class VideoPlayerHostBridge {
  /// Active process-wide host bridge instance.
  ///
  /// Web registers its direct Dart implementation in [XueHuaNaviteVideoPlayerWeb.registerWith];
  /// IO platforms default to [PigeonVideoPlayerHostBridge].
  static VideoPlayerHostBridge instance = PigeonVideoPlayerHostBridge();

  /// Player lifecycle, playback state, metadata, video size, and cast events.
  Stream<PlayerEventData> get events;

  /// Window fullscreen notifications originating from native OS controls.
  Stream<bool> get fullscreenEvents;

  Future<int> create();

  Future<void> open(OpenMediaRequest request);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(int positionMs);

  Future<void> setVolume(double volume);

  Future<void> setSpeed(double speed);

  Future<void> setAspectRatioMode(NativeAspectRatioMode mode);

  Future<void> setVideoViewSize(double width, double height, double devicePixelRatio);

  Future<void> showCastPicker();

  Future<void> stopCasting();

  Future<void> dispose();

  Future<double> getBrightness();

  Future<void> setBrightness(double value);

  Future<void> setWindowFullscreen(bool value);

  Future<SnapshotData?> takeSnapshot();

  Future<int?> getDuration(DurationProbeRequest request);

  Future<List<CoverFrameData>> extractCovers(CoverExtractRequest request);

  Future<void> configureCache(CacheConfigRequest request);

  Future<void> precache(PrecacheRequest request);

  Future<void> cancelPrecache(String cacheKey);

  Future<bool> isCached(CacheEntryRequest request);

  Future<int> getCacheSize(String? cacheDir);

  Future<void> removeCache(CacheEntryRequest request);

  Future<void> clearCache(String? cacheDir);

  Future<void> pinCacheKey(String cacheKey);

  Future<void> unpinCacheKey(String cacheKey);
}

/// Default [VideoPlayerHostBridge] backed by Pigeon [PlayerHostApi] and
/// [PlayerFlutterApi].
///
/// Native Interop (`PlayerHostApi.createWithNativeInteropApi()`) is initialized
/// lazily so plugin registration never invokes JNI/FFI before engine startup.
class PigeonVideoPlayerHostBridge implements VideoPlayerHostBridge, PlayerFlutterApi {
  PigeonVideoPlayerHostBridge({
    @visibleForTesting PlayerHostApi? hostApi,
    @visibleForTesting this._binaryMessenger,
  }) : _hostApiOverride = hostApi;

  final PlayerHostApi? _hostApiOverride;
  final BinaryMessenger? _binaryMessenger;
  PlayerHostApi? _hostApi;
  bool _flutterApiSetUp = false;

  late final StreamController<PlayerEventData> _eventController =
      StreamController<PlayerEventData>.broadcast(onListen: _ensureFlutterApiSetUp);
  late final StreamController<bool> _fullscreenController =
      StreamController<bool>.broadcast(onListen: _ensureFlutterApiSetUp);

  bool get _usesNativeInterop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  PlayerHostApi _resolveHostApi() {
    final override = _hostApiOverride;
    if (override != null) {
      return override;
    }
    return _hostApi ??= _usesNativeInterop
        ? PlayerHostApi.createWithNativeInteropApi(binaryMessenger: _binaryMessenger)
        : PlayerHostApi(binaryMessenger: _binaryMessenger);
  }

  void _ensureFlutterApiSetUp() {
    if (kIsWeb || _flutterApiSetUp) {
      return;
    }
    _flutterApiSetUp = true;
    try {
      PlayerFlutterApi.setUp(this, binaryMessenger: _binaryMessenger);
    } catch (_) {
      if (!isFlutterTestEnvironment) {
        _flutterApiSetUp = false;
        rethrow;
      }
    }
  }

  @override
  Stream<PlayerEventData> get events => _eventController.stream;

  @override
  Stream<bool> get fullscreenEvents => _fullscreenController.stream;

  @override
  Future<void> onPlayerEvent(PlayerEventData event) async {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  @override
  Future<void> onWindowFullscreen(bool isFullscreen) async {
    if (!_fullscreenController.isClosed) {
      _fullscreenController.add(isFullscreen);
    }
  }

  @override
  Future<int> create() {
    _ensureFlutterApiSetUp();
    return _resolveHostApi().create();
  }

  @override
  Future<void> open(OpenMediaRequest request) {
    _ensureFlutterApiSetUp();
    return _resolveHostApi().open(request);
  }

  @override
  Future<void> play() => _resolveHostApi().play();

  @override
  Future<void> pause() => _resolveHostApi().pause();

  @override
  Future<void> seek(int positionMs) => _resolveHostApi().seek(positionMs);

  @override
  Future<void> setVolume(double volume) => _resolveHostApi().setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => _resolveHostApi().setSpeed(speed);

  @override
  Future<void> setAspectRatioMode(NativeAspectRatioMode mode) =>
      _resolveHostApi().setAspectRatioMode(mode);

  @override
  Future<void> setVideoViewSize(double width, double height, double devicePixelRatio) =>
      _resolveHostApi().setVideoViewSize(width, height, devicePixelRatio);

  @override
  Future<void> showCastPicker() => _resolveHostApi().showCastPicker();

  @override
  Future<void> stopCasting() => _resolveHostApi().stopCasting();

  @override
  Future<void> dispose() => _resolveHostApi().dispose();

  @override
  Future<double> getBrightness() => _resolveHostApi().getBrightness();

  @override
  Future<void> setBrightness(double value) => _resolveHostApi().setBrightness(value);

  @override
  Future<void> setWindowFullscreen(bool value) => _resolveHostApi().setWindowFullscreen(value);

  @override
  Future<SnapshotData?> takeSnapshot() => _resolveHostApi().takeSnapshot();

  @override
  Future<int?> getDuration(DurationProbeRequest request) => _resolveHostApi().getDuration(request);

  @override
  Future<List<CoverFrameData>> extractCovers(CoverExtractRequest request) =>
      _resolveHostApi().extractCovers(request);

  @override
  Future<void> configureCache(CacheConfigRequest request) =>
      _resolveHostApi().configureCache(request);

  @override
  Future<void> precache(PrecacheRequest request) => _resolveHostApi().precache(request);

  @override
  Future<void> cancelPrecache(String cacheKey) => _resolveHostApi().cancelPrecache(cacheKey);

  @override
  Future<bool> isCached(CacheEntryRequest request) => _resolveHostApi().isCached(request);

  @override
  Future<int> getCacheSize(String? cacheDir) => _resolveHostApi().getCacheSize(cacheDir);

  @override
  Future<void> removeCache(CacheEntryRequest request) => _resolveHostApi().removeCache(request);

  @override
  Future<void> clearCache(String? cacheDir) => _resolveHostApi().clearCache(cacheDir);

  @override
  Future<void> pinCacheKey(String cacheKey) => _resolveHostApi().pinCacheKey(cacheKey);

  @override
  Future<void> unpinCacheKey(String cacheKey) => _resolveHostApi().unpinCacheKey(cacheKey);
}
