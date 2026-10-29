import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import '../utils/temp_paths.dart';
import 'video_cache_types.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

class _RegisteredSource {
  String url;
  Map<String, String>? headers;
  final String cacheKey;

  _RegisteredSource({required this.url, required this.cacheKey, this.headers});
}

class _EntryMetadata {
  final String url;
  final int totalLength;
  final String contentType;
  final String ext;
  final int updatedAtMs;

  const _EntryMetadata({
    required this.url,
    required this.totalLength,
    required this.contentType,
    required this.ext,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'totalLength': totalLength,
    'contentType': contentType,
    'ext': ext,
    'updatedAtMs': updatedAtMs,
  };

  factory _EntryMetadata.fromJson(Map<String, dynamic> map) {
    return _EntryMetadata(
      url: (map['url'] as String?) ?? '',
      totalLength: (map['totalLength'] as num?)?.toInt() ?? -1,
      contentType: (map['contentType'] as String?) ?? 'video/mp4',
      ext: (map['ext'] as String?) ?? '.mp4',
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class _DiskSegment {
  final int start;
  final int length;
  final File file;

  const _DiskSegment({required this.start, required this.length, required this.file});

  int get end => start + length;

  ByteInterval get interval => ByteInterval(start, end);
}

class _EvictCandidate {
  final String key;
  final FileSystemEntity entity;
  final int byteSize;
  final DateTime lastModified;

  const _EvictCandidate({
    required this.key,
    required this.entity,
    required this.byteSize,
    required this.lastModified,
  });
}

/// 纯 Dart 稀疏分片磁盘缓存引擎 + 本机回环 (`127.0.0.1`) HTTP Range 代理服务。
///
/// 核心特性：
/// - 完整缓存命中直返 `file://` 本地路径（零代理 Socket 开销）；
/// - 未完成缓存时通过 `127.0.0.1` 提供标准 `206 Partial Content` 流服务，
///   已落盘区间直接读本地 `.seg` 分片，缺失区间向上游按需发起 `Range` 请求并实时落盘；
/// - 区间覆盖 `[0, totalLength)` 后自动原子重命名为完整媒体文件；
/// - 支持活跃会话 `pin/unpin` 引用保护、单文件体积阈值旁路、LRU 容量淘汰及 `precache` 预加载。
class LocalVideoCacheEngine {
  VideoCacheConfig _config = const VideoCacheConfig();
  HttpServer? _server;
  final String _sessionToken = _randomHex(16);
  final Map<String, _RegisteredSource> _sources = <String, _RegisteredSource>{};
  final Set<String> _pinnedKeys = <String>{};
  final Set<String> _lockedSegmentPaths = <String>{};
  final Map<String, Future<void>> _keyLocks = <String, Future<void>>{};
  final Map<String, HttpClient> _precacheClients = <String, HttpClient>{};

  VideoCacheConfig get config => _config;

  /// 解析当前生效的磁盘缓存目录路径。
  Future<String> resolveCacheDir() async {
    final custom = _config.cacheDirectory?.trim();
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    }
    return pluginMediaCacheDir();
  }

  Future<void> configure(VideoCacheConfig config) async {
    _config = config;
    if (config.enabled && config.maxCacheBytes > 0) {
      await evictIfNeeded();
    } else if (config.maxCacheBytes == 0) {
      await clearCache();
    }
  }

  void pin(String cacheKey) {
    _pinnedKeys.add(cacheKey);
  }

  void unpin(String cacheKey) {
    _pinnedKeys.remove(cacheKey);
  }

  /// 查找指定 [cacheKey] 是否已有 100% 落盘的完整媒体文件。
  static Future<File?> findCompleteFileInDir(String cacheDir, String cacheKey) async {
    for (final ext in VideoCacheKeyUtils.knownMediaExtensions) {
      final candidate = File('$cacheDir/$cacheKey$ext');
      if (await candidate.exists()) {
        final len = await candidate.length();
        if (len > 0) {
          return candidate;
        }
      }
    }
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return null;
    final prefix = '$cacheKey.';
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      if (!name.startsWith(prefix)) continue;
      if (name.endsWith('.tmp') || name.endsWith('.json') || name.endsWith('.part')) {
        continue;
      }
      final len = await entity.length();
      if (len > 0) {
        return entity;
      }
    }
    return null;
  }

  /// 为桌面端播放器（或测试调用方）解析播放目标。
  Future<ResolvedVideoCacheTarget> resolveForPlayback(NetworkVideoSource source) async {
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, _config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final enabled =
        (source.enableCache ?? _config.enabled) &&
        _config.maxCacheBytes > 0 &&
        _config.maxSingleFileBytes > 0 &&
        !VideoCacheKeyUtils.isStreamingManifestUrl(source.url);

    if (!enabled) {
      return ResolvedVideoCacheTarget(
        playUrl: source.url,
        castUrl: source.url,
        cacheKey: cacheKey,
        headers: source.headers,
        enableCache: false,
      );
    }

    final cacheDir = await resolveCacheDir();
    final complete = await findCompleteFileInDir(cacheDir, cacheKey);
    if (complete != null) {
      _touchFileBestEffort(complete);
      return ResolvedVideoCacheTarget(
        playUrl: Uri.file(complete.path).toString(),
        castUrl: source.url,
        cacheKey: cacheKey,
        headers: source.headers,
        enableCache: true,
        isCompleteFileHit: true,
      );
    }

    try {
      await _ensureServerStarted();
      final server = _server;
      if (server != null) {
        _sources[cacheKey] = _RegisteredSource(
          url: source.url,
          cacheKey: cacheKey,
          headers: source.headers,
        );
        final ext = VideoCacheKeyUtils.inferExtension(source.url);
        final proxyUrl = 'http://127.0.0.1:${server.port}/cache/$_sessionToken/$cacheKey$ext';
        return ResolvedVideoCacheTarget(
          playUrl: proxyUrl,
          castUrl: source.url,
          cacheKey: cacheKey,
          headers: source.headers,
          enableCache: true,
        );
      }
    } catch (_) {
      // Fallback to direct remote URL if loopback server bind is restricted.
    }

    return ResolvedVideoCacheTarget(
      playUrl: source.url,
      castUrl: source.url,
      cacheKey: cacheKey,
      headers: source.headers,
      enableCache: false,
    );
  }

  /// 为 `MediaProbe` 解析目标（完整命中走本地 `file://`，未完成走代理或原地址）。
  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) async {
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, _config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await resolveCacheDir();
    final complete = await findCompleteFileInDir(cacheDir, cacheKey);
    if (complete != null) {
      _touchFileBestEffort(complete);
      return ResolvedVideoCacheTarget(
        playUrl: Uri.file(complete.path).toString(),
        castUrl: source.url,
        cacheKey: cacheKey,
        headers: source.headers,
        enableCache: true,
        isCompleteFileHit: true,
      );
    }
    return ResolvedVideoCacheTarget(
      playUrl: source.url,
      castUrl: source.url,
      cacheKey: cacheKey,
      headers: source.headers,
      enableCache: false,
    );
  }

  /// 后台预加载指定字节数（`preloadBytes == null` 时预加载完整文件）。
  Future<void> precache(NetworkVideoSource source, {int? preloadBytes}) async {
    final enabled =
        (source.enableCache ?? _config.enabled) &&
        _config.maxCacheBytes > 0 &&
        _config.maxSingleFileBytes > 0 &&
        !VideoCacheKeyUtils.isStreamingManifestUrl(source.url);
    if (!enabled) return;

    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, _config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await resolveCacheDir();

    if (await findCompleteFileInDir(cacheDir, cacheKey) != null) {
      return;
    }
    if (_precacheClients.containsKey(cacheKey)) {
      return;
    }

    final partDir = Directory('$cacheDir/$cacheKey.part');
    await partDir.create(recursive: true);

    final segments = await _listSegments(partDir);
    var startOffset = 0;
    for (final seg in segments) {
      if (seg.start == 0) {
        startOffset = max(startOffset, seg.end);
      }
    }
    if (preloadBytes != null && preloadBytes > 0 && startOffset >= preloadBytes) {
      return;
    }

    final uri = Uri.tryParse(source.url);
    if (uri == null) return;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    _precacheClients[cacheKey] = client;
    String? lockedSegPath;
    RandomAccessFile? segRaf;

    try {
      final req = await client.getUrl(uri);
      _applyRequestHeaders(req, source.headers);
      if (preloadBytes != null && preloadBytes > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-${preloadBytes - 1}');
      } else if (startOffset > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-');
      }

      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != HttpStatus.ok && res.statusCode != HttpStatus.partialContent) {
        await res.drain<void>();
        return;
      }

      final existingMeta = await _readMetadata(partDir);
      final meta = _extractMetadataFromResponse(res, url: source.url, fallback: existingMeta);
      if (meta.totalLength > _config.maxSingleFileBytes) {
        return;
      }
      await _writeMetadata(partDir, meta);

      final actualStart = res.statusCode == HttpStatus.partialContent ? startOffset : 0;
      segRaf = await _openWritableSegment(partDir, actualStart, (p) => lockedSegPath = p);
      if (segRaf == null) {
        await res.drain<void>();
        return;
      }

      var written = actualStart;
      await for (final chunk in res) {
        if (!_precacheClients.containsKey(cacheKey)) {
          break;
        }
        await segRaf.writeFrom(chunk);
        written += chunk.length;
        if (preloadBytes != null && preloadBytes > 0 && written >= preloadBytes) {
          break;
        }
      }
      await segRaf.flush();
      await segRaf.close();
      segRaf = null;
      if (lockedSegPath != null) {
        _lockedSegmentPaths.remove(lockedSegPath);
        lockedSegPath = null;
      }

      await _tryPromoteAndEvict(cacheDir: cacheDir, cacheKey: cacheKey);
    } catch (_) {
      // Quietly ignore network or cancellation errors during background precache.
    } finally {
      _precacheClients.remove(cacheKey);
      try {
        await segRaf?.close();
      } catch (_) {}
      if (lockedSegPath != null) {
        _lockedSegmentPaths.remove(lockedSegPath);
      }
      client.close(force: true);
    }
  }

