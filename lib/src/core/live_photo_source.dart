import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'video_source.dart';

/// 描述一个动态照片（Live Photo / Motion Photo）的来源。
///
/// 支持三种构造形态：
/// 1. [PairedLivePhotoSource] ─ 双源配对（静态封面图 + 独立短视频，如 iOS/macOS Live Photo 或云端配对 URL）。
/// 2. [SingleFileLivePhotoSource] ─ 单源动态照片（如 Android/Pixel/Xiaomi/Samsung 单文件 `.jpg`/`.heic`
///    Motion Photo，或本地自动配对同名 `.MOV`/`.MP4` 及 `.pvt` 包）。
/// 3. [BytesLivePhotoSource] ─ 内存中的单文件动态照片字节流。
///
/// Sealed description of a Live Photo / Motion Photo source.
@immutable
sealed class LivePhotoSource {
  /// 静态封面图对应的视频内呈现时间戳（可选）。
  ///
  /// Optional presentation timestamp for the still cover frame.
  final Duration? presentationTimestamp;

  /// 构造动态照片来源基类。
  ///
  /// Base constructor accepting an optional [presentationTimestamp].
  const LivePhotoSource({this.presentationTimestamp});

  /// 用作缓存与状态判断的稳定唯一标识。
  ///
  /// Stable identity string for caching and state tracking.
  String get identity;

  /// 是否为纯网络配对来源。
  ///
  /// Whether this Live Photo is backed by network URLs.
  bool get isNetwork;

  /// 双源配对动态照片（显式指定图片源与视频源）。
  ///
  /// Paired Live Photo with explicit still [image] and motion [video] sources.
  const factory LivePhotoSource.paired({
    required VideoSource image,
    required VideoSource video,
    Duration? presentationTimestamp,
  }) = PairedLivePhotoSource;

  /// 单源动态照片（自动解析单文件 Motion Photo 内嵌视频流，或在本地目录自动查找同名 `.MOV`/`.MP4` 与 `.pvt` 包）。
  ///
  /// Single-source Motion Photo or auto-paired local Live Photo.
  const factory LivePhotoSource.single(VideoSource source, {Duration? presentationTimestamp}) =
      SingleFileLivePhotoSource;

  /// 内存字节动态照片（从单文件 Motion Photo 字节流直接解析）。
  ///
  /// In-memory Motion Photo byte buffer.
  const factory LivePhotoSource.bytes(
    Uint8List bytes, {
    String name,
    Duration? presentationTimestamp,
  }) = BytesLivePhotoSource;

  /// 快速构造网络动态照片。
  ///
  /// - 若同时提供 [videoUrl]，作为双文件配对网络实况照片；
  /// - 若省略 [videoUrl]，将下载并解析单文件网络 Motion Photo。
  ///
  /// Shortcut for network-backed Live Photo (paired if [videoUrl] is given, or single-file Motion Photo).
  ///
  /// - [imageUrl]：静态封面图或单文件动态照片的网络 URL。Image or single-file Motion Photo URL.
  /// - [videoUrl]：可选配对动态短视频的网络 URL。Optional companion motion video URL.
  /// - [presentationTimestamp]：可选静态封面帧时间戳。Optional still frame timestamp.
  /// - [cacheKey]：可选静态图/单文件缓存键。Optional cache key for [imageUrl].
  /// - [videoCacheKey]：可选配对视频缓存键。Optional cache key for [videoUrl].
  /// - [headers]：可选自定义 HTTP 请求头。Optional custom HTTP request headers.
  /// - [enableCache]：单源缓存开关覆盖。Optional per-source cache toggle.
  ///
  /// 返回值 / Returns：对应的 [PairedLivePhotoSource] 或 [SingleFileLivePhotoSource]。
  factory LivePhotoSource.network({
    required String imageUrl,
    String? videoUrl,
    Duration? presentationTimestamp,
    String? cacheKey,
    String? videoCacheKey,
    Map<String, String>? headers,
    bool? enableCache,
  }) {
    if (videoUrl != null && videoUrl.isNotEmpty) {
      return PairedLivePhotoSource(
        image: VideoSource.network(
          imageUrl,
          cacheKey: cacheKey,
          headers: headers,
          enableCache: enableCache,
        ),
        video: VideoSource.network(
          videoUrl,
          cacheKey: videoCacheKey,
          headers: headers,
          enableCache: enableCache,
        ),
        presentationTimestamp: presentationTimestamp,
      );
    }
    return SingleFileLivePhotoSource(
      VideoSource.network(imageUrl, cacheKey: cacheKey, headers: headers, enableCache: enableCache),
      presentationTimestamp: presentationTimestamp,
    );
  }

  /// 快速构造本地文件动态照片。
  ///
  /// - 若同时提供 [videoPath]，作为双文件配对实况照片；
  /// - 若省略 [videoPath]，自动解析单文件 Motion Photo 或自动查找同目录同名 `.MOV`/`.MP4` 及 `.pvt` 包。
  ///
  /// Shortcut for local-file Live Photo (paired if [videoPath] is given, or auto-detected).
  ///
  /// - [imagePath]：本地静态图或单文件动态照片路径。Local still image or Motion Photo path.
  /// - [videoPath]：可选本地配对短视频路径。Optional companion motion video path.
  /// - [presentationTimestamp]：可选静态封面帧时间戳。Optional still frame timestamp.
  ///
  /// 返回值 / Returns：对应的 [PairedLivePhotoSource] 或 [SingleFileLivePhotoSource]。
  factory LivePhotoSource.file({
    required String imagePath,
    String? videoPath,
    Duration? presentationTimestamp,
  }) {
    if (videoPath != null && videoPath.isNotEmpty) {
      return PairedLivePhotoSource(
        image: VideoSource.file(imagePath),
        video: VideoSource.file(videoPath),
        presentationTimestamp: presentationTimestamp,
      );
    }
    return SingleFileLivePhotoSource(
      VideoSource.file(imagePath),
      presentationTimestamp: presentationTimestamp,
    );
  }

