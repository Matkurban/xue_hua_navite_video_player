import 'package:flutter/foundation.dart';

import 'navite_file.dart';

/// 视频封面候选帧。
///
/// Represents one candidate cover frame extracted from a video.
@immutable
class VideoCoverFrame {
  /// 封面图片（PNG）。跨平台标识是 [NaviteFile.uri]：原生为 `file://` URI，Web 为 data / blob URL。
  /// 原生本地文件路径见 [NaviteFile.path]。
  /// Cover PNG. [NaviteFile.uri] is the cross-platform id (`file://` on native, a
  /// data or blob URL on the web). The local file path is [NaviteFile.path].
  final NaviteFile image;

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
