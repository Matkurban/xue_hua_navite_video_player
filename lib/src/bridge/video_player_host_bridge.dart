import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../pigeon/player_api.g.dart';
import 'bridge_env.dart';

/// 跨平台统一宿主桥接抽象接口。
///
/// 底层封装 Pigeon Native Interop（Android JNI、iOS/macOS FFI）、Pigeon 通道宿主
/// （Windows C++、Linux GObject）以及 Web 平台的纯 Dart 宿主实现。
///
/// Unified host bridge interface over Pigeon Native Interop (Android JNI, Apple FFI),
/// Pigeon channel hosts (Windows C++, Linux GObject), and the direct Dart Web host.
abstract interface class VideoPlayerHostBridge {
  /// 进程级当前活跃的宿主桥接实例。
  ///
  /// Web 平台会在 `XueHuaNaviteVideoPlayerWeb.registerWith` 中注册纯 Dart 实现；
  /// IO 平台默认使用 [PigeonVideoPlayerHostBridge]。
  ///
  /// Active process-wide host bridge instance. Web registers its direct Dart
  /// implementation on startup; IO platforms default to [PigeonVideoPlayerHostBridge].
  static VideoPlayerHostBridge instance = PigeonVideoPlayerHostBridge();

  /// 播放器生命周期、播放状态、媒体元数据、视频尺寸与投屏事件流。
  ///
  /// Broadcast stream of playback lifecycle, progress, metadata, video size, and cast events.
  Stream<PlayerEventData> get events;

  /// 由原生操作系统窗口触发的全屏状态变化事件流（桌面端）。
  ///
  /// Stream of window fullscreen state changes originating from native OS controls.
  Stream<bool> get fullscreenEvents;

  /// 创建原生播放器实例并返回纹理 ID（PlatformView 平台通常返回 `0`）。
  ///
  /// Creates the native player instance and returns a texture ID (`0` on PlatformView hosts).
  Future<int> create();

  /// 打开指定媒体资源请求（[request]）。
  ///
  /// Opens the media source described by [request].
  Future<void> open(OpenMediaRequest request);

  /// 开始或恢复媒体播放。
  ///
  /// Starts or resumes playback.
  Future<void> play();

  /// 暂停媒体播放。
  ///
  /// Pauses playback.
  Future<void> pause();

  /// 跳转至指定播放时间点（[positionMs]，单位毫秒）。
  ///
  /// Seeks to [positionMs] in milliseconds.
  Future<void> seek(int positionMs);

  /// 设置播放音量（[volume]，范围 `0.0..1.0`）。
  ///
  /// Sets output audio [volume] (`0.0..1.0`).
  Future<void> setVolume(double volume);

  /// 设置播放倍速（[speed]，例如 `1.0`、`1.5`、`2.0`）。
  ///
  /// Sets playback rate [speed] (e.g. `1.0`, `1.5`, `2.0`).
  Future<void> setSpeed(double speed);

  /// 设置画面适应模式（[mode]）。
  ///
  /// Sets native video scaling [mode].
  Future<void> setAspectRatioMode(NativeAspectRatioMode mode);

  /// 上报 Flutter 视频视图尺寸与设备像素比（供 libmpv 桌面渲染纹理适配）。
  ///
  /// Reports Flutter view [width], [height], and [devicePixelRatio] to the native host.
  Future<void> setVideoViewSize(double width, double height, double devicePixelRatio);

  /// 唤起系统原生的无线投屏设备选择器。
  ///
  /// Presents the operating system's native wireless cast route picker.
  Future<void> showCastPicker();

  /// 断开当前无线投屏会话并恢复本地播放。
  ///
  /// Disconnects the active wireless cast session and returns playback locally.
  Future<void> stopCasting();

  /// 释放底层原生播放器资源与状态。
  ///
  /// Disposes the native player and frees its resources.
  Future<void> dispose();

  /// 读取当前屏幕亮度（范围 `0.0..1.0`）。
  ///
  /// Reads the current screen brightness (`0.0..1.0`).
  Future<double> getBrightness();