  /// 快速构造 Flutter Asset 动态照片。
  ///
  /// - 若同时提供 [videoAsset]，作为双文件配对实况照片；
  /// - 若省略 [videoAsset]，自动从单文件 Asset Motion Photo 中拆分图片与视频。
  ///
  /// Shortcut for Flutter asset Live Photo.
  ///
  /// - [imageAsset]：静态图或单文件动态照片的 Asset 路径。Image or single-file Motion Photo asset key.
  /// - [videoAsset]：可选配对短视频的 Asset 路径。Optional companion video asset key.
  /// - [bundle]：可选自定义 [AssetBundle]，默认 `rootBundle`。Optional custom [AssetBundle].
  /// - [presentationTimestamp]：可选静态封面帧时间戳。Optional still frame timestamp.
  ///
  /// 返回值 / Returns：对应的 [PairedLivePhotoSource] 或 [SingleFileLivePhotoSource]。
  factory LivePhotoSource.asset({
    required String imageAsset,
    String? videoAsset,
    AssetBundle? bundle,
    Duration? presentationTimestamp,
  }) {
    if (videoAsset != null && videoAsset.isNotEmpty) {
      return PairedLivePhotoSource(
        image: VideoSource.asset(imageAsset, bundle: bundle),
        video: VideoSource.asset(videoAsset, bundle: bundle),
        presentationTimestamp: presentationTimestamp,
      );
    }
    return SingleFileLivePhotoSource(
      VideoSource.asset(imageAsset, bundle: bundle),
      presentationTimestamp: presentationTimestamp,
    );
  }
}

/// 双文件配对的动态照片来源（静态封面图 [image] + 动态视频 [video]）。
///
/// Paired Live Photo source consisting of a still [image] source and a motion [video] source.
class PairedLivePhotoSource extends LivePhotoSource {
  /// 静态封面图来源。
  ///
  /// Still cover image source.
  final VideoSource image;

  /// 动态短视频来源。
  ///
  /// Companion motion video source.
  final VideoSource video;

  /// 创建双文件配对的动态照片来源。
  ///
  /// Creates a [PairedLivePhotoSource] from [image] and [video].
  const PairedLivePhotoSource({
    required this.image,
    required this.video,
    super.presentationTimestamp,
  });

  @override
  String get identity => 'livephoto://paired?image=${image.identity}&video=${video.identity}';

  @override
  bool get isNetwork => video.isNetwork;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairedLivePhotoSource &&
          other.image == image &&
          other.video == video &&
          other.presentationTimestamp == presentationTimestamp;

  @override
  int get hashCode => Object.hash(image, video, presentationTimestamp);
}

/// 单文件或自动配对的动态照片来源（如单文件 Motion Photo `.jpg`/`.heic` 或 `.pvt` 包）。
///
/// Single-file Motion Photo or auto-paired local Live Photo source.
class SingleFileLivePhotoSource extends LivePhotoSource {
  /// 原始单文件（或主文件）来源。
  ///
  /// Underlying single-file or primary image source.
  final VideoSource source;

  /// 创建单文件或自动配对动态照片来源。
  ///
  /// Creates a [SingleFileLivePhotoSource] wrapping [source].
  const SingleFileLivePhotoSource(this.source, {super.presentationTimestamp});

  @override
  String get identity => 'livephoto://single?source=${source.identity}';

  @override
  bool get isNetwork => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SingleFileLivePhotoSource &&
          other.source == source &&
          other.presentationTimestamp == presentationTimestamp;

  @override
  int get hashCode => Object.hash(source, presentationTimestamp);
}

/// 内存字节流的单文件动态照片来源。
///
/// In-memory single-file Motion Photo source.
class BytesLivePhotoSource extends LivePhotoSource {
  /// 包含内嵌视频流的单文件动态照片字节。
  ///
  /// Raw single-file Motion Photo bytes containing an embedded video track.
  final Uint8List bytes;

  /// 文件标识名（默认 `'motion_photo.jpg'`）。
  ///
  /// Logical file name identifier (defaults to `'motion_photo.jpg'`).
  final String name;

  /// 创建基于内存字节流的动态照片来源。
  ///
  /// Creates a [BytesLivePhotoSource] from [bytes] and an optional [name].
  const BytesLivePhotoSource(
    this.bytes, {
    this.name = 'motion_photo.jpg',
    super.presentationTimestamp,
  });

  @override
  String get identity => 'livephoto://bytes/$name/${bytes.length}';

  @override
  bool get isNetwork => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BytesLivePhotoSource &&
          identical(other.bytes, bytes) &&
          other.name == name &&
          other.presentationTimestamp == presentationTimestamp;

  @override
  int get hashCode => Object.hash(identityHashCode(bytes), name, presentationTimestamp);
}
