import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../style/video_player_theme.dart';

/// Theme-adaptive activity indicator: [CupertinoActivityIndicator] for Cupertino,
/// [CircularProgressIndicator] for Material.
class PlayerLoadingIndicator extends StatelessWidget {
  const PlayerLoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.strokeWidth = 2.2,
  });

  final double? size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = VideoPlayerTheme.of(context);
    final effectiveColor = color ?? theme.foregroundColor;
    final effectiveSize = size ?? theme.chromeIconSize;

    if (theme.isCupertino) {
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
