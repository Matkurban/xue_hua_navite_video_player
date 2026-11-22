import '../bridge/video_player_host_bridge.dart';
import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import 'video_cache_types.dart';

/// 平台缓存引擎的兜底桩实现（用于既非 `dart:io` 也非 Web `dart:js_interop` 的目标环境）。
///
/// Fallback stub implementation of [PlatformVideoCacheEngine] used on platforms
/// without `dart:io` or Web `dart:js_interop` support.
class PlatformVideoCacheEngine {
  /// 创建一个兜底缓存引擎实例。
  ///
  /// Creates a stub [PlatformVideoCacheEngine] instance.
  PlatformVideoCacheEngine({VideoPlayerHostBridge? bridge});

  VideoCacheConfig _config = const VideoCacheConfig();

  /// 当前保存的缓存配置。
  ///
  /// Current [VideoCacheConfig].
  VideoCacheConfig get config => _config;

  /// 更新内存中的缓存配置 [config]。
  ///
  /// Stores the updated [config].
  Future<void> configure(VideoCacheConfig config) async {
    _config = config;
  }

  /// 直接返回原始远程播放地址且不启用缓存。
  ///
  /// Returns the original [source] URL with caching disabled.
  Future<ResolvedVideoCacheTarget> resolveForPlayback(NetworkVideoSource source) async {
    return ResolvedVideoCacheTarget(
      playUrl: source.url,
      castUrl: source.url,
      headers: source.headers,
      enableCache: false,
    );
  }

  /// 为媒体探测解析目标（委托至 [resolveForPlayback]）。
  ///
  /// Resolves a probe target by delegating to [resolveForPlayback].
  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) async {
    return resolveForPlayback(source);
  }

  /// 固定缓存键 [cacheKey]（桩实现为空操作）。
  ///
  /// No-op pin in stub implementation.
  void pin(String cacheKey) {}

  /// 解除缓存键 [cacheKey] 固定（桩实现为空操作）。
  ///
  /// No-op unpin in stub implementation.
  void unpin(String cacheKey) {}

  /// 预热网络源 [source]（桩实现为空操作）。
  ///
  /// No-op precache in stub implementation.
  Future<void> precache(NetworkVideoSource source, {int? preloadBytes}) async {}

  /// 取消预热网络源 [source]（桩实现为空操作）。
  ///
  /// No-op cancelPrecache in stub implementation.
  Future<void> cancelPrecache(NetworkVideoSource source) async {}

  /// 查询 [source] 是否已缓存（桩实现始终返回 `false`）。
  ///
  /// Always returns `false` in stub implementation.
  Future<bool> isCached(NetworkVideoSource source) async => false;

  /// 获取当前缓存总字节数（桩实现始终返回 `0`）。
  ///
  /// Always returns `0` in stub implementation.
  Future<int> getCacheSize() async => 0;

  /// 移除 [source] 的缓存（桩实现为空操作）。
  ///
  /// No-op removeCache in stub implementation.
  Future<void> removeCache(NetworkVideoSource source) async {}

  /// 清空全部缓存（桩实现为空操作）。
  ///
  /// No-op clearCache in stub implementation.
  Future<void> clearCache() async {}

  /// 释放缓存引擎资源（桩实现为空操作）。
  ///
  /// No-op dispose in stub implementation.
  Future<void> dispose() async {}
}
