import 'package:meta/meta.dart';

import '../player/video_player_controller.dart';
import 'style/video_player_theme.dart';

/// 全屏手势操作期间在屏幕中央 HUD 展示的反馈类别。
///
/// Active gesture feedback category displayed in the center overlay HUD.
enum PlayerHudKind {
  /// 水平拖动快进/快退预览。
  ///
  /// Horizontal drag seek preview.
  seek,

  /// 垂直拖动调节屏幕亮度。
  ///
  /// Vertical drag screen brightness adjustment.
  brightness,

  /// 垂直拖动调节播放音量。
  ///
  /// Vertical drag audio volume adjustment.
  volume,
}

/// 传递给 `VideoPlayer.gestureHudBuilder` 与默认 `PlayerGestureHud` 的不可变实时手势快照。
///
/// Immutable real-time snapshot passed to `VideoPlayer.gestureHudBuilder` and
/// the default `PlayerGestureHud` during fullscreen drag gestures.
@immutable
class PlayerGestureHudContext {
  /// 创建手势 HUD 实时快照上下文。
  ///
  /// Creates a [PlayerGestureHudContext] snapshot.
  ///
  /// - [controller]：当前活跃的播放器控制器。Active player controller.
  /// - [theme]：当前解析生效的播放器主题。Resolved player theme.
  /// - [kind]：当前正在调节的手势类型。Active gesture feedback kind.
  /// - [value]：亮度/音量的归一化实时值（`0.0..1.0`）；快进/快退时为 `0.0`。Normalized real-time value (`0.0..1.0`).
  /// - [label]：格式化后的实时文本（如 `'75%'` 或 `'+10s'`）。Formatted real-time label.
  /// - [seekForward]：当 [kind] 为 [PlayerHudKind.seek] 时的方向标志（`true` 快进，`false` 快退）。Seek direction flag.
  const PlayerGestureHudContext({
    required this.controller,
    required this.theme,
    required this.kind,
    required this.value,
    required this.label,
    required this.seekForward,
  });

  /// 当前活跃的播放器控制器。
  ///
  /// Active player controller.
  final VideoPlayerController controller;

  /// 当前子树解析出的播放器主题配置。
  ///
  /// Resolved player theme for the current subtree.
  final VideoPlayerTheme theme;

  /// 当前正在触发的手势反馈类别。
  ///
  /// Type of gesture currently being adjusted.
  final PlayerHudKind kind;

  /// 亮度或音量的归一化实时数值（范围 `0.0..1.0`）；当 [kind] 为 [PlayerHudKind.seek] 时为 `0.0`。
  ///
  /// Normalized real-time value in `[0.0, 1.0]` for brightness and volume;
  /// `0.0` for [PlayerHudKind.seek].
  final double value;

  /// 格式化后的实时展示文本（例如 `'75%'` 或 `'+10s'`）。
  ///
  /// Formatted real-time text label (for example `'75%'` or `'+10s'`).
  final String label;

  /// 当 [kind] 为 [PlayerHudKind.seek] 时的快进/快退方向标志（`true` 表示快进，`false` 表示快退）。
  ///
  /// Direction flag when [kind] is [PlayerHudKind.seek] (`true` for forward, `false` for backward).
  final bool seekForward;

  /// 由 [value] 换算得到的整数百分比（`0..100`）。
  ///
  /// Integer percentage (`0..100`) derived from [value].
  int get percentage => (value * 100).round().clamp(0, 100);

  /// 当 [kind] 为 [PlayerHudKind.volume] 且音量归零时返回 `true`。
  ///
  /// Whether [kind] is [PlayerHudKind.volume] and the audio level is zero.
  bool get isMuted => kind == PlayerHudKind.volume && value <= 0.0;
}
