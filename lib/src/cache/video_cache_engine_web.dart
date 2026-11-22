import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as html;

import '../bridge/video_player_host_bridge.dart';
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

/// Web / WASM 平台缓存引擎：
/// - 常规渐进式大视频默认复用浏览器原生 HTTP 缓存；
/// - 显式调用 [precache] 的同源或允许 CORS 短视频会缓存为内存 LRU `Blob` Object URL，
///   实现列表预热与二次零网络秒开，超限时自动调用 `URL.revokeObjectURL` 释放内存。
///
/// Web / WASM cache engine. Progressive videos rely on the browser's HTTP cache
/// by default, while explicitly precached CORS-accessible videos are stored as
/// in-memory LRU `Blob` Object URLs and revoked automatically on eviction.
class PlatformVideoCacheEngine {
  /// 创建 Web 平台缓存引擎实例。
  ///
  /// Creates a Web [PlatformVideoCacheEngine] instance.
  PlatformVideoCacheEngine({VideoPlayerHostBridge? bridge});

  VideoCacheConfig _config = const VideoCacheConfig();
  final Map<String, _WebCachedBlobEntry> _entries = <String, _WebCachedBlobEntry>{};
  final Map<String, html.AbortController> _inflightAbort = <String, html.AbortController>{};
  final Set<String> _pinnedKeys = <String>{};

  /// 当前生效的缓存配置。
  ///
  /// Currently active [VideoCacheConfig].
  VideoCacheConfig get config => _config;

  /// 更新缓存配置 [config]，并在关闭缓存或容量缩小时触发清理或 LRU 淘汰。
  ///
  /// Applies [config], clearing entries if disabled or evicting excess blobs.
  Future<void> configure(VideoCacheConfig config) async {
    _config = config;
    if (!config.enabled || config.maxCacheBytes == 0) {
      await clearCache();
    } else {
      _evictIfNeeded();
    }
  }

  /// 为播放会话解析缓存目标：若命中内存 `Blob` 缓存则返回 `blob:` 地址并刷新 LRU 时间戳。
  ///
  /// Resolves [source] to a cached `blob:` URL when available, otherwise falls
  /// back to the original network URL while preserving `castUrl`.
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

  /// 为媒体探测解析目标（委托至 [resolveForPlayback]）。
  ///
  /// Resolves a probe target via [resolveForPlayback].
  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) {
    return resolveForPlayback(source);
  }

  /// 固定 [cacheKey]，防止正在播放的 `Blob` 被 LRU 淘汰释放。
  ///
  /// Pins [cacheKey] to protect its `Blob` Object URL from LRU eviction.
  void pin(String cacheKey) {
    _pinnedKeys.add(cacheKey);
  }

  /// 解除 [cacheKey] 的淘汰保护。
  ///
  /// Unpins [cacheKey], making it eligible for LRU eviction again.
  void unpin(String cacheKey) {
    _pinnedKeys.remove(cacheKey);
  }

  /// 使用浏览器 `fetch` API 预下载 [source] 并生成 `Blob` Object URL 存入内存 LRU 缓存。
  ///
  /// 自动跳过自适应流媒体索引（`.m3u8`/`.mpd`）以及超过 `maxSingleFileBytes` 的大文件。
  ///
  /// Fetches [source] via `window.fetch` and stores it as a `Blob` Object URL
  /// in the in-memory LRU cache (skipping streaming manifests and oversized files).
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

  /// 通过 `AbortController` 中止正在进行的 [source] 预下载请求。
  ///
  /// Aborts an in-flight `fetch` precache request for [source], if any.
  Future<void> cancelPrecache(NetworkVideoSource source) async {
    final key = VideoCacheKeyUtils.computeSha1Key(
      VideoCacheKeyUtils.resolveRawIdentity(source, _config),
    );
    final controller = _inflightAbort.remove(key);
    try {
      controller?.abort();
    } catch (_) {}
  }

  /// 查询 [source] 是否已存在于内存 `Blob` 缓存中。
  ///
  /// Returns `true` if [source] has an active cached `Blob` entry.
  Future<bool> isCached(NetworkVideoSource source) async {
    final key = VideoCacheKeyUtils.computeSha1Key(
      VideoCacheKeyUtils.resolveRawIdentity(source, _config),
    );
    return _entries.containsKey(key);
  }

  /// 统计当前所有已缓存 `Blob` 占用的总字节数。
  ///
  /// Returns the sum of byte lengths of all cached `Blob` entries.
  Future<int> getCacheSize() async {
    var total = 0;
    for (final entry in _entries.values) {
      total += entry.byteLength;
    }
    return total;
  }

  /// 取消 [source] 的预下载（如有）并撤销释放对应的 `Blob` Object URL。
  ///
  /// Cancels any active precache and revokes the cached `Blob` URL for [source].
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

  /// 中止所有进行中的预下载任务并撤销全部 `Blob` Object URL。
  ///
  /// Aborts all in-flight precaches and revokes all cached `Blob` Object URLs.
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

  /// 释放 Web 缓存引擎并清理全部已分配的 `Blob` 资源。
  ///
  /// Disposes the engine by clearing all cached blobs and aborting fetches.
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
