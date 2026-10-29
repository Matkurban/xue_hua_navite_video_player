import 'package:flutter/foundation.dart';

/// 网络媒体磁盘缓存全局配置。
///
/// Global configuration for on-disk network media caching.
@immutable
class VideoCacheConfig {
  /// 默认最大磁盘缓存总容量（512 MiB）。
  /// Default maximum total disk cache capacity (512 MiB).
  static const int defaultMaxCacheBytes = 512 * 1024 * 1024;

  /// 默认单个视频允许写入缓存的最大字节数（256 MiB）。
  /// Default maximum byte size of a single media file eligible for caching (256 MiB).
  static const int defaultMaxSingleFileBytes = 256 * 1024 * 1024;

  /// 是否全局启用网络视频与实况照片磁盘缓存（默认 `true`）。
  /// Whether disk caching is enabled globally for network media sources (defaults to `true`).
  final bool enabled;

  /// 磁盘缓存总容量上限（字节，默认 512 MiB）。超出后按 LRU 自动淘汰非活跃缓存。
  /// Maximum total disk cache size in bytes before LRU eviction kicks in.
  final int maxCacheBytes;

  /// 单个媒体文件允许写入缓存的最大体积（字节，默认 256 MiB）。
  /// 超过该阈值的超大长视频将自动旁路直连，避免单个视频挤占整个缓存池。
  /// Maximum size in bytes of a single media file eligible to be written to disk cache.
  final int maxSingleFileBytes;

  /// 自定义磁盘缓存根目录路径；为 `null` 时默认使用系统临时目录下的插件专属缓存目录。
  /// Optional custom root directory path for cached media files.
  final String? cacheDirectory;

  /// 全局自定义缓存键生成器。
  ///
  /// 适用于带动态防盗链签名的云存储地址（如 OSS / S3 / CDN URL 中的临时 `sign`、`token`、`t` 参数），
  /// 可将不同签名周期的 [Uri] 映射为同一稳定字符串以保持缓存命中。
  ///
  /// Optional callback that maps a network [Uri] into a stable cache identity string.
  final String Function(Uri uri)? cacheKeyBuilder;

  const VideoCacheConfig({
    this.enabled = true,
    this.maxCacheBytes = defaultMaxCacheBytes,
    this.maxSingleFileBytes = defaultMaxSingleFileBytes,
    this.cacheDirectory,
    this.cacheKeyBuilder,
  }) : assert(maxCacheBytes >= 0, 'maxCacheBytes must be >= 0'),
       assert(maxSingleFileBytes >= 0, 'maxSingleFileBytes must be >= 0');

  /// 创建修改部分字段后的新配置。
  /// Creates a copy of this configuration with the given fields replaced.
  VideoCacheConfig copyWith({
    bool? enabled,
    int? maxCacheBytes,
    int? maxSingleFileBytes,
    String? cacheDirectory,
    bool clearCacheDirectory = false,
    String Function(Uri uri)? cacheKeyBuilder,
    bool clearCacheKeyBuilder = false,
  }) {
    return VideoCacheConfig(
      enabled: enabled ?? this.enabled,
      maxCacheBytes: maxCacheBytes ?? this.maxCacheBytes,
      maxSingleFileBytes: maxSingleFileBytes ?? this.maxSingleFileBytes,
      cacheDirectory: clearCacheDirectory ? null : (cacheDirectory ?? this.cacheDirectory),
      cacheKeyBuilder: clearCacheKeyBuilder ? null : (cacheKeyBuilder ?? this.cacheKeyBuilder),
    );
  }

  /// 序列化为可通过 MethodChannel 同步给原生层的参数字典。
  Map<String, dynamic> toChannelMap({required String resolvedCacheDir}) {
    return <String, dynamic>{
      'enabled': enabled,
      'maxCacheBytes': maxCacheBytes,
      'maxSingleFileBytes': maxSingleFileBytes,
      'cacheDir': resolvedCacheDir,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoCacheConfig &&
          other.enabled == enabled &&
          other.maxCacheBytes == maxCacheBytes &&
          other.maxSingleFileBytes == maxSingleFileBytes &&
          other.cacheDirectory == cacheDirectory &&
          other.cacheKeyBuilder == cacheKeyBuilder;

  @override
  int get hashCode =>
      Object.hash(enabled, maxCacheBytes, maxSingleFileBytes, cacheDirectory, cacheKeyBuilder);
}
