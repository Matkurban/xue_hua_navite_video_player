import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/bridge_env.dart';
import '../bridge/video_player_host_bridge.dart';
import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import '../pigeon/player_api.g.dart';
import '../utils/temp_paths.dart';
import 'local_video_cache_server_io.dart';
import 'video_cache_types.dart';

/// 原生 IO 平台缓存引擎统一调度器：
/// - **Android**：同步配置并委托给 Media3 `SimpleCache` (`AndroidMediaCacheManager`)；
/// - **iOS / macOS**：完整文件直通 `file://` 快路径，未完成流委托给 Swift `AVAssetResourceLoaderDelegate`；
/// - **Windows / Linux**：完整文件直通 `file://` 快路径，未完成流使用 Dart [LocalVideoCacheEngine] 回环 Range 代理。
///
/// Unified native IO cache engine dispatcher routing Android to Media3
/// `SimpleCache`, Apple platforms to `AVAssetResourceLoaderDelegate`, and
/// Windows/Linux to the Dart [LocalVideoCacheEngine] loopback Range proxy.
class PlatformVideoCacheEngine {
  /// 创建原生 IO 缓存引擎，可选注入自定义桥接实例（便于测试）。
  ///
  /// Creates an IO [PlatformVideoCacheEngine] with an optional custom bridge.
  PlatformVideoCacheEngine({this._bridge});

  final VideoPlayerHostBridge? _bridge;
  final LocalVideoCacheEngine _localEngine = LocalVideoCacheEngine();
  bool _nativeConfigSynced = false;

  VideoPlayerHostBridge get _resolvedBridge => _bridge ?? VideoPlayerHostBridge.instance;

  /// 暴露内部纯 Dart 稀疏分片缓存引擎（便于桌面端与单元测试直接校验）。
  ///
  /// Exposes the internal Dart sparse-segment [LocalVideoCacheEngine] for testing.
  @visibleForTesting
  LocalVideoCacheEngine get localEngine => _localEngine;

  /// 当前生效的全局缓存配置。
  ///
  /// Currently active [VideoCacheConfig].
  VideoCacheConfig get config => _localEngine.config;

  bool get _usesDesktopDartProxy {
    final p = defaultTargetPlatform;
    return p == TargetPlatform.windows || p == TargetPlatform.linux || p == TargetPlatform.fuchsia;
  }

  bool get _usesAndroidMedia3Cache => defaultTargetPlatform == TargetPlatform.android;

  bool get _usesAppleResourceLoader {
    final p = defaultTargetPlatform;
    return p == TargetPlatform.iOS || p == TargetPlatform.macOS;
  }

  bool _isMissingNativeBinding(Object error) {
    return error is MissingPluginException || (isFlutterTestEnvironment && _bridge == null);
  }

  /// 更新缓存策略配置 [config]，并在移动端/macOS 上同步下发至原生缓存层。
  ///
  /// Updates [config] locally and synchronizes it to the native bridge on mobile/macOS.
  Future<void> configure(VideoCacheConfig config) async {
    _nativeConfigSynced = false;
    await _localEngine.configure(config);
    if (!_usesDesktopDartProxy) {
      await _syncConfigToNative();
    }
  }

  Future<void> _ensureNativeConfigured() async {
    if (_usesDesktopDartProxy || _nativeConfigSynced) return;
    await _syncConfigToNative();
  }

  Future<void> _syncConfigToNative() async {
    final cacheDir = await _localEngine.resolveCacheDir();
    try {
      await _resolvedBridge.configureCache(
        CacheConfigRequest(
          enabled: config.enabled,
          maxCacheBytes: config.maxCacheBytes,
          maxSingleFileBytes: config.maxSingleFileBytes,
          cacheDir: cacheDir,
        ),
      );
      _nativeConfigSynced = true;
    } on PlatformException {
      // Safe fallback if platform does not implement native cache governance.
    } catch (error) {
      if (!_isMissingNativeBinding(error)) {
        rethrow;
      }
    }
  }

