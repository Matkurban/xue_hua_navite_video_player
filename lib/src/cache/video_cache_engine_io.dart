import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/video_source.dart';
import '../data/models/video_cache_config.dart';
import '../utils/temp_paths.dart';
import 'local_video_cache_server_io.dart';
import 'video_cache_types.dart';

/// 原生 IO 平台缓存引擎统一调度器：
/// - **Android**：同步配置并委托给 Media3 `SimpleCache` (`AndroidMediaCacheManager`)；
/// - **iOS / macOS**：完整文件直通 `file://` 快路径，未完成流委托给 Swift `AVAssetResourceLoaderDelegate`；
/// - **Windows / Linux**：完整文件直通 `file://` 快路径，未完成流使用 Dart `LocalVideoCacheEngine` 回环 Range 代理。
class PlatformVideoCacheEngine {
  static const MethodChannel _defaultChannel = MethodChannel('xue_hua_navite_video_player/player');

  final MethodChannel _channel;
  final LocalVideoCacheEngine _localEngine = LocalVideoCacheEngine();
  bool _nativeConfigSynced = false;

  PlatformVideoCacheEngine({MethodChannel? channel}) : _channel = channel ?? _defaultChannel;

  /// 暴露内部纯 Dart 稀疏分片缓存引擎（便于桌面端与单元测试直接校验）。
  @visibleForTesting
  LocalVideoCacheEngine get localEngine => _localEngine;

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
      await _channel.invokeMethod<void>(
        'configureCache',
        config.toChannelMap(resolvedCacheDir: cacheDir),
      );
      _nativeConfigSynced = true;
    } on MissingPluginException {
      // Safe no-op in Dart VM unit tests without native channel handler.
    } on PlatformException {
      // Safe fallback if platform does not implement native cache governance.
    }
  }

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
        final cached = await _channel.invokeMethod<bool>('isCached', <String, dynamic>{
          'url': source.url,
          'cacheKey': cacheKey,
          'cacheDir': cacheDir,
        });
        isCompleteHit = cached == true;
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

  void pin(String cacheKey) {
    _localEngine.pin(cacheKey);
    if (!_usesDesktopDartProxy) {
      _invokeBestEffort('pinCacheKey', <String, dynamic>{'cacheKey': cacheKey});
    }
  }

  void unpin(String cacheKey) {
    _localEngine.unpin(cacheKey);
    if (!_usesDesktopDartProxy) {
      _invokeBestEffort('unpinCacheKey', <String, dynamic>{'cacheKey': cacheKey});
    }
  }

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
      await _channel.invokeMethod<void>('precache', <String, dynamic>{
        'url': source.url,
        'cacheKey': cacheKey,
        'cacheDir': cacheDir,
        'headers': ?source.headers,
        'preloadBytes': ?preloadBytes,
        'maxSingleFileBytes': config.maxSingleFileBytes,
        'maxCacheBytes': config.maxCacheBytes,
      });
    } on MissingPluginException {
      await _localEngine.precache(source, preloadBytes: preloadBytes);
    } on PlatformException {
      // Quietly ignore background precache failures.
    }
  }

  Future<void> cancelPrecache(NetworkVideoSource source) async {
    if (_usesDesktopDartProxy) {
      await _localEngine.cancelPrecache(source);
      return;
    }
    final rawId = VideoCacheKeyUtils.resolveRawIdentity(source, config);
    final cacheKey = VideoCacheKeyUtils.computeSha1Key(rawId);
    try {
      await _channel.invokeMethod<void>('cancelPrecache', <String, dynamic>{'cacheKey': cacheKey});
    } on MissingPluginException {
      await _localEngine.cancelPrecache(source);
    } on PlatformException {
      // Ignore.
    }
  }

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
      final res = await _channel.invokeMethod<bool>('isCached', <String, dynamic>{
        'url': source.url,
        'cacheKey': cacheKey,
        'cacheDir': cacheDir,
      });
      if (res != null) return res;
    } on MissingPluginException {
      return _localEngine.isCached(source);
    } on PlatformException {
      return false;
    }
    return false;
  }

  Future<int> getCacheSize() async {
    final livePhotoBytes = await _getNetworkLivePhotoCacheSize();
    if (_usesDesktopDartProxy) {
      return (await _localEngine.getCacheSize()) + livePhotoBytes;
    }

    await _ensureNativeConfigured();
    final cacheDir = await _localEngine.resolveCacheDir();
    try {
      final nativeSize = await _channel.invokeMethod<int>('getCacheSize', <String, dynamic>{
        'cacheDir': cacheDir,
      });
      if (nativeSize != null) {
        return nativeSize + livePhotoBytes;
      }
    } on MissingPluginException {
      return (await _localEngine.getCacheSize()) + livePhotoBytes;
    } on PlatformException {
      // Fallback to directory scan on Apple if channel failed.
      if (!_usesAndroidMedia3Cache) {
        return (await _localEngine.getCacheSize()) + livePhotoBytes;
      }
    }
    return livePhotoBytes;
  }

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
      await _channel.invokeMethod<void>('removeCache', <String, dynamic>{
        'url': source.url,
        'cacheKey': cacheKey,
        'cacheDir': cacheDir,
      });
    } on MissingPluginException {
      await _localEngine.removeCache(source);
    } on PlatformException {
      if (!_usesAndroidMedia3Cache) {
        await _localEngine.removeCache(source);
      }
    }
  }

  Future<void> clearCache() async {
    await _clearNetworkLivePhotoCache();
    if (_usesDesktopDartProxy) {
      await _localEngine.clearCache();
      return;
    }

    await _ensureNativeConfigured();
    final cacheDir = await _localEngine.resolveCacheDir();
    try {
      await _channel.invokeMethod<void>('clearCache', <String, dynamic>{'cacheDir': cacheDir});
    } on MissingPluginException {
      await _localEngine.clearCache();
    } on PlatformException {
      if (!_usesAndroidMedia3Cache) {
        await _localEngine.clearCache();
      }
    }
  }

  Future<void> dispose() async {
    await _localEngine.dispose();
  }

  void _invokeBestEffort(String method, Map<String, dynamic> args) {
    _channel.invokeMethod<void>(method, args).then((_) {}, onError: (_) {});
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
