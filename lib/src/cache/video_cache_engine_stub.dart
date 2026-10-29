import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import 'video_cache_types.dart';

/// 平台缓存引擎抽象基类（非 IO / 非 Web 兜底实现）。
class PlatformVideoCacheEngine {
  VideoCacheConfig _config = const VideoCacheConfig();

  VideoCacheConfig get config => _config;

  Future<void> configure(VideoCacheConfig config) async {
    _config = config;
  }

  Future<ResolvedVideoCacheTarget> resolveForPlayback(NetworkVideoSource source) async {
    return ResolvedVideoCacheTarget(
      playUrl: source.url,
      castUrl: source.url,
      headers: source.headers,
      enableCache: false,
    );
  }

  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) async {
    return resolveForPlayback(source);
  }

  void pin(String cacheKey) {}

  void unpin(String cacheKey) {}

  Future<void> precache(NetworkVideoSource source, {int? preloadBytes}) async {}

  Future<void> cancelPrecache(NetworkVideoSource source) async {}

  Future<bool> isCached(NetworkVideoSource source) async => false;

  Future<int> getCacheSize() async => 0;

  Future<void> removeCache(NetworkVideoSource source) async {}

  Future<void> clearCache() async {}

  Future<void> dispose() async {}
}