  /// 按当前平台策略为 [source] 解析播放目标（含完整文件直通、原生分片流或回环代理）。
  ///
  /// Resolves [source] into a [ResolvedVideoCacheTarget] according to the active platform strategy.
  Future<ResolvedVideoCacheTarget> resolveForPlayback(NetworkVideoSource source) async {
    if (_usesDesktopDartProxy) {
      return _localEngine.resolveForPlayback(source);
    }

    await _ensureNativeConfigured();
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await _localEngine.resolveCacheDir();

    if (_usesAppleResourceLoader) {
      final enabled =
          (source.enableCache ?? config.enabled) &&
          config.maxCacheBytes > 0 &&
          config.maxSingleFileBytes > 0 &&
          !VideoCacheKeyUtils.isStreamingManifestUrl(source.url);

      if (enabled) {
        final complete = await LocalVideoCacheEngine.findCompleteFileInDir(cacheDir, cacheKey);
        if (complete != null) {
          try {
            complete.setLastModifiedSync(DateTime.now());
          } catch (_) {}
          return ResolvedVideoCacheTarget(
            playUrl: Uri.file(complete.path).toString(),
            castUrl: source.url,
            cacheKey: cacheKey,
            headers: source.headers,
            enableCache: true,
            isCompleteFileHit: true,
          );
        }
      }

      return ResolvedVideoCacheTarget(
        playUrl: source.url,
        castUrl: source.url,
        cacheKey: cacheKey,
        headers: source.headers,
        enableCache: enabled,
      );
    }

    // Android (Media3 SimpleCache natively supports progressive MP4/MOV/MP3 + HLS/DASH).
    final enabled =
        (source.enableCache ?? config.enabled) &&
        config.maxCacheBytes > 0 &&
        config.maxSingleFileBytes > 0;
    var isCompleteHit = false;
    if (enabled) {
      try {
        isCompleteHit = await _resolvedBridge.isCached(
          CacheEntryRequest(url: source.url, cacheKey: cacheKey, cacheDir: cacheDir),
        );
      } catch (_) {}
    }

    return ResolvedVideoCacheTarget(
      playUrl: source.url,
      castUrl: source.url,
      cacheKey: cacheKey,
      headers: source.headers,
      enableCache: enabled,
      isCompleteFileHit: isCompleteHit,
    );
  }

  /// 为媒体探测（时长/封面抽帧）解析 [source] 的缓存目标。
  ///
  /// Resolves a [ResolvedVideoCacheTarget] for media probing (duration/cover extraction).
  Future<ResolvedVideoCacheTarget> resolveForProbe(NetworkVideoSource source) async {
    if (_usesDesktopDartProxy) {
      return _localEngine.resolveForProbe(source);
    }
    await _ensureNativeConfigured();
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await _localEngine.resolveCacheDir();

    if (_usesAppleResourceLoader) {
      final complete = await LocalVideoCacheEngine.findCompleteFileInDir(cacheDir, cacheKey);
      if (complete != null) {
        return ResolvedVideoCacheTarget(
          playUrl: Uri.file(complete.path).toString(),
          castUrl: source.url,
          cacheKey: cacheKey,
          headers: source.headers,
          enableCache: true,
          isCompleteFileHit: true,
        );
      }
    }

    return ResolvedVideoCacheTarget(
      playUrl: source.url,
      castUrl: source.url,
      cacheKey: cacheKey,
      headers: source.headers,
      enableCache: (source.enableCache ?? config.enabled) && config.maxCacheBytes > 0,
    );
  }

  /// 固定 [cacheKey] 防止活跃播放期间被 LRU 淘汰。
  ///
  /// Pins [cacheKey] in both Dart and native cache layers to prevent eviction.
  void pin(String cacheKey) {
    _localEngine.pin(cacheKey);
    if (!_usesDesktopDartProxy) {
      _ignoreBestEffort(() => _resolvedBridge.pinCacheKey(cacheKey));
    }
  }

