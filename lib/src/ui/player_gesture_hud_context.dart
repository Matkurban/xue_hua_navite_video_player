import 'package:meta/meta.dart';

import '../player/video_player_controller.dart';
import 'style/video_player_theme.dart';

/// Active gesture feedback category displayed in the center overlay HUD.
enum PlayerHudKind {
  /// Horizontal drag seek preview.
  seek,

  /// Vertical drag screen brightness adjustment.
  brightness,

  /// Vertical drag audio volume adjustment.
  volume,
}

/// Immutable snapshot passed to [VideoPlayer.gestureHudBuilder] and the default
/// [PlayerGestureHud] while the user drags horizontally or vertically in fullscreen.
@immutable
class PlayerGestureHudContext {
  const PlayerGestureHudContext({
    required this.controller,
    required this.theme,
    required this.kind,
    required this.value,
    required this.label,
    required this.seekForward,
  });

  /// Active player controller.
  final VideoPlayerController controller;

  /// Resolved player theme for the current subtree.
  final VideoPlayerTheme theme;

  /// Type of gesture currently being adjusted.
  final PlayerHudKind kind;

  /// Normalized real-time value in `[0.0, 1.0]` for brightness and volume;
  /// `0.0` for [PlayerHudKind.seek].
  final double value;

  /// Formatted real-time text label (for example `'75%'` or `'+10s'`).
  final String label;

  /// Direction flag when [kind] is [PlayerHudKind.seek].
  final bool seekForward;

  /// Integer percentage (`0..100`) derived from [value].
  int get percentage => (value * 100).round().clamp(0, 100);

  /// Whether [kind] is [PlayerHudKind.volume] and the audio level is zero.
  bool get isMuted => kind == PlayerHudKind.volume && value <= 0.0;
}
