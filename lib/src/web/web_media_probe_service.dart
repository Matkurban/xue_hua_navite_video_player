import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as html;

/// Handles offscreen HTML5 `<video>` / `<canvas>` operations on Web:
/// frame snapshots, cover candidate extraction, and metadata duration probing.
abstract final class WebMediaProbeService {
  /// Captures the current frame of [video] as a PNG data URL (`data:image/png;base64,...`).
  /// Returns `null` if [video] is null or if the canvas is tainted by CORS.
  static String? takeSnapshot(html.HTMLVideoElement? video) {
    if (video == null) return null;
    try {
      final w = video.videoWidth == 0 ? 640 : video.videoWidth;
      final h = video.videoHeight == 0 ? 360 : video.videoHeight;
      final canvas = html.HTMLCanvasElement()
        ..width = w
        ..height = h;
      final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D?;
      if (ctx == null) return null;
      ctx.drawImage(video, 0, 0, w.toDouble(), h.toDouble());
      return canvas.toDataURL('image/png');
    } catch (_) {
      return null;
    }
  }

  /// Extracts candidate cover frames using an offscreen `<video>` element.
  static Future<List<Map<String, dynamic>>> extractCovers(
    Map<String, dynamic> args,
  ) async {
    final url = args['url'] as String? ?? '';
    final count = (args['count'] as int?) ?? 5;
    final candidates = (args['candidates'] as int?) ?? (count * 3);
    final minBrightness = (args['minBrightness'] as num?)?.toDouble() ?? 0.08;
    if (url.isEmpty) return const [];

    final video = html.HTMLVideoElement()
      ..crossOrigin = 'anonymous'
      ..muted = true
      ..preload = 'auto'
      ..src = url;
    try {
      try {
        await video.onLoadedMetadata.first.timeout(const Duration(seconds: 15));
      } catch (_) {
        return const [];
      }
      final durationSec = video.duration;
      if (!durationSec.isFinite || durationSec <= 0) return const [];

      final lower = durationSec * 0.05;
      final upper = durationSec * 0.95;
      final span = (upper - lower).clamp(0.1, double.infinity);
      final n = candidates > count ? candidates : count;

      final frames = <Map<String, dynamic>>[];
      final canvas = html.HTMLCanvasElement();
      for (var i = 0; i < n; i++) {
        final t = lower + span * (i + 0.5) / n;
        video.currentTime = t;
        try {
          await video.onSeeked.first.timeout(const Duration(seconds: 5));
        } catch (_) {
          continue;
        }
        final w = video.videoWidth == 0 ? 640 : video.videoWidth;
        final h = video.videoHeight == 0 ? 360 : video.videoHeight;
        canvas
          ..width = w
          ..height = h;
        final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D?;
        if (ctx == null) continue;
        try {
          ctx.drawImage(video, 0, 0, w.toDouble(), h.toDouble());
          final brightness = _canvasAverageBrightness(ctx, w, h);
          if (brightness < minBrightness) continue;
          final dataUrl = canvas.toDataURL('image/png');
          frames.add({
            'path': dataUrl,
            'positionMs': (t * 1000).toInt(),
            'brightness': brightness,
          });
        } catch (_) {
          continue;
        }
      }
      frames.sort(
        (a, b) => ((b['brightness'] as num).toDouble()).compareTo(
          (a['brightness'] as num).toDouble(),
        ),
      );
      return frames.take(count).toList();
    } finally {
      try {
        video.removeAttribute('src');
      } catch (_) {}
    }
  }

  /// Probes media duration (milliseconds) using a detached offscreen `<video>`.
  static Future<int?> getDuration(Map<String, dynamic> args) async {
    final url = args['url'] as String? ?? '';
    final timeoutMs = (args['timeoutMs'] as int?) ?? 15000;
    if (url.isEmpty) return null;

    final video = html.HTMLVideoElement()
      ..crossOrigin = 'anonymous'
      ..muted = true
      ..preload = 'metadata'
      ..src = url;
    try {
      await video.onLoadedMetadata.first.timeout(Duration(milliseconds: timeoutMs));
    } catch (_) {
      try {
        video.removeAttribute('src');
      } catch (_) {}
      return null;
    }
    try {
      final seconds = video.duration;
      if (!seconds.isFinite || seconds <= 0) return null;
      return (seconds * 1000).toInt();
    } finally {
      try {
        video.removeAttribute('src');
      } catch (_) {}
    }
  }

  static double _canvasAverageBrightness(
    html.CanvasRenderingContext2D ctx,
    int width,
    int height,
  ) {
    const sw = 64;
    const sh = 64;
    final tmp = html.HTMLCanvasElement()
      ..width = sw
      ..height = sh;
    final tctx = tmp.getContext('2d') as html.CanvasRenderingContext2D?;
    if (tctx == null) return 0;
    tctx.drawImage(
      ctx.canvas,
      0,
      0,
      width.toDouble(),
      height.toDouble(),
      0,
      0,
      sw.toDouble(),
      sh.toDouble(),
    );
    final imageData = tctx.getImageData(0, 0, sw, sh);
    final data = imageData.data.toDart;
    var total = 0.0;
    for (var i = 0; i < data.length; i += 4) {
      final r = data[i] / 255.0;
      final g = data[i + 1] / 255.0;
      final b = data[i + 2] / 255.0;
      total += 0.299 * r + 0.587 * g + 0.114 * b;
    }
    return total / (sw * sh);
  }
}
