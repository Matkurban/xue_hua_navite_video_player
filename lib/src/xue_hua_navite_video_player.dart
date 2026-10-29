import 'package:material_ui/material_ui.dart';

import 'cache/video_cache_manager.dart';
import 'core/live_photo_source.dart';
import 'core/video_source.dart';
import 'data/models/live_photo_bundle.dart';
import 'data/models/video_cache_config.dart';
import 'data/models/video_cover_frame.dart';
import 'player/media_probe.dart';
import 'utils/live_photo_extractor.dart';

/// 插件主入口：封面/时长探测、动态照片（Live Photo / Motion Photo）探测与提取、
/// 网络媒体磁盘缓存配置与预热清理等工具能力，以及可选的幂等 [initialize]。
///
/// Probe work is owned by [MediaProbe] and [LivePhotoExtractor]; media cache
/// governance is owned by [VideoCacheManager]; this type keeps the historical
/// singleton call sites.
class XueHuaNaviteVideoPlayer {
  XueHuaNaviteVideoPlayer._();

  static final XueHuaNaviteVideoPlayer _instance = XueHuaNaviteVideoPlayer._();

  static XueHuaNaviteVideoPlayer get instance => _instance;

  factory XueHuaNaviteVideoPlayer() => _instance;

  final MediaProbe _probe = MediaProbe();

  Future<void>? _initFuture;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 当前全局网络视频缓存配置。
  /// Current global network video cache configuration.
  VideoCacheConfig get cacheConfig => VideoCacheManager.instance.config;

  /// 幂等初始化：确保 Flutter binding 已就绪，并可选同步初始 [cacheConfig]。
  Future<void> initialize({VideoCacheConfig? cacheConfig}) async {
    if (!_initialized) {
      await (_initFuture ??= _doInitialize());
    }
    if (cacheConfig != null) {
      await VideoCacheManager.instance.configure(cacheConfig);
    }
  }

  Future<void> _doInitialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _initialized = true;
  }

  /// 动态更新全局网络视频磁盘缓存策略（容量上限、单文件上限、自定义目录、缓存键构建器）。
  ///
  /// Updates the global on-disk media cache configuration at runtime.
  Future<void> configureCache(VideoCacheConfig config) {
    return VideoCacheManager.instance.configure(config);
  }

  /// 预热指定网络视频或实况照片至本地缓存（[preloadBytes] 为空时预下载完整文件，
  /// 传入如 `2 * 1024 * 1024` 可用于短视频上下滑列表提前预热下一条首包）。
  ///
  /// Preloads up to [preloadBytes] (or the full file when `null`) into the local disk cache.
  Future<void> precache(VideoSource source, {int? preloadBytes}) {
    return VideoCacheManager.instance.precache(source, preloadBytes: preloadBytes);
  }

  /// 取消正在针对 [source] 进行的后台预加载任务。
  ///
  /// Cancels an active background [precache] task for [source], if any.
  Future<void> cancelPrecache(VideoSource source) {
    return VideoCacheManager.instance.cancelPrecache(source);
  }

  /// 判断 [source] 是否已在本地完成 100% 缓存落盘（可直接零网络离线播放）。
  ///
  /// Returns `true` if [source] is completely cached locally.
  Future<bool> isCached(VideoSource source) {
    return VideoCacheManager.instance.isCached(source);
  }

  /// 获取当前所有网络视频及网络实况照片缓存占用的磁盘总字节数。
  ///
  /// Returns the total disk space in bytes currently used by the media cache.
  Future<int> getCacheSize() {
    return VideoCacheManager.instance.getCacheSize();
  }

  /// 移除指定 [source] 对应的本地缓存文件。
  ///
  /// Deletes any cached data associated with [source].
  Future<void> removeCache(VideoSource source) {
    return VideoCacheManager.instance.removeCache(source);
  }

  /// 清空所有非活跃的网络媒体磁盘缓存。
  ///
  /// Clears all non-pinned cached media files from disk.
  Future<void> clearCache() {
    return VideoCacheManager.instance.clearCache();
  }

  /// 从任意来源的视频中抽取若干非黑的封面候选帧。
  ///
  /// Delegates to [MediaProbe.extractCovers].
  Future<List<VideoCoverFrame>> extractCoverCandidates(
    VideoSource source, {
    int count = 5,
    double minBrightness = 0.08,
    String? outputDir,
  }) {
    return _probe.extractCovers(
      source,
      count: count,
      minBrightness: minBrightness,
      outputDir: outputDir,
    );
  }

  /// 在不创建播放器实例的前提下，精确获取任意 [VideoSource] 的总时长。
  ///
  /// Delegates to [MediaProbe.probeDuration].
  Future<Duration?> getDuration(
    VideoSource source, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _probe.probeDuration(source, timeout: timeout);
  }

  /// 将任意 [LivePhotoSource] 解析为包含静态封面图、可播放视频源及元数据的 [LivePhotoBundle]。
  ///
  /// Resolves a [LivePhotoSource] into a [LivePhotoBundle] without starting a playback session.
  Future<LivePhotoBundle> resolveLivePhoto(LivePhotoSource source) {
    return LivePhotoExtractor.resolve(source);
  }

  /// 在不创建播放器会话的前提下，尝试从 [source]（如单文件 Motion Photo `.jpg`/`.heic`、
  /// 本地同名配对图片/视频或 `.pvt` 包）中提取 [LivePhotoBundle]。
  /// 若 [source] 不是有效的动态照片，返回 `null`。
  ///
  /// Probes and extracts a [LivePhotoBundle] from [source], or returns `null`
  /// if [source] is not a Motion Photo or paired Live Photo.
  Future<LivePhotoBundle?> extractLivePhoto(VideoSource source, {Duration? presentationTimestamp}) {
    return LivePhotoExtractor.tryExtractFromVideoSource(
      source,
      presentationTimestampOverride: presentationTimestamp,
    );
  }

  /// 检测 [source] 是否为动态照片（单文件 Motion Photo 或本地配对 Live Photo）。
  ///
  /// Returns `true` if [source] is a valid Motion Photo or paired Live Photo.
  Future<bool> isLivePhoto(VideoSource source) {
    return LivePhotoExtractor.isLivePhoto(source);
  }

  /// 释放初始化状态。
  Future<void> dispose() async {
    _initialized = false;
    _initFuture = null;
  }
}
