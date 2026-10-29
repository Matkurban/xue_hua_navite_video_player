import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import '../utils/live_photo_extractor.dart';
import '../utils/mime_detector.dart';
import 'video_cache_engine.dart';
import 'video_cache_types.dart';

/// 全局统一媒体缓存管理器。
///
/// 负责维护全局 [VideoCacheConfig]、生成稳定 `cacheKey`、协调各平台缓存后端、
/// 并向上提供预热（[precache]）、命中查询（[isCached]）、体积统计（[getCacheSize]）与清理能力。
class VideoCacheManager {
  VideoCacheManager._();

  static final VideoCacheManager instance = VideoCacheManager._();

  final PlatformVideoCacheEngine _engine = PlatformVideoCacheEngine();

  /// 当前生效的缓存全局配置。
  VideoCacheConfig get config => _engine.config;

  /// 平台底层缓存引擎（仅供包内调试与测试使用）。
  PlatformVideoCacheEngine get engine => _engine;

  /// 更新缓存策略配置。
  Future<void> configure(VideoCacheConfig config) => _engine.configure(config);

  /// 解析网络媒体源对应的原始业务去重标识。
  String resolveRawCacheIdentity(NetworkVideoSource source) {
    return VideoCacheKeyUtils.resolveRawIdentity(source, _engine.config);
  }

  /// 计算网络媒体源对应的 40 位十六进制 SHA-1 缓存键。
  String computeCacheKey(NetworkVideoSource source) {
    return VideoCacheKeyUtils.computeSha1Key(resolveRawCacheIdentity(source));
  }

  /// 为播放会话解析缓存目标（自动处理完整文件快路径、平台分片流与 `castUrl` 隔离）。
  Future<ResolvedVideoCacheTarget> resolveForPlayback(NetworkVideoSource source) {
    return _engine.resolveForPlayback(source);
  }

  /// 为 `MediaProbe`（时长探测 / 封面抽帧）解析缓存目标。
  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) {
    return _engine.resolveForProbe(source);
  }

  /// 标记指定 `cacheKey` 正在被活跃会话读取，防止被 LRU 淘汰。
  void pin(String cacheKey) => _engine.pin(cacheKey);

  /// 解除指定 `cacheKey` 的活跃引用保护。
  void unpin(String cacheKey) => _engine.unpin(cacheKey);

  /// 预加载 [source] 的媒体数据（[preloadBytes] 为空时预加载完整媒体）。
  ///
  /// - 对于 [NetworkVideoSource]：预下载指定字节数或完整视频文件；
  /// - 对于网络动态照片（[LivePhotoVideoSource] 或网络单文件 Motion Photo）：预下载并完成拆分落盘。
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

  /// 取消正在进行的后台预加载任务。
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

  /// 查询 [source] 是否已在本地完成缓存。
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

  /// 获取当前所有已缓存媒体占用的磁盘字节总数。
  Future<int> getCacheSize() => _engine.getCacheSize();

  /// 删除指定 [source] 对应的本地缓存数据。
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

  /// 清空所有非活跃网络媒体缓存。
  Future<void> clearCache() => _engine.clearCache();
}
