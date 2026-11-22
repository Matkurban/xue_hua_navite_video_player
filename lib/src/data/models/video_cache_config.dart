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

  /// 创建磁盘缓存配置对象。
  ///
  /// Creates a [VideoCacheConfig] instance.
  ///
  /// - [enabled]：是否全局启用磁盘缓存，默认 `true`。Whether caching is enabled globally.
  /// - [maxCacheBytes]：磁盘缓存总容量上限（字节，必须 `>= 0`）。Maximum total cache size in bytes.
  /// - [maxSingleFileBytes]：单文件缓存上限（字节，必须 `>= 0`）。Maximum single-file cache size in bytes.
  /// - [cacheDirectory]：可选自定义缓存目录路径。Optional custom cache directory.
  /// - [cacheKeyBuilder]：可选稳定缓存键生成回调。Optional stable cache-key builder.
  const VideoCacheConfig({
    this.enabled = true,
    this.maxCacheBytes = defaultMaxCacheBytes,
    this.maxSingleFileBytes = defaultMaxSingleFileBytes,
    this.cacheDirectory,
    this.cacheKeyBuilder,
  }) : assert(maxCacheBytes >= 0, 'maxCacheBytes must be >= 0'),
       assert(maxSingleFileBytes >= 0, 'maxSingleFileBytes must be >= 0');

  /// 创建修改部分字段后的新配置。
  ///
  /// Creates a copy of this configuration with the given fields replaced.
  ///
  /// - [enabled]：替换后的缓存总开关。Updated enabled flag.
  /// - [maxCacheBytes]：替换后的总容量上限（字节）。Updated total capacity limit.
  /// - [maxSingleFileBytes]：替换后的单文件上限（字节）。Updated single-file size limit.
  /// - [cacheDirectory]：替换后的缓存目录路径。Updated cache directory path.
  /// - [clearCacheDirectory]：为 `true` 时显式清空 [cacheDirectory] 为 `null`。Clears [cacheDirectory] when `true`.
  /// - [cacheKeyBuilder]：替换后的缓存键生成器。Updated cache key builder.
  /// - [clearCacheKeyBuilder]：为 `true` 时显式清空 [cacheKeyBuilder] 为 `null`。Clears [cacheKeyBuilder] when `true`.
  ///
  /// 返回值 / Returns：合并修改后的新 [VideoCacheConfig] 实例。Updated [VideoCacheConfig] copy.
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

  /// 序列化为可同步给原生层的参数字典。
  ///
  /// Serializes this configuration into a map suitable for native channel sync.
  ///
  /// - [resolvedCacheDir]：已解析的缓存根目录绝对路径。Resolved absolute cache directory path.
  ///
  /// 返回值 / Returns：包含缓存开关、容量上限与目录路径的键值映射。Serialized configuration map.
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
