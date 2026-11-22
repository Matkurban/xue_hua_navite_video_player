import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/aspect_ratio_mode.dart';
import '../data/models/navite_file.dart';
import 'player_event.dart';

/// 进程级单一原生播放器的传输层抽象接口。
///
/// 进程级不变量：全局底层仅维护一个原生播放器实例；[create] 与 [dispose] 用于获取和释放该会话，
/// 而非多实例工厂。不包含独立媒体探测能力（时长探测与封面抽取位于 `MediaProbe`）。
///
/// Session-transport abstraction for the single process-wide native player.
/// Does not include standalone media probing (`getDuration` / `extractCovers`).
abstract class PlayerBackend {
  /// 调用 [create] 后获得的 Flutter 纹理 ID；创建前或释放后为 `null`。
  ///
  /// 在 PlatformView 平台（iOS/macOS/Android）原生 `create` 返回 `0`（非纹理 ID），
  /// 画面由已注册的 PlatformView 展示。
  ///
  /// Flutter texture ID after [create]; `null` before creation or after disposal.
  FlutterSignal<int?> get textureId;

  /// 来自原生（或测试桩）播放器的强类型事件流。
  ///
  /// Typed playback, metadata, video size, and cast event stream.
  Stream<PlayerEvent> get events;

  /// 获取全局唯一原生会话并注册渲染纹理或 PlatformView。
  ///
  /// Acquires the single native session and returns its texture ID (`0` on PlatformView hosts).
  Future<int> create();

  /// 在当前活跃会话上打开媒体 [url]。
  ///
  /// Opens [url] on the active session.
  ///
  /// - [url]：原生可直接播放的媒体地址。Native-playable media URL.
  /// - [castUrl]：可选公网/局域网 HTTP(S) 投屏地址。Optional HTTP(S) URL for remote cast receivers.
  /// - [cacheKey]：可选稳定磁盘缓存键。Optional stable disk cache key.
  /// - [headers]：可选自定义 HTTP 请求头。Optional custom HTTP request headers.
  /// - [enableCache]：可选单源缓存开关覆盖。Optional per-source cache toggle.
  Future<void> open(
    String url, {
    String? castUrl,
    String? cacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  });

  /// 开始或恢复播放。
  ///
  /// Starts or resumes playback.
  Future<void> play();

  /// 暂停播放。
  ///
  /// Pauses playback.
  Future<void> pause();

  /// 跳转至指定时间点（[positionMs]，单位毫秒）。
  ///
  /// Seeks to [positionMs] in milliseconds.
  Future<void> seek(int positionMs);

  /// 设置播放音量（[volume]，范围 `0.0..1.0`）。
  ///
  /// Sets output audio [volume] (`0.0..1.0`).
  Future<void> setVolume(double volume);

  /// 设置播放倍速（[speed]）。
  ///
  /// Sets playback rate [speed].
  Future<void> setSpeed(double speed);

  /// 设置画面适应模式（映射到各平台官方缩放属性：`videoGravity` / `resizeMode` / `object-fit` / mpv）。
  ///
  /// Maps [mode] to each platform's native scaling property.
  Future<void> setAspectRatioMode(AspectRatioMode mode);

  /// 上报 Flutter 视图尺寸与设备像素比（供 libmpv 桌面渲染纹理适配，PlatformView 平台为空操作）。
  ///
  /// Reports Flutter view [width], [height], and [devicePixelRatio] to texture-based hosts.
  Future<void> setVideoViewSize({
    required double width,
    required double height,
    required double devicePixelRatio,
  });

  /// 唤起操作系统原生的无线投屏设备选择器。
  ///
  /// Presents the operating system's native wireless cast route picker.
  Future<void> showCastPicker() async {}

  /// 断开当前无线投屏会话并恢复本地播放。
  ///
  /// Disconnects the active wireless cast session and restores local playback.
  Future<void> stopCasting() async {}

  /// 释放原生播放器资源。
  ///
  /// Releases native player resources.
  Future<void> dispose();

  /// 截取当前播放画面帧为 PNG [NaviteFile]（可选指定保存路径 [savePath]）。
  ///
  /// Captures the current playback frame as a PNG [NaviteFile], optionally saving to [savePath].
  Future<NaviteFile> takeSnapshot({String? savePath});
}
