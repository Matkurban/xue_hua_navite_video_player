import 'dart:async';

import 'package:flutter/services.dart';

import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/live_photo_format.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';
import 'live_photo_parser.dart';

/// 非 IO / 兜底平台的动态照片解析器，将拆出的静态封面与内嵌 MP4 封装为内存 `data:` URL。
///
/// Fallback / stub implementation of [LivePhotoExtractor] that wraps extracted
/// still images and embedded MP4 streams as in-memory `data:` URLs via [NaviteFile.fromBytes].
class LivePhotoExtractor {
  LivePhotoExtractor._();

  /// 将任意 [LivePhotoSource] 解析为可供播放与展示的 [LivePhotoBundle]。
  ///
  /// - [source]：实况照片源（配对源、字节源或单文件源）。
  /// - 返回值：包含静态封面、视频源及元数据的 [LivePhotoBundle]。
  ///
  /// Resolves any [LivePhotoSource] into a playable [LivePhotoBundle].
  static Future<LivePhotoBundle> resolve(LivePhotoSource source) async {
    switch (source) {
      case PairedLivePhotoSource(:final image, :final video, :final presentationTimestamp):
        final nativeVideoUrl = await video.resolveToNativeUrl();
        final imageUrl = await image.resolveToNativeUrl();
        return LivePhotoBundle(
          imageFile: NaviteFile.fromLocation(imageUrl),
          imageSource: image,
          videoSource: video,
          nativeVideoUrl: nativeVideoUrl,
          metadata: LivePhotoMetadata(
            format: LivePhotoFormat.paired,
            presentationTimestamp: presentationTimestamp,
          ),
        );

      case BytesLivePhotoSource(:final bytes, :final name, :final presentationTimestamp):
        final parsed = LivePhotoParser.parseBytes(bytes);
        if (parsed == null) {
          throw FormatException(
            'BytesLivePhotoSource ($name) does not contain an embedded Motion Photo video stream.',
          );
        }
        return _bundleFromParsed(parsed, presentationTimestampOverride: presentationTimestamp);

      case SingleFileLivePhotoSource(:final source, :final presentationTimestamp):
        final bundle = await tryExtractFromVideoSource(
          source,
          presentationTimestampOverride: presentationTimestamp,
        );
        if (bundle != null) return bundle;
        return _stillContainerBundle(source, presentationTimestampOverride: presentationTimestamp);
    }
  }

  static Future<LivePhotoBundle> _stillContainerBundle(
    VideoSource source, {
    Duration? presentationTimestampOverride,
  }) async {
    String nativeVideoUrl;
    try {
      nativeVideoUrl = await source.resolveToNativeUrl();
    } catch (_) {
      nativeVideoUrl = source.identity;
    }
    final imageUrl = nativeVideoUrl;
    return LivePhotoBundle(
      imageFile: NaviteFile.fromLocation(imageUrl),
      imageSource: source,
      videoSource: source,
      nativeVideoUrl: nativeVideoUrl,
      metadata: LivePhotoMetadata(
        format: LivePhotoFormat.unknown,
        presentationTimestamp: presentationTimestampOverride,
      ),
    );
  }

  /// 尝试从单个 [VideoSource] 中探测并提取动态照片；若不支持或非动态照片则返回 `null`。
  ///
  /// - [source]：待探测的媒体源。
  /// - [presentationTimestampOverride]：可选的封面帧时间戳覆盖值。
  ///
  /// Attempts to probe and extract a [LivePhotoBundle] from [source], returning
  /// `null` when [source] is not a supported Motion Photo.
  static Future<LivePhotoBundle?> tryExtractFromVideoSource(
    VideoSource source, {
    Duration? presentationTimestampOverride,
  }) async {
    try {
      switch (source) {
        case LivePhotoVideoSource(:final livePhoto):
          return await resolve(livePhoto);

        case AssetVideoSource(:final assetPath, :final bundle):
          final effectiveBundle = bundle ?? rootBundle;
          final data = await effectiveBundle.load(assetPath);
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          final parsed = LivePhotoParser.parseBytes(bytes);
          if (parsed == null) return null;
          return _bundleFromParsed(
            parsed,
            presentationTimestampOverride: presentationTimestampOverride,
          );

        case NetworkVideoSource() || FileVideoSource():
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// 检测 [source] 是否为动态照片。
  ///
  /// Returns `true` if [source] is detected as a valid Live Photo / Motion Photo.
  static Future<bool> isLivePhoto(VideoSource source) async {
    final bundle = await tryExtractFromVideoSource(source);
    return bundle != null;
  }

  static LivePhotoBundle _bundleFromParsed(
    ParsedMotionPhotoBytes parsed, {
    Duration? presentationTimestampOverride,
  }) {
    final imageFile = NaviteFile.fromBytes(
      parsed.imageBytes,
      name: 'live_cover.jpg',
      mimeType: parsed.imageMimeType,
    );
    final videoFile = NaviteFile.fromBytes(
      parsed.videoBytes,
      name: 'live_motion.mp4',
      mimeType: parsed.videoMimeType,
    );
    final metadata = presentationTimestampOverride != null
        ? LivePhotoMetadata(
            format: parsed.metadata.format,
            videoOffset: parsed.metadata.videoOffset,
            videoLength: parsed.metadata.videoLength,
            presentationTimestamp: presentationTimestampOverride,
            contentIdentifier: parsed.metadata.contentIdentifier,
          )
        : parsed.metadata;

    return LivePhotoBundle(
      imageFile: imageFile,
      imageSource: VideoSource.network(imageFile.uri),
      videoSource: VideoSource.network(videoFile.uri),
      nativeVideoUrl: videoFile.uri,
      metadata: metadata,
    );
  }
}