  /// 解除 [cacheKey] 的 LRU 淘汰保护。
  ///
  /// Unpins [cacheKey] in both Dart and native cache layers.
  void unpin(String cacheKey) {
    _localEngine.unpin(cacheKey);
    if (!_usesDesktopDartProxy) {
      _ignoreBestEffort(() => _resolvedBridge.unpinCacheKey(cacheKey));
    }
  }

  /// 后台预加载网络媒体 [source]，可选通过 [preloadBytes] 限制首包预热字节数。
  ///
  /// Precaches [source] up to [preloadBytes] (or full file when `null`).
  Future<void> precache(NetworkVideoSource source, {int? preloadBytes}) async {
    final enabled =
        (source.enableCache ?? config.enabled) &&
        config.maxCacheBytes > 0 &&
        config.maxSingleFileBytes > 0;
    if (!enabled) return;

    if (_usesDesktopDartProxy) {
      await _localEngine.precache(source, preloadBytes: preloadBytes);
      return;
    }

    await _ensureNativeConfigured();
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await _localEngine.resolveCacheDir();
    try {
      await _resolvedBridge.precache(
        PrecacheRequest(
          url: source.url,
          cacheKey: cacheKey,
          cacheDir: cacheDir,
          headers: source.headers,
          preloadBytes: preloadBytes,
          maxSingleFileBytes: config.maxSingleFileBytes,
          maxCacheBytes: config.maxCacheBytes,
        ),
      );
    } on PlatformException {
      // Quietly ignore background precache failures.
    } catch (error) {
      if (_isMissingNativeBinding(error)) {
        await _localEngine.precache(source, preloadBytes: preloadBytes);
      } else {
        rethrow;
      }
    }
  }

  /// 取消正在针对 [source] 执行的后台预加载任务。
  ///
  /// Cancels an active background precache task for [source].
  Future<void> cancelPrecache(NetworkVideoSource source) async {
    if (_usesDesktopDartProxy) {
      await _localEngine.cancelPrecache(source);
      return;
    }
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    try {
      await _resolvedBridge.cancelPrecache(cacheKey);
    } on PlatformException {
      // Ignore.
    } catch (error) {
      if (_isMissingNativeBinding(error)) {
        await _localEngine.cancelPrecache(source);
      } else {
        rethrow;
      }
    }
  }

  /// 查询 [source] 是否已完成本地完整缓存（同时检查网络实况照片缓存目录）。
  ///
  /// Returns `true` if [source] is completely cached locally (including network Live Photo cache).
  Future<bool> isCached(NetworkVideoSource source) async {
    if (await _hasCachedNetworkLivePhoto(source)) {
      return true;
    }
    if (_usesDesktopDartProxy) {
      return _localEngine.isCached(source);
    }

    await _ensureNativeConfigured();
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await _localEngine.resolveCacheDir();

    if (_usesAppleResourceLoader) {
      final complete = await LocalVideoCacheEngine.findCompleteFileInDir(cacheDir, cacheKey);
      if (complete != null) return true;
    }

    try {
      return await _resolvedBridge.isCached(
        CacheEntryRequest(url: source.url, cacheKey: cacheKey, cacheDir: cacheDir),
      );
    } on PlatformException {
      return false;
    } catch (error) {
      if (_isMissingNativeBinding(error)) {
        return _localEngine.isCached(source);
      }
      rethrow;
    }
  }

