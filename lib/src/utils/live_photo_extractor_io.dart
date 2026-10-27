import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../core/live_photo_source.dart';
import '../core/video_source.dart';
import '../data/enums/live_photo_format.dart';
import '../data/models/live_photo_bundle.dart';
import '../data/models/live_photo_metadata.dart';
import '../data/models/navite_file.dart';
import 'asset_extractor.dart';
import 'live_photo_parser.dart';
import 'temp_paths.dart';

/// 原生平台（Android / iOS / macOS / Linux / Windows）动态照片解析与文件落地抽取器。
///
/// Native IO implementation of [LivePhotoExtractor] for resolving paired Live Photos,
/// `.pvt` bundles, and single-file Motion Photos into playable [LivePhotoBundle]s.
class LivePhotoExtractor {
  LivePhotoExtractor._();

  static final Map<String, Future<LivePhotoBundle>> _inflight =
      <String, Future<LivePhotoBundle>>{};

  static const List<String> _companionVideoExts = <String>[
    '.MOV',
    '.mov',
    '.MP4',
    '.mp4',
    '.M4V',
    '.m4v',
  ];

  static const List<String> _companionImageExts = <String>[
    '.HEIC',
    '.heic',
    '.JPG',
    '.jpg',
    '.JPEG',
    '.jpeg',
    '.PNG',
    '.png',
    '.WEBP',
    '.webp',
    '.AVIF',
    '.avif',
  ];

