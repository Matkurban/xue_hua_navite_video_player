import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../cache/video_cache_manager.dart';
import '../core/video_source.dart';
import '../data/models/navite_file.dart';
import '../data/models/video_cover_frame.dart';
import '../utils/temp_paths.dart';

/// Probe duration / cover frames without a live playback session.
///
/// Uses the same MethodChannel wire methods as playback transport, but is a
/// separate module from [PlayerBackend].
class MediaProbe {
  MediaProbe({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('xue_hua_navite_video_player/player');

  final MethodChannel _channel;

  /// Probe total duration for [source]. Returns `null` on failure / timeout.
  Future<Duration?> probeDuration(
    VideoSource source, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    String? pinnedKey;
    try {
      String mediaUrl;
      String? cacheKey;
      Map<String, String>? headers;
      if (source is NetworkVideoSource) {
        final target = await VideoCacheManager.instance.resolveForProbe(source);
        mediaUrl = target.playUrl;
        cacheKey = target.cacheKey;
        headers = target.headers;
        if (cacheKey != null) {
          pinnedKey = cacheKey;
          VideoCacheManager.instance.pin(cacheKey);
        }
      } else {
        mediaUrl = await source.resolveToNativeUrl();
      }
      final raw = await _channel
          .invokeMethod<dynamic>('getDuration', {
            'url': mediaUrl,
            'timeoutMs': timeout.inMilliseconds,
            'cacheKey': ?cacheKey,
            'headers': ?headers,
          })
          .timeout(timeout);
      if (raw == null) return null;
      final ms = switch (raw) {
        final int v => v,
        final num v => v.toInt(),
        _ => null,
      };
      if (ms == null || ms <= 0) return null;
      return Duration(milliseconds: ms);
    } catch (_) {
      return null;
    } finally {
      if (pinnedKey != null) {
        VideoCacheManager.instance.unpin(pinnedKey);
      }
    }
  }

  /// Extract non-black cover candidates, sorted by brightness descending.
  Future<List<VideoCoverFrame>> extractCovers(
    VideoSource source, {
    int count = 5,
    double minBrightness = 0.08,
    String? outputDir,
  }) async {
    assert(count > 0, 'count must be > 0');
    final candidateCount = (count * 3).clamp(count, 30);

    String? pinnedKey;
    try {
      String resolved;
      String? cacheKey;
      Map<String, String>? headers;
      if (source is NetworkVideoSource) {
        final target = await VideoCacheManager.instance.resolveForProbe(source);
        resolved = target.playUrl;
        cacheKey = target.cacheKey;
        headers = target.headers;
        if (cacheKey != null) {
          pinnedKey = cacheKey;
          VideoCacheManager.instance.pin(cacheKey);
        }
      } else {
        resolved = await source.resolveToNativeUrl();
      }
      final dir = kIsWeb ? '' : (outputDir ?? await pluginCoverDir());
      final raw = await _channel
          .invokeMethod<dynamic>('extractCovers', {
            'url': resolved,
            'count': count,
            'candidates': candidateCount,
            'minBrightness': minBrightness,
            'outputDir': dir,
            'cacheKey': ?cacheKey,
            'headers': ?headers,
          })
          .timeout(const Duration(seconds: 60));
      if (raw is! List) return const <VideoCoverFrame>[];
      final list = raw
          .whereType<Map<Object?, Object?>>()
          .map(Map<String, dynamic>.from)
          .map(_frameFromMap)
          .whereType<VideoCoverFrame>()
          .toList();
      list.sort((a, b) => b.brightness.compareTo(a.brightness));
      return list;
    } catch (_) {
      return const <VideoCoverFrame>[];
    } finally {
      if (pinnedKey != null) {
        VideoCacheManager.instance.unpin(pinnedKey);
      }
    }
  }

  static VideoCoverFrame? _frameFromMap(Map<String, dynamic> map) {
    final path = map['path'] as String?;
    final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
    final brightness = (map['brightness'] as num?)?.toDouble() ?? 0.0;
    if (path == null || path.isEmpty) return null;
    return VideoCoverFrame(
      image: NaviteFile.fromLocation(path),
      position: Duration(milliseconds: positionMs),
      brightness: brightness.clamp(0.0, 1.0),
    );
  }
}
