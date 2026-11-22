import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as html;

import '../pigeon/player_api.g.dart';

/// Web 平台离屏 HTML5 `<video>` / `<canvas>` 媒体探测与截图服务。
///
/// 负责当前帧截图、候选封面帧抽取以及媒体总时长探测。
///
/// Handles offscreen HTML5 `<video>` / `<canvas>` operations on Web:
/// frame snapshots, cover candidate extraction, and metadata duration probing.
abstract final class WebMediaProbeService {
  /// 将 [video] 当前播放画面绘制到 `<canvas>` 并编码为 PNG `data:` URL 封装在 [SnapshotData] 中。
  ///
  /// Captures the current frame of [video] as a PNG data URL inside [SnapshotData].
  ///
  /// - [video]：目标 `<video>` 元素。Target HTML5 `<video>` element.
  ///
  /// 返回值 / Returns：包含 PNG `dataUri` 的 [SnapshotData]；若 [video] 为 `null` 或触发 CORS 污染则返回 `null`。
  /// [SnapshotData] containing a PNG `dataUri`, or `null` if [video] is null or tainted by CORS.
  static SnapshotData? takeSnapshot(html.HTMLVideoElement? video) {
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
      return SnapshotData(dataUri: canvas.toDataURL('image/png'));
    } catch (_) {
      return null;
    }
  }

  /// 使用离屏 `<video>` 元素在媒体时间轴上采样并抽取候选封面帧。
  ///
  /// Extracts candidate cover frames using an offscreen `<video>` element.
  ///
  /// - [request]：包含媒体地址、抽取数量、候选采样数与最小亮度阈值的请求参数。
  ///   Extraction request specifying URL, target count, candidates, and minimum brightness.
  ///
  /// 返回值 / Returns：按平均亮度降序排列的 [CoverFrameData] 列表。
  /// List of [CoverFrameData] sorted by descending average brightness.
  static Future<List<CoverFrameData>> extractCovers(CoverExtractRequest request) async {
    final url = request.url;
    final count = request.count;
    final candidates = request.candidates;
    final minBrightness = request.minBrightness;
    if (url.isEmpty || count <= 0) return const [];

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

      final frames = <CoverFrameData>[];
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
          frames.add(
            CoverFrameData(path: dataUrl, positionMs: (t * 1000).toInt(), brightness: brightness),
          );
        } catch (_) {
          continue;
        }
      }
      frames.sort((a, b) => b.brightness.compareTo(a.brightness));
      return frames.take(count).toList();
    } finally {
      try {
        video.removeAttribute('src');
      } catch (_) {}
    }
  }

  /// 使用独立离屏 `<video>` 探测媒体总时长（单位毫秒）。
  ///
  /// Probes media duration (in milliseconds) using a detached offscreen `<video>`.
  ///
  /// - [request]：包含媒体地址与超时时间的探测请求。Duration probe request.
  ///
  /// 返回值 / Returns：媒体时长（毫秒）；失败、超时或直播流（非有限时长）返回 `null`。
  /// Media duration in milliseconds, or `null` on failure, timeout, or non-finite duration.
  static Future<int?> getDuration(DurationProbeRequest request) async {
    final url = request.url;
    final timeoutMs = request.timeoutMs > 0 ? request.timeoutMs : 15000;
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

  static double _canvasAverageBrightness(html.CanvasRenderingContext2D ctx, int width, int height) {
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
