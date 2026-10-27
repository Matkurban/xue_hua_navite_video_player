import 'package:flutter/foundation.dart';

import '../enums/live_photo_format.dart';

/// 动态照片（Live Photo / Motion Photo）的解析元数据。
///
/// Metadata extracted or associated with a Live Photo / Motion Photo.
@immutable
class LivePhotoMetadata {
  /// 动态照片容器格式（双文件配对、Google MicroVideo、Android MotionPhoto 1.0、Samsung 等）。
  ///
  /// Container format of the Live Photo / Motion Photo.
  final LivePhotoFormat format;

  /// 单文件动态照片中内嵌视频流在原文件中的起始字节偏移量（配对格式为 `null`）。
  ///
  /// Byte offset where the embedded video stream starts inside a single-file Motion Photo.
  final int? videoOffset;

  /// 单文件动态照片中内嵌视频流的字节长度（配对格式为 `null`）。
  ///
  /// Byte length of the embedded video stream inside a single-file Motion Photo.
  final int? videoLength;

  /// 静态主图对应的视频时间戳（由 XMP `MicroVideoPresentationTimestampUs` /
  /// `MotionPhotoPresentationTimestampUs` 或用户指定提供）。
  ///
  /// Presentation timestamp of the still cover frame within the motion clip.
  final Duration? presentationTimestamp;

  /// Apple Live Photo 的 `com.apple.quicktime.content.identifier` 或内容标识（若有）。
  ///
  /// Optional content identifier linking the still image and motion video.
  final String? contentIdentifier;

  const LivePhotoMetadata({
    required this.format,
    this.videoOffset,
    this.videoLength,
    this.presentationTimestamp,
    this.contentIdentifier,
  });

  /// 是否为单文件内嵌格式的动态照片。
  ///
  /// True when the video was extracted from a single-file Motion Photo container.
  bool get isSingleFile => format.isSingleFile;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LivePhotoMetadata &&
          other.format == format &&
          other.videoOffset == videoOffset &&
          other.videoLength == videoLength &&
          other.presentationTimestamp == presentationTimestamp &&
          other.contentIdentifier == contentIdentifier;

  @override
  int get hashCode =>
      Object.hash(format, videoOffset, videoLength, presentationTimestamp, contentIdentifier);

  @override
  String toString() =>
      'LivePhotoMetadata(format: ${format.name}, videoOffset: $videoOffset, '
      'videoLength: $videoLength, presentationTimestamp: $presentationTimestamp, '
      'contentIdentifier: $contentIdentifier)';
}