  Future<void> cancelPrecache(NetworkVideoSource source) async {
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, _config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final client = _precacheClients.remove(cacheKey);
    client?.close(force: true);
  }

  Future<bool> isCached(NetworkVideoSource source) async {
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, _config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await resolveCacheDir();
    var complete = await findCompleteFileInDir(cacheDir, cacheKey);
    if (complete == null) {
      await _tryPromoteAndEvict(cacheDir: cacheDir, cacheKey: cacheKey);
      complete = await findCompleteFileInDir(cacheDir, cacheKey);
    }
    return complete != null;
  }

  Future<int> getCacheSize() async {
    final cacheDir = await resolveCacheDir();
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return 0;
    return _directoryByteSize(dir);
  }

  Future<void> removeCache(NetworkVideoSource source) async {
    await cancelPrecache(source);
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, _config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    await removeCacheByKey(cacheKey);
  }

  Future<void> removeCacheByKey(String cacheKey) async {
    final cacheDir = await resolveCacheDir();
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return;
    await _withKeyLock(cacheKey, () async {
      await for (final entity in dir.list(followLinks: false)) {
        final name = _basename(entity.path);
        if (name == '$cacheKey.part' || name.startsWith('$cacheKey.')) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    });
  }

  Future<void> clearCache() async {
    for (final client in _precacheClients.values) {
      client.close(force: true);
    }
    _precacheClients.clear();

    final cacheDir = await resolveCacheDir();
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      final name = _basename(entity.path);
      final key = _extractKeyFromEntryName(name);
      if (key != null && _pinnedKeys.contains(key)) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> evictIfNeeded() async {
    final maxBytes = _config.maxCacheBytes;
    final cacheDir = await resolveCacheDir();
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return;

    final candidates = <_EvictCandidate>[];
    var totalBytes = 0;

    await for (final entity in dir.list(followLinks: false)) {
      final name = _basename(entity.path);
      if (name.endsWith('.tmp')) continue;
      final key = _extractKeyFromEntryName(name);
      if (key == null) continue;

      try {
        if (entity is File) {
          final stat = await entity.stat();
          totalBytes += stat.size;
          candidates.add(
            _EvictCandidate(
              key: key,
              entity: entity,
              byteSize: stat.size,
              lastModified: stat.modified,
            ),
          );
        } else if (entity is Directory && name.endsWith('.part')) {
          final size = await _directoryByteSize(entity);
          final stat = await entity.stat();
          totalBytes += size;
          candidates.add(
            _EvictCandidate(key: key, entity: entity, byteSize: size, lastModified: stat.modified),
          );
        }
      } catch (_) {}
    }

    if (totalBytes <= maxBytes) return;

    candidates.sort((a, b) => a.lastModified.compareTo(b.lastModified));
    for (final item in candidates) {
      if (totalBytes <= maxBytes) break;
      if (_pinnedKeys.contains(item.key)) continue;
      if (_hasActiveWriterForKey(cacheDir, item.key)) continue;
      try {
        await item.entity.delete(recursive: true);
        totalBytes -= item.byteSize;
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    for (final client in _precacheClients.values) {
      client.close(force: true);
    }
    _precacheClients.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> _ensureServerStarted() async {
    if (_server != null) return;
    await Zone.root.run(() async {
      if (_server != null) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
      _server = server;
      server.listen(_handleProxyRequest, onError: (_) {}, cancelOnError: false);
    });
  }

  Future<void> _handleProxyRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length != 3 || segments[0] != 'cache' || segments[1] != _sessionToken) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }

      final fileToken = segments[2];
      final dot = fileToken.indexOf('.');
      final cacheKey = dot > 0 ? fileToken.substring(0, dot) : fileToken;
      final source = _sources[cacheKey];
      if (source == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final cacheDir = await resolveCacheDir();
      final complete = await findCompleteFileInDir(cacheDir, cacheKey);
      if (complete != null) {
        _touchFileBestEffort(complete);
        await _serveCompleteLocalFile(request, complete);
        return;
      }

      await _serveSparseOrStream(request: request, cacheDir: cacheDir, source: source);
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveCompleteLocalFile(HttpRequest request, File file) async {
    final response = request.response;
    final totalLength = await file.length();
    final contentType = _mimeFromExtension(_extensionOf(file.path));

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);

    final parsedRange = _parseRangeHeader(
      request.headers.value(HttpHeaders.rangeHeader),
      totalLength,
    );

    if (parsedRange == _RangeParseResult.unsatisfiable) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
      await response.close();
      return;
    }

    if (parsedRange != null && parsedRange.interval != null) {
      final range = parsedRange.interval!;
      final endInclusive = range.end - 1;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-$endInclusive/$totalLength',
      );
      response.contentLength = range.length;
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await response.addStream(file.openRead(range.start, range.end));
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.contentLength = totalLength;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    await response.addStream(file.openRead());
    await response.close();
  }

  Future<void> _serveSparseOrStream({
    required HttpRequest request,
    required String cacheDir,
    required _RegisteredSource source,
  }) async {
    final response = request.response;
    final partDir = Directory('$cacheDir/${source.cacheKey}.part');
    await partDir.create(recursive: true);

    var meta = await _readMetadata(partDir);
    var diskSegments = await _listSegments(partDir);
    final rawRangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    // Cold-start fast path: no cached segments yet and GET from offset >= 0 (not suffix range).
    // Open a single upstream connection immediately so zero extra probe round-trip is needed.
    final isSuffixRange = rawRangeHeader != null && rawRangeHeader.startsWith('bytes=-');
    if (meta == null && diskSegments.isEmpty && request.method == 'GET' && !isSuffixRange) {
      await _serveColdStartDirect(
        request: request,
        cacheDir: cacheDir,
        partDir: partDir,
        source: source,
        rawRangeHeader: rawRangeHeader,
      );
      return;
    }

    // Ensure metadata (especially totalLength) is known before computing Content-Range.
    meta ??= await _probeUpstreamMetadata(partDir: partDir, source: source);
    if (meta == null || meta.totalLength <= 0) {
      // Upstream does not expose Content-Length (chunked / live stream): proxy directly without caching.
      await _proxyPassThroughWithoutCache(request: request, source: source);
      return;
    }

    final totalLength = meta.totalLength;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, meta.contentType);

    final parsedRange = _parseRangeHeader(rawRangeHeader, totalLength);
    if (parsedRange == _RangeParseResult.unsatisfiable) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
      await response.close();
      return;
    }

    final int reqStart;
    final int reqEndExclusive;
    if (parsedRange != null && parsedRange.interval != null) {
      reqStart = parsedRange.interval!.start;
      reqEndExclusive = parsedRange.interval!.end;
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $reqStart-${reqEndExclusive - 1}/$totalLength',
      );
      response.contentLength = reqEndExclusive - reqStart;
    } else {
      reqStart = 0;
      reqEndExclusive = totalLength;
      response.statusCode = HttpStatus.ok;
      response.contentLength = totalLength;
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    final canWriteToDisk =
        _config.enabled && _config.maxCacheBytes > 0 && totalLength <= _config.maxSingleFileBytes;

    var cursor = reqStart;
    var wroteNewBytes = false;

    while (cursor < reqEndExclusive) {
      final promotedComplete = await findCompleteFileInDir(cacheDir, source.cacheKey);
      if (promotedComplete != null) {
        await for (final chunk in promotedComplete.openRead(cursor, reqEndExclusive)) {
          response.add(chunk);
        }
        await response.flush();
        cursor = reqEndExclusive;
        wroteNewBytes = false;
        break;
      }

      diskSegments = await _listSegments(partDir);
      _DiskSegment? hitSeg;
      for (final seg in diskSegments) {
        if (seg.start <= cursor && seg.end > cursor) {
          if (hitSeg == null || seg.end > hitSeg.end) {
            hitSeg = seg;
          }
        }
      }

      if (hitSeg != null) {
        final sliceEnd = min(reqEndExclusive, hitSeg.end);
        final localOffsetStart = cursor - hitSeg.start;
        final localOffsetEnd = sliceEnd - hitSeg.start;
        await for (final chunk in hitSeg.file.openRead(localOffsetStart, localOffsetEnd)) {
          response.add(chunk);
        }
        await response.flush();
        cursor = sliceEnd;
        continue;
      }

      // Find the next cached segment after `cursor` so we only fetch the missing gap!
      var gapEndExclusive = reqEndExclusive;
      for (final seg in diskSegments) {
        if (seg.start > cursor && seg.start < gapEndExclusive) {
          gapEndExclusive = seg.start;
        }
      }

      final gapResult = await _fetchGapFromUpstream(
        response: response,
        partDir: partDir,
        source: source,
        gapStart: cursor,
        gapEndExclusive: gapEndExclusive,
        canWriteToDisk: canWriteToDisk,
        holdFinalChunk: canWriteToDisk && gapEndExclusive == reqEndExclusive,
      );
      if (gapResult.forwarded <= 0) {
        break;
      }
      if (canWriteToDisk) {
        wroteNewBytes = true;
        await _tryPromoteAndEvict(cacheDir: cacheDir, cacheKey: source.cacheKey);
        wroteNewBytes = false;
      }
      if (gapResult.heldFinalChunk != null) {
        response.add(gapResult.heldFinalChunk!);
        await response.flush();
      }
      cursor += gapResult.forwarded;
    }

    if (wroteNewBytes) {
      await _tryPromoteAndEvict(cacheDir: cacheDir, cacheKey: source.cacheKey);
    }
    await response.close();
  }

