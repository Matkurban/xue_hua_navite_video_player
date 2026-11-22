import 'package:material_ui/material_ui.dart';

import '../player/video_player_controller.dart';
import 'style/video_player_theme.dart';

/// 传递给 `VideoPlayer` 各自定义槽位构建器的上下文对象。
///
/// Context passed to custom slot builders in `VideoPlayer`.
class VideoPlayerSlotContext {
  /// 当前绑定的播放器控制器实例。
  ///
  /// Active [VideoPlayerController] bound to the player.
  final VideoPlayerController controller;

  /// 当前生效的播放器主题配置。
  ///
  /// Resolved [VideoPlayerTheme] for the current player subtree.
  final VideoPlayerTheme theme;

  /// 立即显示播放器控件层并在播放中重新调度自动隐藏计时器。
  ///
  /// Shows player controls and reschedules the auto-hide timer when playing.
  final VoidCallback showControls;

  /// 立即隐藏播放器控件层。
  ///
  /// Immediately hides player controls.
  final VoidCallback hideControls;

  /// 创建播放器槽位上下文对象。
  ///
  /// Creates a [VideoPlayerSlotContext].
  const VideoPlayerSlotContext({
    required this.controller,
    required this.theme,
    required this.showControls,
    required this.hideControls,
  });
}