  /// 统计当前磁盘缓存总字节数（包含网络实况照片缓存体积）。
  ///
  /// Returns total cached disk usage in bytes, including cached network Live Photos.
  Future<int> getCacheSize() async {
    final livePhotoBytes = await _getNetworkLivePhotoCacheSize();
    if (_usesDesktopDartProxy) {
      return (await _localEngine.getCacheSize()) + livePhotoBytes;
    }

    await _ensureNativeConfigured();
    final cacheDir = await _localEngine.resolveCacheDir();
    try {
      final nativeSize = await _resolvedBridge.getCacheSize(cacheDir);
      return nativeSize + livePhotoBytes;
    } on PlatformException {
      // Fallback to directory scan on Apple if bridge failed.
      if (!_usesAndroidMedia3Cache) {
        return (await _localEngine.getCacheSize()) + livePhotoBytes;
      }
    } catch (error) {
      if (_isMissingNativeBinding(error)) {
        return (await _localEngine.getCacheSize()) + livePhotoBytes;
      }
      rethrow;
    }
    return livePhotoBytes;
  }

  /// 删除 [source] 对应的本地缓存条目（含关联的网络实况照片缓存）。
  ///
  /// Deletes cached entries for [source], including any network Live Photo artifacts.
  Future<void> removeCache(NetworkVideoSource source) async {
    await cancelPrecache(source);
    await _removeCachedNetworkLivePhoto(source);

    if (_usesDesktopDartProxy) {
      await _localEngine.removeCache(source);
      return;
    }

    await _ensureNativeConfigured();
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    final cacheDir = await _localEngine.resolveCacheDir();
    try {
      await _resolvedBridge.removeCache(
        CacheEntryRequest(url: source.url, cacheKey: cacheKey, cacheDir: cacheDir),
      );
    } on PlatformException {
      if (!_usesAndroidMedia3Cache) {
        await _localEngine.removeCache(source);
      }
    } catch (error) {
      if (_isMissingNativeBinding(error)) {
        await _localEngine.removeCache(source);
      } else {
        rethrow;
      }
    }
  }

  /// 清空所有非活跃的网络视频与网络实况照片磁盘缓存。
  ///
  /// Clears all non-pinned cached network video and Live Photo files from disk.
  Future<void> clearCache() async {
    await _clearNetworkLivePhotoCache();
    if (_usesDesktopDartProxy) {
      await _localEngine.clearCache();
      return;
    }

    await _ensureNativeConfigured();
    final cacheDir = await _localEngine.resolveCacheDir();
    try {
      await _resolvedBridge.clearCache(cacheDir);
    } on PlatformException {
      if (!_usesAndroidMedia3Cache) {
        await _localEngine.clearCache();
      }
    } catch (error) {
      if (_isMissingNativeBinding(error)) {
        await _localEngine.clearCache();
      } else {
        rethrow;
      }
    }
  }

  /// 释放本地回环代理服务与底层缓存引擎资源。
  ///
  /// Disposes the underlying local cache engine and loopback proxy server.
  Future<void> dispose() async {
    await _localEngine.dispose();
  }

  void _ignoreBestEffort(Future<void> Function() action) {
    try {
      unawaited(action().then((_) {}, onError: (_) {}));
    } catch (_) {}
  }

  String _networkLivePhotoHash(NetworkVideoSource source) {
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    return 'net-${sha1.convert(utf8.encode('net://$rawId'))}';
  }

  Future<bool> _hasCachedNetworkLivePhoto(NetworkVideoSource source) async {
    try {
      final dirPath = await pluginLivePhotoDir();
      final prefix = _networkLivePhotoHash(source);
      final metaFile = File('$dirPath/$prefix-meta.json');
      return await metaFile.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _removeCachedNetworkLivePhoto(NetworkVideoSource source) async {
    try {
      final dir = Directory(await pluginLivePhotoDir());
      if (!await dir.exists()) return;
      final prefix = _networkLivePhotoHash(source);
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
        if (name.startsWith('$prefix-')) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<int> _getNetworkLivePhotoCacheSize() async {
    var total = 0;
    try {
      final dir = Directory(await pluginLivePhotoDir());
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
        if (name.startsWith('net-')) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _clearNetworkLivePhotoCache() async {
    try {
      final dir = Directory(await pluginLivePhotoDir());
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
        if (name.startsWith('net-')) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