  Future<void> _serveColdStartDirect({
    required HttpRequest request,
    required String cacheDir,
    required Directory partDir,
    required _RegisteredSource source,
    required String? rawRangeHeader,
  }) async {
    final response = request.response;
    final uri = Uri.parse(source.url);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    String? lockedSegPath;
    RandomAccessFile? segRaf;
    var wroteBytes = false;
    var promoted = false;

    try {
      int requestedStart = 0;
      int? requestedEndInclusive;
      if (rawRangeHeader != null && rawRangeHeader.startsWith('bytes=')) {
        final spec = rawRangeHeader.substring('bytes='.length).split(',').first.trim();
        final parts = spec.split('-');
        if (parts.length == 2) {
          requestedStart = int.tryParse(parts[0]) ?? 0;
          requestedEndInclusive = parts[1].isEmpty ? null : int.tryParse(parts[1]);
        }
      }

      final upReq = await client.getUrl(uri);
      _applyRequestHeaders(upReq, source.headers);
      if (rawRangeHeader != null) {
        upReq.headers.set(HttpHeaders.rangeHeader, rawRangeHeader);
      } else {
        // Request with Range: bytes=0- when possible so servers confirm byte-range capability.
        upReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      }

      final upRes = await upReq.close().timeout(const Duration(seconds: 20));
      final meta = _extractMetadataFromResponse(upRes, url: source.url);
      final canCache =
          _config.enabled &&
          _config.maxCacheBytes > 0 &&
          meta.totalLength > 0 &&
          meta.totalLength <= _config.maxSingleFileBytes &&
          (upRes.statusCode == HttpStatus.ok || upRes.statusCode == HttpStatus.partialContent);

      if (canCache) {
        await _writeMetadata(partDir, meta);
      }

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentTypeHeader, meta.contentType);

      var expectedOutLength = -1;
      if (rawRangeHeader != null && upRes.statusCode == HttpStatus.partialContent) {
        response.statusCode = HttpStatus.partialContent;
        final cr = upRes.headers.value(HttpHeaders.contentRangeHeader);
        if (cr != null) {
          response.headers.set(HttpHeaders.contentRangeHeader, cr);
        } else if (meta.totalLength > 0) {
          final endInc = requestedEndInclusive != null
              ? min(requestedEndInclusive, meta.totalLength - 1)
              : (meta.totalLength - 1);
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $requestedStart-$endInc/${meta.totalLength}',
          );
        }
        if (upRes.contentLength >= 0) {
          response.contentLength = upRes.contentLength;
          expectedOutLength = upRes.contentLength;
        }
      } else if (rawRangeHeader != null &&
          upRes.statusCode == HttpStatus.ok &&
          requestedStart == 0 &&
          requestedEndInclusive == null &&
          meta.totalLength > 0) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-${meta.totalLength - 1}/${meta.totalLength}',
        );
        response.contentLength = meta.totalLength;
        expectedOutLength = meta.totalLength;
      } else if (rawRangeHeader == null &&
          upRes.statusCode == HttpStatus.partialContent &&
          requestedStart == 0) {
        // Non-Range client GET: return RFC-compliant 200 OK instead of unsolicited 206.
        response.statusCode = HttpStatus.ok;
        if (upRes.contentLength >= 0) {
          response.contentLength = upRes.contentLength;
          expectedOutLength = upRes.contentLength;
        }
      } else {
        response.statusCode = upRes.statusCode;
        if (upRes.contentLength >= 0) {
          response.contentLength = upRes.contentLength;
          expectedOutLength = upRes.contentLength;
        }
      }

      final writeStartOffset = upRes.statusCode == HttpStatus.partialContent ? requestedStart : 0;
      if (canCache) {
        segRaf = await _openWritableSegment(partDir, writeStartOffset, (p) => lockedSegPath = p);
      }

      var upstreamOffset = writeStartOffset;
      var sentOutBytes = 0;
      List<int>? heldFinalChunk;

      void emitOutChunk(List<int> outChunk) {
        if (outChunk.isEmpty) return;
        if (canCache &&
            expectedOutLength > 0 &&
            sentOutBytes + outChunk.length >= expectedOutLength) {
          if (heldFinalChunk == null) {
            heldFinalChunk = outChunk;
          } else {
            heldFinalChunk = <int>[...heldFinalChunk!, ...outChunk];
          }
          sentOutBytes += outChunk.length;
        } else {
          response.add(outChunk);
          sentOutBytes += outChunk.length;
        }
      }

      await for (final chunk in upRes) {
        if (segRaf != null) {
          await segRaf.writeFrom(chunk);
          wroteBytes = true;
        }
        // If rawRangeHeader asked for an offset > 0 but upstream ignored Range and returned 200 OK,
        // slice the outgoing bytes to match what the player requested.
        if (rawRangeHeader != null && upRes.statusCode == HttpStatus.ok && requestedStart > 0) {
          final chunkStart = upstreamOffset;
          final chunkEnd = upstreamOffset + chunk.length;
          final wantEnd = requestedEndInclusive != null ? (requestedEndInclusive + 1) : chunkEnd;
          if (chunkEnd > requestedStart && chunkStart < wantEnd) {
            final s = max(0, requestedStart - chunkStart);
            final e = min(chunk.length, wantEnd - chunkStart);
            emitOutChunk(chunk.sublist(s, e));
          }
          upstreamOffset = chunkEnd;
          if (requestedEndInclusive != null && upstreamOffset > requestedEndInclusive) {
            break;
          }
        } else {
          emitOutChunk(chunk);
        }
      }

      if (segRaf != null) {
        await segRaf.flush();
        await segRaf.close();
        segRaf = null;
      }
      if (lockedSegPath != null) {
        _lockedSegmentPaths.remove(lockedSegPath);
        lockedSegPath = null;
      }
      if (wroteBytes) {
        await _tryPromoteAndEvict(cacheDir: cacheDir, cacheKey: source.cacheKey);
        promoted = true;
      }
      if (heldFinalChunk != null) {
        response.add(heldFinalChunk!);
      }
      await response.close();
    } finally {
      try {
        await segRaf?.flush();
        await segRaf?.close();
      } catch (_) {}
      if (lockedSegPath != null) {
        _lockedSegmentPaths.remove(lockedSegPath);
      }
      client.close(force: true);
      if (wroteBytes && !promoted) {
        await _tryPromoteAndEvict(cacheDir: cacheDir, cacheKey: source.cacheKey);
      }
    }
  }

  Future<_GapFetchResult> _fetchGapFromUpstream({
    required HttpResponse response,
    required Directory partDir,
    required _RegisteredSource source,
    required int gapStart,
    required int gapEndExclusive,
    required bool canWriteToDisk,
    required bool holdFinalChunk,
  }) async {
    final uri = Uri.parse(source.url);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    String? lockedSegPath;
    RandomAccessFile? segRaf;
    var forwarded = 0;
    List<int>? heldFinalChunk;
    final targetSpan = gapEndExclusive - gapStart;

    void emitSlice(List<int> slice) {
      if (slice.isEmpty) return;
      if (holdFinalChunk && forwarded + slice.length >= targetSpan) {
        if (heldFinalChunk == null) {
          heldFinalChunk = slice;
        } else {
          heldFinalChunk = <int>[...heldFinalChunk!, ...slice];
        }
      } else {
        response.add(slice);
      }
      forwarded += slice.length;
    }

    try {
      final upReq = await client.getUrl(uri);
      _applyRequestHeaders(upReq, source.headers);
      upReq.headers.set(HttpHeaders.rangeHeader, 'bytes=$gapStart-${gapEndExclusive - 1}');
      final upRes = await upReq.close().timeout(const Duration(seconds: 20));

      if (upRes.statusCode == HttpStatus.partialContent) {
        if (canWriteToDisk) {
          segRaf = await _openWritableSegment(partDir, gapStart, (p) => lockedSegPath = p);
        }
        await for (final chunk in upRes) {
          final remaining = targetSpan - forwarded;
          if (remaining <= 0) break;
          final slice = chunk.length <= remaining ? chunk : chunk.sublist(0, remaining);
          if (segRaf != null) {
            await segRaf.writeFrom(slice);
          }
          emitSlice(slice);
          if (forwarded >= targetSpan) {
            break;
          }
        }
        if (heldFinalChunk == null) {
          await response.flush();
        }
        return _GapFetchResult(forwarded: forwarded, heldFinalChunk: heldFinalChunk);
      }

      if (upRes.statusCode == HttpStatus.ok) {
        // Upstream server ignored Range and started from 0.
        if (canWriteToDisk && gapStart == 0) {
          segRaf = await _openWritableSegment(partDir, 0, (p) => lockedSegPath = p);
        }
        var streamPos = 0;
        await for (final chunk in upRes) {
          final chunkStart = streamPos;
          final chunkEnd = streamPos + chunk.length;
          streamPos = chunkEnd;

          if (segRaf != null) {
            await segRaf.writeFrom(chunk);
          }
          if (chunkEnd <= gapStart) continue;
          if (chunkStart >= gapEndExclusive) break;

          final s = max(0, gapStart - chunkStart);
          final e = min(chunk.length, gapEndExclusive - chunkStart);
          final slice = (s == 0 && e == chunk.length) ? chunk : chunk.sublist(s, e);
          emitSlice(slice);
          if (streamPos >= gapEndExclusive && segRaf == null) {
            break;
          }
        }
        if (heldFinalChunk == null) {
          await response.flush();
        }
        return _GapFetchResult(forwarded: forwarded, heldFinalChunk: heldFinalChunk);
      }

      await upRes.drain<void>();
      return const _GapFetchResult(forwarded: 0);
    } finally {
      try {
        await segRaf?.flush();
        await segRaf?.close();
      } catch (_) {}
      if (lockedSegPath != null) {
        _lockedSegmentPaths.remove(lockedSegPath);
      }
      client.close(force: true);
    }
  }

  Future<_EntryMetadata?> _probeUpstreamMetadata({
    required Directory partDir,
    required _RegisteredSource source,
  }) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      // Use GET with `Range: bytes=0-0` instead of `HEAD` so S3/OSS presigned GET URLs never 403.
      final req = await client.getUrl(uri);
      _applyRequestHeaders(req, source.headers);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != HttpStatus.partialContent && res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }
      final meta = _extractMetadataFromResponse(res, url: source.url);
      if (res.statusCode == HttpStatus.partialContent) {
        final firstByte = await res.expand((c) => c).toList();
        if (firstByte.isNotEmpty &&
            meta.totalLength > 0 &&
            meta.totalLength <= _config.maxSingleFileBytes) {
          final existing = await _listSegments(partDir);
          if (existing.every((s) => s.start > 0)) {
            String? locked;
            final raf = await _openWritableSegment(partDir, 0, (p) => locked = p);
            if (raf != null) {
              try {
                await raf.writeFrom(firstByte);
                await raf.flush();
              } finally {
                await raf.close();
                if (locked != null) _lockedSegmentPaths.remove(locked!);
              }
            }
          }
        }
      }
      if (meta.totalLength > 0) {
        await _writeMetadata(partDir, meta);
      }
      return meta;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _proxyPassThroughWithoutCache({
    required HttpRequest request,
    required _RegisteredSource source,
  }) async {
    final response = request.response;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final upReq = await client.openUrl(request.method, Uri.parse(source.url));
      _applyRequestHeaders(upReq, source.headers);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upReq.headers.set(HttpHeaders.rangeHeader, range);
      }
      final upRes = await upReq.close().timeout(const Duration(seconds: 20));
      response.statusCode = upRes.statusCode;
      final ct = upRes.headers.value(HttpHeaders.contentTypeHeader);
      if (ct != null) response.headers.set(HttpHeaders.contentTypeHeader, ct);
      final cr = upRes.headers.value(HttpHeaders.contentRangeHeader);
      if (cr != null) response.headers.set(HttpHeaders.contentRangeHeader, cr);
      if (upRes.contentLength >= 0) response.contentLength = upRes.contentLength;
      if (request.method != 'HEAD') {
        await response.addStream(upRes);
      }
      await response.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<RandomAccessFile?> _openWritableSegment(
    Directory partDir,
    int targetOffset,
    void Function(String lockedPath) onLocked,
  ) async {
    await partDir.create(recursive: true);
    final segments = await _listSegments(partDir);

    // 1. Check if an unlocked existing segment ends right at `targetOffset` -> append seamlessly!
    for (final seg in segments) {
      if (seg.end == targetOffset && !_lockedSegmentPaths.contains(seg.file.path)) {
        _lockedSegmentPaths.add(seg.file.path);
        onLocked(seg.file.path);
        return seg.file.open(mode: FileMode.writeOnlyAppend);
      }
    }

    // 2. Otherwise create a new segment starting at `targetOffset` if not already present/locked.
    final segFile = File('${partDir.path}/$targetOffset.seg');
    if (await segFile.exists() || _lockedSegmentPaths.contains(segFile.path)) {
      return null;
    }
    _lockedSegmentPaths.add(segFile.path);
    onLocked(segFile.path);
    return segFile.open(mode: FileMode.writeOnlyAppend);
  }

  Future<void> _tryPromoteAndEvict({required String cacheDir, required String cacheKey}) async {
    await _withKeyLock(cacheKey, () async {
      if (_hasActiveWriterForKey(cacheDir, cacheKey)) return;

      final partDir = Directory('$cacheDir/$cacheKey.part');
      if (!await partDir.exists()) return;

      if (await findCompleteFileInDir(cacheDir, cacheKey) != null) {
        try {
          await partDir.delete(recursive: true);
        } catch (_) {}
        return;
      }

      final meta = await _readMetadata(partDir);
      if (meta == null || meta.totalLength <= 0) return;

      final segments = await _listSegments(partDir);
      if (segments.isEmpty) return;

      final intervals = segments.map((s) => s.interval).toList();
      if (!ByteInterval.coversRange(intervals, 0, meta.totalLength)) {
        await evictIfNeeded();
        return;
      }

      final targetPath = '$cacheDir/$cacheKey${meta.ext}';

      // O(1) zero-copy fast path: single contiguous `0.seg` of exact `totalLength`.
      if (segments.length == 1 &&
          segments.first.start == 0 &&
          segments.first.length == meta.totalLength) {
        await segments.first.file.rename(targetPath);
        try {
          await partDir.delete(recursive: true);
        } catch (_) {}
        await evictIfNeeded();
        return;
      }

      // Multi-segment / overlapping assembly into `.tmp` + atomic rename.
      final tmpFile = File('$targetPath.tmp.${DateTime.now().microsecondsSinceEpoch}');
      final sink = tmpFile.openWrite(mode: FileMode.writeOnly);
      try {
        var offset = 0;
        while (offset < meta.totalLength) {
          _DiskSegment? best;
          for (final seg in segments) {
            if (seg.start <= offset && seg.end > offset) {
              if (best == null || seg.end > best.end) {
                best = seg;
              }
            }
          }
          if (best == null) {
            throw StateError('Segment gap during promotion at offset $offset');
          }
          final copyEnd = min(meta.totalLength, best.end);
          await sink.addStream(best.file.openRead(offset - best.start, copyEnd - best.start));
          offset = copyEnd;
        }
        await sink.flush();
        await sink.close();
        await tmpFile.rename(targetPath);
        try {
          await partDir.delete(recursive: true);
        } catch (_) {}
      } catch (_) {
        try {
          await sink.close();
        } catch (_) {}
        try {
          if (await tmpFile.exists()) {
            await tmpFile.delete();
          }
        } catch (_) {}
      }
      await evictIfNeeded();
    });
  }

  bool _hasActiveWriterForKey(String cacheDir, String cacheKey) {
    final prefix = '$cacheDir/$cacheKey.part/';
    for (final locked in _lockedSegmentPaths) {
      if (locked.startsWith(prefix)) return true;
    }
    return false;
  }

  Future<void> _withKeyLock(String key, Future<void> Function() action) async {
    final previous = _keyLocks[key];
    final completer = Completer<void>();
    _keyLocks[key] = completer.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    try {
      await action();
    } finally {
      if (identical(_keyLocks[key], completer.future)) {
        _keyLocks.remove(key);
      }
      completer.complete();
    }
  }

  static Future<List<_DiskSegment>> _listSegments(Directory partDir) async {
    if (!await partDir.exists()) return const <_DiskSegment>[];
    final result = <_DiskSegment>[];
    await for (final entity in partDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      if (!name.endsWith('.seg')) continue;
      final start = int.tryParse(name.substring(0, name.length - '.seg'.length));
      if (start == null || start < 0) continue;
      try {
        final len = await entity.length();
        if (len > 0) {
          result.add(_DiskSegment(start: start, length: len, file: entity));
        }
      } catch (_) {}
    }
    result.sort((a, b) {
      final cmp = a.start.compareTo(b.start);
      return cmp != 0 ? cmp : b.length.compareTo(a.length);
    });
    return result;
  }

  static Future<_EntryMetadata?> _readMetadata(Directory partDir) async {
    final file = File('${partDir.path}/meta.json');
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return _EntryMetadata.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _writeMetadata(Directory partDir, _EntryMetadata meta) async {
    await partDir.create(recursive: true);
    final targetPath = '${partDir.path}/meta.json';
    final tmp = File('$targetPath.tmp.${DateTime.now().microsecondsSinceEpoch}');
    try {
      await tmp.writeAsString(jsonEncode(meta.toJson()), flush: true);
      await tmp.rename(targetPath);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  static _EntryMetadata _extractMetadataFromResponse(
    HttpClientResponse res, {
    required String url,
    _EntryMetadata? fallback,
  }) {
    var totalLength = fallback?.totalLength ?? -1;
    final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      // e.g. `bytes 0-1023/987654`
      final slash = contentRange.lastIndexOf('/');
      if (slash >= 0 && slash < contentRange.length - 1) {
        final parsedTotal = int.tryParse(contentRange.substring(slash + 1).trim());
        if (parsedTotal != null && parsedTotal > 0) {
          totalLength = parsedTotal;
        }
      }
    }
    if (totalLength <= 0 && res.statusCode == HttpStatus.ok && res.contentLength > 0) {
      totalLength = res.contentLength;
    }

    final rawCt = res.headers.value(HttpHeaders.contentTypeHeader);
    final contentType = (rawCt != null && rawCt.isNotEmpty)
        ? rawCt.split(';').first.trim()
        : (fallback?.contentType ?? 'video/mp4');
    final ext = VideoCacheKeyUtils.inferExtension(url, contentType: contentType);

    return _EntryMetadata(
      url: url,
      totalLength: totalLength,
      contentType: contentType,
      ext: ext,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static void _applyRequestHeaders(HttpClientRequest req, Map<String, String>? headers) {
    var hasUserAgent = false;
    if (headers != null) {
      headers.forEach((k, v) {
        if (k.toLowerCase() == 'user-agent') {
          hasUserAgent = true;
        }
        req.headers.set(k, v);
      });
    }
    if (!hasUserAgent) {
      req.headers.set(HttpHeaders.userAgentHeader, _kDefaultUserAgent);
    }
  }

  static _RangeParseResult? _parseRangeHeader(String? rangeHeader, int totalLength) {
    if (rangeHeader == null || !rangeHeader.startsWith('bytes=')) {
      return null;
    }
    final spec = rangeHeader.substring('bytes='.length).split(',').first.trim();
    final parts = spec.split('-');
    if (parts.length != 2) return null;

    int? start = parts[0].isEmpty ? null : int.tryParse(parts[0]);
    int? end = parts[1].isEmpty ? null : int.tryParse(parts[1]);

    if (start == null && end != null) {
      if (end <= 0) return _RangeParseResult.unsatisfiable;
      start = (totalLength - end).clamp(0, totalLength);
      end = totalLength - 1;
    } else if (start != null) {
      end = (end == null || end >= totalLength) ? (totalLength - 1) : end;
    } else {
      return null;
    }

    if (start < 0 || start >= totalLength || end < start) {
      return _RangeParseResult.unsatisfiable;
    }
    return _RangeParseResult(ByteInterval(start, end + 1));
  }

  static Future<int> _directoryByteSize(Directory dir) async {
    var sum = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            sum += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return sum;
  }

  static void _touchFileBestEffort(File file) {
    try {
      file.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  static String? _extractKeyFromEntryName(String name) {
    if (name.endsWith('.part')) {
      return name.substring(0, name.length - '.part'.length);
    }
    final dot = name.indexOf('.');
    if (dot > 0) {
      return name.substring(0, dot);
    }
    return null;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash >= 0 ? normalized.substring(slash + 1) : normalized;
  }

  static String _extensionOf(String path) {
    final name = _basename(path);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot).toLowerCase() : '.mp4';
  }

  static String _mimeFromExtension(String ext) {
    return switch (ext) {
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.mkv' => 'video/x-matroska',
      '.mp3' => 'audio/mpeg',
      '.m4a' => 'audio/mp4',
      '.aac' => 'audio/aac',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.flac' => 'audio/flac',
      _ => 'video/mp4',
    };
  }

  static String _randomHex(int length) {
    final rng = Random.secure();
    const chars = '0123456789abcdef';
    return List<String>.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

class _GapFetchResult {
  final int forwarded;
  final List<int>? heldFinalChunk;

  const _GapFetchResult({required this.forwarded, this.heldFinalChunk});
}

class _RangeParseResult {
  static const _RangeParseResult unsatisfiable = _RangeParseResult(null, isUnsatisfiable: true);

  final ByteInterval? interval;
  final bool isUnsatisfiable;

  const _RangeParseResult(this.interval, {this.isUnsatisfiable = false});
}
