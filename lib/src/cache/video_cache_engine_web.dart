import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as html;

import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import 'video_cache_types.dart';

class _WebCachedBlobEntry {
  final String blobUrl;
  final int byteLength;
  int lastTouchedMs;

  _WebCachedBlobEntry({
    required this.blobUrl,
    required this.byteLength,
    required this.lastTouchedMs,
  });
}

/// Web / WASM 缓存引擎：
/// - 常规渐进式大视频默认复用浏览器原生 HTTP 缓存；
/// - 显式调用 [precache] 的同源/允许 CORS 短视频缓存为内存 LRU `Blob` Object URL，
///   实现列表预热与二次零网络秒开，超限时自动调用 `URL.revokeObjectURL` 释放内存。
class PlatformVideoCacheEngine {
  VideoCacheConfig _config = const VideoCacheConfig();
  final Map<String, _WebCachedBlobEntry> _entries = <String, _WebCachedBlobEntry>{};
  final Map<String, html.AbortController> _inflightAbort = <String, html.AbortController>{};
  final Set<String> _pinnedKeys = <String>{};

  VideoCacheConfig get config => _config;

  Future<void> configure(VideoCacheConfig config) async {
    _config = config;
    if (!config.enabled || config.maxCacheBytes == 0) {
      await clearCache();
    } else {
      _evictIfNeeded();
    }
  }

  Future<ResolvedVideoCacheTarget> resolveForPlayback(NetworkVideoSource source) async {
    final enabled = (source.enableCache ?? _config.enabled) && _config.maxCacheBytes > 0;
    final key = VideoCacheKeyUtils.computeSha1Key(
      VideoCacheKeyUtils.resolveRawIdentity(source, _config),
    );
    if (enabled) {
      final hit = _entries[key];
      if (hit != null) {
        hit.lastTouchedMs = DateTime.now().millisecondsSinceEpoch;
        return ResolvedVideoCacheTarget(
          playUrl: hit.blobUrl,
          castUrl: source.url,
          cacheKey: key,
          headers: source.headers,
          enableCache: true,
          isCompleteFileHit: true,
        );
      }
    }
    return ResolvedVideoCacheTarget(
      playUrl: source.url,
      castUrl: source.url,
      cacheKey: key,
      headers: source.headers,
      enableCache: enabled,
    );
  }

  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) {
    return resolveForPlayback(source);
  }

  void pin(String cacheKey) {
    _pinnedKeys.add(cacheKey);
  }

  void unpin(String cacheKey) {
    _pinnedKeys.remove(cacheKey);
  }

  Future<void> precache(NetworkVideoSource source, {int? preloadBytes}) async {
    final enabled = (source.enableCache ?? _config.enabled) && _config.maxCacheBytes > 0;
    if (!enabled || VideoCacheKeyUtils.isStreamingManifestUrl(source.url)) return;

    final key = VideoCacheKeyUtils.computeSha1Key(
      VideoCacheKeyUtils.resolveRawIdentity(source, _config),
    );
    if (_entries.containsKey(key) || _inflightAbort.containsKey(key)) return;

    final abortController = html.AbortController();
    _inflightAbort[key] = abortController;
    try {
      final headersInit = html.Headers();
      source.headers?.forEach((k, v) {
        try {
          headersInit.append(k, v);
        } catch (_) {}
      });
      final init = html.RequestInit(signal: abortController.signal, headers: headersInit);
      final response = await html.window.fetch(source.url.toJS, init).toDart;
      if (!response.ok) return;

      final contentType = response.headers.get('content-type') ?? 'video/mp4';
      final buffer = await response.arrayBuffer().toDart;
      final Uint8List bytes = buffer.toDart.asUint8List();
      if (bytes.isEmpty || bytes.length > _config.maxSingleFileBytes) return;

      final blob = html.Blob(<JSAny>[bytes.toJS].toJS, html.BlobPropertyBag(type: contentType));
      final blobUrl = html.URL.createObjectURL(blob);
      _entries[key] = _WebCachedBlobEntry(
        blobUrl: blobUrl,
        byteLength: bytes.length,
        lastTouchedMs: DateTime.now().millisecondsSinceEpoch,
      );
      _evictIfNeeded();
    } catch (_) {
      // Quiet fallback when CORS or AbortController cancels fetch.
    } finally {
      _inflightAbort.remove(key);
    }
  }

  Future<void> cancelPrecache(NetworkVideoSource source) async {
    final key = VideoCacheKeyUtils.computeSha1Key(
      VideoCacheKeyUtils.resolveRawIdentity(source, _config),
    );
    final controller = _inflightAbort.remove(key);
    try {
      controller?.abort();
    } catch (_) {}
  }

  Future<bool> isCached(NetworkVideoSource source) async {
    final key = VideoCacheKeyUtils.computeSha1Key(
      VideoCacheKeyUtils.resolveRawIdentity(source, _config),
    );
    return _entries.containsKey(key);
  }

  Future<int> getCacheSize() async {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.byteLength;
    }
    return total;
  }

  Future<void> removeCache(NetworkVideoSource source) async {
    await cancelPrecache(source);
    final key = VideoCacheKeyUtils.computeSha1Key(
      VideoCacheKeyUtils.resolveRawIdentity(source, _config),
    );
    final removed = _entries.remove(key);
    if (removed != null) {
      try {
        html.URL.revokeObjectURL(removed.blobUrl);
      } catch (_) {}
    }
  }

  Future<void> clearCache() async {
    for (final controller in _inflightAbort.values) {
      try {
        controller.abort();
      } catch (_) {}
    }
    _inflightAbort.clear();
    for (final entry in _entries.values) {
      try {
        html.URL.revokeObjectURL(entry.blobUrl);
      } catch (_) {}
    }
    _entries.clear();
  }

  Future<void> dispose() async {
    await clearCache();
  }

  void _evictIfNeeded() {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.byteLength;
    }
    if (total <= _config.maxCacheBytes) return;

    final candidates = _entries.entries.where((e) => !_pinnedKeys.contains(e.key)).toList()
      ..sort((a, b) => a.value.lastTouchedMs.compareTo(b.value.lastTouchedMs));

    for (final item in candidates) {
      if (total <= _config.maxCacheBytes) break;
      _entries.remove(item.key);
      total -= item.value.byteLength;
      try {
        html.URL.revokeObjectURL(item.value.blobUrl);
      } catch (_) {}
    }
  }
}
