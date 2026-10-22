import 'package:material_ui/material_ui.dart';

import '../player/video_player_controller.dart';
import 'style/video_player_theme.dart';

/// 传递给自定义槽位 builder 的上下文。
///
/// Context passed to custom slot builders in [VideoPlayer].
class VideoPlayerSlotContext {
  final VideoPlayerController controller;
  final VideoPlayerTheme theme;
  final VoidCallback showControls;
  final VoidCallback hideControls;

  const VideoPlayerSlotContext({
    required this.controller,
    required this.theme,
    required this.showControls,
    required this.hideControls,
  });
}