  /// 设置屏幕亮度（[value]，范围 `0.0..1.0`）。
  ///
  /// Sets the screen brightness to [value] (`0.0..1.0`).
  Future<void> setBrightness(double value);

  /// 切换桌面窗口全屏状态（[value] 为 `true` 进入全屏，`false` 退出全屏）。
  ///
  /// Toggles native desktop window fullscreen state (`true` to enter, `false` to exit).
  Future<void> setWindowFullscreen(bool value);

  /// 截取当前播放画面帧，返回 [SnapshotData]（失败或无帧时返回 `null`）。
  ///
  /// Captures the current playback frame as [SnapshotData], or `null` if unavailable.
  Future<SnapshotData?> takeSnapshot();

  /// 不起播探测媒体总时长（单位毫秒），失败或超时返回 `null`。
  ///
  /// Probes media duration in milliseconds for [request] without starting playback.
  Future<int?> getDuration(DurationProbeRequest request);

  /// 不起播从媒体中抽取非黑候选封面帧列表。
  ///
  /// Extracts candidate cover frames for [request] without starting playback.
  Future<List<CoverFrameData>> extractCovers(CoverExtractRequest request);

  /// 同步磁盘缓存配置（[request]）至原生缓存引擎。
  ///
  /// Applies disk cache configuration [request] to the native cache engine.
  Future<void> configureCache(CacheConfigRequest request);

  /// 预缓存指定网络媒体资源（[request]）。
  ///
  /// Precaches the network media specified by [request].
  Future<void> precache(PrecacheRequest request);

  /// 取消指定 [cacheKey] 对应的进行中预缓存任务。
  ///
  /// Cancels an active precache task identified by [cacheKey].
  Future<void> cancelPrecache(String cacheKey);

  /// 检查 [request] 对应的媒体是否已完整命中磁盘缓存。
  ///
  /// Returns whether the entry described by [request] is completely cached on disk.
  Future<bool> isCached(CacheEntryRequest request);

  /// 查询指定缓存目录（[cacheDir]）当前已占用的总字节数。
  ///
  /// Returns the total disk usage in bytes under [cacheDir] (or the default directory).
  Future<int> getCacheSize(String? cacheDir);

  /// 删除 [request] 对应的单条磁盘缓存记录。
  ///
  /// Removes the single cached entry identified by [request].
  Future<void> removeCache(CacheEntryRequest request);

  /// 清空指定缓存目录（[cacheDir]）下的全部非活跃缓存。
  ///
  /// Clears all unpinned cache entries under [cacheDir] (or the default directory).
  Future<void> clearCache(String? cacheDir);

  /// 锁定指定 [cacheKey]，防止正在播放的缓存被 LRU 淘汰。
  ///
  /// Pins [cacheKey] to protect an actively playing entry from LRU eviction.
  Future<void> pinCacheKey(String cacheKey);

  /// 解除 [cacheKey] 的防淘汰锁定。
  ///
  /// Unpins [cacheKey], allowing LRU eviction when needed.
  Future<void> unpinCacheKey(String cacheKey);
}

/// 基于 Pigeon [PlayerHostApi] 与 [PlayerFlutterApi] 的默认宿主桥接实现。
///
/// Native Interop（`PlayerHostApi.createWithNativeInteropApi()`）采用懒初始化，
/// 确保在 Flutter 引擎完全启动前不会过早触发 JNI/FFI 调用。
///
/// Default [VideoPlayerHostBridge] backed by Pigeon [PlayerHostApi] and
/// [PlayerFlutterApi]. Initializes Native Interop lazily to avoid invoking
/// JNI/FFI before engine startup.
class PigeonVideoPlayerHostBridge implements VideoPlayerHostBridge, PlayerFlutterApi {
  /// 创建基于 Pigeon 的宿主桥接实例。
  ///
  /// Creates a [PigeonVideoPlayerHostBridge] with optional test-only [hostApi]
  /// and [binaryMessenger] overrides.
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
  late final StreamController<bool> _fullscreenController = StreamController<bool>.broadcast(
    onListen: _ensureFlutterApiSetUp,
  );

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
