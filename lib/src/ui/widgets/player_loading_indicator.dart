import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../style/video_player_theme.dart';

/// 主题自适应加载指示器：Cupertino 风格使用 [CupertinoActivityIndicator]，Material 风格使用 [CircularProgressIndicator]。
///
/// Theme-adaptive activity indicator rendering [CupertinoActivityIndicator] in
/// Cupertino mode and [CircularProgressIndicator] in Material mode.
class PlayerLoadingIndicator extends StatelessWidget {
  /// 创建主题自适应加载指示器。
  ///
  /// Creates a [PlayerLoadingIndicator].
  const PlayerLoadingIndicator({super.key, this.size, this.color, this.strokeWidth = 2.2});

  /// 指示器宽高尺寸；为 `null` 时使用 `VideoPlayerTheme.chromeIconSize`。
  ///
  /// Indicator width and height; defaults to `VideoPlayerTheme.chromeIconSize`.
  final double? size;

  /// 指示器颜色；为 `null` 时使用 `VideoPlayerTheme.foregroundColor`。
  ///
  /// Indicator foreground color; defaults to `VideoPlayerTheme.foregroundColor`.
  final Color? color;

  /// Material 模式下圆形进度条的线条宽度，默认 `2.2`。
  ///
  /// Stroke width of [CircularProgressIndicator] in Material mode (defaults to `2.2`).
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = VideoPlayerTheme.of(context);
    final effectiveColor = color ?? theme.foregroundColor;
    final effectiveSize = size ?? theme.chromeIconSize;

    if (theme.isCupertinoFor(context)) {
      return SizedBox(
        width: effectiveSize,
        height: effectiveSize,
        child: CupertinoActivityIndicator(
          color: effectiveColor,
          radius: (effectiveSize / 2).clamp(8.0, 16.0),
        ),
      );
    }

    return SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
      ),
    );
  }
}
