import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/video_source.dart';
import '../data/models/video_cover_frame.dart';

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
    try {
      final mediaUrl = await source.resolveToNativeUrl();
      final raw = await _channel.invokeMethod<dynamic>('getDuration', {
        'url': mediaUrl,
        'timeoutMs': timeout.inMilliseconds,
      });
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
    final resolved = await source.resolveToNativeUrl();

    final dir = kIsWeb ? '' : (outputDir ?? await _defaultCoverDir());

    final raw = await _channel.invokeMethod<dynamic>('extractCovers', {
      'url': resolved,
      'count': count,
      'candidates': candidateCount,
      'minBrightness': minBrightness,
      'outputDir': dir,
    });
    if (raw == null) return const <VideoCoverFrame>[];
    final list = (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(_frameFromMap)
        .whereType<VideoCoverFrame>()
        .toList();
    list.sort((a, b) => b.brightness.compareTo(a.brightness));
    return list;
  }

  static VideoCoverFrame? _frameFromMap(Map<String, dynamic> map) {
    final path = map['path'] as String?;
    final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
    final brightness = (map['brightness'] as num?)?.toDouble() ?? 0.0;
    if (path == null || path.isEmpty) return null;
    return VideoCoverFrame(
      image: XFile(path, mimeType: 'image/png'),
      position: Duration(milliseconds: positionMs),
      brightness: brightness.clamp(0.0, 1.0),
    );
  }

  static Future<String> _defaultCoverDir() async {
    final base = await getTemporaryDirectory();
    return '${base.path}/xue_hua_navite_video_player/covers';
  }
}
