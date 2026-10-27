import 'package:flutter/foundation.dart';

import '../../core/video_source.dart';
import 'live_photo_metadata.dart';
import 'navite_file.dart';

/// 解析并准备就绪的动态照片资源包，包含静态封面图、可播放视频源、原生播放地址及元数据。
///
/// A resolved Live Photo / Motion Photo bundle containing the still image,
/// playable video source, native playback URL, and parsed metadata.
@immutable
class LivePhotoBundle {
  /// 抽取或落地后的静态封面图文件（单文件 Motion Photo 拆分出的纯净图片，或本地/内存图片）。
  /// 若为纯网络配对来源且未下载静态图字节，则可能为 `null`（此时通过 [imageSource] 加载）。
  ///
  /// Extracted or resolved still image as a [NaviteFile], when available.
  final NaviteFile? imageFile;

  /// 静态封面图的来源描述（用于配对网络/本地/Asset 封面图展示）。
  ///
  /// Source description of the still cover image.
  final VideoSource? imageSource;

  /// 可供播放器消费的动态视频来源。
  ///
  /// Playable video source for the motion clip.
  final VideoSource videoSource;

  /// 已解析完毕、可直接传给原生播放器的视频 URL（`file://`、`http(s)://`、`assets/` 或 `data:`）。
  ///
  /// Native URL ready to be opened by the platform video player.
  final String nativeVideoUrl;

  /// 动态照片格式与偏移量元数据。
  ///
  /// Parsed format and presentation metadata.
  final LivePhotoMetadata metadata;

  const LivePhotoBundle({
    required this.videoSource,
    required this.nativeVideoUrl,
    required this.metadata,
    this.imageFile,
    this.imageSource,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LivePhotoBundle &&
          other.imageFile == imageFile &&
          other.imageSource == imageSource &&
          other.videoSource == videoSource &&
          other.nativeVideoUrl == nativeVideoUrl &&
          other.metadata == metadata;

  @override
  int get hashCode => Object.hash(
    imageFile,
    imageSource,
    videoSource,
    nativeVideoUrl,
    metadata,
  );

  @override
  String toString() =>
      'LivePhotoBundle(nativeVideoUrl: $nativeVideoUrl, imageFile: $imageFile, '
      'imageSource: $imageSource, metadata: $metadata)';
}
