import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import '../utils/live_photo_extractor.dart';
import '../utils/mime_detector.dart';
import 'video_cache_engine.dart';
import 'video_cache_types.dart';

/// 全局统一媒体缓存管理器。
///
/// 负责维护全局 [VideoCacheConfig]、生成稳定 `cacheKey`、协调各平台缓存引擎、
/// 并向上提供预热（[precache]）、命中查询（[isCached]）、体积统计（[getCacheSize]）
/// 与缓存清理能力。
///
/// Global singleton coordinator for media caching across platforms. Manages
/// [VideoCacheConfig], deterministic cache key generation, playback/probe
/// resolution, pinning, precaching, and cache eviction/cleanup.
class VideoCacheManager {
  VideoCacheManager._();

  /// 全局唯一的 [VideoCacheManager] 单例实例。
  ///
  /// Global singleton instance of [VideoCacheManager].
  static final VideoCacheManager instance = VideoCacheManager._();

  final PlatformVideoCacheEngine _engine = PlatformVideoCacheEngine();

  /// 当前生效的缓存全局配置。
  ///
  /// Currently active global [VideoCacheConfig].
  VideoCacheConfig get config => _engine.config;

  /// 平台底层缓存引擎（仅供包内调试与测试使用）。
  ///
  /// Underlying platform-specific [PlatformVideoCacheEngine] (for internal/testing use).
  PlatformVideoCacheEngine get engine => _engine;

  /// 更新缓存策略配置并同步至底层引擎。
  ///
  /// - [config]：新的全局缓存配置。
  ///
  /// Applies a new [VideoCacheConfig] and synchronizes it to the backing engine.
  Future<void> configure(VideoCacheConfig config) => _engine.configure(config);

  /// 解析网络媒体源 [source] 对应的原始业务去重标识（未哈希）。
  ///
  /// Resolves the raw pre-hash cache identity string for [source].
  String resolveRawCacheIdentity(NetworkVideoSource source) {
    return VideoCacheKeyUtils.resolveRawIdentity(source, _engine.config);
  }

  /// 计算网络媒体源 [source] 对应的 40 位十六进制 SHA-1 缓存键。
  ///
  /// Computes the 40-character hexadecimal SHA-1 cache key for [source].
  String computeCacheKey(NetworkVideoSource source) {
    return VideoCacheKeyUtils.computeSha1Key(resolveRawCacheIdentity(source));
  }

  /// 为播放会话解析缓存目标（自动处理完整文件快路径、平台分片流与 `castUrl` 隔离）。
  ///
  /// - [source]：待播放的网络视频源。
  /// - 返回值：包含本地播放地址、投屏地址及缓存元信息的 [ResolvedVideoCacheTarget]。
  ///
  /// Resolves a [ResolvedVideoCacheTarget] for playback, handling complete-file
  /// fast paths, sparse proxy/resource-loader routing, and `castUrl` isolation.
  Future<ResolvedVideoCacheTarget> resolveForPlayback(NetworkVideoSource source) {
    return _engine.resolveForPlayback(source);
  }

