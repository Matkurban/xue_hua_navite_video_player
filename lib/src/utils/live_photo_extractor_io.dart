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
        if (bundle != null) return bundle;
        // Never FormatException on bare HEIC/JPG assets: example Live Photos are
        // valid inputs even without embedded motion / sibling .MOV. Return a
        // still-container bundle so LivePhotoPlayer can enter the play flow
        // (it keeps the Flutter still opaque for format.unknown).
        return _stillContainerBundle(
          source,
          presentationTimestampOverride: presentationTimestamp,
        );
    }
  }

  /// Build a still-only Live Photo bundle when motion bytes / companion video are absent.
  ///
  /// Apple `MiPr` / vivo-trailer HEIC files are tagged [LivePhotoFormat.appleLivePhoto]
  /// so callers can distinguish "needs sibling .MOV" from plain images. The phone
  /// gallery pairs motion by the vivo content id; that video is **not** in-file.
  static Future<LivePhotoBundle> _stillContainerBundle(
    VideoSource source, {
    Duration? presentationTimestampOverride,
    Uint8List? probeBytes,
  }) async {
    NaviteFile? imageFile;
    try {
      imageFile = await _resolveCoverNaviteFile(source);
    } catch (_) {
      imageFile = null;
    }
    String nativeVideoUrl;
    try {
      nativeVideoUrl = await source.resolveToNativeUrl();
    } catch (_) {
      nativeVideoUrl = source.identity;
    }

    Uint8List? bytes = probeBytes;
    if (bytes == null) {
      try {
        bytes = await _readSourceBytes(source);
      } catch (_) {
        bytes = null;
      }
    }

    final isAppleOrVivo =
        bytes != null && LivePhotoParser.isLivePhotoStillContainerBytes(bytes);
    final vivoId =
        bytes != null ? LivePhotoParser.extractVivoLivePhotoContentId(bytes) : null;

    return LivePhotoBundle(
      imageFile: imageFile,
      imageSource: source,
      videoSource: source,
      nativeVideoUrl: nativeVideoUrl,
      metadata: LivePhotoMetadata(
        format: isAppleOrVivo ? LivePhotoFormat.appleLivePhoto : LivePhotoFormat.unknown,
        presentationTimestamp: presentationTimestampOverride,
        contentIdentifier: vivoId,
      ),
    );
  }

  static Future<Uint8List?> _readSourceBytes(VideoSource source) async {
    switch (source) {
      case FileVideoSource(:final path):
        final normalized = path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
        final file = File(normalized);
        if (!await file.exists()) return null;
        return file.readAsBytes();
      case AssetVideoSource(:final assetPath, :final bundle):
        final data = await (bundle ?? rootBundle).load(assetPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      case NetworkVideoSource(:final url):
        return _downloadNetworkBytes(url);
      case LivePhotoVideoSource(:final livePhoto):
        final bundle = await resolve(livePhoto);
        final img = bundle.imageFile;
        if (img == null) return null;
        return img.readAsBytes();
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
        Uint8List? stillProbeBytes;
        if (!isVideoExt) {
          stillProbeBytes = await file.readAsBytes();
          final parsed = LivePhotoParser.parseBytes(stillProbeBytes);
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
        final paired = await _discoverSiblingPairedFile(
          file,
          isPrimaryVideo: isVideoExt,
          presentationTimestampOverride: presentationTimestampOverride,
        );
        if (paired != null) return paired;

        // 4. Apple MiPr / vivo still (motion lives in gallery / sibling .MOV, not in-file).
        if (stillProbeBytes != null &&
            LivePhotoParser.isLivePhotoStillContainerBytes(stillProbeBytes)) {
          return _stillContainerBundle(
            source,
            presentationTimestampOverride: presentationTimestampOverride,
            probeBytes: stillProbeBytes,
          );
        }
        return null;

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
        // Fallback: check if a sibling .mov or .mp4 asset exists in the bundle
        // (exact basename + common case variants).
        final baseNoExt = _stripExtension(assetPath);
        final assetCandidates = <String>{
          for (final ext in _companionVideoExts) '$baseNoExt$ext',
          for (final ext in _companionVideoExts) '${baseNoExt.toLowerCase()}$ext',
          for (final ext in _companionVideoExts) '${baseNoExt.toUpperCase()}$ext',
        };
        for (final candidateVideoAsset in assetCandidates) {
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
        if (LivePhotoParser.isLivePhotoStillContainerBytes(bytes)) {
          return _stillContainerBundle(
            source,
            presentationTimestampOverride: presentationTimestampOverride,
            probeBytes: bytes,
          );
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
    final wantedExts = isPrimaryVideo ? _companionImageExts : _companionVideoExts;

    // 1) Fast path: same basename + known extension variants.
    for (final ext in wantedExts) {
      for (final candidatePath in <String>[
        '$baseNoExt$ext',
        '${baseNoExt.toLowerCase()}$ext',
        '${baseNoExt.toUpperCase()}$ext',
      ]) {
        final candidate = File(candidatePath);
        if (candidate.path == primaryFile.path) continue;
        if (await candidate.exists()) {
          return _pairedBundleFromFiles(
            imageFile: isPrimaryVideo ? candidate : primaryFile,
            videoFile: isPrimaryVideo ? primaryFile : candidate,
            presentationTimestampOverride: presentationTimestampOverride,
          );
        }
      }
    }

    // 2) Directory scan: case-insensitive basename match (Finder / Windows exports).
    final dir = primaryFile.parent;
    if (!await dir.exists()) return null;
    final primaryBase = _fileBasenameNoExt(primaryFile.path).toLowerCase();
    final wantedLower = {
      for (final e in wantedExts) e.toLowerCase(),
    };
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path == primaryFile.path) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      final lowerName = name.toLowerCase();
      final dot = lowerName.lastIndexOf('.');
      if (dot <= 0) continue;
      final ext = lowerName.substring(dot);
      if (!wantedLower.contains(ext)) continue;
      final base = lowerName.substring(0, dot);
      if (base != primaryBase) continue;
      return _pairedBundleFromFiles(
        imageFile: isPrimaryVideo ? entity : primaryFile,
        videoFile: isPrimaryVideo ? primaryFile : entity,
        presentationTimestampOverride: presentationTimestampOverride,
      );
    }
    return null;
  }

  static LivePhotoBundle _pairedBundleFromFiles({
    required File imageFile,
    required File videoFile,
    Duration? presentationTimestampOverride,
  }) {
    final imgSource = VideoSource.file(imageFile.path);
    final vidSource = VideoSource.file(videoFile.path);
    return LivePhotoBundle(
      imageFile: NaviteFile.fromLocation(imageFile.path),
      imageSource: imgSource,
      videoSource: vidSource,
      nativeVideoUrl: Uri.file(videoFile.path).toString(),
      metadata: LivePhotoMetadata(
        format: LivePhotoFormat.paired,
        presentationTimestamp: presentationTimestampOverride,
      ),
    );
  }

  static String _fileBasenameNoExt(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash == -1 ? normalized : normalized.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) return name.substring(0, dot);
    return name;
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
