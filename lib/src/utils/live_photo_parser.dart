import 'dart:convert';
import 'dart:typed_data';

import '../data/enums/live_photo_format.dart';
import '../data/models/live_photo_metadata.dart';

/// 单文件动态照片（Motion Photo / MicroVideo）二进制拆分结果。
///
/// Result of parsing a single-file Motion Photo binary payload.
class ParsedMotionPhotoBytes {
  /// 纯净的静态封面图像字节（移除了尾部拼接的视频流）。
  ///
  /// Clean still image bytes (with the trailing video stream stripped when applicable).
  final Uint8List imageBytes;

  /// 静态封面图的 MIME 类型（如 `'image/jpeg'`、`'image/heic'`、`'image/png'`）。
  ///
  /// MIME type of the still image.
  final String imageMimeType;

  /// 拆分出的独立视频流字节（MP4 / MOV）。
  ///
  /// Extracted standalone MP4 / QuickTime video bytes.
  final Uint8List videoBytes;

  /// 视频流的 MIME 类型（如 `'video/mp4'` 或 `'video/quicktime'`）。
  ///
  /// MIME type of the extracted video stream.
  final String videoMimeType;

  /// 解析出的动态照片格式与时间戳元数据。
  ///
  /// Parsed metadata (format, byte offset, byte length, presentation timestamp).
  final LivePhotoMetadata metadata;

  const ParsedMotionPhotoBytes({
    required this.imageBytes,
    required this.imageMimeType,
    required this.videoBytes,
    required this.videoMimeType,
    required this.metadata,
  });
}

/// 纯 Dart 实现的跨平台动态照片（Motion Photo / Live Photo）二进制与 XMP 解析器及合成器。
///
/// 支持格式：
/// 1. Google Camera MicroVideo XMP (`GCamera:MicroVideoOffset`)
/// 2. Android / Google Motion Photo 1.0 (`Container:Directory` / `Item:Semantic="MotionPhoto"` + `Item:Length`)
/// 3. Samsung Motion Photo (`MotionPhoto_Data` 标记块)
/// 4. 通用内嵌 MP4 / QuickTime 尾部流（JPEG `FF D9` 之后或 HEIC 二级 `ftyp` 视频容器）
/// 5. Apple QuickTime `com.apple.quicktime.content.identifier` 元数据嗅探
abstract final class LivePhotoParser {
  static const List<int> _samsungMarker = <int>[
    0x4D, 0x6F, 0x74, 0x69, 0x6F, 0x6E, 0x50, 0x68, // MotionPh
    0x6F, 0x74, 0x6F, 0x5F, 0x44, 0x61, 0x74, 0x61, // oto_Data
  ];

  static const Set<String> _videoMajorBrands = <String>{
    'mp41',
    'mp42',
    'isom',
    'iso2',
    'iso4',
    'iso5',
    'iso6',
    'avc1',
    'hvc1',
    'hev1',
    'qt  ',
    'MSNV',
    '3gp4',
    '3gp5',
    '3gp6',
    'M4V ',
    'f4v ',
    'ndsc',
    'ndsh',
    'ndsm',
    'ndsp',
    'ndss',
  };

  /// Returns `true` if [bytes] looks like an Apple Live Photo *still* (HEIC `MiPr` brand).
  ///
  /// These files are valid Live Photo stills; the motion clip is a paired `.MOV`
  /// (or an embedded Motion Photo stream). Detecting this avoids treating the
  /// still as a playable video URL when the companion is missing.
  static bool isAppleLivePhotoStillBytes(Uint8List bytes) {
    if (bytes.length < 16) return false;
    if (bytes[4] != 0x66 || bytes[5] != 0x74 || bytes[6] != 0x79 || bytes[7] != 0x70) {
      return false;
    }
    final end = bytes.length < 64 ? bytes.length : 64;
    for (var i = 8; i + 4 <= end; i++) {
      if (bytes[i] == 0x4D &&
          bytes[i + 1] == 0x69 &&
          bytes[i + 2] == 0x50 &&
          bytes[i + 3] == 0x72) {
        return true;
      }
    }
    return false;
  }

  /// Returns `true` if [bytes] carries a vivo / Android `livephoto` trailer marker.
  static bool isVivoLivePhotoMarkerBytes(Uint8List bytes) {
    if (bytes.length < 32) return false;
    return _indexOfSequence(bytes, ascii.encode('com.android.camera.livephoto')) != -1 ||
        _indexOfSequence(bytes, ascii.encode('com.vivo.gallery.livePhoto')) != -1;
  }