  /// 为媒体探测（时长探测 / 封面抽帧）解析缓存目标。
  ///
  /// - [source]：待探测的网络视频源。
  /// - 返回值：解析后的 [ResolvedVideoCacheTarget]。
  ///
  /// Resolves a [ResolvedVideoCacheTarget] for media probing (duration/covers).
  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) {
    return _engine.resolveForProbe(source);
  }

  /// 标记指定 [cacheKey] 正在被活跃会话读取，防止被 LRU 淘汰。
  ///
  /// Pins [cacheKey] to protect it from LRU eviction while actively playing.
  void pin(String cacheKey) => _engine.pin(cacheKey);

  /// 解除指定 [cacheKey] 的活跃引用保护。
  ///
  /// Releases the active-session eviction pin for [cacheKey].
  void unpin(String cacheKey) => _engine.unpin(cacheKey);

  /// 预加载 [source] 的媒体数据。
  ///
  /// - [source]：待预热的媒体源（本地文件与 Asset 无需预热会直接返回）。
  /// - [preloadBytes]：可选的预加载字节数上限；为 `null` 时预加载完整媒体。
  /// - 对于网络动态照片（[LivePhotoVideoSource] 或网络单文件 Motion Photo）：预下载并完成拆分落盘。
  ///
  /// Preloads media data for [source] up to [preloadBytes] (or full file when `null`).
  /// Network Live Photos / Motion Photos are downloaded and extracted to disk.
  Future<void> precache(VideoSource source, {int? preloadBytes}) async {
    switch (source) {
      case NetworkVideoSource():
        if (MimeDetector.isCandidateLivePhotoContainer(source.identity)) {
          final extracted = await LivePhotoExtractor.tryExtractFromVideoSource(source);
          if (extracted != null) return;
        }
        await _engine.precache(source, preloadBytes: preloadBytes);
      case LivePhotoVideoSource(:final livePhoto):
        switch (livePhoto) {
          case PairedLivePhotoSource(:final video):
            if (video is NetworkVideoSource) {
              await _engine.precache(video, preloadBytes: preloadBytes);
            }
          case SingleFileLivePhotoSource(:final source):
            if (source is NetworkVideoSource) {
              await LivePhotoExtractor.resolve(livePhoto);
            }
          case BytesLivePhotoSource():
            await LivePhotoExtractor.resolve(livePhoto);
        }
      case FileVideoSource():
      case AssetVideoSource():
        // Local files and bundled assets do not require network precaching.
        return;
    }
  }

  /// 取消正在针对 [source] 进行的后台预加载任务。
  ///
  /// Cancels an active background [precache] task for [source], if any.
  Future<void> cancelPrecache(VideoSource source) async {
    switch (source) {
      case NetworkVideoSource():
        await _engine.cancelPrecache(source);
      case LivePhotoVideoSource(:final livePhoto):
        if (livePhoto is PairedLivePhotoSource && livePhoto.video is NetworkVideoSource) {
          await _engine.cancelPrecache(livePhoto.video as NetworkVideoSource);
        } else if (livePhoto is SingleFileLivePhotoSource &&
            livePhoto.source is NetworkVideoSource) {
          await _engine.cancelPrecache(livePhoto.source as NetworkVideoSource);
        }
      case FileVideoSource():
      case AssetVideoSource():
        return;
    }
  }

  /// 查询 [source] 是否已在本地完成完整缓存。
  ///
  /// 本地文件、Asset 与内存字节实况照片始终视为已就绪并返回 `true`。
  ///
  /// Returns `true` if [source] is completely cached locally (always `true` for
  /// local files, bundled assets, and in-memory Live Photo bytes).
  Future<bool> isCached(VideoSource source) async {
    switch (source) {
      case NetworkVideoSource():
        return _engine.isCached(source);
      case FileVideoSource():
      case AssetVideoSource():
        return true;
      case LivePhotoVideoSource(:final livePhoto):
        return switch (livePhoto) {
          PairedLivePhotoSource(:final video) => isCached(video),
          SingleFileLivePhotoSource(:final source) => isCached(source),
          BytesLivePhotoSource() => true,
        };
    }
  }

  /// 获取当前所有已缓存媒体占用的磁盘总字节数。
  ///
  /// Returns the total cached disk usage in bytes.
  Future<int> getCacheSize() => _engine.getCacheSize();

  /// 删除指定 [source] 对应的本地缓存数据。
  ///
  /// Removes cached files associated with [source].
  Future<void> removeCache(VideoSource source) async {
    switch (source) {
      case NetworkVideoSource():
        await _engine.removeCache(source);
      case LivePhotoVideoSource(:final livePhoto):
        if (livePhoto is PairedLivePhotoSource && livePhoto.video is NetworkVideoSource) {
          await _engine.removeCache(livePhoto.video as NetworkVideoSource);
        } else if (livePhoto is SingleFileLivePhotoSource &&
            livePhoto.source is NetworkVideoSource) {
          await _engine.removeCache(livePhoto.source as NetworkVideoSource);
        }
      case FileVideoSource():
      case AssetVideoSource():
        return;
    }
  }

  /// 清空所有非活跃（未被固定）的网络媒体缓存。
  ///
  /// Clears all non-pinned cached network media entries.
  Future<void> clearCache() => _engine.clearCache();
}
