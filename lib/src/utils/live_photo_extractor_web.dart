import 'dart:async';
import 'dart:js_interop';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as html;

import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/live_photo_format.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';
import 'live_photo_parser.dart';

/// Web / WASM 平台完整动态照片解析与原生 `Blob` Object URL (`blob:`) 抽取器。
///
/// 支持：
/// - 双源配对实况照片（`http(s)://`、`blob:`、`assets/`）
/// - 单文件 Motion Photo（从 `http(s)://`、Web 本地文件选择器 `blob:`、Flutter `assets/` 或 `Uint8List` 字节流中解析）
/// - 使用浏览器原生 `URL.createObjectURL(Blob)` 生成零 Base64 损耗的 `blob:` 播放地址，确保 HTML5 `<video>` 高速加载与任意 Seek。
class LivePhotoExtractor {
  LivePhotoExtractor._();

  static final Map<String, Future<LivePhotoBundle>> _inflight = <String, Future<LivePhotoBundle>>{};
  static final Map<String, LivePhotoBundle> _blobCache = <String, LivePhotoBundle>{};

  static const List<String> _companionVideoExts = <String>[
    '.MOV',
    '.mov',
    '.MP4',
    '.mp4',
    '.M4V',
    '.m4v',
  ];

  /// 将任意 [LivePhotoSource] 解析为可供 Web 播放与展示的 [LivePhotoBundle]。
  static Future<LivePhotoBundle> resolve(LivePhotoSource source) {
    final key = source.identity;
    final cached = _blobCache[key];
    if (cached != null) return Future<LivePhotoBundle>.value(cached);

    final existing = _inflight[key];
    if (existing != null) return existing;
    final future = _doResolve(source).then((bundle) {
      _blobCache[key] = bundle;
      return bundle;
    });
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  /// 尝试从单个 [VideoSource]（`NetworkVideoSource`、Web `blob:` `FileVideoSource` 或 `AssetVideoSource`）
  /// 中探测并提取动态照片；若不是动态照片则返回 `null`。
  static Future<LivePhotoBundle?> tryExtractFromVideoSource(
    VideoSource source, {
    Duration? presentationTimestampOverride,
  }) async {
    try {
      return await _extractFromVideoSource(
        source,
        presentationTimestampOverride: presentationTimestampOverride,
      );
    } catch (_) {
      return null;
    }
  }

  /// 检测 [source] 是否为动态照片。
  static Future<bool> isLivePhoto(VideoSource source) async {
    final bundle = await tryExtractFromVideoSource(source);
    return bundle != null;
  }

  static Future<LivePhotoBundle> _doResolve(LivePhotoSource source) async {
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
        final cacheSeed = '$name-${bytes.length}-${sha1.convert(bytes.take(4096).toList())}';
        return _bundleFromParsed(
          parsed,
          cacheKey: cacheSeed,
          presentationTimestampOverride: presentationTimestamp,
        );

      case SingleFileLivePhotoSource(:final source, :final presentationTimestamp):
        final bundle = await _extractFromVideoSource(
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
    final bundle = LivePhotoBundle(
      imageFile: NaviteFile.fromLocation(imageUrl),
      imageSource: source,
      videoSource: source,
      nativeVideoUrl: nativeVideoUrl,
      metadata: LivePhotoMetadata(
        format: LivePhotoFormat.unknown,
        presentationTimestamp: presentationTimestampOverride,
      ),
    );
    return bundle;
  }

  static Future<LivePhotoBundle?> _extractFromVideoSource(
    VideoSource source, {
    Duration? presentationTimestampOverride,
  }) async {
    switch (source) {
      case LivePhotoVideoSource(:final livePhoto):
        return resolve(livePhoto);

      case AssetVideoSource(:final assetPath, :final bundle):
        final effectiveBundle = bundle ?? rootBundle;
        final data = await effectiveBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final parsed = LivePhotoParser.parseBytes(bytes);
        if (parsed != null) {
          return _bundleFromParsed(
            parsed,
            cacheKey: 'asset://$assetPath-${bytes.length}',
            presentationTimestampOverride: presentationTimestampOverride,
          );
        }
        // Fallback: check if a sibling .mov or .mp4 asset exists in the bundle.
        final baseNoExt = _stripExtension(assetPath);
        for (final ext in _companionVideoExts) {
          final candidateVideoAsset = '$baseNoExt$ext';
          if (candidateVideoAsset == assetPath) continue;
          try {
            await effectiveBundle.load(candidateVideoAsset);
            final imgSource = VideoSource.asset(assetPath, bundle: bundle);
            final vidSource = VideoSource.asset(candidateVideoAsset, bundle: bundle);
            final nativeVideoUrl = await vidSource.resolveToNativeUrl();
            final imageUrl = await imgSource.resolveToNativeUrl();
            return LivePhotoBundle(
              imageFile: NaviteFile.fromLocation(imageUrl),
              imageSource: imgSource,
              videoSource: vidSource,
              nativeVideoUrl: nativeVideoUrl,
              metadata: LivePhotoMetadata(
                format: LivePhotoFormat.paired,
                presentationTimestamp: presentationTimestampOverride,
              ),
            );
          } catch (_) {}
        }
        return null;

      case NetworkVideoSource(:final url):
        final bytes = await _fetchBytesOnWeb(url);
        if (bytes == null) return null;
        final parsed = LivePhotoParser.parseBytes(bytes);
        if (parsed == null) return null;
        return _bundleFromParsed(
          parsed,
          cacheKey: 'net://$url-${bytes.length}',
          presentationTimestampOverride: presentationTimestampOverride,
        );

      case FileVideoSource(:final path):
        // On Web, FileVideoSource typically holds a `blob:` or `data:` URL from a file picker.
        final bytes = await _fetchBytesOnWeb(path);
        if (bytes == null) return null;
        final parsed = LivePhotoParser.parseBytes(bytes);
        if (parsed == null) return null;
        return _bundleFromParsed(
          parsed,
          cacheKey: 'file://$path-${bytes.length}',
          presentationTimestampOverride: presentationTimestampOverride,
        );
    }
  }

  static LivePhotoBundle _bundleFromParsed(
    ParsedMotionPhotoBytes parsed, {
    required String cacheKey,
    Duration? presentationTimestampOverride,
  }) {
    final existing = _blobCache[cacheKey];
    if (existing != null) return existing;

    final imageBlobUrl = _createBlobUrl(parsed.imageBytes, parsed.imageMimeType);
    final videoBlobUrl = _createBlobUrl(parsed.videoBytes, parsed.videoMimeType);

    final imageFile = NaviteFile.fromBytes(
      parsed.imageBytes,
      name: 'live_cover.jpg',
      mimeType: parsed.imageMimeType,
      path: imageBlobUrl,
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

    final bundle = LivePhotoBundle(
      imageFile: imageFile,
      imageSource: VideoSource.network(imageBlobUrl),
      videoSource: VideoSource.network(videoBlobUrl),
      nativeVideoUrl: videoBlobUrl,
      metadata: metadata,
    );
    _blobCache[cacheKey] = bundle;
    return bundle;
  }

  static String _createBlobUrl(Uint8List bytes, String mimeType) {
    try {
      final parts = <JSAny>[bytes.toJS].toJS;
      final blob = html.Blob(parts, html.BlobPropertyBag(type: mimeType));
      return html.URL.createObjectURL(blob);
    } catch (_) {
      // Fallback to data: URL if Blob creation is unavailable in the current JS environment.
      return NaviteFile.fromBytes(bytes, mimeType: mimeType).uri;
    }
  }

  static Future<Uint8List?> _fetchBytesOnWeb(String url) async {
    if (url.startsWith('data:')) {
      try {
        return UriData.parse(url).contentAsBytes();
      } catch (_) {
        return null;
      }
    }
    try {
      final response = await html.window.fetch(url.toJS).toDart;
      if (!response.ok) return null;
      final arrayBuffer = await response.arrayBuffer().toDart;
      return arrayBuffer.toDart.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static String _stripExtension(String path) {
    final slash = path.replaceAll('\\', '/').lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    if (dot > slash && dot != -1) {
      return path.substring(0, dot);
    }
    return path;
  }
}
