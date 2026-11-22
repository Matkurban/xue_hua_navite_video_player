import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import '../utils/mime_detector.dart';

/// 表示文件已缓存切片的半开字节区间 `[start, end)`（满足 `0 <= start <= end`）。
///
/// Half-open byte range `[start, end)` representing a cached slice of a file.
@immutable
class ByteInterval {
  /// 区间起始字节偏移量（包含），必须大于等于 `0`。
  ///
  /// Inclusive starting byte offset (must be `>= 0`).
  final int start;

  /// 区间结束字节偏移量（不包含），必须大于等于 [start]。
  ///
  /// Exclusive ending byte offset (must be `>= start`).
  final int end;

  /// 创建一个半开字节区间 `[start, end)`。
  ///
  /// Creates a half-open byte interval `[start, end)`.
  const ByteInterval(this.start, this.end)
    : assert(start >= 0, 'start must be >= 0'),
      assert(end >= start, 'end must be >= start');

  /// 当前区间包含的字节长度（`end - start`）。
  ///
  /// Number of bytes covered by this interval (`end - start`).
  int get length => end - start;

  /// 当前区间是否为空（`end <= start`）。
  ///
  /// Whether this interval covers zero bytes (`end <= start`).
  bool get isEmpty => end <= start;

  /// 判断给定字节偏移量 [offset] 是否落在当前区间内。
  ///
  /// Returns `true` if [offset] falls within `[start, end)`.
  bool contains(int offset) => offset >= start && offset < end;

  /// 将任意乱序、重叠或相邻的 [intervals] 合并为互不重叠且严格递增的最简区间列表。
  ///
  /// Merges arbitrary unsorted, overlapping, or adjacent [intervals] into a
  /// sorted list of disjoint minimal intervals.
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

  /// 计算 [intervals] 合并后覆盖的总字节数。
  ///
  /// Computes the total number of unique bytes covered by [intervals].
  static int totalCoveredBytes(Iterable<ByteInterval> intervals) {
    var sum = 0;
    for (final item in merge(intervals)) {
      sum += item.length;
    }
    return sum;
  }

  /// 判断目标区间 `[targetStart, targetEnd)` 是否已被 [intervals] 完整覆盖。
  ///
  /// Returns `true` if `[targetStart, targetEnd)` is fully covered by [intervals].
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
///
/// Resolved playback or probe target returned by the caching layer, separating
/// local playback URLs from remote wireless casting URLs.
@immutable
class ResolvedVideoCacheTarget {
  /// 交给本地原生播放器或探测器的实际播放地址（可能是 `file://`、`http://127.0.0.1:...`、`blob:` 或原始远程 URL）。
  ///
  /// Actual URL passed to the local native player or prober (`file://`,
  /// `http://127.0.0.1:...`, `blob:`, or the original remote URL).
  final String playUrl;

  /// 交给无线投屏接收器（Google Cast / AirPlay / Windows Miracast/DLNA）的远程地址。
  /// 对于网络源，始终保持原始 `http(s)://` 地址，绝不暴露本机回环或自定义协议。
  ///
  /// Remote URL forwarded to wireless cast receivers; always preserves the
  /// original `http(s)://` address for network sources rather than loopback proxies.
  final String? castUrl;

  /// 规范化后的 40 位十六进制 SHA-1 缓存键。
  ///
  /// Normalized 40-character hexadecimal SHA-1 cache key.
  final String? cacheKey;

  /// 需要透传给上游网络请求的 HTTP 头。
  ///
  /// Optional HTTP request headers forwarded to upstream network requests.
  final Map<String, String>? headers;

  /// 本次打开是否启用缓存写入与读取。
  ///
  /// Whether cache reading and writing are enabled for this open request.
  final bool enableCache;

  /// 是否已 100% 命中本地完整缓存文件。
  ///
  /// Whether the target resolved to a 100% complete local cached file.
  final bool isCompleteFileHit;

  /// 创建一个 [ResolvedVideoCacheTarget] 实例。
  ///
  /// Creates a [ResolvedVideoCacheTarget] with [playUrl] and optional cache/cast metadata.
  const ResolvedVideoCacheTarget({
    required this.playUrl,
    this.castUrl,
    this.cacheKey,
    this.headers,
    this.enableCache = false,
    this.isCompleteFileHit = false,
  });
}

/// 缓存键计算与媒体扩展名推断工具类。
///
/// Utility helpers for computing deterministic SHA-1 cache keys, identifying
/// adaptive streaming manifests, and inferring container file extensions.
abstract final class VideoCacheKeyUtils {
  /// 插件支持的常见音视频容器扩展名白名单（带 `.` 前缀）。
  ///
  /// Whitelist of recognized audio/video container file extensions (with leading `.`).
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

  /// 解析网络源 [source] 用于缓存去重的原始业务标识字符串（尚未进行哈希）。
  ///
  /// 优先级：`source.cacheKey` > `config.cacheKeyBuilder` > `source.url`。
  ///
  /// Resolves the raw pre-hash cache identity string for [source] using
  /// [config], checking explicit `source.cacheKey`, `config.cacheKeyBuilder`,
  /// and finally falling back to `source.url`.
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

  /// 对原始标识 [rawIdentity] 计算跨平台文件名安全的固定 40 位十六进制 SHA-1 缓存键。
  ///
  /// Computes a filesystem-safe 40-character hexadecimal SHA-1 key from [rawIdentity].
  static String computeSha1Key(String rawIdentity) {
    return sha1.convert(utf8.encode(rawIdentity)).toString();
  }

  /// 判断 [url] 是否为自适应流媒体索引清单（HLS `.m3u8` 或 DASH `.mpd`）。
  ///
  /// Returns `true` if [url] points to an adaptive streaming manifest (`.m3u8` or `.mpd`).
  static bool isStreamingManifestUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  /// 结合原始 [url] 路径与可选 HTTP [contentType] 推断标准容器扩展名（带 `.` 前缀，默认 `.mp4`）。
  ///
  /// Infers a canonical media container extension (with leading `.`, defaulting
  /// to `.mp4`) from optional [contentType], [url] path, or [MimeDetector].
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
