import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/video_player_host_bridge.dart';
import '../cache/video_cache_manager.dart';
import '../core/video_source.dart';
import '../data/models/navite_file.dart';
import '../data/models/video_cover_frame.dart';
import '../pigeon/player_api.g.dart';
import '../utils/temp_paths.dart';

/// 独立于播放会话的媒体探测服务（支持在不创建活跃播放器的情况下探测时长与抽取封面帧）。
///
/// Probes media duration and candidate cover frames without a live playback session,
/// using [VideoPlayerHostBridge] independently of `PlayerBackend`.
class MediaProbe {
  /// 创建媒体探测服务实例，可选注入测试用 [bridge]。
  ///
  /// Creates a [MediaProbe] with an optional [bridge] override.
  MediaProbe({this._bridge});

  final VideoPlayerHostBridge? _bridge;

  VideoPlayerHostBridge get _resolvedBridge => _bridge ?? VideoPlayerHostBridge.instance;

  /// 探测 [source] 的媒体总时长（超时时间由 [timeout] 控制）。
  ///
  /// Probes total media duration for [source] within [timeout].
  ///
  /// 返回值 / Returns：媒体总时长 [Duration]；失败、超时或直播流返回 `null`。
  /// Media [Duration], or `null` on failure, timeout, or non-finite duration.
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

  /// 从 [source] 中抽取非黑候选封面帧并按平均亮度降序返回。
  ///
  /// Extracts non-black candidate cover frames from [source], sorted by descending brightness.
  ///
  /// - [count]：目标返回封面帧数量（必须 `> 0`，默认 `5`）。Target number of frames.
  /// - [minBrightness]：过滤黑帧的最小平均亮度阈值（`0.0..1.0`，默认 `0.08`）。Minimum brightness threshold.
  /// - [outputDir]：可选原生输出目录路径。Optional native output directory.
  ///
  /// 返回值 / Returns：按亮度降序排列的 [VideoCoverFrame] 列表。Sorted [VideoCoverFrame] list.
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