  /// Returns `true` when [bytes] is an Apple / vivo Live Photo *still container*
  /// (MiPr brand and/or vivo livephoto trailer) even if no motion bytes are present.
  static bool isLivePhotoStillContainerBytes(Uint8List bytes) {
    return isAppleLivePhotoStillBytes(bytes) || isVivoLivePhotoMarkerBytes(bytes);
  }

  /// Extracts vivo / Android `com.android.camera.livephoto` pairing id from a trailer, if any.
  ///
  /// This id is used by the phone gallery to locate the companion motion clip; it is
  /// **not** embedded video. Returns `null` when the marker is absent.
  static String? extractVivoLivePhotoContentId(Uint8List bytes) {
    if (bytes.length < 32) return null;
    final text = latin1.decode(
      bytes.length > 4096 ? bytes.sublist(bytes.length - 4096) : bytes,
      allowInvalid: true,
    );
    final match = RegExp(
      r'com\.android\.camera\.livephoto"\s*:\s*"([^"]+)"',
    ).firstMatch(text);
    if (match != null) return match.group(1);
    final album = RegExp(r'cameralbum!\x00\x00\x00/([^\x00\xff]+)').firstMatch(text);
    return album?.group(1);
  }

  /// 快速检测字节流是否包含单文件动态照片（Motion Photo）。
  ///
  /// Returns `true` if [bytes] contains an embedded Motion Photo video stream.
  static bool isMotionPhotoBytes(Uint8List bytes) {
    return parseBytes(bytes) != null;
  }

  /// 解析单文件动态照片字节流，拆分出静态图片、内嵌视频与 [LivePhotoMetadata]。
  /// 若 [bytes] 不是有效的单文件动态照片，返回 `null`。
  ///
  /// Parses a single-file Motion Photo byte buffer into still image bytes,
  /// embedded video bytes, and [LivePhotoMetadata]. Returns `null` if [bytes]
  /// does not contain an embedded video stream.
  static ParsedMotionPhotoBytes? parseBytes(Uint8List bytes) {
    if (bytes.length < 32) return null;

    // If the file itself starts at offset 0 with a video ftyp brand, it is a
    // standalone video file, not an image with an embedded Motion Photo stream.
    if (_isVideoFtypAt(bytes, 0)) {
      return null;
    }

    final imageMime = _detectImageMime(bytes);
    final xmpText = _extractXmpString(bytes);
    final presentationTs = xmpText != null ? _parsePresentationTimestamp(xmpText) : null;

    // 1. Try Google Camera MicroVideo XMP (GCamera:MicroVideoOffset)
    if (xmpText != null) {
      final microOffset = _parseMicroVideoOffset(xmpText);
      if (microOffset != null && microOffset > 16 && microOffset < bytes.length) {
        final rawStart = bytes.length - microOffset;
        final resolvedStart = _refineVideoStartOffset(bytes, rawStart);
        if (resolvedStart != null && resolvedStart > 0 && resolvedStart < bytes.length - 16) {
          return _buildResult(
            bytes: bytes,
            videoStart: resolvedStart,
            imageMime: imageMime,
            format: LivePhotoFormat.gcameraMicroVideo,
            presentationTimestamp: presentationTs,
          );
        }
      }

      // 2. Try Android / Google Motion Photo 1.0 (Container:Directory / Item:Length)
      final motionPhotoLength = _parseMotionPhotoContainerLength(xmpText);
      if (motionPhotoLength != null &&
          motionPhotoLength > 16 &&
          motionPhotoLength < bytes.length) {
        final rawStart = bytes.length - motionPhotoLength;
        final resolvedStart = _refineVideoStartOffset(bytes, rawStart);
        if (resolvedStart != null && resolvedStart > 0 && resolvedStart < bytes.length - 16) {
          return _buildResult(
            bytes: bytes,
            videoStart: resolvedStart,
            imageMime: imageMime,
            format: LivePhotoFormat.androidMotionPhoto,
            presentationTimestamp: presentationTs,
          );
        }
      }
    }

    // 3. Try Samsung "MotionPhoto_Data" marker
    final samsungIndex = _indexOfSequence(bytes, _samsungMarker, start: 2);
    if (samsungIndex != -1) {
      final afterMarker = samsungIndex + _samsungMarker.length;
      final resolvedStart = _refineVideoStartOffset(bytes, afterMarker) ??
          (afterMarker < bytes.length - 16 && _isLikelyMp4At(bytes, afterMarker)
              ? afterMarker
              : null);
      if (resolvedStart != null && resolvedStart > 0 && resolvedStart < bytes.length - 16) {
        return _buildResult(
          bytes: bytes,
          videoStart: resolvedStart,
          imageEndOverride: samsungIndex,
          imageMime: imageMime,
          format: LivePhotoFormat.samsungMotionPhoto,
          presentationTimestamp: presentationTs,
        );
      }
    }

    // 4. Fallback: Scan for embedded ISO BMFF video `ftyp` box after image header
    final embeddedStart = _findEmbeddedVideoFtypOffset(bytes);
    if (embeddedStart != null && embeddedStart > 0 && embeddedStart < bytes.length - 16) {
      return _buildResult(
        bytes: bytes,
        videoStart: embeddedStart,
        imageMime: imageMime,
        format: LivePhotoFormat.embeddedMp4,
        presentationTimestamp: presentationTs,
      );
    }

    return null;
  }

