import 'package:material_ui/material_ui.dart';

import 'core/live_photo_source.dart';
import 'core/video_source.dart';
import 'data/models/live_photo_bundle.dart';
import 'data/models/video_cover_frame.dart';
import 'player/media_probe.dart';
import 'utils/live_photo_extractor.dart';

/// 插件主入口：封面/时长探测、动态照片（Live Photo / Motion Photo）探测与提取等工具能力，
/// 以及可选的幂等 [initialize]。
///
/// Probe work is owned by [MediaProbe] and [LivePhotoExtractor]; this type
/// keeps the historical singleton call sites.
class XueHuaNaviteVideoPlayer {
  XueHuaNaviteVideoPlayer._();

  static final XueHuaNaviteVideoPlayer _instance = XueHuaNaviteVideoPlayer._();

  static XueHuaNaviteVideoPlayer get instance => _instance;

  factory XueHuaNaviteVideoPlayer() => _instance;

  final MediaProbe _probe = MediaProbe();

  Future<void>? _initFuture;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 幂等初始化（无害 no-op）：确保 Flutter binding 已就绪。
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _initialized = true;
  }

  /// 从任意来源的视频中抽取若干非黑的封面候选帧。
  ///
  /// Delegates to [MediaProbe.extractCovers].
  Future<List<VideoCoverFrame>> extractCoverCandidates(
    VideoSource source, {
    int count = 5,
    double minBrightness = 0.08,
    String? outputDir,
  }) {
    return _probe.extractCovers(
      source,
      count: count,
      minBrightness: minBrightness,
      outputDir: outputDir,
    );
  }

  /// 在不创建播放器实例的前提下，精确获取任意 [VideoSource] 的总时长。
  ///
  /// Delegates to [MediaProbe.probeDuration].
  Future<Duration?> getDuration(
    VideoSource source, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return _probe.probeDuration(source, timeout: timeout);
  }

  /// 将任意 [LivePhotoSource] 解析为包含静态封面图、可播放视频源及元数据的 [LivePhotoBundle]。
  ///
  /// Resolves a [LivePhotoSource] into a [LivePhotoBundle] without starting a playback session.
  Future<LivePhotoBundle> resolveLivePhoto(LivePhotoSource source) {
    return LivePhotoExtractor.resolve(source);
  }

  /// 在不创建播放器会话的前提下，尝试从 [source]（如单文件 Motion Photo `.jpg`/`.heic`、
  /// 本地同名配对图片/视频或 `.pvt` 包）中提取 [LivePhotoBundle]。
  /// 若 [source] 不是有效的动态照片，返回 `null`。
  ///
  /// Probes and extracts a [LivePhotoBundle] from [source], or returns `null`
  /// if [source] is not a Motion Photo or paired Live Photo.
  Future<LivePhotoBundle?> extractLivePhoto(
    VideoSource source, {
    Duration? presentationTimestamp,
  }) {
    return LivePhotoExtractor.tryExtractFromVideoSource(
      source,
      presentationTimestampOverride: presentationTimestamp,
    );
  }

  /// 检测 [source] 是否为动态照片（单文件 Motion Photo 或本地配对 Live Photo）。
  ///
  /// Returns `true` if [source] is a valid Motion Photo or paired Live Photo.
  Future<bool> isLivePhoto(VideoSource source) {
    return LivePhotoExtractor.isLivePhoto(source);
  }

  /// 释放初始化状态。
  Future<void> dispose() async {
    _initialized = false;
    _initFuture = null;
  }
}
