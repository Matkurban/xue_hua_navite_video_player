import 'package:flutter/material.dart';

import 'core/video_source.dart';
import 'data/models/video_cover_frame.dart';
import 'player/media_probe.dart';

/// 插件主入口：封面/时长探测等工具能力，以及可选的幂等 [initialize]。
///
/// Probe work is owned by [MediaProbe]; this type keeps the historical
/// singleton call sites.
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

  /// 释放初始化状态。
  Future<void> dispose() async {
    _initialized = false;
    _initFuture = null;
  }
}
