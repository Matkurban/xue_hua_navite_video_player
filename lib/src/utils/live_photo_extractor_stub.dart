import 'dart:async';

import 'package:flutter/services.dart';

import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/live_photo_format.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';
import 'live_photo_parser.dart';

/// Web / WASM 平台动态照片解析与内存 `data:` URL 封装实现。
///
/// Web / WASM implementation of [LivePhotoExtractor] that wraps extracted still
/// images and embedded MP4 streams as in-memory `data:` URLs via [NaviteFile.fromBytes].
class LivePhotoExtractor {
  LivePhotoExtractor._();

  /// 将任意 [LivePhotoSource] 解析为可供播放与展示的 [LivePhotoBundle]。
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

  /// 尝试从单个 [VideoSource] 中探测并提取动态照片。
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