  /// 将任意 [LivePhotoSource] 解析为可供播放与展示的 [LivePhotoBundle]。
  ///
  /// Resolves any [LivePhotoSource] into a playable [LivePhotoBundle].
  static Future<LivePhotoBundle> resolve(LivePhotoSource source) {
    final key = source.identity;
    final existing = _inflight[key];
    if (existing != null) return existing;
    final future = _doResolve(source);
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  /// 尝试从单个 [VideoSource] 中探测并提取动态照片；若不是动态照片则返回 `null`。
  ///
  /// Attempts to probe and extract a [LivePhotoBundle] from [source]. Returns
  /// `null` if [source] is not a Motion Photo or paired Live Photo.
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
  ///
  /// Returns `true` if [source] is a valid Motion Photo or paired Live Photo.
  static Future<bool> isLivePhoto(VideoSource source) async {
    final bundle = await tryExtractFromVideoSource(source);
    return bundle != null;
  }

  static Future<LivePhotoBundle> _doResolve(LivePhotoSource source) async {
    switch (source) {
      case PairedLivePhotoSource(
        :final image,
        :final video,
        :final presentationTimestamp,
      ):
        final nativeVideoUrl = await video.resolveToNativeUrl();
        final imageFile = await _resolveCoverNaviteFile(image);
        return LivePhotoBundle(
          imageFile: imageFile,
          imageSource: image,
          videoSource: video,
          nativeVideoUrl: nativeVideoUrl,
          metadata: LivePhotoMetadata(
            format: LivePhotoFormat.paired,
            presentationTimestamp: presentationTimestamp,
          ),
        );

      case BytesLivePhotoSource(
        :final bytes,
        :final name,
        :final presentationTimestamp,
      ):
        final parsed = LivePhotoParser.parseBytes(bytes);
        if (parsed == null) {
          throw FormatException(
            'BytesLivePhotoSource ($name) does not contain an embedded Motion Photo video stream.',
          );
        }
        return _materializeParsedBytes(
          parsed: parsed,
          cacheKeySeed: '$name-${bytes.length}-${sha1.convert(bytes.take(4096).toList())}',
          presentationTimestampOverride: presentationTimestamp,
        );

      case SingleFileLivePhotoSource(:final source, :final presentationTimestamp):
        final bundle = await _extractFromVideoSource(
          source,
          presentationTimestampOverride: presentationTimestamp,
        );
        if (bundle == null) {
          throw FormatException(
            'Source is not a valid Motion Photo or paired Live Photo: ${source.identity}',
          );
        }
        return bundle;
    }
  }

  static Future<LivePhotoBundle?> _extractFromVideoSource(
    VideoSource source, {
    Duration? presentationTimestampOverride,
  }) async {
    switch (source) {
      case LivePhotoVideoSource(:final livePhoto):
        return resolve(livePhoto);

      case FileVideoSource(:final path):
        final normalizedPath = path.startsWith('file://')
            ? Uri.parse(path).toFilePath()
            : path;

        // 1. Check if it is a macOS `.pvt` Live Photo package directory.
        final dir = Directory(normalizedPath);
        if (await dir.exists()) {
          return _extractFromPvtDirectory(
            dir,
            presentationTimestampOverride: presentationTimestampOverride,
          );
        }

        final file = File(normalizedPath);
        if (!await file.exists()) return null;

        // 2. Check if the file itself is a single-file Motion Photo.
        final lower = normalizedPath.toLowerCase();
        final isVideoExt = _companionVideoExts.any((ext) => lower.endsWith(ext.toLowerCase()));
        if (!isVideoExt) {
          final bytes = await file.readAsBytes();
          final parsed = LivePhotoParser.parseBytes(bytes);
          if (parsed != null) {
            final stat = await file.stat();
            return _materializeParsedBytes(
              parsed: parsed,
              cacheKeySeed: '$normalizedPath-${stat.size}-${stat.modified.millisecondsSinceEpoch}',
              presentationTimestampOverride: presentationTimestampOverride,
            );
          }
        }

        // 3. Auto-discover sibling companion file in the same directory (.MOV/.MP4 <-> .HEIC/.JPG).
        return _discoverSiblingPairedFile(
          file,
          isPrimaryVideo: isVideoExt,
          presentationTimestampOverride: presentationTimestampOverride,
        );

      case AssetVideoSource(:final assetPath, :final bundle):
        final effectiveBundle = bundle ?? rootBundle;
        final data = await effectiveBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final parsed = LivePhotoParser.parseBytes(bytes);
        if (parsed != null) {
          return _materializeParsedBytes(
            parsed: parsed,
            cacheKeySeed: 'asset://$assetPath-${bytes.length}',
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
            final imageFile = await _resolveCoverNaviteFile(imgSource);
            return LivePhotoBundle(
              imageFile: imageFile,
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
        final bytes = await _downloadNetworkBytes(url);
        if (bytes == null) return null;
        final parsed = LivePhotoParser.parseBytes(bytes);
        if (parsed == null) return null;
        return _materializeParsedBytes(
          parsed: parsed,
          cacheKeySeed: 'net://$url-${bytes.length}',
          presentationTimestampOverride: presentationTimestampOverride,
        );
    }
  }

  static Future<LivePhotoBundle?> _extractFromPvtDirectory(
    Directory dir, {
    Duration? presentationTimestampOverride,
  }) async {
    File? foundImage;
    File? foundVideo;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final p = entity.path.toLowerCase();
      if (foundImage == null && _companionImageExts.any((e) => p.endsWith(e.toLowerCase()))) {
        foundImage = entity;
      } else if (foundVideo == null &&
          _companionVideoExts.any((e) => p.endsWith(e.toLowerCase()))) {
        foundVideo = entity;
      }
    }
    if (foundVideo == null) return null;
    final videoSource = VideoSource.file(foundVideo.path);
    final imageSource = foundImage != null ? VideoSource.file(foundImage.path) : null;
    final imageFile = foundImage != null ? NaviteFile.fromLocation(foundImage.path) : null;
    return LivePhotoBundle(
      imageFile: imageFile,
      imageSource: imageSource,
      videoSource: videoSource,
      nativeVideoUrl: Uri.file(foundVideo.path).toString(),
      metadata: LivePhotoMetadata(
        format: LivePhotoFormat.paired,
        presentationTimestamp: presentationTimestampOverride,
      ),
    );
  }

  static Future<LivePhotoBundle?> _discoverSiblingPairedFile(
    File primaryFile, {
    required bool isPrimaryVideo,
    Duration? presentationTimestampOverride,
  }) async {
    final baseNoExt = _stripExtension(primaryFile.path);
    if (isPrimaryVideo) {
      for (final ext in _companionImageExts) {
        final candidate = File('$baseNoExt$ext');
        if (await candidate.exists()) {
          final imgSource = VideoSource.file(candidate.path);
          final vidSource = VideoSource.file(primaryFile.path);
          return LivePhotoBundle(
            imageFile: NaviteFile.fromLocation(candidate.path),
            imageSource: imgSource,
            videoSource: vidSource,
            nativeVideoUrl: Uri.file(primaryFile.path).toString(),
            metadata: LivePhotoMetadata(
              format: LivePhotoFormat.paired,
              presentationTimestamp: presentationTimestampOverride,
            ),
          );
        }
      }
      return null;
    } else {
      for (final ext in _companionVideoExts) {
        final candidate = File('$baseNoExt$ext');
        if (await candidate.exists()) {
          final imgSource = VideoSource.file(primaryFile.path);
          final vidSource = VideoSource.file(candidate.path);
          return LivePhotoBundle(
            imageFile: NaviteFile.fromLocation(primaryFile.path),
            imageSource: imgSource,
            videoSource: vidSource,
            nativeVideoUrl: Uri.file(candidate.path).toString(),
            metadata: LivePhotoMetadata(
              format: LivePhotoFormat.paired,
              presentationTimestamp: presentationTimestampOverride,
            ),
          );
        }
      }
      return null;
    }
  }

  static Future<LivePhotoBundle> _materializeParsedBytes({
    required ParsedMotionPhotoBytes parsed,
    required String cacheKeySeed,
    Duration? presentationTimestampOverride,
  }) async {
    final outDir = await pluginLivePhotoDir();
    final hash = sha1.convert(cacheKeySeed.codeUnits).toString();
    final imgExt = _imageExtFromMime(parsed.imageMimeType);
    final vidExt = parsed.videoMimeType == 'video/quicktime' ? 'mov' : 'mp4';

    final imgPath = '$outDir/$hash-cover.$imgExt';
    final vidPath = '$outDir/$hash-motion.$vidExt';

    await _writeAtomicallyIfMissing(imgPath, parsed.imageBytes);
    await _writeAtomicallyIfMissing(vidPath, parsed.videoBytes);

    final imageFile = NaviteFile.fromLocation(imgPath, mimeType: parsed.imageMimeType);
    final imageSource = VideoSource.file(imgPath);
    final videoSource = VideoSource.file(vidPath);
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
      imageSource: imageSource,
      videoSource: videoSource,
      nativeVideoUrl: Uri.file(vidPath).toString(),
      metadata: metadata,
    );
  }

  static Future<void> _writeAtomicallyIfMissing(String targetPath, Uint8List bytes) async {
    final target = File(targetPath);
    if (await target.exists() && await target.length() == bytes.length) {
      return;
    }
    await target.parent.create(recursive: true);
    final tmp = File('$targetPath.tmp.${DateTime.now().microsecondsSinceEpoch}');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(targetPath);
    } catch (_) {
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  static Future<NaviteFile?> _resolveCoverNaviteFile(VideoSource imageSource) async {
    switch (imageSource) {
      case FileVideoSource(:final path):
        final normalized = path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
        return NaviteFile.fromLocation(normalized, mimeType: _mimeFromPath(normalized));
      case AssetVideoSource(:final assetPath, :final bundle):
        final extracted = await AssetExtractor.extract(assetPath, bundle: bundle);
        return NaviteFile.fromLocation(extracted, mimeType: _mimeFromPath(assetPath));
      case NetworkVideoSource(:final url):
        return NaviteFile.fromLocation(url, mimeType: _mimeFromPath(url));
      case LivePhotoVideoSource(:final livePhoto):
        final bundle = await resolve(livePhoto);
        return bundle.imageFile;
    }
  }

  static Future<Uint8List?> _downloadNetworkBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != HttpStatus.ok) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
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

  static String _imageExtFromMime(String mime) {
    return switch (mime) {
      'image/png' => 'png',
      'image/heic' || 'image/heif' => 'heic',
      'image/avif' => 'avif',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
  }

  static String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    if (lower.endsWith('.avif')) return 'image/avif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
