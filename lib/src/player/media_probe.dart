import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/video_player_host_bridge.dart';
import '../cache/video_cache_manager.dart';
import '../core/video_source.dart';
import '../data/models/navite_file.dart';
import '../data/models/video_cover_frame.dart';
import '../pigeon/player_api.g.dart';
import '../utils/temp_paths.dart';

/// Probe duration / cover frames without a live playback session.
///
/// Uses [VideoPlayerHostBridge] for host interop, independent from [PlayerBackend].
class MediaProbe {
  MediaProbe({this._bridge});

  final VideoPlayerHostBridge? _bridge;

  VideoPlayerHostBridge get _resolvedBridge => _bridge ?? VideoPlayerHostBridge.instance;

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
      final ms = await _resolvedBridge
          .getDuration(
            DurationProbeRequest(
              url: mediaUrl,
              timeoutMs: timeout.inMilliseconds,
              cacheKey: cacheKey,
              headers: headers,
            ),
          )
          .timeout(timeout);
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
      final raw = await _resolvedBridge
          .extractCovers(
            CoverExtractRequest(
              url: resolved,
              count: count,
              candidates: candidateCount,
              minBrightness: minBrightness,
              outputDir: dir,
              cacheKey: cacheKey,
              headers: headers,
            ),
          )
          .timeout(const Duration(seconds: 60));
      final list = raw.map(_frameFromData).whereType<VideoCoverFrame>().toList();
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

  static VideoCoverFrame? _frameFromData(CoverFrameData data) {
    final path = data.path;
    if (path.isEmpty) return null;
    return VideoCoverFrame(
      image: NaviteFile.fromLocation(path),
      position: Duration(milliseconds: data.positionMs),
      brightness: data.brightness.clamp(0.0, 1.0),
    );
  }
}
