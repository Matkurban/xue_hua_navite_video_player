import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

/// 视频封面候选帧。
///
/// Represents one candidate cover frame extracted from a video.
@immutable
class VideoCoverFrame {
  /// 封面图片（PNG）。跨平台标识是 [XFile.uri]：原生为 `file://` URI，Web 为 data / blob URL。
  /// 原生裸路径见 [FileSystemXFile.path]。
  /// Cover PNG. [XFile.uri] is the cross-platform id (`file://` on native, a
  /// data or blob URL on the web). The raw native path is [FileSystemXFile.path].
  final XFile image;

  /// 帧在视频中的时间戳。
  /// Position of the frame within the video.
  final Duration position;

  /// 平均亮度评分（0.0 – 1.0，越大越亮）。用于过滤纯黑帧、方便排序。
  /// Average brightness score (0.0–1.0, higher is brighter). Used to filter
  /// pure-black frames and rank candidates.
  final double brightness;

  const VideoCoverFrame({required this.image, required this.position, required this.brightness});

  @override
  String toString() =>
      'VideoCoverFrame(position: $position, brightness: ${brightness.toStringAsFixed(3)}, '
      'uri: ${image.uri})';
}
