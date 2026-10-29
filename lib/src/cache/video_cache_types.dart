import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import '../utils/mime_detector.dart';

/// 半开字节区间 `[start, end)`（`0 <= start < end`）。
///
/// Half-open byte range `[start, end)` representing a cached slice of a file.
@immutable
class ByteInterval {
  final int start;
  final int end;

  const ByteInterval(this.start, this.end)
    : assert(start >= 0, 'start must be >= 0'),
      assert(end >= start, 'end must be >= start');

  int get length => end - start;

  bool get isEmpty => end <= start;

  bool contains(int offset) => offset >= start && offset < end;

  /// 将任意乱序、重叠或相邻的区间列表合并为互不重叠且严格递增的最简区间表。
  static List<ByteInterval> merge(Iterable<ByteInterval> intervals) {
    final nonEmpty = intervals.where((i) => i.end > i.start).toList();
    if (nonEmpty.isEmpty) return const <ByteInterval>[];
    nonEmpty.sort((a, b) {
      final cmp = a.start.compareTo(b.start);
      return cmp != 0 ? cmp : b.end.compareTo(a.end);
    });

    final merged = <ByteInterval>[nonEmpty.first];
    for (var i = 1; i < nonEmpty.length; i++) {
      final current = nonEmpty[i];
      final last = merged.last;
      if (current.start <= last.end) {
        if (current.end > last.end) {
          merged[merged.length - 1] = ByteInterval(last.start, current.end);
        }
      } else {
        merged.add(current);
      }
    }
    return merged;
  }

  /// 计算合并后所有已缓存字节总数。
  static int totalCoveredBytes(Iterable<ByteInterval> intervals) {
    var sum = 0;
    for (final item in merge(intervals)) {
      sum += item.length;
    }
    return sum;
  }

  /// 判断 `[targetStart, targetEnd)` 是否已被区间集合完整覆盖。
  static bool coversRange(Iterable<ByteInterval> intervals, int targetStart, int targetEnd) {
    if (targetEnd <= targetStart) return true;
    for (final item in merge(intervals)) {
      if (item.start <= targetStart && item.end >= targetEnd) {
        return true;
      }
      if (item.start > targetStart) {
        return false;
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ByteInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start, $end)';
}

/// 缓存层为一次播放或媒体探测解析出的目标描述。
@immutable
class ResolvedVideoCacheTarget {
  /// 交给本地原生播放器或探测器的实际播放地址（可能是 `file://`、`http://127.0.0.1:...`、`blob:` 或原始远程 URL）。
  final String playUrl;

  /// 交给无线投屏接收器（Google Cast / AirPlay / Windows Miracast/DLNA）的远程地址。
  /// 对于网络源，始终保持原始 `http(s)://` 地址，绝不暴露本机回环或自定义协议。
  final String? castUrl;

  /// 规范化后的 40 位十六进制 SHA-1 缓存键。
  final String? cacheKey;

  /// 需要透传给上游网络请求的 HTTP 头。
  final Map<String, String>? headers;

  /// 本次打开是否启用缓存写入与读取。
  final bool enableCache;

  /// 是否已 100% 命中本地完整缓存文件。
  final bool isCompleteFileHit;

  const ResolvedVideoCacheTarget({
    required this.playUrl,
    this.castUrl,
    this.cacheKey,
    this.headers,
    this.enableCache = false,
    this.isCompleteFileHit = false,
  });
}

/// 缓存键计算与媒体扩展名推断工具。
abstract final class VideoCacheKeyUtils {
  static const List<String> knownMediaExtensions = <String>[
    '.mp4',
    '.mov',
    '.m4v',
    '.webm',
    '.mkv',
    '.avi',
    '.flv',
    '.ts',
    '.3gp',
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.flac',
  ];

  /// 解析网络源用于缓存去重的原始业务标识字符串（尚未哈希）。
  static String resolveRawIdentity(NetworkVideoSource source, VideoCacheConfig config) {
    final explicit = source.cacheKey?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final builder = config.cacheKeyBuilder;
    if (builder != null) {
      final uri = Uri.tryParse(source.url);
      if (uri != null) {
        final built = builder(uri).trim();
        if (built.isNotEmpty) {
          return built;
        }
      }
    }
    return source.url.trim();
  }

  /// 生成跨平台文件名安全的固定 40 字符 SHA-1 缓存键。
  static String computeSha1Key(String rawIdentity) {
    return sha1.convert(utf8.encode(rawIdentity)).toString();
  }

  /// 判断 URL 是否为自适应流媒体索引清单（HLS `.m3u8` / DASH `.mpd`）。
  static bool isStreamingManifestUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  /// 结合原始 URL 路径与可选的 HTTP `Content-Type` 推断标准容器扩展名（带 `.` 前缀）。
  static String inferExtension(String url, {String? contentType}) {
    if (contentType != null && contentType.isNotEmpty) {
      final cleanMime = contentType.split(';').first.trim().toLowerCase();
      final byMime = switch (cleanMime) {
        'video/mp4' || 'application/mp4' => '.mp4',
        'video/quicktime' => '.mov',
        'video/x-m4v' => '.m4v',
        'video/webm' => '.webm',
        'video/x-matroska' => '.mkv',
        'video/x-msvideo' => '.avi',
        'video/x-flv' => '.flv',
        'video/mp2t' => '.ts',
        'video/3gpp' => '.3gp',
        'audio/mpeg' || 'audio/mp3' => '.mp3',
        'audio/mp4' || 'audio/x-m4a' => '.m4a',
        'audio/aac' => '.aac',
        'audio/wav' || 'audio/x-wav' => '.wav',
        'audio/ogg' || 'video/ogg' => '.ogg',
        'audio/flac' => '.flac',
        _ => null,
      };
      if (byMime != null) return byMime;
    }

    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    final slash = path.lastIndexOf('/');
    final fileName = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = fileName.lastIndexOf('.');
    if (dot > 0 && dot < fileName.length - 1) {
      final ext = fileName.substring(dot).toLowerCase();
      if (knownMediaExtensions.contains(ext)) {
        return ext;
      }
    }

    final detected = MimeDetector.detect(url);
    return switch (detected) {
      'video/quicktime' => '.mov',
      'video/webm' => '.webm',
      'video/x-matroska' => '.mkv',
      'audio/mpeg' => '.mp3',
      'audio/mp4' => '.m4a',
      'audio/aac' => '.aac',
      'audio/wav' => '.wav',
      'audio/ogg' => '.ogg',
      'audio/flac' => '.flac',
      _ => '.mp4',
    };
  }
}