  /// 从 QuickTime / MP4 字节流中提取 Apple Live Photo 的 `com.apple.quicktime.content.identifier`（若有）。
  ///
  /// Extracts `com.apple.quicktime.content.identifier` from a QuickTime/MP4 byte buffer if present.
  static String? extractQuickTimeContentIdentifier(Uint8List bytes) {
    const key = 'com.apple.quicktime.content.identifier';
    final keyBytes = ascii.encode(key);
    final idx = _indexOfSequence(bytes, keyBytes);
    if (idx == -1) return null;
    // Scan up to 256 bytes after the key for a UUID-like ASCII identifier.
    final end = (idx + keyBytes.length + 256).clamp(0, bytes.length);
    final window = String.fromCharCodes(bytes.sublist(idx + keyBytes.length, end));
    final uuidMatch = RegExp(
      r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}',
    ).firstMatch(window);
    return uuidMatch?.group(0);
  }

  /// 将静态 JPEG（或任意图片）字节与 MP4/MOV 视频字节合成为标准 XMP 单文件动态照片（Motion Photo）。
  ///
  /// 同时写入 Google Camera `GCamera:MicroVideoOffset` 与 Android Motion Photo 1.0
  /// `Container:Directory` 双兼容 XMP 元数据，确保所有主流相册与本插件解析器均可直接识别。
  ///
  /// Synthesizes a standard single-file Motion Photo by injecting dual-compatible
  /// Google `GCamera:MicroVideo` + `GCamera:MotionPhoto` XMP metadata and appending [videoBytes].
  static Uint8List createMotionPhotoBytes({
    required Uint8List imageBytes,
    required Uint8List videoBytes,
    Duration? presentationTimestamp,
    String? contentIdentifier,
  }) {
    if (videoBytes.isEmpty) {
      throw ArgumentError.value(videoBytes, 'videoBytes', 'Video bytes cannot be empty.');
    }
    final tsUs = presentationTimestamp?.inMicroseconds ?? 0;
    final videoLen = videoBytes.length;
    final xmpPayload =
        '<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" '
        'xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" '
        'xmlns:Container="http://ns.google.com/photos/1.0/container/" '
        'xmlns:Item="http://ns.google.com/photos/1.0/container/item/" '
        'GCamera:MicroVideo="1" '
        'GCamera:MicroVideoVersion="1" '
        'GCamera:MicroVideoOffset="$videoLen" '
        'GCamera:MicroVideoPresentationTimestampUs="$tsUs" '
        'GCamera:MotionPhoto="1" '
        'GCamera:MotionPhotoVersion="1" '
        'GCamera:MotionPhotoPresentationTimestampUs="$tsUs">'
        '<Container:Directory>'
        '<rdf:Seq>'
        '<rdf:li rdf:parseType="Resource">'
        '<Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Length="0" Item:Padding="0"/>'
        '</rdf:li>'
        '<rdf:li rdf:parseType="Resource">'
        '<Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="$videoLen" Item:Padding="0"/>'
        '</rdf:li>'
        '</rdf:Seq>'
        '</Container:Directory>'
        '</rdf:Description>'
        '</rdf:RDF>'
        '</x:xmpmeta>';

    final xmpNamespace = ascii.encode('http://ns.adobe.com/xap/1.0/\x00');
    final xmpBody = utf8.encode(xmpPayload);
    final app1DataLength = 2 + xmpNamespace.length + xmpBody.length;

    final builder = BytesBuilder(copy: false);
    // If imageBytes starts with JPEG SOI (0xFF 0xD8), insert APP1 (0xFF 0xE1) right after SOI.
    if (imageBytes.length >= 2 &&
        imageBytes[0] == 0xFF &&
        imageBytes[1] == 0xD8 &&
        app1DataLength <= 0xFFFF) {
      builder.addByte(0xFF);
      builder.addByte(0xD8);
      builder.addByte(0xFF);
      builder.addByte(0xE1);
      builder.addByte((app1DataLength >> 8) & 0xFF);
      builder.addByte(app1DataLength & 0xFF);
      builder.add(xmpNamespace);
      builder.add(xmpBody);
      builder.add(imageBytes.sublist(2));
    } else {
      // Non-JPEG cover: keep original image bytes and embed XMP + video trailer.
      builder.add(imageBytes);
      builder.add(xmpNamespace);
      builder.add(xmpBody);
    }
    builder.add(videoBytes);
    return builder.toBytes();
  }

  static ParsedMotionPhotoBytes _buildResult({
    required Uint8List bytes,
    required int videoStart,
    required String imageMime,
    required LivePhotoFormat format,
    int? imageEndOverride,
    Duration? presentationTimestamp,
  }) {
    final imageEnd = (imageEndOverride ?? videoStart).clamp(0, bytes.length);
    final imageSlice = Uint8List.fromList(bytes.sublist(0, imageEnd));
    final videoSlice = Uint8List.fromList(bytes.sublist(videoStart));
    final videoMime = _detectVideoMime(videoSlice);
    final contentId = extractQuickTimeContentIdentifier(videoSlice);

    return ParsedMotionPhotoBytes(
      imageBytes: imageSlice,
      imageMimeType: imageMime,
      videoBytes: videoSlice,
      videoMimeType: videoMime,
      metadata: LivePhotoMetadata(
        format: format,
        videoOffset: videoStart,
        videoLength: videoSlice.length,
        presentationTimestamp: presentationTimestamp,
        contentIdentifier: contentId,
      ),
    );
  }

  static String? _extractXmpString(Uint8List bytes) {
    // Search within the first 256 KB (or full buffer if smaller) where XMP headers reside.
    final scanLen = bytes.length < 262144 ? bytes.length : 262144;
    final headerText = latin1.decode(bytes.sublist(0, scanLen), allowInvalid: true);
    final xmpStart = headerText.indexOf('<x:xmpmeta');
    if (xmpStart != -1) {
      final xmpEnd = headerText.indexOf('</x:xmpmeta>', xmpStart);
      if (xmpEnd != -1) {
        return headerText.substring(xmpStart, xmpEnd + 12);
      }
    }
    final rdfStart = headerText.indexOf('<rdf:RDF');
    if (rdfStart != -1) {
      final rdfEnd = headerText.indexOf('</rdf:RDF>', rdfStart);
      if (rdfEnd != -1) {
        return headerText.substring(rdfStart, rdfEnd + 10);
      }
    }
    return null;
  }

  static int? _parseMicroVideoOffset(String xmp) {
    // Attribute form: GCamera:MicroVideoOffset="12345" or MicroVideoOffset="12345"
    final attrMatch = RegExp(
      r'(?:GCamera:)?MicroVideoOffset\s*=\s*["\x27](\d+)["\x27]',
    ).firstMatch(xmp);
    if (attrMatch != null) {
      return int.tryParse(attrMatch.group(1)!);
    }
    // Element form: <GCamera:MicroVideoOffset>12345</GCamera:MicroVideoOffset>
    final elemMatch = RegExp(
      r'<(?:GCamera:)?MicroVideoOffset>\s*(\d+)\s*</(?:GCamera:)?MicroVideoOffset>',
    ).firstMatch(xmp);
    if (elemMatch != null) {
      return int.tryParse(elemMatch.group(1)!);
    }
    return null;
  }

  static int? _parseMotionPhotoContainerLength(String xmp) {
    // Match Container:Item tags that describe MotionPhoto or video/mp4 or video/quicktime
    final itemRegex = RegExp(
      r'<(?:Container:)?Item\b[^>]*>',
       dotAll: true,
    );
    for (final match in itemRegex.allMatches(xmp)) {
      final tag = match.group(0)!;
      final isMotionItem =
          tag.contains('MotionPhoto') ||
          tag.contains('video/mp4') ||
          tag.contains('video/quicktime');
      if (!isMotionItem) continue;
      final lenMatch = RegExp(r'(?:Item:)?Length\s*=\s*["\x27](\d+)["\x27]').firstMatch(tag);
      if (lenMatch != null) {
        final len = int.tryParse(lenMatch.group(1)!);
        if (len != null && len > 0) return len;
      }
    }
    return null;
  }

  static Duration? _parsePresentationTimestamp(String xmp) {
    final match = RegExp(
      r'(?:GCamera:)?(?:MotionPhoto|MicroVideo)PresentationTimestampUs\s*=\s*["\x27](-?\d+)["\x27]',
    ).firstMatch(xmp);
    if (match != null) {
      final us = int.tryParse(match.group(1)!);
      if (us != null && us >= 0) {
        return Duration(microseconds: us);
      }
    }
    final elemMatch = RegExp(
      r'<(?:GCamera:)?(?:MotionPhoto|MicroVideo)PresentationTimestampUs>\s*(-?\d+)\s*<',
    ).firstMatch(xmp);
    if (elemMatch != null) {
      final us = int.tryParse(elemMatch.group(1)!);
      if (us != null && us >= 0) {
        return Duration(microseconds: us);
      }
    }
    return null;
  }

  static int? _refineVideoStartOffset(Uint8List bytes, int candidateStart) {
    if (candidateStart >= 0 &&
        candidateStart <= bytes.length - 16 &&
        _isLikelyMp4At(bytes, candidateStart)) {
      return candidateStart;
    }
    // Search within a +/- 128 byte window around candidateStart in case of padding or markers.
    final windowStart = (candidateStart - 128).clamp(2, bytes.length - 16);
    final windowEnd = (candidateStart + 128).clamp(2, bytes.length - 16);
    for (var i = windowStart; i <= windowEnd; i++) {
      if (_isLikelyMp4At(bytes, i)) {
        return i;
      }
    }
    return null;
  }

  static int? _findEmbeddedVideoFtypOffset(Uint8List bytes) {
    // Scan from offset 4 onwards for 'ftyp' (0x66 0x74 0x79 0x70) where offset - 4 is box size.
    for (var i = 8; i <= bytes.length - 12; i++) {
      if (bytes[i] == 0x66 &&
          bytes[i + 1] == 0x74 &&
          bytes[i + 2] == 0x79 &&
          bytes[i + 3] == 0x70) {
        final boxStart = i - 4;
        if (_isVideoFtypAt(bytes, boxStart)) {
          return boxStart;
        }
      }
    }
    return null;
  }

  static bool _isLikelyMp4At(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 12 > bytes.length) return false;
    if (_isVideoFtypAt(bytes, offset)) return true;
    final boxType = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (boxType == 'moov' || boxType == 'wide' || boxType == 'free') {
      final boxSize = _readUint32BE(bytes, offset);
      return boxSize >= 8 && offset + boxSize <= bytes.length;
    }
    return false;
  }

  static bool _isVideoFtypAt(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 12 > bytes.length) return false;
    if (bytes[offset + 4] != 0x66 ||
        bytes[offset + 5] != 0x74 ||
        bytes[offset + 6] != 0x79 ||
        bytes[offset + 7] != 0x70) {
      return false;
    }
    final boxSize = _readUint32BE(bytes, offset);
    if (boxSize < 12 || boxSize > 4096 || offset + boxSize > bytes.length) {
      return false;
    }
    final majorBrand = String.fromCharCodes(bytes.sublist(offset + 8, offset + 12));
    if (_videoMajorBrands.contains(majorBrand)) {
      return true;
    }
    // Also inspect compatible brands in the ftyp box.
    for (var pos = offset + 16; pos + 4 <= offset + boxSize; pos += 4) {
      final compat = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      if (_videoMajorBrands.contains(compat)) {
        return true;
      }
    }
    return false;
  }

  static int _readUint32BE(Uint8List bytes, int offset) {
    return ((bytes[offset] & 0xFF) << 24) |
        ((bytes[offset + 1] & 0xFF) << 16) |
        ((bytes[offset + 2] & 0xFF) << 8) |
        (bytes[offset + 3] & 0xFF);
  }

  static int _indexOfSequence(Uint8List bytes, List<int> pattern, {int start = 0}) {
    if (pattern.isEmpty || bytes.length < pattern.length) return -1;
    final first = pattern[0];
    final maxIdx = bytes.length - pattern.length;
    for (var i = start; i <= maxIdx; i++) {
      if (bytes[i] != first) continue;
      var matched = true;
      for (var j = 1; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }

  static String _detectImageMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (brand == 'avif' || brand == 'avis') return 'image/avif';
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  static String _detectVideoMime(Uint8List videoBytes) {
    if (videoBytes.length >= 12 &&
        videoBytes[4] == 0x66 &&
        videoBytes[5] == 0x74 &&
        videoBytes[6] == 0x79 &&
        videoBytes[7] == 0x70) {
      final brand = String.fromCharCodes(videoBytes.sublist(8, 12));
      if (brand == 'qt  ') {
        return 'video/quicktime';
      }
    }
    return 'video/mp4';
  }
}
